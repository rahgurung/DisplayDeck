#!/bin/zsh
# Uploads the signing and notarization credentials the Release workflow needs as GitHub Actions secrets.
# Usage: Packaging/set-release-secrets.sh <DeveloperID.p12> <AuthKey_XXXX.p8> <key-id> <issuer-id>
set -euo pipefail
P12=${1:?Usage: $0 <DeveloperID.p12> <AuthKey.p8> <key-id> <issuer-id>}
P8=${2:?}; KEY_ID=${3:?}; ISSUER_ID=${4:?}
REPO=rahgurung/DisplayDeck

read -rs "P12_PASSWORD?Password you set when exporting $P12: "; echo
openssl pkcs12 -in "$P12" -passin "pass:$P12_PASSWORD" -nokeys -legacy 2>/dev/null | grep -q "Developer ID Application" \
  || openssl pkcs12 -in "$P12" -passin "pass:$P12_PASSWORD" -nokeys 2>/dev/null | grep -q "Developer ID Application" \
  || { echo "That .p12 doesn't contain a Developer ID Application certificate, or the password is wrong." >&2; exit 1; }

base64 -i "$P12" | gh secret set DEVELOPER_ID_P12 -R $REPO
print -rn -- "$P12_PASSWORD" | gh secret set DEVELOPER_ID_P12_PASSWORD -R $REPO
gh secret set NOTARY_KEY_P8 -R $REPO < "$P8"
print -rn -- "$KEY_ID" | gh secret set NOTARY_KEY_ID -R $REPO
print -rn -- "$ISSUER_ID" | gh secret set NOTARY_ISSUER_ID -R $REPO
echo "Done. Release with: ./release.sh <version>"
