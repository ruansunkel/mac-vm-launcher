#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p 'Mac VM.app/Contents/MacOS'
cp Info.plist 'Mac VM.app/Contents/Info.plist'
swiftc VM.swift -o 'Mac VM.app/Contents/MacOS/MacVM' \
    -framework AppKit -framework Virtualization \
    -module-cache-path /tmp/macvm-module-cache
codesign --force --sign - --entitlements entitlements.plist 'Mac VM.app'
codesign --verify --deep --strict 'Mac VM.app'
