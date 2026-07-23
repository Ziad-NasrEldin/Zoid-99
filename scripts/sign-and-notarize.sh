#!/bin/zsh
set -euo pipefail

if (( $# != 1 )); then
    print -u2 "Usage: sign-and-notarize.sh <Zoid 99.app>"
    exit 64
fi

app_path=${1:A}
identity=${ZOID99_SIGNING_IDENTITY:?Set ZOID99_SIGNING_IDENTITY to the Developer ID Application certificate name.}
notary_profile=${ZOID99_NOTARY_PROFILE:?Set ZOID99_NOTARY_PROFILE to an existing notarytool Keychain profile.}
entitlements=${0:A:h:h}/packaging/Zoid99.entitlements
archive_path=${app_path:h}/${app_path:t:r}-notarization.zip

codesign --force --timestamp --options runtime \
    --entitlements "$entitlements" \
    --sign "$identity" "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

ditto -c -k --keepParent --sequesterRsrc "$app_path" "$archive_path"
xcrun notarytool submit "$archive_path" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"

ditto -c -k --keepParent --sequesterRsrc "$app_path" "${archive_path:r}-stapled.zip"
shasum -a 256 "${archive_path:r}-stapled.zip" > "${archive_path:r}-stapled.zip.sha256"
