#!/bin/zsh
# Spike 1: run the spec queries and print only shape/cost (never values; public repo).
set -euo pipefail
cd "${0:A:h}"
w=$(gh api graphql -F query=@waiting.graphql)
print -r -- "$w" | jq '{errors, cost: .data.rateLimit.cost, nodes: (.data.search.nodes|length),
  rrPageInfo: [.data.search.nodes[].reviewRequests.pageInfo|keys],
  eventsWithId: [.data.search.nodes[].timelineItems.nodes[]|select(.__typename=="ReviewRequestedEvent")|(.id!=null)],
  eventsWithActor: [.data.search.nodes[].timelineItems.nodes[]|select(.__typename=="ReviewRequestedEvent")|(.actor!=null)]}'
login=$(print -r -- "$w" | jq -r .data.viewer.login)
gh api graphql -F query=@teams.graphql -f login="$login" | jq '{errors, cost: .data.rateLimit.cost,
  orgs: (.data.viewer.organizations.nodes|length)}'
