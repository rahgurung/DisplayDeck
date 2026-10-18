#!/bin/zsh
# Publishes a DisplayDeck release: builds, signs and notarizes the DMG, tags it and creates the GitHub release.
# Publishing the release triggers the Pages workflow, which points the website's download links at it.
# Usage: ./release.sh <version>    e.g. ./release.sh 1.1
set -euo pipefail
cd "$(dirname "$0")"

VERSION=${1:?Usage: ./release.sh <version>}
TAG="v$VERSION"
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first." >&2; exit 1; }
[[ "$(git branch --show-current)" == main ]] || { echo "Release from main." >&2; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "$TAG already exists." >&2; exit 1; }

BUILD=$(( $(git tag -l 'v*' | wc -l) + 1 ))
VERSION=$VERSION BUILD=$BUILD ./build.sh --release

git push origin main
git tag -a "$TAG" -m "DisplayDeck $VERSION"
git push origin "$TAG"
gh release create "$TAG" "build/DisplayDeck-$VERSION.dmg" --title "DisplayDeck $VERSION" --generate-notes --verify-tag

echo "Released $TAG. The website updates in a minute or two: https://displaydeck.rahulgurung.com"
