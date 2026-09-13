#!/usr/bin/env bash
#
# Build Transcriber for distribution.
#
#   scripts/release.sh                 Developer ID + notarize + staple + DMG
#   scripts/release.sh --skip-notarize Developer ID signed, no notarization
#   scripts/release.sh --adhoc         Ad-hoc signed ZIP (no Apple membership needed)
#
# Environment:
#   TEAM_ID         Apple Developer team ID   (required unless --adhoc)
#   NOTARY_PROFILE  notarytool keychain profile name (default: transcriber-notary)
#
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME=Transcriber
PROJECT=Transcriber.xcodeproj
APP_NAME=Transcriber
BUILD_DIR=build
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/$APP_NAME.app"

TEAM_ID="${TEAM_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-transcriber-notary}"
MODE=full

for arg in "$@"; do
  case "$arg" in
    --skip-notarize) MODE=skip-notarize ;;
    --adhoc)         MODE=adhoc ;;
    -h|--help)       sed -n "2,12p" "$0" | sed "s/^# \{0,1\}//"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

# ---------------------------------------------------------------- preflight

command -v xcodegen >/dev/null || die "xcodegen not found. Install with: brew install xcodegen"

if [ "$MODE" = adhoc ]; then
  SIGN_IDENTITY="-"
  HARDENED=NO
else
  [ -n "$TEAM_ID" ] || die "TEAM_ID is not set. Find it at developer.apple.com > Membership,
       then run: TEAM_ID=XXXXXXXXXX scripts/release.sh
       No paid membership yet? Use: scripts/release.sh --adhoc"

  security find-identity -v -p codesigning | grep -q "Developer ID Application" \
    || die "No 'Developer ID Application' certificate in the keychain.
       Create one at developer.apple.com > Certificates (needs a paid membership),
       or build a local build instead: scripts/release.sh --adhoc"

  SIGN_IDENTITY="Developer ID Application"
  HARDENED=YES

  if [ "$MODE" = full ]; then
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
      || die "No notarytool credentials stored under profile '$NOTARY_PROFILE'.
       Store them once with:
         xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\
           --apple-id <your-apple-id> --team-id $TEAM_ID --password <app-specific-password>
       App-specific passwords come from appleid.apple.com > Sign-In and Security."
  fi
fi

# ------------------------------------------------------------------- build

step "Generating Xcode project"
xcodegen generate

step "Archiving ($MODE)"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  ENABLE_HARDENED_RUNTIME="$HARDENED" \
  ${TEAM_ID:+DEVELOPMENT_TEAM="$TEAM_ID"} \
  archive

if [ "$MODE" = adhoc ]; then
  mkdir -p "$EXPORT_DIR"
  cp -R "$ARCHIVE/Products/Applications/$APP_NAME.app" "$APP"
else
  step "Exporting"
  cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>          <string>developer-id</string>
    <key>teamID</key>          <string>$TEAM_ID</string>
    <key>signingStyle</key>    <string>manual</string>
    <key>destination</key>     <string>export</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -exportPath "$EXPORT_DIR"
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")

# --------------------------------------------------------------- distribute

if [ "$MODE" = adhoc ]; then
  ZIP="$BUILD_DIR/$APP_NAME-$VERSION-adhoc.zip"
  step "Packaging $ZIP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  cat <<NOTE

Built $ZIP (ad-hoc signed, NOT notarized).

Recipients must bypass Gatekeeper on first launch, either by right-clicking the
app and choosing Open, or by running:

    xattr -dr com.apple.quarantine /Applications/$APP_NAME.app

NOTE
  exit 0
fi

if [ "$MODE" = full ]; then
  ZIP="$BUILD_DIR/$APP_NAME-notarize.zip"
  step "Submitting for notarization (this can take a few minutes)"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

  step "Stapling"
  xcrun stapler staple "$APP"
fi

DMG="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
step "Building $DMG"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null

if [ "$MODE" = full ]; then
  xcrun stapler staple "$DMG"
  step "Verifying"
  spctl -a -vvv -t install "$APP"
  echo
  echo "Done. $DMG is signed, notarized, and stapled."
else
  echo
  echo "Done. $DMG is signed but NOT notarized — Gatekeeper will reject it on other Macs."
fi
