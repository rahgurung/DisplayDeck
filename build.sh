#!/bin/zsh
# Builds DisplayDeck.app into ./build.
# Usage: ./build.sh [--install | --release]
#   --install  copy the app to /Applications and launch it
#   --release  sign with Developer ID, package build/DisplayDeck-$VERSION.dmg, notarize and staple
#              (needs a "Developer ID Application" certificate and a notarytool profile named
#              by $NOTARY_PROFILE, default "DisplayDeck")
# Set TELEMETRYDECK_APP_ID (or put it in release.env) to enable anonymous usage stats; non-release builds
# send them as test signals.
# In-app updates (Sparkle) are only enabled in release builds, or when SPARKLE_FEED_URL is set for testing, so
# development builds never replace themselves with a release.
set -euo pipefail
cd "$(dirname "$0")"

# Local, untracked settings such as TELEMETRYDECK_APP_ID.
[[ -f release.env ]] && source release.env
# Releases pass VERSION; local builds take it from the latest v* tag, e.g. 1.2.1, or 1.2.1-3-gb49ee3b after it.
VERSION=${VERSION:-$(git describe --tags --match 'v*' 2>/dev/null | sed 's/^v//' || true)}
VERSION=${VERSION:-1.0}
TELEMETRYDECK_APP_ID=${TELEMETRYDECK_APP_ID:-}
[[ "${1:-}" == "--release" ]] && TEST_MODE=false || TEST_MODE=true
BUILD=${BUILD:-1}
NOTARY_PROFILE=${NOTARY_PROFILE:-DisplayDeck}
APP=build/DisplayDeck.app

SPARKLE_VERSION=2.10.0
SPARKLE_SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
SPARKLE_PUBLIC_KEY=oYMZ37MpCqT1DD4Pr09SAQpdbVdtvbP3w/YYpUN+mXI=
SPARKLE=.sparkle/Sparkle-$SPARKLE_VERSION
if [[ "${1:-}" == "--release" ]]; then
  SPARKLE_FEED_URL=${SPARKLE_FEED_URL:-https://displaydeck.rahulgurung.com/appcast.xml}
fi
SPARKLE_FEED_URL=${SPARKLE_FEED_URL:-}

# Download Sparkle once and verify it against the pinned checksum.
if [[ ! -d "$SPARKLE/Sparkle.framework" ]]; then
  mkdir -p .sparkle
  ARCHIVE=.sparkle/Sparkle-$SPARKLE_VERSION.tar.xz
  curl -fsSL -o "$ARCHIVE" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  echo "$SPARKLE_SHA256  $ARCHIVE" | shasum -a 256 -c - >/dev/null || { echo "Sparkle checksum mismatch" >&2; rm -f "$ARCHIVE"; exit 1; }
  mkdir -p "$SPARKLE" && tar -xJf "$ARCHIVE" -C "$SPARKLE" && rm "$ARCHIVE"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

swiftc -O -parse-as-library -swift-version 5 \
  -target arm64-apple-macos14.0 \
  -framework IOKit -framework AppKit -framework SwiftUI -framework ServiceManagement \
  -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  Sources/*.swift -o "$APP/Contents/MacOS/DisplayDeck"

[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Embed Sparkle. Its XPC services are only needed by sandboxed apps, so leave them out.
FRAMEWORK=$APP/Contents/Frameworks/Sparkle.framework
ditto "$SPARKLE/Sparkle.framework" "$FRAMEWORK"
rm -rf "$FRAMEWORK/XPCServices" "$FRAMEWORK/Versions/B/XPCServices"

# Signs Sparkle's helpers, then the framework, then the app (codesign needs nested code signed first).
sign_app() {
  local identity=$1; shift
  for item in "$FRAMEWORK/Versions/B/Autoupdate" "$FRAMEWORK/Versions/B/Updater.app" "$FRAMEWORK" "$APP"; do
    codesign --force --sign "$identity" "$@" "$item"
  done
}

SPARKLE_KEYS=""
if [[ -n "$SPARKLE_FEED_URL" ]]; then
  SPARKLE_KEYS="<key>SUFeedURL</key><string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>DisplayDeck</string>
  <key>CFBundleDisplayName</key><string>DisplayDeck</string>
  <key>CFBundleIdentifier</key><string>com.rahulgurung.DisplayDeck</string>
  <key>CFBundleExecutable</key><string>DisplayDeck</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Rahul Gurung. MIT License.</string>
  <key>TelemetryDeckAppID</key><string>$TELEMETRYDECK_APP_ID</string>
  <key>TelemetryDeckTestMode</key><$TEST_MODE/>
  $SPARKLE_KEYS
</dict>
</plist>
PLIST

if [[ "${1:-}" == "--release" ]]; then
  IDENTITY=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
  [[ -n "$IDENTITY" ]] || { echo "No 'Developer ID Application' certificate in the keychain" >&2; exit 1; }
  sign_app "$IDENTITY" --options runtime --timestamp
  codesign --verify --deep --strict --verbose=2 "$APP"

  DMG=build/DisplayDeck-$VERSION.dmg
  STAGE=build/dmg
  rm -rf "$STAGE" "$DMG"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname DisplayDeck -srcfolder "$STAGE" -ov -format UDZO "$DMG"
  rm -rf "$STAGE"
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"

  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
  [[ -n "${NOTARY_KEYCHAIN:-}" ]] && NOTARY_ARGS+=(--keychain "$NOTARY_KEYCHAIN")
  xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
  echo "Released $DMG"
  shasum -a 256 "$DMG"
  exit 0
fi

# Sign with a stable identity when one exists so macOS keeps the Accessibility grant across rebuilds;
# ad-hoc signatures change with every build and invalidate it.
DEV_IDENTITY=$(security find-identity -v -p codesigning | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"' || true)
sign_app "${DEV_IDENTITY:--}"
echo "Built $APP (signed ${DEV_IDENTITY:-ad-hoc}${SPARKLE_FEED_URL:+, updates from $SPARKLE_FEED_URL})"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x DisplayDeck 2>/dev/null || true
  rm -rf /Applications/DisplayDeck.app
  cp -R "$APP" /Applications/
  open /Applications/DisplayDeck.app
  echo "Installed to /Applications"
fi
