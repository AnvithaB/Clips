# Pocket

A small macOS utility for clipboard history and floating sticky notes. Previously called Clips. Built with Swift, SwiftUI, and AppKit as a personal utility.

## Access and startup

First launch introduces Clipboard and Sticky Notes. Each can appear in the menu bar, the Dock, or both. Menu bar is the default. Dock access can use separate tool icons or one Pocket chooser. Change these choices in **Features & Icons…**. Newly added tools are introduced through the same setup.

Enable **Start at login** in clipboard settings to make the clipboard shortcut available after signing in. Keep the app installed in Applications. Separate Dock helpers are bundled inside Pocket.app.

## Clipboard

Copy text or images normally. Open history with the clipboard menu-bar icon or **⌘E**, select an item to copy it, then paste with **⌘V**. Customize the shortcut in settings. On selection, Escape, or a shortcut toggle, Pocket returns focus to the prior typing app. Clicking another app keeps the destination you clicked.

- Compact, translucent, resizable history, with favorites first.
- History limits: 50, 100, 200, 500, or 1,000 recent items. Text and images share the limit.
- Favorites remain outside the recent-item limit, with no imposed favorite count cap.
- Search, image thumbnails, checkboxes, Shift-click selection, and bulk deletion.
- Deleting favorites asks for confirmation.
- **+** adds text or an image manually, including when automatic recording is paused.
- Drag the dotted top handle to move history; drag the bottom-right grip to resize it. Outside clicks and Escape dismiss history.
- Clipboard history and favorites persist when Pocket quits.

Pocket has no screenshot capture tool or screenshot shortcuts. Use macOS screenshot controls instead. Include **Control** with a macOS screenshot shortcut to copy the result to the clipboard; Pocket records that image like other copied images. Saved screenshot files are not automatically imported.

## Sticky Notes

Create text notes, checklists, or image notes. Notes float above other apps and can be moved, resized, faded, minimized into the Dock, or shrunk into a floating icon or label. Individual notes stay visible when you click elsewhere.

- Drag the dotted top handle to move a note, and the bottom-right grip to resize it. Expanded sizes persist through icon collapse, Dock minimization, and relaunch.
- Colors, text size, and transparency per note. New notes default to Sky. Make a chosen color the default for future notes, or apply it to all existing and future notes.
- 140 selectable icons, including 40 smileys, or custom text for a minimized label.
- Floating icons and labels stay fully opaque with no background box or shadow. Move an icon, then open it to restore its note nearby at the saved size. Right-click an icon to open, minimize, or delete its note.
- Search all notes by title, text, checklist contents, or custom label.
- Find within a text note with highlighted matches and previous/next navigation. Checklist search filters tasks. Image text is not recognized.
- Delete directly from a note, the Notes list, or a symbol’s right-click menu. Notes settings can disable delete confirmations.
- Custom text labels replace the emoji on the note’s shrink button and in the Notes list. Drag a compact label anywhere across its text to move it; click to reopen.
- Press **Command–Option–N** to switch between compact note symbols. Tab or arrow keys highlight a symbol; Enter opens its note. Escape dismisses the switcher.
- Press **Command–Shift–M** while editing a note to shrink it into its symbol. Both shortcuts are editable in Notes settings and remembered between launches.
- Content, appearance, window position, and minimized state persist between launches.

## Local data

Data remains in `~/Library/Application Support/Clips` to preserve earlier versions’ history:

- `history.json` and `Images/`: clipboard entries and images.
- `notes.json` and `NoteImages/`: sticky notes and attached images.

There are no accounts, cloud sync, analytics, or Screen Recording permission requirements. Clipboard history can contain sensitive copied information. Pause recording or delete entries as needed. Copies marked concealed by another app are excluded.

## Build and checks

Requires macOS 13 or later, Xcode command-line tools, and Python 3. Double-click `Build.command` (or run `zsh Build.command` from Terminal). It builds `Pocket.app`, generates native artwork, and bundles two Dock helpers. Open the app or place it in Applications.

Local builds use a persistent certificate stored privately in `~/Library/Application Support/Pocket Development Signing`, outside this repository. It is not an Apple Developer ID certificate and is not added to system trust. Keep this directory when rebuilding locally. This build is not notarized for public distribution.

`Pocket.app/Contents/MacOS/Pocket --test` checks private test clipboard storage, image/text retention, favorites, legacy migration, note persistence, labels, Unicode search, feature preferences, and unreadable-file protection. `--test-windows` checks temporary note windows, resizing, compact icons/labels, Dock minimization, and utility dismissal.
