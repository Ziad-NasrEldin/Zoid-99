#!/bin/zsh
set -euo pipefail

if (( $# != 1 )); then
    print -u2 "Usage: verify-release.sh <Zoid 99.app>"
    exit 64
fi

app_path=${1:A}
plist="$app_path/Contents/Info.plist"
executable="$app_path/Contents/MacOS/Zoid99"

test -d "$app_path"
test -x "$executable"
test -f "$app_path/Contents/Resources/AppIcon.icns"
plutil -lint "$plist"

[[ $(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist") == "com.ziadnasreldin.zoid99" ]]
[[ $(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$plist") == "Zoid 99" ]]
[[ $(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist") == "Zoid99" ]]
[[ $(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$plist") == "14.0" ]]
lipo "$executable" -verify_arch arm64 x86_64

file "$executable"
codesign -d --verbose=4 "$app_path" 2>&1 || true
print "Bundle metadata verified: $app_path"
