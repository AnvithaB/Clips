#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}"
mkdir -p Pocket.app/Contents/MacOS .build
xcrun swiftc -parse-as-library -O -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$PWD/.build" Sources/Clips.swift Sources/Notes.swift Sources/FeatureAccess.swift Sources/Design.swift -o Pocket.app/Contents/MacOS/Pocket -framework AppKit -framework SwiftUI -framework ServiceManagement -framework Carbon
cp Info.plist Pocket.app/Contents/Info.plist
xcrun swiftc -parse-as-library -O -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$PWD/.build" Sources/DockLauncher.swift -o .build/DockLauncher -framework AppKit
xcrun swiftc -O -module-cache-path "$PWD/.build" Scripts/draw-icons.swift -o .build/DrawIcons -framework AppKit
python3 Scripts/make-launchers.py
python3 Scripts/sign-local.py
