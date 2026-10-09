# Clips — Text Clipboard History for macOS

A small macOS menu-bar clipboard manager built with Swift, SwiftUI, and AppKit. It keeps recent copied text and lets you star items you want to keep.

## Features

- Choose a history limit of 50, 100, or 200 recent items.
- Keep favorites separately from that limit, with no imposed favorite count cap.
- Search one list with favorites at the top.
- Select several items with checkboxes; Shift-click to select a range.
- Delete recent items immediately; confirm before deleting favorites.
- Open a compact, translucent overlay from the menu bar or with **Command-E**.
- Resize with the bottom-right grip; click outside or press Escape to dismiss.
- Pause recording, clear recent history while keeping favorites, and optionally start at login.

This is a personal utility with limited testing, not a polished replacement for every clipboard manager.

## Build and use

Requires macOS 13 or later and Xcode or Apple's Command Line Tools. Built and used on an Apple silicon Mac; other configurations have not been validated.

1. Download or clone this repository and open its folder in Terminal.
2. Run:

   ```sh
   ./Build.command
   ```

3. Move the generated **Clips.app** to Applications and open it.
4. Copy text normally. Click the clipboard icon in the menu bar to view history.
5. Click an item to copy it back, then return to your app and press **Command-V** to paste.

**Command-E is the default.** To change it, open the gear menu → **Keyboard Shortcut…**, choose modifiers and a letter or number, then Save. At least Command, Option, or Control is required; Shift is optional. The chosen combination overrides that shortcut in other apps while Clips runs. Changes take effect immediately and are saved between launches. If registration fails, the previous shortcut stays active. **Default** restores Command-E in the editor; Save applies it. Settings are in the gear menu. Start-at-login registration may require approval in System Settings.

The app is signed locally, not notarized. This repository provides source and a build script, not a signed installer.

## Selection and favorites

Use the checkbox at the front of an item to select it. Shift-click another checkbox to select the range between them in the displayed list. **Delete selected** appears when items are selected. If the selection includes favorites, the entire deletion asks for confirmation. Changing the search clears selection.

The star at the right toggles a favorite. Favorites survive restarts and history trimming. Unfavoriting an older item can make it eligible for removal under the history limit. Deletion cannot be undone in the app.

## Local storage and limits

- Plain text and links only; no images, files, or rich formatting.
- Copies larger than 1 MB are skipped. Clipboard polling runs twice per second, so very rapid copies may be missed.
- Only new copies made while Clips is running are captured. Existing Clipy history is not imported.
- History is saved in `~/Library/Application Support/Clips/history.json` with owner-only file permissions. It is **not encrypted by Clips**.
- No accounts, network requests, or cloud service.
- Clipboard entries marked concealed or transient by other apps are skipped. This does not guarantee passwords or other sensitive text will never be saved; pause recording when needed.
- Transparency depends on macOS settings. Window placement, outside-click dismissal, resizing, and shortcut behavior may vary across desktop setups.

## Development and verification

Implementation: `Sources/Clips.swift`. Quit Clips before rebuilding.

```sh
./Build.command
./Clips.app/Contents/MacOS/Clips --test
```

The executable checks shortcut defaults, modifier combinations, validation and serialization, plus retention limits, duplicate favorites, more favorites than the history limit, serialization, and clearing recent history while preserving favorites. Native compilation and local code signature verification passed.

Live checks covered text capture, favoriting, persistence after relaunch, Command-E reopening, multiple selection, and favorite-deletion confirmation/cancellation. Range selection, resize persistence, outside-click behavior across apps, and login registration still need broader end-to-end testing. These checks are not a compatibility guarantee.
