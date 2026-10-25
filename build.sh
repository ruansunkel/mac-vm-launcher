#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p 'Mac VM.app/Contents/MacOS' 'Mac VM.app/Contents/Resources'
cp Info.plist 'Mac VM.app/Contents/Info.plist'
cp AppIcon.icns 'Mac VM.app/Contents/Resources/AppIcon.icns'
swiftc VM.swift -target arm64-apple-macosx13.0 -o 'Mac VM.app/Contents/MacOS/MacVM' \
    -framework AppKit -framework Virtualization \
    -module-cache-path /tmp/macvm-module-cache
codesign --force --sign - --entitlements entitlements.plist 'Mac VM.app'
codesign --verify --deep --strict 'Mac VM.app'
