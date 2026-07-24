#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h}
version=${ZOID99_VERSION:-0.2.0}
build_number=${ZOID99_BUILD_NUMBER:-2}
output_root=${ZOID99_OUTPUT_DIR:-"$project_root/.build/release-artifacts"}
source_date_epoch=${SOURCE_DATE_EPOCH:-1767225600}
app_path="$output_root/Zoid 99.app"
zip_path="$output_root/Zoid-99-$version-unsigned.zip"
iconset_path="$output_root/AppIcon.iconset"

if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    print -u2 "ZOID99_VERSION must contain two or three numeric components."
    exit 64
fi
if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    print -u2 "ZOID99_BUILD_NUMBER must be a positive integer."
    exit 64
fi
if [[ ! "$source_date_epoch" =~ ^[0-9]+$ ]]; then
    print -u2 "SOURCE_DATE_EPOCH must be a non-negative integer."
    exit 64
fi

rm -rf "$app_path" "$zip_path" "$iconset_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$iconset_path"

swift build --package-path "$project_root" -c release --arch arm64 --arch x86_64 --product Zoid99
binary_path=$(swift build --package-path "$project_root" -c release --arch arm64 --arch x86_64 --show-bin-path)/Zoid99
cp "$binary_path" "$app_path/Contents/MacOS/Zoid99"
chmod 755 "$app_path/Contents/MacOS/Zoid99"

"$project_root/scripts/generate-app-icon.swift" "$iconset_path"
iconutil -c icns "$iconset_path" -o "$app_path/Contents/Resources/AppIcon.icns"

sed \
    -e "s/\${ZOID99_VERSION}/$version/g" \
    -e "s/\${ZOID99_BUILD_NUMBER}/$build_number/g" \
    "$project_root/packaging/Info.plist" > "$app_path/Contents/Info.plist"
plutil -lint "$app_path/Contents/Info.plist"

if codesign --verify --verbose=2 "$app_path" >/dev/null 2>&1; then
    print -u2 "Refusing to label a signed bundle as unsigned."
    exit 1
fi

release_timestamp=$(date -u -r "$source_date_epoch" +%Y%m%d%H%M.%S)
find "$app_path" -exec touch -h -t "$release_timestamp" {} +
(
    cd "$output_root"
    COPYFILE_DISABLE=1 /usr/bin/zip -X -q -r "$zip_path:t" "$app_path:t"
)
shasum -a 256 "$zip_path" > "$zip_path.sha256"

print "App: $app_path"
print "Archive: $zip_path"
print "SHA-256: $(awk '{print $1}' "$zip_path.sha256")"
