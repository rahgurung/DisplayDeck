#!/bin/bash
# Prints the version to release for a release line, based on the existing v* tags.
#   release-version.sh 1.1      -> 1.1 if v1.1 doesn't exist yet, otherwise the next patch (1.1.1, 1.1.2, ...)
#   release-version.sh 1.1.3    -> 1.1.3, or an error if v1.1.3 already exists
set -euo pipefail
BASE=${1:?Usage: release-version.sh <major.minor[.patch]>}

if [[ ! "$BASE" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Release branch must be named release/<major>.<minor> or release/<major>.<minor>.<patch>, e.g. release/1.1" >&2
  exit 1
fi

if ! git rev-parse -q --verify "refs/tags/v$BASE" >/dev/null; then
  echo "$BASE"
  exit 0
fi

if [[ "$BASE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "v$BASE is already released. Use a new release branch for the next version." >&2
  exit 1
fi

LAST=0
for TAG in $(git tag -l "v$BASE.*"); do
  PATCH=${TAG#"v$BASE."}
  if [[ "$PATCH" =~ ^[0-9]+$ ]] && (( PATCH > LAST )); then
    LAST=$PATCH
  fi
done
echo "$BASE.$((LAST + 1))"
