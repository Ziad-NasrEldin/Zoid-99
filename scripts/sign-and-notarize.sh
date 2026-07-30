#!/bin/zsh
set -euo pipefail

if (( $# != 1 )); then
    print -u2 "Usage: sign-and-notarize.sh <Zoid 99.app>"
    exit 64
fi

app_path=${1:A}
identity=${ZOID99_SIGNING_IDENTITY:?Set ZOID99_SIGNING_IDENTITY to the Developer ID Application certificate name.}
notary_key=${ZOID99_NOTARY_KEY:?Set ZOID99_NOTARY_KEY to the App Store Connect API key path.}
notary_key_id=${ZOID99_NOTARY_KEY_ID:?Set ZOID99_NOTARY_KEY_ID to the App Store Connect API key ID.}
notary_issuer=${ZOID99_NOTARY_ISSUER:?Set ZOID99_NOTARY_ISSUER to the App Store Connect issuer ID.}
entitlements=${0:A:h:h}/packaging/Zoid99.entitlements
archive_path=${app_path:h}/${app_path:t:r}-notarization.zip

codesign --force --timestamp --options runtime \
    --entitlements "$entitlements" \
    --sign "$identity" "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

ditto -c -k --keepParent --sequesterRsrc "$app_path" "$archive_path"
xcrun notarytool submit "$archive_path" \
    --key "$notary_key" \
    --key-id "$notary_key_id" \
    --issuer "$notary_issuer" \
    --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"

ditto -c -k --keepParent --sequesterRsrc "$app_path" "${archive_path:r}-stapled.zip"
shasum -a 256 "${archive_path:r}-stapled.zip" > "${archive_path:r}-stapled.zip.sha256"
