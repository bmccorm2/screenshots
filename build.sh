#!/bin/sh
set -eu
cd "$(dirname "$0")"
APP="dist/Screenshots.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc Sources/Screenshots.swift -O -assert-config Debug -swift-version 5 \
    -target arm64-apple-macosx14.0 \
    -framework AppKit -framework Carbon -framework ServiceManagement \
    -o "$APP/Contents/MacOS/Screenshots"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier local.bryan.screenshots "$APP"
"$APP/Contents/MacOS/Screenshots" --self-test
printf '\nBuilt %s\nDrag it into Applications, then open it.\n' "$APP"
