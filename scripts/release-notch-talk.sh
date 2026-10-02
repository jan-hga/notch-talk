#!/bin/bash
# Build, sign (Developer ID), notarize and package Notch Talk as a DMG.
# Notarization uses the Apple account that is signed in to Xcode.
# Usage: scripts/release-notch-talk.sh   (bump MARKETING_VERSION / CURRENT_PROJECT_VERSION first)
set -euo pipefail

TEAM_ID="${TEAM_ID:-8TL7467H2U}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/build/release}"
ARCHIVE="$OUT/NotchTalk.xcarchive"

rm -rf "$OUT" && mkdir -p "$OUT"

echo "== Archive"
xcodebuild -project "$ROOT/ClaudeIsland.xcodeproj" -scheme ClaudeIsland -configuration Release \
  -archivePath "$ARCHIVE" -derivedDataPath "$OUT/derived" \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates archive | tail -1

cat > "$OUT/upload.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>upload</string>
</dict></plist>
PLIST

echo "== Upload for notarization"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/upload" \
  -exportOptionsPlist "$OUT/upload.plist" -allowProvisioningUpdates | tail -1

echo "== Wait for notarization"
for i in $(seq 1 60); do
  if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$OUT/app" >/dev/null 2>&1; then
    break
  fi
  [ "$i" = 60 ] && { echo "Notarization did not finish in time"; exit 1; }
  sleep 15
done

APP="$OUT/app/Notch Talk.app"
spctl -a -vvv -t exec "$APP"
xcrun stapler validate "$APP"

VERSION=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)
DMG="$OUT/NotchTalk-$VERSION.dmg"

echo "== DMG"
STAGE="$OUT/dmg"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Notch Talk" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --sign "Developer ID Application" --timestamp "$DMG" 2>/dev/null || true

echo "Done: $DMG"
