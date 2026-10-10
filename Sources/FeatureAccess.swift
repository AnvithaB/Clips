import AppKit
import SwiftUI

struct PocketFeature: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let summary: String
    static let all = [
        PocketFeature(id: "clipboard", name: "Clipboard", symbol: "doc.on.clipboard", summary: "Keep copied text and images, add your own items, and star the things you want to keep."),
        PocketFeature(id: "notes", name: "Sticky Notes", symbol: "note.text", summary: "Keep text, checklists, and images above your apps. Move, resize, fade, or shrink notes to a little symbol.")
    ]
}
struct AccessPreferences: Codable, Equatable {
    var locations: [String: String] = Dictionary(uniqueKeysWithValues: PocketFeature.all.map { ($0.id, "Menu bar") })
    var dockStyle = "Separate icons"
    var introduced: [String] = []
    func location(_ feature: String) -> String { locations[feature] ?? "Menu bar" }
    func inMenu(_ feature: String) -> Bool { location(feature) != "Dock" }
    func inDock(_ feature: String) -> Bool { location(feature) != "Menu bar" }
    var hasNewFeatures: Bool { PocketFeature.all.contains { !introduced.contains($0.id) } }
    static func load() -> AccessPreferences {
        guard let data = UserDefaults.standard.data(forKey: "featureAccess"), let saved = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        var active = saved
        active.locations.removeValue(forKey: "screenshots")
        active.introduced.removeAll { $0 == "screenshots" }
        return active
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "featureAccess") }
}
struct WelcomeView: View {
    @State var draft: AccessPreferences
    var apply: (AccessPreferences) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                PocketMark()
                VStack(alignment: .leading, spacing: 5) {
                    Text(draft.hasNewFeatures ? "Welcome to Pocket" : "Make Pocket yours").font(.system(size: 27, weight: .bold, design: .rounded))
                    Text("Two little tools, right where you need them.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            Text("Where would you like each tool?").font(.system(size: 14, weight: .semibold))
            ForEach(PocketFeature.all) { feature in
                HStack(alignment: .top, spacing: 14) {
                    FeatureGlyph(feature: feature, size: 44).padding(.top, 3)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(feature.name).font(.headline)
                        Text(feature.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Picker("Show in", selection: Binding(get: { draft.location(feature.id) }, set: { draft.locations[feature.id] = $0 })) {
                            Text("Menu bar").tag("Menu bar"); Text("Dock").tag("Dock"); Text("Both").tag("Both")
                        }.pickerStyle(.segmented).controlSize(.small)
                    }
                }.padding(14).background(Color(nsColor: .controlBackgroundColor).opacity(0.72)).clipShape(RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(feature.tint.opacity(0.12), lineWidth: 1))
            }
            if PocketFeature.all.contains(where: { draft.inDock($0.id) }) {
                Picker("Dock layout", selection: $draft.dockStyle) { Text("Separate icons").tag("Separate icons"); Text("One Pocket icon").tag("One Pocket icon") }.pickerStyle(.segmented)
                Text(draft.dockStyle == "Separate icons" ? "Each chosen tool gets its own Dock launcher. Right-click an icon → Options → Keep in Dock to pin it." : "The Pocket Dock icon opens a chooser for your tools.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack { Text("New tools will be introduced here when they’re added.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Let’s go") { draft.introduced = PocketFeature.all.map(\.id); apply(draft) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(.teal) }
        }.padding(24).frame(width: 510).background(PocketSurface())
    }
}
struct ToolChooser: View {
    @ObservedObject var store: Store
    var open: (String) -> Void
    var configure: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 15) {
                PocketMark()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pocket").font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("ABANDLA").font(.system(size: 11, weight: .medium)).tracking(3).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                ForEach(PocketFeature.all) { feature in
                    ToolCard(feature: feature, detail: detail(feature.id), hint: hint(feature.id)) { open(feature.id) }
                }
            }
            HStack {
                Label("Saved on this Mac", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: configure) { Label("Features & Icons", systemImage: "slider.horizontal.3") }.buttonStyle(.plain).font(.caption).foregroundStyle(.teal)
            }.padding(.top, 3)
        }.padding(26).frame(width: 540).background(PocketSurface())
    }
    func detail(_ id: String) -> String {
        switch id { case "clipboard": return "Your copied text, images, and favorites in one small list."; default: return "Floating notes for ideas, checklists, and images." }
    }
    func hint(_ id: String) -> String { id == "clipboard" ? store.shortcut.label : "🦩" }
}
struct AddClipboardItem: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var favorite = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add to clipboard history").font(.headline)
            TextEditor(text: $text).font(.system(size: 12)).frame(height: 120).border(Color.secondary.opacity(0.2))
            Toggle("Keep as favorite", isOn: $favorite)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Add image…") {
                    let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
                    guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url), let png = Store.png(image) else { return }
                    if let message = store.addImageManually(png, favorite: favorite) { error = message } else { dismiss() }
                }
                Spacer(); Button("Cancel") { dismiss() }
                Button("Add text") {
                    if let message = store.addTextManually(text, favorite: favorite) { error = message } else { dismiss() }
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(18).frame(width: 310)
    }
}
@MainActor enum FeatureTests {
    static func run() {
        precondition(PocketFeature.all.map(\.id) == ["clipboard", "notes"])
        var preferences = AccessPreferences()
        precondition(preferences.hasNewFeatures && preferences.inMenu("notes") && !preferences.inDock("notes"))
        preferences.locations["notes"] = "Both"
        preferences.introduced = PocketFeature.all.map(\.id)
        precondition(!preferences.hasNewFeatures && preferences.inMenu("notes") && preferences.inDock("notes"))
        precondition(try! JSONDecoder().decode(AccessPreferences.self, from: JSONEncoder().encode(preferences)) == preferences)
        preferences.introduced.removeLast(); precondition(preferences.hasNewFeatures)
        precondition(StickyNote.symbols.count == 140 && Set(StickyNote.symbols).count == 140)
        precondition(NoteSearch.ranges(in: "Café CAFÉ cafe", query: "cafe").count == 3)
        precondition(NoteSearch.ranges(in: "🦩 idea 🦩", query: "🦩").map(\.location) == [0, 8])
        precondition(NoteSearch.ranges(in: "Anything", query: "").isEmpty)
        var searchNote = StickyNote(title: "Plans", text: "Read a book", tasks: [NoteTask(text: "Buy milk")])
        searchNote.compactLabel = "Weekend"
        precondition(NoteSearch.matches(searchNote, query: "READ") && NoteSearch.matches(searchNote, query: "milk") && NoteSearch.matches(searchNote, query: "weekend"))
        precondition(!NoteSearch.matches(searchNote, query: "missing"))
        var labelNote = StickyNote()
        labelNote.compactLabel = "Project ideas"
        precondition(try! JSONDecoder().decode(StickyNote.self, from: JSONEncoder().encode(labelNote)).compactDisplay == "Project ideas")
        var legacy = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(labelNote)) as! [String: Any]
        legacy.removeValue(forKey: "compactLabel")
        precondition(try! JSONDecoder().decode(StickyNote.self, from: JSONSerialization.data(withJSONObject: legacy)).compactDisplay == "🦩")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Pocket-notes-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notes.json")
        let suite = "local.pocket.note-settings-test." + UUID().uuidString
        let settings = UserDefaults(suiteName: suite)!
        defer { settings.removePersistentDomain(forName: suite) }
        let defaultsStore = NoteStore(file: directory.appendingPathComponent("defaults-test.json"), preferences: settings)
        precondition(defaultsStore.defaultColor == "Sky" && defaultsStore.confirmsDeletion)
        let oldNote = defaultsStore.add(kind: "Text")!
        precondition(defaultsStore.notes[0].color == "Sky")
        defaultsStore.setDefaultColor("Rose", applyToAll: false)
        precondition(defaultsStore.notes[0].color == "Sky")
        _ = defaultsStore.add(kind: "Checklist")
        precondition(defaultsStore.notes[1].color == "Rose")
        defaultsStore.update(oldNote) { $0.text = "Content preserved" }
        defaultsStore.setDefaultColor("Mint", applyToAll: true)
        defaultsStore.saveShortcut(0, Shortcut(key: 17, option: true))
        defaultsStore.confirmsDeletion = false
        let restoredDefaults = NoteStore(file: defaultsStore.file, preferences: settings)
        precondition(restoredDefaults.shortcuts[0] == Shortcut(key: 17, option: true))
        precondition(restoredDefaults.defaultColor == "Mint" && !restoredDefaults.confirmsDeletion)
        precondition(restoredDefaults.notes.allSatisfy { $0.color == "Mint" })
        precondition(restoredDefaults.notes[0].text == "Content preserved")

        let notes = NoteStore(file: file)
        let id = notes.add(kind: "Checklist")!
        notes.update(id) { $0.title = "Test note"; $0.text = "Text retained across types"; $0.tasks = [NoteTask(text: "First", done: true)]; $0.opacity = 0.5; $0.state = "compact"; $0.frame = "{{20, 20}, {310, 300}}" }
        precondition(notes.flushBeforeQuit())
        let restored = NoteStore(file: file)
        precondition(restored.notes == notes.notes && restored.notes[0].tasks[0].done)
        restored.update(id) { $0.kind = "Text" }; restored.save()
        precondition(restored.notes[0].tasks.count == 1 && restored.notes[0].text == "Text retained across types")
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in NSColor.systemTeal.setFill(); rect.fill(); return true }
        precondition(restored.saveImage(Store.png(image)!, to: id))
        let filename = restored.notes[0].imageFile!
        precondition(NSImage(contentsOf: restored.imageURL(filename)) != nil)
        let imageRestored = NoteStore(file: file)
        precondition(imageRestored.notes[0].imageFile == filename)
        imageRestored.notes.removeAll(); imageRestored.save()
        precondition(!FileManager.default.fileExists(atPath: imageRestored.imageURL(filename).path))
        try! Data("broken".utf8).write(to: file)
        let corrupt = NoteStore(file: file)
        precondition(corrupt.error != nil && corrupt.add(kind: "Text") == nil)
        corrupt.save(); precondition(try! String(contentsOf: file, encoding: .utf8) == "broken")
        let blockedParent = directory.appendingPathComponent("not-a-directory")
        try! Data("test".utf8).write(to: blockedParent)
        let cannotSave = NoteStore(file: blockedParent.appendingPathComponent("notes.json"))
        precondition(!cannotSave.flushBeforeQuit() && cannotSave.error != nil)
        print("PASS: per-feature placement, future-feature introduction, preference persistence, note content/appearance/state persistence, type changes preserve content, corrupt notes protected")
    }
}
@MainActor enum WindowTests {
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Pocket-windows-test-" + UUID().uuidString)
        let store = NoteStore(file: directory.appendingPathComponent("notes.json"))
        let controller = NotesController(store: store)
        defer {
            for id in Array(controller.windows.keys) { controller.delete(id) }
            try? FileManager.default.removeItem(at: directory)
        }
        let id = store.add(kind: "Text")!
        controller.show(id, activate: false)
        let window = controller.windows[id]!
        window.setFrame(NSRect(x: 150, y: 250, width: 420, height: 350), display: true)
        controller.show(id, compact: true, activate: false)
        precondition(controller.windows[id]!.frame.size == NSSize(width: 58, height: 58))
        precondition(store.notes[0].state == "compact")
        precondition(controller.windows[id]!.alphaValue == 1 && !controller.windows[id]!.hasShadow)
        store.update(id) { $0.compactLabel = "Project ideas"; $0.opacity = 0.3 }
        controller.show(id, compact: true, activate: false)
        precondition(controller.windows[id]!.frame.height == 36)
        precondition((controller.windows[id]!.contentView as! NoteSymbolView).symbol == "Project ideas")
        let labelWindow = controller.windows[id]!
        let labelView = labelWindow.contentView as! NoteSymbolView
        precondition(!labelWindow.isMovableByWindowBackground && !labelView.mouseDownCanMoveWindow)
        precondition(labelView.acceptsFirstMouse(for: nil))
        precondition(labelView.bounds.size == labelWindow.contentLayoutRect.size)
        let originalOrigin = labelWindow.frame.origin
        var openedByDrag = false
        let originalExpand = labelView.expand
        labelView.expand = { openedByDrag = true }
        func pointer(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: labelWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        labelView.mouseDown(with: pointer(.leftMouseDown, NSPoint(x: 15, y: 18)))
        labelView.mouseDragged(with: pointer(.leftMouseDragged, NSPoint(x: 75, y: 48)))
        labelView.mouseUp(with: pointer(.leftMouseUp, NSPoint(x: 15, y: 18)))
        precondition(labelWindow.frame.origin == NSPoint(x: originalOrigin.x + 60, y: originalOrigin.y + 30))
        precondition(!openedByDrag)
        labelView.mouseDown(with: pointer(.leftMouseDown, NSPoint(x: 15, y: 18)))
        labelView.mouseUp(with: pointer(.leftMouseUp, NSPoint(x: 15, y: 18)))
        precondition(openedByDrag)
        labelView.expand = originalExpand
        controller.updateAppearance()
        precondition(controller.windows[id]!.alphaValue == 1)
        let movedIcon = NSRect(x: 320, y: 400, width: 120, height: 36)
        controller.windows[id]!.setFrame(movedIcon, display: true)
        controller.show(id, activate: false)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: movedIcon.midX, y: movedIcon.midY)) }) ?? NSScreen.main!
        precondition(controller.windows[id]!.frame == NotePlacement.expandedFrame(size: NSSize(width: 420, height: 350), beside: movedIcon, within: screen.visibleFrame))
        precondition(controller.windows[id]!.frame.size == NSSize(width: 420, height: 350))
        precondition(controller.windows[id]!.level == .floating)
        controller.minimize(id)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        precondition(controller.windows[id]!.isMiniaturized)
        precondition(store.notes[0].state == "minimized")
        controller.windows[id]!.deminiaturize(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        precondition(!controller.windows[id]!.isMiniaturized && store.notes[0].state == "open")
        precondition(controller.windows[id]!.frame.size == NSSize(width: 420, height: 350))
        let reloaded = NotesController(store: NoteStore(file: store.file))
        reloaded.restore()
        precondition(reloaded.windows[id]!.frame.size == NSSize(width: 420, height: 350))
        reloaded.windows[id]?.delegate = nil; reloaded.windows[id]?.close()
        controller.show(id, compact: true, activate: false)
        let other = store.add(kind: "Text")!
        controller.show(other, compact: true, activate: false)
        controller.showSwitcher()
        precondition(controller.selection.id == id)
        controller.moveSelection(1)
        precondition(controller.selection.id == other)
        controller.moveSelection(1)
        precondition(controller.selection.id == id)
        controller.openSelected()
        precondition(store.notes.first { $0.id == id }!.state == "open")
        precondition(store.notes.first { $0.id == other }!.state == "compact")
        precondition(controller.windows[id]!.frame.size == NSSize(width: 420, height: 350))
        controller.windows[id]!.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        controller.shrinkActiveNote(window: controller.windows[id])
        precondition(store.notes.first { $0.id == id }!.state == "compact")
        controller.windows[other]?.delegate = nil; controller.windows[other]?.close()
        controller.windows[id]!.close()
        precondition(store.notes[0].state == "hidden" && controller.windows[id] == nil)
        let first = PocketPanel(title: "Test Utility", size: NSSize(width: 240, height: 180))
        let second = PocketPanel(title: "Test Notes", size: NSSize(width: 240, height: 180))
        defer { first.close(); second.close() }
        first.orderFront(nil); second.orderFront(nil)
        precondition(!first.styleMask.contains(.closable) && first.standardWindowButton(.closeButton) == nil)
        PanelDismissal.dismiss([first, second], except: first)
        precondition(first.isVisible && !second.isVisible)
        PanelDismissal.dismiss([first, second])
        precondition(!first.isVisible && !second.isVisible)
        first.orderFront(nil); precondition(first.isVisible)
        print("PASS: chrome-free utility panels, inside click retains target, outside click hides, reopening works")
        print("PASS: floating note, full-size/compact round trip, Dock minimize and restore, close preserves note")
    }
}
