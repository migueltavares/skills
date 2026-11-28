#!/usr/bin/env bash
# Waits for the GitHub Actions deploy of one merge commit, for mig-merge.
#
# Usage:
#   wait-deploy.sh --sha <merge sha> --workflow <deploy.yml> [--after <ci.yml>]
#                  [--timeout <seconds>] [--repo <owner/repo>]
#
# --after names the workflow the deploy waits for (a workflow_run trigger). Its
# run is watched first, so a red CI fails fast instead of waiting out the clock.
# --timeout is how long to wait for each run to appear, default 600 seconds.
# Prints "RUN <workflow> <id> <url>" as soon as a run exists.
#
# Exit codes: 0 deployed, 1 the deploy failed (the failed log tail follows),
# 2 the --after workflow failed, 3 no run appeared in time, 4 the workflow is
# disabled or missing, 5 a gh call failed.

set -uo pipefail

die() { echo "ERROR $*" >&2; exit 5; }
command -v gh >/dev/null || die "gh is not installed"

sha="" workflow="" after="" timeout=600 repo=""
interval=${WAIT_DEPLOY_INTERVAL:-10}
while [ $# -gt 0 ]; do
    case $1 in
        --sha) sha=${2:-}; shift ;;
        --workflow) workflow=${2:-}; shift ;;
        --after) after=${2:-}; shift ;;
        --timeout) timeout=${2:-}; shift ;;
        --repo) repo=${2:-}; shift ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done
[ -n "$sha" ] && [ -n "$workflow" ] || die "--sha and --workflow are required"
[[ "$timeout" =~ ^[0-9]+$ ]] || die "--timeout takes seconds"
R=()
[ -n "$repo" ] && R=(--repo "$repo")

state=$(gh workflow list --all "${R[@]+"${R[@]}"}" --json path,state \
    --jq ".[] | select(.path | endswith(\"/$workflow\")) | .state") || die "gh workflow list failed"
case $state in
    active) ;;
    "") echo "MISSING workflow $workflow"; exit 4 ;;
    *) echo "DISABLED workflow $workflow ($state): it deploys nothing until it is enabled"; exit 4 ;;
esac

# find_run <workflow>: prints "<id> <url>" for the newest run on $sha, waiting up to $timeout.
find_run() {
    local wf=$1 found deadline=$((SECONDS + timeout))
    while :; do
        found=$(gh run list "${R[@]+"${R[@]}"}" --commit "$sha" --workflow "$wf" --limit 1 --json databaseId,url \
            --jq '.[0] | select(. != null) | "\(.databaseId) \(.url)"') || die "gh run list failed"
        [ -n "$found" ] && { echo "$found"; return 0; }
        [ "$SECONDS" -ge "$deadline" ] && return 1
        sleep "$interval"
    done
}

if [ -n "$after" ]; then
    ci=$(find_run "$after"); rc=$?
    [ "$rc" -eq 5 ] && exit 5
    [ "$rc" -ne 0 ] && { echo "NO RUN of $after for $sha after ${timeout}s"; exit 3; }
    echo "RUN $after $ci"
    if ! gh run watch "${R[@]+"${R[@]}"}" "${ci%% *}" --exit-status >/dev/null; then
        echo "FAILED $after run ${ci%% *}: the deploy will not start"
        gh run view "${R[@]+"${R[@]}"}" "${ci%% *}" --log-failed 2>/dev/null | tail -50
        exit 2
    fi
fi

run=$(find_run "$workflow"); rc=$?
[ "$rc" -eq 5 ] && exit 5
if [ "$rc" -ne 0 ]; then
    echo "NO RUN of $workflow for $sha after ${timeout}s. Check its trigger and paths filter."
    exit 3
fi
echo "RUN $workflow $run"
if gh run watch "${R[@]+"${R[@]}"}" "${run%% *}" --exit-status >/dev/null; then
    echo "DEPLOYED run ${run%% *}"
    exit 0
fi
echo "FAILED $workflow run ${run%% *}"
gh run view "${R[@]+"${R[@]}"}" "${run%% *}" --log-failed 2>/dev/null | tail -50
exit 1
