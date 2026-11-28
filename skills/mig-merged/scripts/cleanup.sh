#!/usr/bin/env bash
# The deterministic part of mig-merged: verify merged PRs, update the default
# branch, remove clean worktrees and delete branches that hold nothing the PR
# did not. Anything that needs judgment is reported, never acted on.
#
# Usage:
#   cleanup.sh [--plan] [--skip-worktree <path>]... <pr>...
#       Clean up after these PRs. --plan reports what would happen and deletes
#       nothing. --skip-worktree protects a checkout another thread uses, the
#       main checkout included: it is neither switched, removed, nor has its
#       branch deleted.
#   cleanup.sh
#       Sweep: list merged branches and worktrees left behind. Deletes nothing.
#
# Both read-only modes still fetch from origin. Run the script from any checkout
# of the repo; it works in the main checkout. The worktree the caller's shell
# runs in is detached, never removed: the caller removes it last, with the
# command on the LAST line.
#
# A worktree holding untracked files, or ignored files beyond dependencies,
# build output, caches and .env copies, is kept and reported.
#
# Exit codes: 0 nothing is left for the agent, 3 a line needs the agent (it is
# repeated in the final "Loose ends:" line), 1 git or gh failed (a STOP line
# says where; everything else that ran is reported too).

set -uo pipefail

die() { echo "STOP $*"; echo "Loose ends: STOP $*"; exit 1; }

plan=false
skips=()
prs=()
while [ $# -gt 0 ]; do
    case $1 in
        --plan) plan=true ;;
        --skip-worktree) [ $# -ge 2 ] || die "--skip-worktree needs a path"; skips+=("$(realpath -m "$2")"); shift ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
        *) [[ "$1" =~ ^#?[0-9]+$ ]] || die "unknown argument: $1"; prs+=("${1#\#}") ;;
    esac
    shift
done

for tool in git gh jq realpath; do
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
failed=0
detached=""
say() { echo "$*"; }
flag() { echo "$*"; loose+=("$*"); need=1; }
stop() { echo "STOP $*"; loose+=("STOP $*"); failed=1; }
finish() {
    if [ -n "$detached" ]; then
        printf 'LAST git -C %q worktree remove %q\n' "$main" "$detached"
    fi
    if [ ${#loose[@]} -eq 0 ]; then
        echo "Loose ends: none"
    else
        local joined
        joined=$(printf ' | %s' "${loose[@]}")
        echo "Loose ends:${joined# |}"
    fi
    [ "$failed" -eq 1 ] && exit 1
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

# Ignored files that are not dependencies, build output, caches or .env copies.
# Those are the only ignored files a worktree removal may delete.
precious_ignored() {
    git -C "$1" status --porcelain --ignored=matching --untracked-files=normal 2>/dev/null \
        | sed -n 's/^!! //p' \
        | grep -vE '^(vendor|node_modules|public/build|public/hot|bootstrap/cache|storage|coverage|dist|build|\.next|\.nuxt|\.turbo|\.cache|\.phpunit\.cache|\.playwright-mcp)(/|$)|^\.phpunit\.result\.cache$|^\.env(\.[A-Za-z0-9_.-]+)?$|\.log$' \
        | head -3
}

# Open PRs that use branch $1 as head or base, read live just before acting.
open_prs_on() {
    ghm pr list --state open --limit 1000 --json number,headRefName,baseRefName \
        | jq -r --arg b "$1" '[.[] | select(.headRefName == $b or .baseRefName == $b) | "#\(.number)"] | join(" ")'
}

# gh and git must point at the same repository, or the PR checks prove nothing
# about the branches being deleted.
gh_repo=$(ghm repo view --json nameWithOwner --jq .nameWithOwner) || die "gh repo view failed"
for url in "$(g remote get-url origin)" "$(g remote get-url --push origin)"; do
    slug=$(sed -E 's#^(git@[^:]+:|ssh://[^/]+/|https?://[^/]+/)##; s#\.git$##' <<<"$url")
    [ "${slug,,}" = "${gh_repo,,}" ] || die "gh uses $gh_repo but origin is $url. Run gh repo set-default, or fix origin."
done

g fetch -q --prune origin || die "git fetch origin failed in $main"
default=$(g ls-remote --symref origin HEAD | awk '/^ref:/{sub("refs/heads/", "", $2); print $2; exit}')
[ -n "$default" ] || die "cannot read origin's default branch"

# ---------- Sweep: list candidates, delete nothing ----------
if [ ${#prs[@]} -eq 0 ]; then
    open_json=$(ghm pr list --state open --limit 1000 --json number,headRefName,baseRefName) || die "gh pr list failed"
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
main_branch=$(g branch --show-current)
if is_skipped "$main"; then
    say "KEPT $main as it is: another thread uses it, so $default was not updated there"
elif $plan; then
    say "WOULD update $default in $main"
else
    if [ "$main_branch" != "$default" ]; then
        if g switch -q "$default" 2>/dev/null; then
            main_branch=$default
        else
            flag "KEPT $main on $main_branch: it can't switch to $default (uncommitted changes?)"
        fi
    fi
    if [ "$main_branch" = "$default" ]; then
        if g merge -q --ff-only "origin/$default" 2>/dev/null; then
            say "UPDATED $default in $main at $(g rev-parse --short HEAD)"
            changes=$(g status --porcelain | wc -l)
            [ "$changes" -gt 0 ] && say "NOTE $changes uncommitted files in $main came along"
        else
            flag "KEPT $default in $main: it can't fast-forward to origin/$default"
        fi
    fi
fi

# ---------- Each PR ----------
for n in "${prs[@]}"; do
    pr=$(ghm pr view "$n" --json state,headRefName,headRefOid,baseRefName,isCrossRepository,body,closingIssuesReferences) \
        || { stop "gh pr view $n failed"; continue; }
    state=$(jq -r .state <<<"$pr")
    b=$(jq -r .headRefName <<<"$pr")
    oid=$(jq -r .headRefOid <<<"$pr")
    base=$(jq -r .baseRefName <<<"$pr")
    fork=$(jq -r .isCrossRepository <<<"$pr")

    if [ "$state" != "MERGED" ]; then
        flag "SKIP #$n is $state, not merged"
        continue
    fi
    if [ "$b" = "$default" ] || [ "$fork" = true ]; then
        say "KEPT the head branch of #$n: $( [ "$fork" = true ] && echo "it lives in a fork" || echo "it is the default branch")"
        b=""
    fi

    keep=false
    if [ -n "$b" ]; then
        if ! on=$(open_prs_on "$b"); then
            stop "gh pr list failed for $b"; keep=true
        elif [ -n "$on" ]; then
            flag "OPEN $on uses $b as head or base: retarget or merge it first, then run this again for #$n"
            keep=true
        fi
        if ! has_commit "$oid" && ! g fetch -q origin "pull/$n/head"; then
            stop "#$n: cannot fetch its head $oid"; keep=true
        fi
        for ref in "refs/heads/$b" "refs/remotes/origin/$b"; do
            g show-ref -q --verify "$ref" || continue
            if ! late=$(g log --format=%h "$oid..$ref"); then
                stop "git log $oid..$ref failed"; keep=true; continue
            fi
            [ -z "$late" ] && continue
            flag "LATE ${ref#refs/*/} has $(wc -l <<<"$late") commits not in #$n: $(echo $late)"
            keep=true
        done
        if [ "$main_branch" = "$b" ]; then
            say "KEPT $b: the main checkout $main is on it"
            keep=true
        fi
    fi

    # Worktrees on the branch, only when the branch itself can go.
    if [ -n "$b" ] && [ "$keep" = false ]; then
        while read -r path; do
            [ -n "$path" ] || continue
            path=$(realpath "$path")
            [ "$path" = "$main" ] && continue
            extra=$(precious_ignored "$path")
            if is_skipped "$path"; then
                say "KEPT worktree $path: another thread uses it"
                keep=true
            elif [ -n "$(git -C "$path" status --porcelain)" ]; then
                flag "DIRTY $path has uncommitted changes: commit or drop them"
                keep=true
            elif [ -n "$extra" ]; then
                flag "DIRTY $path holds ignored files such as $(echo $extra): keep or delete them by hand"
                keep=true
            elif [ "$path" = "$caller" ]; then
                if $plan; then
                    say "WOULD detach $path, this shell's worktree"
                elif git -C "$path" switch -q --detach "origin/$default"; then
                    say "DETACHED $path, this shell's worktree"
                    detached=$path
                else
                    stop "cannot detach $path"; keep=true
                fi
            elif $plan; then
                say "WOULD remove worktree $path"
            elif g worktree remove "$path"; then
                say "REMOVED worktree $path"
            else
                stop "git worktree remove $path failed"; keep=true
            fi
        done < <(worktrees_on "$b")
    fi

    # Branches, only when nothing above asked to keep them.
    if [ -n "$b" ] && [ "$keep" = false ]; then
        if tip=$(g rev-parse -q --verify "refs/heads/$b"); then
            if [ -n "$(worktrees_on "$b")" ]; then
                say "KEPT local $b: a worktree still has it checked out"
            elif ! g merge-base --is-ancestor "$tip" "$oid"; then
                flag "LATE $b: not contained in #$n, kept"
            elif $plan; then
                say "WOULD delete local $b"
            elif g update-ref -d "refs/heads/$b" "$tip"; then
                # update-ref deletes only while the branch still points at the tip checked above.
                say "DELETED local $b"
            else
                flag "CHANGED local $b moved while this ran: kept"
            fi
        fi
        # Read the live tip and open PRs again: a push or a new PR can land after the checks above.
        live=$(g ls-remote --exit-code --heads origin "refs/heads/$b"); rc=$?
        if [ "$rc" -eq 2 ]; then
            say "GONE origin/$b: GitHub already removed it"
        elif [ "$rc" -ne 0 ]; then
            stop "git ls-remote origin failed for $b"
        else
            live=$(cut -f1 <<<"$live")
            if ! has_commit "$live" || ! g merge-base --is-ancestor "$live" "$oid"; then
                flag "CHANGED origin/$b moved to ${live:0:7}, which is not in #$n: kept"
            elif ! on=$(open_prs_on "$b"); then
                stop "gh pr list failed for $b"
            elif [ -n "$on" ]; then
                flag "OPEN $on uses $b as head or base: kept"
            elif $plan; then
                say "WOULD delete origin/$b"
            elif g push -q origin --delete "$b"; then
                say "DELETED origin/$b"
            else
                stop "git push origin --delete $b failed"
            fi
        fi
    fi

    # Issues the PR closes, named by URL so a cross-repo reference stays exact.
    while read -r url; do
        [ -n "$url" ] || continue
        if ! st=$(ghm issue view "$url" --json state | jq -r .state); then
            stop "gh issue view $url failed"; continue
        fi
        [ "$st" = "OPEN" ] && flag "ISSUE $url is still open: close it if #$n delivered it, else comment what is left"
    done < <(jq -r '.closingIssuesReferences[].url' <<<"$pr")
    # "Closes part of #N" also closes #N, but only on a merge into the default branch.
    if [ "$base" = "$default" ]; then
        for i in $(jq -r .body <<<"$pr" | grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?) part of #[0-9]+' | grep -oE '[0-9]+$' | sort -u); do
            st=$(ghm issue view "$i" --json state | jq -r .state) || { stop "gh issue view $i failed"; continue; }
            [ "$st" = "CLOSED" ] && flag "PARTIAL #$i was closed by \"part of\" wording in #$n. Reopen it with a comment if work is left"
        done
    fi
done

finish
