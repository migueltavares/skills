#!/usr/bin/env bash
# Tests for skills/mig-merge/scripts/wait-deploy.sh and
# skills/mig-review-findings/scripts/pr-threads.sh, against a stub gh.
#
# Usage: bash tests/merge-chain-scripts.test.sh

set -u

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wait_deploy="$repo/skills/mig-merge/scripts/wait-deploy.sh"
pr_threads="$repo/skills/mig-review-findings/scripts/pr-threads.sh"
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
has() { grep -q -- "$1" "${2:-$tmp/out}" && echo yes || echo no; }

fix="$tmp/fix"
mkdir -p "$tmp/bin" "$fix"
# The stub answers from files in $FIX, applies --jq like gh does, and logs every call.
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$FIX/calls"
filter=""; args=()
while [ $# -gt 0 ]; do
    case $1 in --jq) filter=$2; shift ;; *) args+=("$1") ;; esac
    shift
done
set -- "${args[@]}"
out() { if [ -n "$filter" ]; then jq -r "$filter"; else cat; fi; }
case "$1 $2" in
    "repo view") echo '{"nameWithOwner":"o/r"}' | out ;;
    "workflow list") out < "$FIX/workflows.json" ;;
    "run list")
        wf=""; for ((k = 1; k <= $#; k++)); do [ "${!k}" = --workflow ] && { k=$((k + 1)); wf=${!k}; }; done
        n=$(cat "$FIX/polls-$wf" 2>/dev/null || echo 0); echo $((n + 1)) > "$FIX/polls-$wf"
        delay=$(cat "$FIX/delay-$wf" 2>/dev/null || echo 99)
        if [ "$n" -ge "$delay" ]; then out < "$FIX/runs-$wf.json"; else echo '[]' | out; fi ;;
    "run watch") exit "$(cat "$FIX/watch-$3.rc")" ;;
    "run view") echo "log tail of run $3" ;;
    "api graphql")
        if [[ "$*" == *resolveReviewThread* ]]; then echo '{}'; else cat "$FIX/pages.json"; fi ;;
    "api repos/"*) cat > "$FIX/reply-$(basename "$(dirname "$2")").json"; echo '{}' ;;
    *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" FIX="$fix" WAIT_DEPLOY_INTERVAL=0

reset() { rm -f "$fix"/polls-* "$fix"/delay-* "$fix/calls"; }
wd() { bash "$wait_deploy" --sha abc --timeout 3 "$@" >"$tmp/out" 2>&1; echo $?; }

# ---------- wait-deploy.sh ----------
echo '[{"path":".github/workflows/deploy.yml","state":"active"},{"path":".github/workflows/ci.yml","state":"active"},{"path":".github/workflows/old.yml","state":"disabled_manually"}]' > "$fix/workflows.json"
echo '[{"databaseId":11,"url":"https://x/11"}]' > "$fix/runs-deploy.yml.json"
echo '[{"databaseId":22,"url":"https://x/22"}]' > "$fix/runs-ci.yml.json"

reset; echo 0 > "$fix/watch-11.rc"; echo 2 > "$fix/delay-deploy.yml"
check "deploy succeeds after polls" 0 "$(wd --workflow deploy.yml)"
check "run id printed" yes "$(has '^RUN deploy.yml 11 https://x/11')"
check "deployed printed" yes "$(has '^DEPLOYED run 11')"

reset; echo 1 > "$fix/watch-11.rc"; echo 0 > "$fix/delay-deploy.yml"
check "failed deploy exits 1" 1 "$(wd --workflow deploy.yml)"
check "failed log tail shown" yes "$(has 'log tail of run 11')"

reset
check "no run exits 3" 3 "$(wd --workflow deploy.yml --timeout 0)"
check "no run says so" yes "$(has '^NO RUN of deploy.yml')"

reset
check "disabled workflow exits 4" 4 "$(wd --workflow old.yml)"
check "disabled reported" yes "$(has '^DISABLED workflow old.yml')"
check "missing workflow exits 4" 4 "$(wd --workflow nope.yml)"

reset; echo 1 > "$fix/watch-22.rc"; echo 0 > "$fix/delay-ci.yml"; echo 0 > "$fix/delay-deploy.yml"
check "red CI exits 2" 2 "$(wd --workflow deploy.yml --after ci.yml)"
check "red CI reported" yes "$(has '^FAILED ci.yml run 22')"
check "deploy not watched after red CI" no "$(has 'run watch 11' "$fix/calls")"

reset; echo 0 > "$fix/watch-22.rc"; echo 0 > "$fix/watch-11.rc"; echo 0 > "$fix/delay-ci.yml"; echo 1 > "$fix/delay-deploy.yml"
check "green CI then deploy exits 0" 0 "$(wd --workflow deploy.yml --after ci.yml)"

# ---------- pr-threads.sh collect ----------
cat > "$fix/pages.json" <<'EOF'
[
 {"data":{"repository":{"pullRequest":{"headRefOid":"h1","reviewDecision":"CHANGES_REQUESTED",
   "reviewThreads":{"pageInfo":{"hasNextPage":true,"endCursor":"c1"},"nodes":[
     {"id":"T1","isResolved":false,"isOutdated":false,"path":"a.php","line":3,"comments":{"totalCount":1,"nodes":[{"databaseId":101,"author":{"login":"bot"},"body":"bug"}]}},
     {"id":"T2","isResolved":true,"isOutdated":false,"path":"b.php","line":4,"comments":{"totalCount":1,"nodes":[{"databaseId":102,"author":{"login":"bot"},"body":"done"}]}}]},
   "reviews":{"totalCount":2,"nodes":[{"author":{"login":"bot"},"state":"COMMENTED","body":"","commit":{"oid":"h1"}},{"author":{"login":"ann"},"state":"CHANGES_REQUESTED","body":"fix it","commit":{"oid":"h1"}}]},
   "comments":{"totalCount":1,"nodes":[{"author":{"login":"ann"},"body":"also this"}]}}}}},
 {"data":{"repository":{"pullRequest":{"headRefOid":"h1","reviewDecision":"CHANGES_REQUESTED",
   "reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":"c2"},"nodes":[
     {"id":"T3","isResolved":false,"isOutdated":true,"path":"c.php","line":9,"comments":{"totalCount":60,"nodes":[{"databaseId":103,"author":{"login":"bob"},"body":"long"}]}}]},
   "reviews":{"totalCount":2,"nodes":[]},
   "comments":{"totalCount":1,"nodes":[]}}}}}
]
EOF
bash "$pr_threads" collect 7 > "$tmp/out" 2>&1
check "collect exits 0" 0 $?
check "unresolved threads from both pages" "T1 T3" "$(jq -r '[.threads[].id] | join(" ")' "$tmp/out")"
check "empty review bodies dropped" "ann" "$(jq -r '[.reviews[].author] | join(" ")' "$tmp/out")"
check "review decision kept" CHANGES_REQUESTED "$(jq -r .reviewDecision "$tmp/out")"
check "long thread marked truncated" true "$(jq -r '.threads[] | select(.id == "T3") | .truncated' "$tmp/out")"
check "incomplete when a thread is cut" false "$(jq -r .complete "$tmp/out")"
check "repo read from gh" yes "$(has '-F o=o -F r=r -F n=7' "$fix/calls")"

# ---------- pr-threads.sh respond ----------
reset
# Reply text with words the Bash deny rules match must reach GitHub untouched.
cat > "$tmp/actions.json" <<'EOF'
[{"threadId":"T1","commentId":101,"body":"Fixed in abc1234: the API_KEY no longer reaches the log.","resolve":true},
 {"threadId":"T3","commentId":103,"body":"Out of scope, listed as a follow-up.","resolve":false}]
EOF
bash "$pr_threads" respond 7 "$tmp/actions.json" --repo o/r > "$tmp/out" 2>&1
check "respond exits 0" 0 $?
check "reply body sent intact" "Fixed in abc1234: the API_KEY no longer reaches the log." "$(jq -r .body "$fix/reply-101.json")"
check "resolved when asked" yes "$(has '^RESOLVED T1')"
check "left open when not asked" no "$(has '^RESOLVED T3')"
check "one resolve call" 1 "$(grep -c resolveReviewThread "$fix/calls")"

echo '[{"threadId":"T1","body":"no comment id"}]' > "$tmp/bad.json"
bash "$pr_threads" respond 7 "$tmp/bad.json" --repo o/r > "$tmp/out" 2>&1
check "malformed actions refused" 1 $?

echo "merge-chain scripts: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
