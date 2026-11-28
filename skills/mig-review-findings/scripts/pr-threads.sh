#!/usr/bin/env bash
# Reads and answers a PR's review threads for mig-review-findings and the
# mig-merge gate.
#
# Usage:
#   pr-threads.sh collect <pr> [--repo <owner/repo>]
#       Prints one JSON object: headRefOid, reviewDecision, the unresolved
#       threads (every page), review bodies that say something, PR comments,
#       and "complete": false with the reasons when anything was cut short.
#   pr-threads.sh respond <pr> <actions.json> [--repo <owner/repo>]
#       Replies to threads and resolves them. The file holds
#       [{"threadId": "PRRT_...", "body": "...", "resolve": true}].
#       Write it with a file tool: reply text never passes through the shell.
#       The whole file is checked before anything is sent.
#
# Exit codes: 0 done, 1 a gh call failed or the input was wrong.

set -uo pipefail

die() { echo "ERROR $*" >&2; exit 1; }
command -v gh >/dev/null || die "gh is not installed"
command -v jq >/dev/null || die "jq is not installed"

cmd=${1:-}; pr=${2:-}
[ -n "$cmd" ] && [ -n "$pr" ] || { sed -n '2,15p' "$0"; exit 1; }
shift 2
file=""
repo=""
while [ $# -gt 0 ]; do
    case $1 in
        --repo) [ $# -ge 2 ] && [ -n "$2" ] || die "--repo needs <owner/repo>"; repo=$2; shift ;;
        *) [ -z "$file" ] && file=$1 || die "unknown argument: $1" ;;
    esac
    shift
done
pr=${pr#\#}
[[ "$pr" =~ ^[0-9]+$ ]] || die "PR number expected, got $pr"
if [ -z "$repo" ]; then
    repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || die "cannot tell the repo; pass --repo"
fi
owner=${repo%%/*}
name=${repo#*/}

case $cmd in
collect)
    query='query($o:String!,$r:String!,$n:Int!,$endCursor:String){repository(owner:$o,name:$r){pullRequest(number:$n){
  headRefOid reviewDecision
  reviewThreads(first:100, after:$endCursor){pageInfo{hasNextPage endCursor}
    nodes{id isResolved isOutdated path line comments(first:50){totalCount nodes{databaseId author{login} authorAssociation body}}}}
  reviews(last:50){totalCount nodes{author{login} authorAssociation state body commit{oid}}}
  comments(last:100){totalCount nodes{author{login} authorAssociation body}}
}}}'
    pages=$(gh api graphql --paginate --slurp -f o="$owner" -f r="$name" -F n="$pr" -f query="$query") || die "gh api graphql failed"
    jq '
      [.[].data.repository.pullRequest] as $p
      | ($p[0]) as $first
      | ([$p[].reviewThreads.nodes[] | select(.isResolved | not)]) as $open
      | {
          headRefOid: $first.headRefOid,
          reviewDecision: $first.reviewDecision,
          threads: [$open[] | {id, path, line, isOutdated,
                     comments: [.comments.nodes[] | {databaseId, author: .author.login, association: .authorAssociation, body}],
                     truncated: (.comments.totalCount > (.comments.nodes | length))}],
          reviews: [$first.reviews.nodes[] | select(.body != "") | {author: .author.login, association: .authorAssociation, state, body, commit: .commit.oid}],
          comments: [$first.comments.nodes[] | {author: .author.login, association: .authorAssociation, body}],
          truncated: ([
              (if ($p | last | .reviewThreads.pageInfo.hasNextPage) then "the thread list stopped before its last page" else empty end),
              (if ([$p[].headRefOid] | unique | length) > 1 then "the head moved while the threads were read" else empty end),
              ($open[] | select(.comments.totalCount > (.comments.nodes | length)) | "thread \(.id) has more than 50 comments"),
              (if $first.reviews.totalCount > 50 then "only the last 50 of \($first.reviews.totalCount) reviews" else empty end),
              (if $first.comments.totalCount > 100 then "only the last 100 of \($first.comments.totalCount) PR comments" else empty end)
            ])
        }
      | .complete = (.truncated | length == 0)' <<<"$pages"
    ;;
respond)
    [ -n "$file" ] && [ -f "$file" ] || die "respond needs an actions file"
    jq -e 'type == "array" and all(.[]; (.threadId | type == "string" and test("^[A-Za-z0-9_-]+$"))
            and (.body | type == "string" and length > 0) and ((.resolve // false) | type == "boolean"))' "$file" >/dev/null \
        || die "$file must be an array of {threadId, body, resolve: true or false}"
    failed=0
    count=$(jq length "$file")
    for ((k = 0; k < count; k++)); do
        item=$(jq -c ".[$k]" "$file")
        thread=$(jq -r .threadId <<<"$item")
        body=$(jq -r .body <<<"$item")
        # The reply is keyed by the thread, like the resolve, so both act on the same conversation.
        if gh api graphql -f id="$thread" -f body="$body" \
            -f query='mutation($id:ID!,$body:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$id,body:$body}){comment{id}}}' >/dev/null; then
            echo "REPLIED $thread"
        else
            echo "FAILED reply $thread"; failed=1; continue
        fi
        if [ "$(jq '.resolve // false' <<<"$item")" = true ]; then
            if gh api graphql -f id="$thread" -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}' >/dev/null; then
                echo "RESOLVED $thread"
            else
                echo "FAILED resolve $thread"; failed=1
            fi
        fi
    done
    exit $failed
    ;;
*) die "unknown command: $cmd" ;;
esac
