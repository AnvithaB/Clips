#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}"
mkdir -p Clips.app/Contents/MacOS .build
xcrun swiftc -parse-as-library -O -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$PWD/.build" Sources/Clips.swift -o Clips.app/Contents/MacOS/Clips -framework AppKit -framework SwiftUI -framework ServiceManagement -framework Carbon
cp Info.plist Clips.app/Contents/Info.plist
codesign --force --sign - Clips.app
