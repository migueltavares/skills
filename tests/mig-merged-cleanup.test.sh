#!/usr/bin/env bash
# Tests for skills/mig-merged/scripts/cleanup.sh.
# Builds a throwaway origin and clone in a temp directory, with a stub gh on PATH.
#
# Usage: bash tests/mig-merged-cleanup.test.sh

set -u

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo/skills/mig-merged/scripts/cleanup.sh"
tmp=$(realpath "$(mktemp -d)")
trap 'rm -rf "$tmp"' EXIT

pass=0 fail=0
check() {
    local label=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $label (expected $expected, got $actual)"
        sed 's/^/    /' "$tmp/out"
    fi
}
has() { grep -q -- "$1" "$tmp/out" && echo yes || echo no; }
exists() { [ -e "$1" ] && echo yes || echo no; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
fix="$tmp/fix"
mkdir -p "$tmp/bin" "$fix"
# The stub answers from files in $FIX and applies --jq like gh does. Its repo is
# whatever origin points at, unless $FIX/repo names another one.
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
filter=""; args=()
while [ $# -gt 0 ]; do
    case $1 in --jq) filter=$2; shift ;; *) args+=("$1") ;; esac
    shift
done
set -- "${args[@]}"
out() { if [ -n "$filter" ]; then jq -r "$filter"; else cat; fi; }
case "$1 $2" in
    "repo view")
        name=$(cat "$FIX/repo" 2>/dev/null || git remote get-url origin | sed 's/\.git$//')
        jq -n --arg n "$name" '{nameWithOwner: $n}' | out ;;
    "pr view") out < "$FIX/pr-$3.json" ;;
    "pr list") if [[ " $* " == *" merged "* ]]; then out < "$FIX/merged.json"; else out < "$FIX/open.json"; fi ;;
    "issue view") out < "$FIX/issue-$(basename "$3").json" ;;
    *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" FIX="$fix"

git init -q --bare -b main "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/main" 2>/dev/null
cd "$tmp/main"
printf 'vendor/\n.env\nnotes.local\n' > .gitignore
git add .gitignore && git commit -q -m init
git push -q origin main

# branch <name>: one commit on a new branch from main, pushed; prints its sha.
branch() {
    git switch -q -c "$1" main
    git commit -q --allow-empty -m "$1"
    git push -q origin "$1"
    git switch -q main
    git rev-parse "$1"
}
pr() { # pr <n> <state> <branch> <oid> [closing issue number] [body]
    local issues="[]"
    [ -n "${5:-}" ] && issues="[{\"number\":$5,\"url\":\"https://github.com/o/r/issues/$5\"}]"
    jq -n --arg s "$2" --arg b "$3" --arg o "$4" --arg body "${6:-}" --argjson i "$issues" \
        '{state: $s, headRefName: $b, headRefOid: $o, baseRefName: "main", isCrossRepository: false, body: $body, closingIssuesReferences: $i}' \
        > "$fix/pr-$1.json"
}
wt() { git worktree add -q "$1" "$2"; }

a=$(branch feat-a); pr 1 MERGED feat-a "$a"; wt "$tmp/wt a" feat-a
mkdir -p "$tmp/wt a/vendor"; touch "$tmp/wt a/vendor/lib.php" "$tmp/wt a/.env"
b=$(branch feat-b); pr 2 MERGED feat-b "$b"; wt "$tmp/wt-b" feat-b
git -C "$tmp/wt-b" commit -q --allow-empty -m late
c=$(branch feat-c); pr 3 MERGED feat-c "$c"; wt "$tmp/wt-c" feat-c
d=$(branch feat-d); pr 4 MERGED feat-d "$d"; wt "$tmp/wt-d" feat-d; touch "$tmp/wt-d/wip"
pr 5 OPEN feat-x 0000000000000000000000000000000000000000
e=$(branch feat-e); pr 6 MERGED feat-e "$e" 60 "Closes part of #61"
echo '{"state":"OPEN"}' > "$fix/issue-60.json"; echo '{"state":"CLOSED"}' > "$fix/issue-61.json"
f=$(branch feat-f); pr 7 MERGED feat-f "$f"; wt "$tmp/wt-f" feat-f
gg=$(branch feat-g); pr 8 MERGED feat-g "$gg"; wt "$tmp/wt g" feat-g
h=$(branch feat-h); pr 9 MERGED feat-h "$h"
i=$(branch feat-i); pr 10 MERGED feat-i "$i"
j=$(branch feat-j); pr 12 MERGED feat-j "$j"; wt "$tmp/wt-j" feat-j; touch "$tmp/wt-j/notes.local"
k=$(branch feat-k); pr 13 MERGED feat-k "$k"
git worktree add -q --detach "$tmp/wt-detached" main
mv "$tmp/wt-detached" "$tmp/moved-away"   # an unreachable checkout that prune would forget
echo '[{"number":30,"headRefName":"feat-z","baseRefName":"feat-c"},{"number":11,"headRefName":"feat-i","baseRefName":"main"}]' > "$fix/open.json"
printf '[{"number":9,"headRefName":"feat-h","headRefOid":"%s"},{"number":2,"headRefName":"feat-b","headRefOid":"%s"},{"number":3,"headRefName":"feat-c","headRefOid":"%s"}]\n' "$h" "$b" "$c" > "$fix/merged.json"

run() { (cd "$1" && shift && bash "$script" "$@") >"$tmp/out" 2>&1; echo $?; }
local_has() { git -C "$tmp/main" show-ref -q --verify "refs/heads/$1" && echo yes || echo no; }
remote_has() { [ -n "$(git -C "$tmp/main" ls-remote --heads origin "$1")" ] && echo yes || echo no; }

# A plain merged PR: worktree, local and remote branch go. Dependencies and .env copies don't block it.
check "merged PR exits 0" 0 "$(run "$tmp/main" 1)"
check "worktree removed" no "$(exists "$tmp/wt a")"
check "local branch deleted" no "$(local_has feat-a)"
check "remote branch deleted" no "$(remote_has feat-a)"
check "loose ends none" yes "$(has 'Loose ends: none')"

# A commit made after the merge keeps the worktree and both branches.
check "late commit exits 3" 3 "$(run "$tmp/main" 2)"
check "late commit reported" yes "$(has '^LATE feat-b')"
check "late worktree kept" yes "$(exists "$tmp/wt-b")"
check "late local branch kept" yes "$(local_has feat-b)"
check "late remote branch kept" yes "$(remote_has feat-b)"

# A PR stacked on the branch keeps it, and its worktree, until it is retargeted.
check "stacked exits 3" 3 "$(run "$tmp/main" 3)"
check "stacked reported" yes "$(has '^OPEN #30 uses feat-c')"
check "stacked worktree kept" yes "$(exists "$tmp/wt-c")"
check "stacked base kept" yes "$(remote_has feat-c)"

# Uncommitted work keeps the worktree and its branch.
check "dirty exits 3" 3 "$(run "$tmp/main" 4)"
check "dirty reported" yes "$(has "^DIRTY $tmp/wt-d")"
check "dirty worktree kept" yes "$(exists "$tmp/wt-d/wip")"
check "dirty branch kept" yes "$(local_has feat-d)"

# An ignored file that isn't a dependency, build output or .env copy keeps the worktree.
check "ignored notes exit 3" 3 "$(run "$tmp/main" 12)"
check "ignored notes reported" yes "$(has "^DIRTY $tmp/wt-j holds ignored files such as notes.local")"
check "ignored notes kept" yes "$(exists "$tmp/wt-j/notes.local")"

# A PR that is not merged is skipped.
check "open PR exits 3" 3 "$(run "$tmp/main" 5)"
check "open PR skipped" yes "$(has '^SKIP #5 is OPEN')"

# An open closing issue and "part of" wording are reported; the branch still goes.
check "open issue exits 3" 3 "$(run "$tmp/main" 6)"
check "open issue named by URL" yes "$(has '^ISSUE https://github.com/o/r/issues/60 is still open')"
check "part-of wording reported" yes "$(has '^PARTIAL #61 was closed')"
check "branch deleted despite issue" no "$(remote_has feat-e)"

# A worktree another thread uses is kept, with its branch.
check "skipped worktree exits 0" 0 "$(run "$tmp/main" --skip-worktree "$tmp/wt-f" 7)"
check "skipped worktree kept" yes "$(exists "$tmp/wt-f")"
check "skipped worktree branch kept" yes "$(local_has feat-f)"

# The caller's own worktree is detached, not removed, and named for the caller with quoting.
check "own worktree exits 0" 0 "$(run "$tmp/wt g" 8)"
check "own worktree still there" yes "$(exists "$tmp/wt g")"
check "own worktree detached" "" "$(git -C "$tmp/wt g" branch --show-current)"
check "own worktree branch deleted" no "$(remote_has feat-g)"
last=$(sed -n 's/^LAST //p' "$tmp/out")
(cd "$tmp" && eval "$last") 2>/dev/null
check "LAST command removes a path with spaces" no "$(exists "$tmp/wt g")"

# A reused branch name with an open PR is left alone.
check "reused name exits 3" 3 "$(run "$tmp/main" 10)"
check "reused name kept" yes "$(remote_has feat-i)"

# --plan deletes nothing.
check "plan exits 0" 0 "$(run "$tmp/main" --plan 9)"
check "plan says would delete" yes "$(has '^WOULD delete origin/feat-h')"
check "plan keeps branch" yes "$(remote_has feat-h)"

# A skipped main checkout is not switched, and its branch stays.
git -C "$tmp/main" switch -q feat-k
check "skipped main exits 0" 0 "$(run "$tmp/wt-f" --skip-worktree "$tmp/main" 13)"
check "skipped main not switched" feat-k "$(git -C "$tmp/main" branch --show-current)"
check "skipped main's branch kept" yes "$(remote_has feat-k)"
git -C "$tmp/main" switch -q main

# No repo-wide prune: an unrelated detached worktree keeps its registration.
check "detached worktree still registered" yes "$(git -C "$tmp/main" worktree list | grep -q "$tmp/wt-detached" && echo yes || echo no)"

# The sweep lists what is left and deletes nothing.
check "sweep exits 0" 0 "$(run "$tmp/main")"
check "sweep lists feat-h" yes "$(has '^CANDIDATE #9 feat-h: local, origin')"
check "sweep skips late branch" no "$(has 'CANDIDATE #2')"
check "sweep marks stacked base" yes "$(has '^CANDIDATE #3 feat-c: .*base of open #30')"
check "sweep keeps feat-h" yes "$(remote_has feat-h)"

# gh pointing at another repo than origin stops everything.
echo other/repo > "$fix/repo"
check "repo mismatch exits 1" 1 "$(run "$tmp/main" 9)"
check "repo mismatch named" yes "$(has '^STOP gh uses other/repo')"
check "repo mismatch deletes nothing" yes "$(remote_has feat-h)"
rm "$fix/repo"

echo "mig-merged cleanup: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
