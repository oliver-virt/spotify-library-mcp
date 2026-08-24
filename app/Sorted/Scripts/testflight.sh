#!/bin/bash
#
# Build Da Capo and upload it to TestFlight.
#
#   Scripts/testflight.sh [build-number]
#
# Prerequisites (checked before any work):
#   1. A RELEASE Xcode (ASC rejects beta-built binaries).
#   2. Paid Apple Developer membership; App ID com.olivervirt.dacapo with the
#      MusicKit App Service enabled; ASC app record exists.
#   3. ASC API key:  export ASC_KEY_ID=... ASC_ISSUER_ID=...
#      with the .p8 at ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8
#   4. Apple Distribution identity in the keychain (Xcode ▸ Settings ▸ Accounts).
#
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/Sorted.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"

die() { printf '\nERROR: %s\n\n' "$1" >&2; exit 1; }
step() { printf '\n==> %s\n' "$1"; }

# --- Preflight ---------------------------------------------------------------
XCODE_VERSION="$(xcodebuild -version | head -1)"
XCODE_BUILD="$(xcodebuild -version | sed -n '2p')"
if [[ "$XCODE_BUILD" =~ [0-9][a-z]$ ]]; then
    die "$XCODE_VERSION ($XCODE_BUILD) looks like a BETA.
   Install release Xcode and: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

TEAM_ID="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM:[[:space:]]*//p' project.yml | head -1 | tr -d '[:space:]')"
[[ -n "$TEAM_ID" ]] || die "DEVELOPMENT_TEAM not found in project.yml"
BUNDLE_ID="$(sed -n 's/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER:[[:space:]]*//p' project.yml | head -1 | tr -d '[:space:]')"
[[ -n "$BUNDLE_ID" ]] || die "PRODUCT_BUNDLE_IDENTIFIER not found in project.yml"

: "${ASC_KEY_ID:?ASC_KEY_ID is not set — see the header of this script}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is not set — see the header of this script}"
KEY_FILE="$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"
[[ -f "$KEY_FILE" ]] || die "API key not found at $KEY_FILE"

security find-identity -v -p codesigning | grep -q "Apple Distribution" \
    || die "No Apple Distribution identity in the keychain.
   Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Apple Distribution."

BUILD_NUMBER="${1:-$(date -u +%Y%m%d%H%M)}"
printf 'Xcode:        %s (%s)\nTeam:         %s\nBundle ID:    %s\nBuild number: %s\n' \
    "$XCODE_VERSION" "$XCODE_BUILD" "$TEAM_ID" "$BUNDLE_ID" "$BUILD_NUMBER"

# --- Build -------------------------------------------------------------------
step "Regenerating the project"
command -v xcodegen >/dev/null || die "xcodegen not installed (brew install xcodegen)"
xcodegen generate

step "Archiving"
rm -rf "$BUILD_DIR"
xcodebuild archive \
    -project Sorted.xcodeproj \
    -scheme Sorted \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$KEY_FILE" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    | tail -5

step "Exporting the .ipa"
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
mkdir -p "$BUILD_DIR"
sed "s/TEAM_ID_PLACEHOLDER/$TEAM_ID/" ExportOptions.plist > "$EXPORT_PLIST"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$KEY_FILE" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    | tail -5

IPA="$(find "$EXPORT_DIR" -name '*.ipa' | head -1)"
[[ -n "$IPA" ]] || die "No .ipa produced — check the export log above."

# --- Upload ------------------------------------------------------------------
step "Validating with App Store Connect"
xcrun altool --validate-app -f "$IPA" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

step "Uploading to TestFlight"
xcrun altool --upload-app -f "$IPA" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

cat <<DONE

Uploaded build $BUILD_NUMBER.
Processing takes 5–30 min; internal testers get it right after.
Export compliance pre-answered (ITSAppUsesNonExemptEncryption=false; app makes no network calls).
DONE
