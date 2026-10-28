#!/usr/bin/env bash
# Prints the next release version from the Conventional Commit subjects since the last v* tag, or nothing if
# there are no new commits. Squash merges make each subject a PR title. Before 1.0, breaking changes bump minor.
set -euo pipefail

last=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)
if [[ -z $last ]]; then
  echo 0.1.0
  exit
fi
[[ $(git rev-list --count "$last..HEAD") -gt 0 ]] || exit 0

IFS=. read -r major minor patch <<<"${last#v}"
log=$(git log --format='%s%n%b' "$last..HEAD")
if grep -qE '^[a-z]+(\([^)]*\))?!:|^BREAKING CHANGE:' <<<"$log"; then
  bump=$([[ $major == 0 ]] && echo minor || echo major)
elif grep -qE '^feat(\([^)]*\))?:' <<<"$log"; then
  bump=minor
else
  bump=patch
fi

case $bump in
  major) echo "$((major + 1)).0.0" ;;
  minor) echo "$major.$((minor + 1)).0" ;;
  patch) echo "$major.$minor.$((patch + 1))" ;;
esac
