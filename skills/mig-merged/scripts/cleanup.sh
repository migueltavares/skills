#!/usr/bin/env bash
# The deterministic part of mig-merged: verify merged PRs, update the default
# branch, remove clean worktrees and delete branches that hold nothing the PR
# did not. Anything that needs judgment is reported, never acted on.
#
# Usage:
#   cleanup.sh [--plan] [--skip-worktree <path>]... <pr>...
#       Clean up after these PRs. --plan reports what would happen and changes
#       nothing. --skip-worktree keeps a worktree that another thread uses.
#   cleanup.sh
#       Sweep: list merged branches and worktrees left behind. Changes nothing.
#
# Run it from any checkout of the repo; it works in the main checkout. The
# worktree the caller's shell runs in is detached, never removed: the caller
# removes it as its last command, with the line this script prints.
#
# Exit codes: 0 nothing is left for the agent, 3 at least one line needs the
# agent (it is repeated in the final "Loose ends:" line), 1 git or gh failed.

set -uo pipefail

die() { echo "ERROR $*" >&2; exit 1; }

plan=false
skips=()
prs=()
while [ $# -gt 0 ]; do
    case $1 in
        --plan) plan=true ;;
        --skip-worktree) [ $# -ge 2 ] || die "--skip-worktree needs a path"; skips+=("$(realpath -m "$2")"); shift ;;
        -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
        \#[0-9]*|[0-9]*) prs+=("${1#\#}") ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done

for tool in git gh jq; do
    command -v "$tool" >/dev/null || die "$tool is not installed"
done

caller=$(git rev-parse --show-toplevel 2>/dev/null) || die "run this inside a checkout of the repo"
caller=$(realpath "$caller")
main=$(git worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')
main=$(realpath "$main")
g() { git -C "$main" "$@"; }
ghm() { (cd "$main" && gh "$@"); }

loose=()
need=0
detached=""
say() { echo "$*"; }
flag() { echo "$*"; loose+=("$*"); need=1; }
finish() {
    [ -n "$detached" ] && say "LAST git -C $main worktree remove $detached"
    if [ ${#loose[@]} -eq 0 ]; then
        echo "Loose ends: none"
    else
        local joined
        joined=$(printf ' | %s' "${loose[@]}")
        echo "Loose ends:${joined# |}"
    fi
    [ "$need" -eq 1 ] && exit 3
    exit 0
}

is_skipped() {
    local p
    for p in "${skips[@]+"${skips[@]}"}"; do [ "$p" = "$1" ] && return 0; done
    return 1
}

# Paths of the worktrees that have branch $1 checked out.
worktrees_on() {
    g worktree list --porcelain | awk -v ref="branch refs/heads/$1" '
        /^worktree /{ p = substr($0, 10) }
        $0 == ref { print p }'
}

has_commit() { g cat-file -e "$1^{commit}" 2>/dev/null; }

g fetch -q --prune origin || die "git fetch origin failed in $main"
default=$(g symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
default=${default#origin/}
[ -n "$default" ] || default=$(g ls-remote --symref origin HEAD | awk '/^ref:/{sub("refs/heads/", "", $2); print $2; exit}')
[ -n "$default" ] || die "cannot tell the default branch of origin"

open_json=$(ghm pr list --state open --limit 1000 --json number,headRefName,baseRefName) || die "gh pr list failed"

# ---------- Sweep: list candidates, change nothing ----------
if [ ${#prs[@]} -eq 0 ]; then
    merged_json=$(ghm pr list --state merged --limit 1000 --json number,headRefName,headRefOid) || die "gh pr list failed"
    found=0
    while read -r b; do
        [ -z "$b" ] || [ "$b" = "$default" ] && continue
        [ -n "$(jq -r --arg b "$b" '.[] | select(.headRefName == $b) | .number' <<<"$open_json")" ] && continue
        n="" oid=""
        read -r n oid < <(jq -r --arg b "$b" 'first(.[] | select(.headRefName == $b)) | "\(.number) \(.headRefOid)"' <<<"$merged_json")
        [ -n "${n:-}" ] || continue
        has_commit "$oid" || g fetch -q origin "pull/$n/head" 2>/dev/null || continue
        where=()
        if g show-ref -q --verify "refs/heads/$b"; then
            g merge-base --is-ancestor "refs/heads/$b" "$oid" || continue
            where+=("local")
        fi
        if g show-ref -q --verify "refs/remotes/origin/$b"; then
            g merge-base --is-ancestor "refs/remotes/origin/$b" "$oid" || continue
            where+=("origin")
        fi
        while read -r p; do [ -n "$p" ] && where+=("worktree $p"); done < <(worktrees_on "$b")
        [ ${#where[@]} -gt 0 ] || continue
        stacked=$(jq -r --arg b "$b" '[.[] | select(.baseRefName == $b) | "#\(.number)"] | join(" ")' <<<"$open_json")
        [ -n "$stacked" ] && where+=("base of open $stacked")
        say "CANDIDATE #$n $b: $(IFS=,; echo "${where[*]}" | sed 's/,/, /g')"
        found=1
    done < <({ g for-each-ref --format='%(refname:lstrip=2)' refs/heads; g for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin; } | grep -vx 'HEAD' | sort -u)
    [ "$found" -eq 1 ] || say "CANDIDATE none"
    finish
fi

# ---------- Update the default branch in the main checkout ----------
if $plan; then
    say "WOULD update $default in $main"
else
    if [ "$(g branch --show-current)" != "$default" ]; then
        g switch -q "$default" 2>/dev/null || { flag "STOP $main cannot switch to $default: commit or stash its changes, then run this again"; finish; }
    fi
    g pull -q --ff-only || { flag "STOP git pull --ff-only failed in $main"; finish; }
    say "UPDATED $default in $main at $(g rev-parse --short HEAD)"
    changes=$(g status --porcelain | wc -l)
    [ "$changes" -gt 0 ] && say "NOTE $changes uncommitted files in $main came along"
fi

# ---------- Each PR ----------
for n in "${prs[@]}"; do
    pr=$(ghm pr view "$n" --json state,headRefName,headRefOid,isCrossRepository,body,closingIssuesReferences) || { flag "STOP gh pr view $n failed"; continue; }
    state=$(jq -r .state <<<"$pr")
    b=$(jq -r .headRefName <<<"$pr")
    oid=$(jq -r .headRefOid <<<"$pr")
    fork=$(jq -r .isCrossRepository <<<"$pr")

    if [ "$state" != "MERGED" ]; then
        flag "SKIP #$n is $state, not merged"
        continue
    fi
    if [ "$b" = "$default" ]; then
        flag "SKIP #$n: its head is the default branch"
        continue
    fi

    keep=false
    reused=$(jq -r --arg b "$b" '[.[] | select(.headRefName == $b) | "#\(.number)"] | join(" ")' <<<"$open_json")
    stacked=$(jq -r --arg b "$b" '[.[] | select(.baseRefName == $b) | "#\(.number)"] | join(" ")' <<<"$open_json")

    if [ -n "$stacked" ]; then
        flag "STACKED $stacked on $b: retarget to $default, then run this again for #$n"
        keep=true
    fi
    if [ -n "$reused" ]; then
        say "KEPT $b: open PR $reused uses this branch name"
        keep=reused
    fi

    if ! has_commit "$oid" && ! g fetch -q origin "pull/$n/head"; then
        flag "STOP #$n: cannot fetch its head $oid"
        continue
    fi
    for ref in "refs/heads/$b" "refs/remotes/origin/$b"; do
        g show-ref -q --verify "$ref" || continue
        late=$(g log --format=%h "$oid..$ref")
        [ -z "$late" ] && continue
        [ "$keep" = reused ] && continue
        flag "LATE ${ref#refs/*/} has $(wc -l <<<"$late") commits not in #$n: $(echo $late)"
        keep=true
    done

    # Worktrees on the branch. A reused branch name belongs to the open PR.
    if [ "$keep" != reused ]; then
        while read -r path; do
            [ -n "$path" ] || continue
            path=$(realpath "$path")
            [ "$path" = "$main" ] && continue
            if is_skipped "$path"; then
                say "KEPT worktree $path: another thread uses it"
                keep=true
            elif [ -n "$(git -C "$path" status --porcelain)" ]; then
                flag "DIRTY $path has uncommitted changes: commit or drop them"
                keep=true
            elif [ "$path" = "$caller" ]; then
                if $plan; then
                    say "WOULD detach $path, this shell's worktree"
                else
                    git -C "$path" switch -q --detach "origin/$default" || { flag "STOP cannot detach $path"; keep=true; continue; }
                    say "DETACHED $path, this shell's worktree"
                    detached=$path
                fi
            elif $plan; then
                say "WOULD remove worktree $path"
            else
                g worktree remove "$path" && say "REMOVED worktree $path" || { flag "STOP git worktree remove $path failed"; keep=true; }
            fi
        done < <(worktrees_on "$b")
        $plan || g worktree prune
    fi

    # Branches, only when nothing above asked to keep them.
    if [ "$keep" = false ]; then
        if g show-ref -q --verify "refs/heads/$b"; then
            if ! g merge-base --is-ancestor "refs/heads/$b" "$oid"; then
                flag "LATE $b: not contained in #$n, kept"
            elif $plan; then
                say "WOULD delete local $b"
            else
                g branch -q -D "$b" && say "DELETED local $b" || flag "STOP git branch -D $b failed"
            fi
        fi
        if [ "$fork" = true ]; then
            say "KEPT the head branch of #$n: it lives in a fork"
        else
            # Read the live tip again: a push can land between the fetch and the delete.
            live=$(g ls-remote --heads origin "refs/heads/$b" | cut -f1)
            if [ -z "$live" ]; then
                say "GONE origin/$b: GitHub already removed it"
            elif ! has_commit "$live" || ! g merge-base --is-ancestor "$live" "$oid"; then
                flag "CHANGED origin/$b moved to ${live:0:7}, which is not in #$n: kept"
            elif $plan; then
                say "WOULD delete origin/$b"
            else
                g push -q origin --delete "$b" && say "DELETED origin/$b" || flag "STOP git push origin --delete $b failed"
            fi
        fi
    fi

    # Issues the PR closes, and "part of" wording that GitHub also treats as closing.
    for i in $(jq -r '.closingIssuesReferences[].number' <<<"$pr"); do
        st=$(ghm issue view "$i" --json state | jq -r .state) || { flag "STOP gh issue view $i failed"; continue; }
        [ "$st" = "OPEN" ] && flag "ISSUE #$i is still open: close it if #$n delivered it, else comment what is left"
    done
    for i in $(jq -r .body <<<"$pr" | grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?) part of #[0-9]+' | grep -oE '[0-9]+$' | sort -u); do
        flag "PARTIAL #$i: \"part of\" wording made GitHub close it. Reopen it with a comment if work is left"
    done
done

finish
