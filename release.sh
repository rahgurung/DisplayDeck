#!/bin/zsh
# Releases happen when a release/<major>.<minor> branch is pushed (see .github/workflows/release.yml).
#   ./release.sh 1.1   on main: creates release/1.1 from main and pushes it, which releases 1.1
#   ./release.sh       on release/1.1: pushes your fixes, which releases the next patch (1.1.1, 1.1.2, ...)
# Then waits for the Release workflow and prints the result.
set -euo pipefail
cd "$(dirname "$0")"

[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first." >&2; exit 1; }
BRANCH=$(git branch --show-current)

if [[ -n "${1:-}" ]]; then
  [[ "$BRANCH" == main ]] || { echo "Start a new release line from main." >&2; exit 1; }
  BRANCH="release/$1"
  git push origin main
  git branch "$BRANCH"  # create the release branch without leaving main, so later commits don't land on it
elif [[ "$BRANCH" != release/* ]]; then
  echo "Usage: ./release.sh <version> on main, or ./release.sh on a release/* branch." >&2
  exit 1
fi

git push -u origin "$BRANCH"
SHA=$(git rev-parse "$BRANCH")
echo "Waiting for the Release workflow…"
until RUN=$(gh run list -w release.yml -c "$SHA" -L 1 --json databaseId -q '.[0].databaseId') && [[ -n "$RUN" ]]; do sleep 3; done
gh run watch "$RUN" --exit-status
gh release view --json tagName,url -q '"Released \(.tagName): \(.url)"'
