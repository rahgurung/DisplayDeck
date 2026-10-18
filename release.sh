#!/bin/zsh
# Starts the Release workflow on GitHub, which builds, signs, notarizes and publishes the release,
# then updates the website and the Homebrew cask. Usage: ./release.sh <version>    e.g. ./release.sh 1.1
set -euo pipefail
cd "$(dirname "$0")"

VERSION=${1:?Usage: ./release.sh <version>}
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first." >&2; exit 1; }
[[ "$(git branch --show-current)" == main ]] || { echo "Release from main." >&2; exit 1; }

git push origin main
gh workflow run release.yml --ref main -f version="$VERSION"
sleep 5
gh run watch "$(gh run list -w release.yml -L 1 --json databaseId -q '.[0].databaseId')" --exit-status
echo "Released v$VERSION: https://github.com/rahgurung/DisplayDeck/releases/tag/v$VERSION"
