#!/bin/zsh
# Builds DisplayDeck.app into ./build.
# Usage: ./build.sh [--install | --release]
#   --install  copy the app to /Applications and launch it
#   --release  sign with Developer ID, package build/DisplayDeck-$VERSION.dmg, notarize and staple
#              (needs a "Developer ID Application" certificate and a notarytool profile named
#              by $NOTARY_PROFILE, default "DisplayDeck")
# Set TELEMETRYDECK_APP_ID (or put it in release.env) to enable anonymous usage stats; non-release builds
# send them as test signals.
set -euo pipefail
cd "$(dirname "$0")"

# Local, untracked settings such as TELEMETRYDECK_APP_ID.
[[ -f release.env ]] && source release.env
VERSION=${VERSION:-1.0}
TELEMETRYDECK_APP_ID=${TELEMETRYDECK_APP_ID:-}
[[ "${1:-}" == "--release" ]] && TEST_MODE=false || TEST_MODE=true
BUILD=${BUILD:-1}
NOTARY_PROFILE=${NOTARY_PROFILE:-DisplayDeck}
APP=build/DisplayDeck.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -parse-as-library -swift-version 5 \
  -target arm64-apple-macos14.0 \
  -framework IOKit -framework AppKit -framework SwiftUI -framework ServiceManagement \
  Sources/*.swift -o "$APP/Contents/MacOS/DisplayDeck"

[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

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
</dict>
</plist>
PLIST

if [[ "${1:-}" == "--release" ]]; then
  IDENTITY=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
  [[ -n "$IDENTITY" ]] || { echo "No 'Developer ID Application' certificate in the keychain" >&2; exit 1; }
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"

  DMG=build/DisplayDeck-$VERSION.dmg
  STAGE=build/dmg
  rm -rf "$STAGE" "$DMG"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname DisplayDeck -srcfolder "$STAGE" -ov -format UDZO "$DMG"
  rm -rf "$STAGE"
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"

  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" ${NOTARY_KEYCHAIN:+--keychain "$NOTARY_KEYCHAIN"} --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
  echo "Released $DMG"
  shasum -a 256 "$DMG"
  exit 0
fi

# Sign with a stable identity when one exists so macOS keeps the Accessibility grant across rebuilds;
# ad-hoc signatures change with every build and invalidate it.
DEV_IDENTITY=$(security find-identity -v -p codesigning | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')
codesign --force --sign "${DEV_IDENTITY:--}" "$APP"
echo "Built $APP (signed ${DEV_IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x DisplayDeck 2>/dev/null || true
  rm -rf /Applications/DisplayDeck.app
  cp -R "$APP" /Applications/
  open /Applications/DisplayDeck.app
  echo "Installed to /Applications"
fi
