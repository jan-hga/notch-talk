#!/bin/bash
# Publish a Notch Talk update so existing installs see it under "Check for Updates":
#   1. build, sign, notarize and package the DMG (release-notch-talk.sh)
#   2. sign the DMG for Sparkle (EdDSA key from the login keychain,
#      or .sparkle-keys/eddsa_private_key if that file exists)
#   3. create the GitHub release vX.Y.Z with the DMG
#   4. add the version to appcast.xml on the gh-pages branch and push it
#
# Run on the Mac, from a checkout of the commit you want to ship
# (bump MARKETING_VERSION / CURRENT_PROJECT_VERSION first).
# Needs: Xcode signed in with the Developer ID team, and `gh auth login`.
# Usage: scripts/publish-update.sh ["Release notes"]
set -euo pipefail

REPO="jan-hga/notch-talk"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/build/release}"
NOTES="${1:-}"

command -v gh >/dev/null || { echo "gh CLI missing: brew install gh && gh auth login"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Not logged in to GitHub: gh auth login"; exit 1; }

echo "=== 1/4 Build, notarize, DMG"
OUT="$OUT" "$ROOT/scripts/release-notch-talk.sh"

APP="$OUT/app/Notch Talk.app"
VERSION=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)
BUILD=$(defaults read "$APP/Contents/Info" CFBundleVersion)
MIN_OS=$(defaults read "$APP/Contents/Info" LSMinimumSystemVersion 2>/dev/null || echo "15.6")
DMG="$OUT/NotchTalk-$VERSION.dmg"
TAG="v$VERSION"
[ -f "$DMG" ] || { echo "DMG not found: $DMG"; exit 1; }

echo "=== 2/4 Sparkle signature"
SIGN_UPDATE=$(find "$OUT/derived/SourcePackages/artifacts" -type f -name sign_update -perm -u+x 2>/dev/null | head -1)
[ -n "$SIGN_UPDATE" ] || SIGN_UPDATE=$(ls -1 "$HOME"/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update 2>/dev/null | head -1 || true)
[ -n "$SIGN_UPDATE" ] || { echo "Sparkle sign_update not found"; exit 1; }

if [ -f "$ROOT/.sparkle-keys/eddsa_private_key" ]; then
  SIG_ATTRS=$("$SIGN_UPDATE" --ed-key-file "$ROOT/.sparkle-keys/eddsa_private_key" "$DMG")
else
  SIG_ATTRS=$("$SIGN_UPDATE" "$DMG")
fi
# SIG_ATTRS looks like: sparkle:edSignature="..." length="12345"
echo "$SIG_ATTRS" | grep -q 'sparkle:edSignature=' || { echo "Signing failed: $SIG_ATTRS"; exit 1; }

echo "=== 3/4 GitHub release $TAG"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DMG" --repo "$REPO" --clobber
else
  gh release create "$TAG" "$DMG" --repo "$REPO" --title "Notch Talk $VERSION" \
    --target "$(git -C "$ROOT" rev-parse HEAD)" --notes "${NOTES:-Notch Talk $VERSION}"
fi

echo "=== 4/4 Appcast on gh-pages"
PAGES="$OUT/gh-pages"
rm -rf "$PAGES"
git -C "$ROOT" fetch "https://github.com/$REPO.git" gh-pages:refs/remotes/pages/gh-pages --force
git -C "$ROOT" worktree prune
git -C "$ROOT" worktree add --force --detach "$PAGES" refs/remotes/pages/gh-pages >/dev/null
trap 'git -C "$ROOT" worktree remove --force "$PAGES" >/dev/null 2>&1 || true' EXIT

APPCAST="$PAGES/appcast.xml"
if grep -q "<sparkle:version>$BUILD</sparkle:version>" "$APPCAST"; then
  echo "Appcast already lists build $BUILD, leaving it as is"
else
  URL="https://github.com/$REPO/releases/download/$TAG/NotchTalk-$VERSION.dmg"
  ITEM_FILE="$OUT/appcast-item.xml"
  cat > "$ITEM_FILE" <<ITEM
        <item>
            <title>$VERSION</title>
            <pubDate>$(LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')</pubDate>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
            <enclosure url="$URL" $SIG_ATTRS type="application/octet-stream"/>
        </item>
ITEM
  # Newest version goes first, right after the channel title
  awk -v itemfile="$ITEM_FILE" '
    { print }
    !done && /<title>Notch Talk<\/title>/ {
      while ((getline line < itemfile) > 0) print line
      done = 1
    }' "$APPCAST" > "$APPCAST.new"
  mv "$APPCAST.new" "$APPCAST"

  git -C "$PAGES" add appcast.xml
  git -C "$PAGES" commit -m "Appcast for Notch Talk $VERSION" >/dev/null
  git -C "$PAGES" push "https://github.com/$REPO.git" HEAD:gh-pages
fi

echo ""
echo "Done: Notch Talk $VERSION is live. Installed apps will offer the update"
echo "(GitHub Pages can take a minute or two to serve the new appcast)."
