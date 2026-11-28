#!/usr/bin/env bash
# Tests for skills/mig-merged/scripts/cleanup.sh.
# Builds a throwaway origin and clone in a temp directory, with a stub gh on PATH.
#
# Usage: bash tests/mig-merged-cleanup.test.sh

set -u

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo/skills/mig-merged/scripts/cleanup.sh"
tmp=$(mktemp -d)
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

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
fix="$tmp/fix"
mkdir -p "$tmp/bin" "$fix"
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
    "pr view") cat "$FIX/pr-$3.json" ;;
    "pr list") if [[ " $* " == *" merged "* ]]; then cat "$FIX/merged.json"; else cat "$FIX/open.json"; fi ;;
    "issue view") cat "$FIX/issue-$3.json" ;;
    *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" FIX="$fix"

git init -q --bare -b main "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/main" 2>/dev/null
cd "$tmp/main"
git commit -q --allow-empty -m init
git push -q origin main

# branch <name>: one commit on a new branch from main, pushed; prints its sha.
branch() {
    git switch -q -c "$1" main
    git commit -q --allow-empty -m "$1"
    git push -q origin "$1"
    git switch -q main
    git rev-parse "$1"
}
pr() { # pr <n> <state> <branch> <oid> [closing issue]
    local issues="[]"
    [ -n "${5:-}" ] && issues="[{\"number\":$5}]"
    printf '{"state":"%s","headRefName":"%s","headRefOid":"%s","isCrossRepository":false,"body":"%s","closingIssuesReferences":%s}\n' \
        "$2" "$3" "$4" "${6:-}" "$issues" > "$fix/pr-$1.json"
}

a=$(branch feat-a); pr 1 MERGED feat-a "$a"; git worktree add -q "$tmp/wt-a" feat-a
b=$(branch feat-b); pr 2 MERGED feat-b "$b"
git switch -q feat-b; git commit -q --allow-empty -m late; git push -q origin feat-b; git switch -q main
c=$(branch feat-c); pr 3 MERGED feat-c "$c"
d=$(branch feat-d); pr 4 MERGED feat-d "$d"; git worktree add -q "$tmp/wt-d" feat-d; touch "$tmp/wt-d/wip"
pr 5 OPEN feat-x 0000000000000000000000000000000000000000
e=$(branch feat-e); pr 6 MERGED feat-e "$e" 60 "Closes part of #61"
echo '{"state":"OPEN"}' > "$fix/issue-60.json"
f=$(branch feat-f); pr 7 MERGED feat-f "$f"; git worktree add -q "$tmp/wt-f" feat-f
gg=$(branch feat-g); pr 8 MERGED feat-g "$gg"; git worktree add -q "$tmp/wt-g" feat-g
h=$(branch feat-h); pr 9 MERGED feat-h "$h"
i=$(branch feat-i); pr 10 MERGED feat-i "$i"
echo '[{"number":30,"headRefName":"feat-z","baseRefName":"feat-c"},{"number":11,"headRefName":"feat-i","baseRefName":"main"}]' > "$fix/open.json"
printf '[{"number":9,"headRefName":"feat-h","headRefOid":"%s"},{"number":2,"headRefName":"feat-b","headRefOid":"%s"},{"number":3,"headRefName":"feat-c","headRefOid":"%s"}]\n' "$h" "$b" "$c" > "$fix/merged.json"

run() { (cd "$1" && shift && bash "$script" "$@") >"$tmp/out" 2>&1; echo $?; }
local_has() { git -C "$tmp/main" show-ref -q --verify "refs/heads/$1" && echo yes || echo no; }
remote_has() { [ -n "$(git -C "$tmp/main" ls-remote --heads origin "$1")" ] && echo yes || echo no; }

# A plain merged PR: worktree, local and remote branch go.
check "merged PR exits 0" 0 "$(run "$tmp/main" 1)"
check "worktree removed" no "$([ -d "$tmp/wt-a" ] && echo yes || echo no)"
check "local branch deleted" no "$(local_has feat-a)"
check "remote branch deleted" no "$(remote_has feat-a)"
check "loose ends none" yes "$(has 'Loose ends: none')"

# Commits pushed after the merge keep the branch.
check "late commit exits 3" 3 "$(run "$tmp/main" 2)"
check "late commit reported" yes "$(has '^LATE origin/feat-b')"
check "late branch kept on origin" yes "$(remote_has feat-b)"

# A PR stacked on the branch keeps it until it is retargeted.
check "stacked exits 3" 3 "$(run "$tmp/main" 3)"
check "stacked reported" yes "$(has '^STACKED #30 on feat-c')"
check "stacked base kept" yes "$(remote_has feat-c)"

# A dirty worktree keeps the worktree and its branch.
check "dirty exits 3" 3 "$(run "$tmp/main" 4)"
check "dirty reported" yes "$(has "^DIRTY $tmp/wt-d")"
check "dirty worktree kept" yes "$([ -f "$tmp/wt-d/wip" ] && echo yes || echo no)"
check "dirty branch kept" yes "$(local_has feat-d)"

# A PR that is not merged is skipped.
check "open PR exits 3" 3 "$(run "$tmp/main" 5)"
check "open PR skipped" yes "$(has '^SKIP #5 is OPEN')"

# An open closing issue and "part of" wording are reported; the branch still goes.
check "open issue exits 3" 3 "$(run "$tmp/main" 6)"
check "open issue reported" yes "$(has '^ISSUE #60 is still open')"
check "part-of wording reported" yes "$(has '^PARTIAL #61')"
check "branch deleted despite issue" no "$(remote_has feat-e)"

# A worktree another thread uses is kept, with its branch.
check "skipped worktree exits 0" 0 "$(run "$tmp/main" --skip-worktree "$tmp/wt-f" 7)"
check "skipped worktree kept" yes "$([ -d "$tmp/wt-f" ] && echo yes || echo no)"
check "skipped worktree branch kept" yes "$(local_has feat-f)"

# The caller's own worktree is detached, not removed, and named for the caller.
check "own worktree exits 0" 0 "$(run "$tmp/wt-g" 8)"
check "own worktree still there" yes "$([ -d "$tmp/wt-g" ] && echo yes || echo no)"
check "own worktree detached" "" "$(git -C "$tmp/wt-g" branch --show-current)"
check "own worktree removal named" yes "$(has "^LAST git -C $tmp/main worktree remove $tmp/wt-g")"
check "own worktree branch deleted" no "$(remote_has feat-g)"

# A reused branch name with an open PR is left alone.
check "reused name exits 0" 0 "$(run "$tmp/main" 10)"
check "reused name kept" yes "$(remote_has feat-i)"

# --plan changes nothing.
check "plan exits 0" 0 "$(run "$tmp/main" --plan 9)"
check "plan says would delete" yes "$(has '^WOULD delete origin/feat-h')"
check "plan keeps branch" yes "$(remote_has feat-h)"

# The sweep lists what is left and changes nothing.
check "sweep exits 0" 0 "$(run "$tmp/main")"
check "sweep lists feat-h" yes "$(has '^CANDIDATE #9 feat-h: local, origin')"
check "sweep skips late branch" no "$(has 'CANDIDATE #2')"
check "sweep marks stacked base" yes "$(has '^CANDIDATE #3 feat-c: .*base of open #30')"
check "sweep keeps feat-h" yes "$(remote_has feat-h)"

echo "mig-merged cleanup: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
