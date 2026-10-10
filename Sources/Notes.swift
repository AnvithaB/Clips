import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NoteTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var done = false
}
struct StickyNote: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = "Untitled note"
    var text = ""
    var kind = "Text"
    var tasks: [NoteTask] = []
    var imageFile: String?
    var color = "Sky"
    var opacity = 0.95
    var fontSize = 14.0
    var symbol = "🦩"
    var compactLabel: String?
    var hasCompactLabel: Bool { !(compactLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var compactDisplay: String {
        let label = (compactLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? symbol : String(label.prefix(40))
    }
    var state = "open"
    var frame: String?
    var compactFrame: String?
    static let smileys = [
        "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "😊", "🙂",
        "🙃", "😉", "😍", "🥰", "😘", "😎", "🤩", "🥳", "😇", "🤗",
        "🤔", "🤭", "🫢", "🫣", "🤫", "🤨", "🧐", "😌", "😴", "🥱",
        "😋", "😛", "😜", "🤪", "😬", "🥹", "🥺", "😢", "😭", "😤"
    ]
    static let symbols = [
        "🦩", "🌿", "⭐️", "📝", "🪷", "🌸", "🌼", "🌻", "🌹", "🌷",
        "🌺", "🍀", "🌱", "🌵", "🌴", "🌳", "🍄", "🍁", "🍂", "🍃",
        "🐈", "🐕", "🐇", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮",
        "🐸", "🐢", "🦋", "🐝", "🐞", "🦉", "🐧", "🦆", "🐬", "🐳",
        "☀️", "🌙", "🌟", "✨", "🌈", "☁️", "❄️", "🔥", "💧", "🌊",
        "🍎", "🍊", "🍋", "🍓", "🍒", "🍉", "🍇", "🥑", "🥐", "🍰",
        "☕️", "🫖", "🍵", "🍯", "🍕", "🍪", "🍩", "🧁", "🍫", "🥨",
        "💡", "📚", "📖", "✏️", "🖊️", "📌", "📎", "✉️", "📅", "⏰",
        "🎨", "🎵", "🎧", "🎮", "🎬", "📷", "🎯", "🎲", "🧩", "🏆",
        "❤️", "🧡", "💛", "💚", "💙", "💜", "💎", "🚀", "🪐", "🎈"
    ] + smileys
    static let colors = ["Butter", "Rose", "Mint", "Sky", "Lilac", "Graphite"]
    var background: Color {
        switch color {
        case "Rose": return Color(red: 0.97, green: 0.76, blue: 0.80)
        case "Mint": return Color(red: 0.72, green: 0.88, blue: 0.79)
        case "Sky": return Color(red: 0.73, green: 0.85, blue: 0.96)
        case "Lilac": return Color(red: 0.83, green: 0.78, blue: 0.95)
        case "Graphite": return Color(red: 0.20, green: 0.23, blue: 0.27)
        default: return Color(red: 0.98, green: 0.91, blue: 0.64)
        }
    }
}
@MainActor final class NoteStore: ObservableObject {
    @Published var notes: [StickyNote] = []
    @Published var error: String?
    private var writable = true
    private var pending: DispatchWorkItem?
    let file: URL
    private let defaults: UserDefaults?
    static let shortcutDefaults = [Shortcut(key: 45, option: true), Shortcut(key: 46, shift: true)]
    @Published var shortcuts = NoteStore.shortcutDefaults
    var applyShortcut: ((Int, Shortcut) -> String?)?
    func saveShortcut(_ index: Int, _ value: Shortcut) {
        shortcuts[index] = value
        if let data = try? JSONEncoder().encode(value) { defaults?.set(data, forKey: "noteShortcut-\(index)") }
    }
    @Published var defaultColor = "Sky" {
        didSet { defaults?.set(defaultColor, forKey: "notesDefaultColor") }
    }
    @Published var confirmsDeletion = true {
        didSet { defaults?.set(confirmsDeletion, forKey: "confirmNoteDeletion") }
    }
    init(file: URL? = nil, preferences: UserDefaults? = nil) {
        defaults = preferences ?? (file == nil ? .standard : nil)
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Clips/notes.json")
        if let saved = defaults?.string(forKey: "notesDefaultColor"), StickyNote.colors.contains(saved) { defaultColor = saved }
        for index in shortcuts.indices {
            if let data = defaults?.data(forKey: "noteShortcut-\(index)"), let value = try? JSONDecoder().decode(Shortcut.self, from: data), value.valid { shortcuts[index] = value }
        }
        confirmsDeletion = defaults?.object(forKey: "confirmNoteDeletion") as? Bool ?? true
        guard FileManager.default.fileExists(atPath: self.file.path) else { return }
        do { notes = try JSONDecoder().decode([StickyNote].self, from: Data(contentsOf: self.file)) }
        catch { writable = false; self.error = "Could not read saved notes. The original file has been left intact." }
    }
    func update(_ id: UUID, _ edit: (inout StickyNote) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        edit(&notes[index]); scheduleSave()
    }
    func scheduleSave() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pending = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    func flushBeforeQuit() -> Bool { !writable || save() }
    @discardableResult func save() -> Bool {
        pending?.cancel(); pending = nil
        guard writable else { return false }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(notes).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let retained = Set(notes.compactMap(\.imageFile))
            for url in (try? FileManager.default.contentsOfDirectory(at: imageDirectory, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "png" && !retained.contains(url.lastPathComponent) { try? FileManager.default.removeItem(at: url) }
            return true
        } catch { self.error = "Could not save notes: \(error.localizedDescription)"; return false }
    }
    var imageDirectory: URL { file.deletingLastPathComponent().appendingPathComponent("NoteImages", isDirectory: true) }
    func imageURL(_ filename: String) -> URL { imageDirectory.appendingPathComponent(URL(fileURLWithPath: filename).lastPathComponent) }
    func importImage(_ id: UUID) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url), let data = Store.png(image) else { return }
        saveImage(data, to: id)
    }
    @discardableResult func saveImage(_ data: Data, to id: UUID) -> Bool {
        guard writable, notes.contains(where: { $0.id == id }) else { return false }
        guard data.count <= 50_000_000, NSImage(data: data) != nil else { error = "Choose a valid image smaller than 50 MB."; return false }
        do {
            try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let filename = UUID().uuidString + ".png"
            try data.write(to: imageURL(filename), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: imageURL(filename).path)
            update(id) { $0.imageFile = filename }; return save()
        } catch { self.error = "Could not save note image: \(error.localizedDescription)"; return false }
    }
    func add(kind: String) -> UUID? {
        guard writable else { return nil }
        let note = StickyNote(kind: kind, color: defaultColor)
        notes.append(note); save(); return note.id
    }
    func setDefaultColor(_ color: String, applyToAll: Bool) {
        guard StickyNote.colors.contains(color) else { return }
        if applyToAll {
            guard writable else { return }
            let original = notes
            for index in notes.indices { notes[index].color = color }
            guard save() else { notes = original; return }
        }
        defaultColor = color
    }
    func binding<T>(_ id: UUID, _ path: WritableKeyPath<StickyNote, T>, fallback: T) -> Binding<T> {
        Binding(get: { self.notes.first(where: { $0.id == id })?[keyPath: path] ?? fallback }, set: { value in self.update(id) { $0[keyPath: path] = value } })
    }
}
struct NotesSettings: View {
    @ObservedObject var store: NoteStore
    @State private var editing: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes settings").font(.headline)
            ForEach(0..<2) { index in
                Button("\(index == 0 ? "Switch symbols" : "Shrink active note") · \(store.shortcuts[index].label)") { editing = index }
            }
            Divider()
            Picker("Default color", selection: $store.defaultColor) {
                ForEach(StickyNote.colors, id: \.self) { Text($0) }
            }
            Text("Changing the default affects future notes.").font(.caption).foregroundStyle(.secondary)
            Button("Apply default color to all notes") { store.setDefaultColor(store.defaultColor, applyToAll: true) }
            Divider()
            Toggle("Confirm before deleting notes", isOn: $store.confirmsDeletion)
            Text("Applies to deletion from note windows and the Notes list.").font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(width: 290)
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            if let index = editing { NoteShortcutEditor(store: store, index: index) }
        }
    }
}
struct NoteShortcutEditor: View {
    @ObservedObject var store: NoteStore
    let index: Int
    @Environment(\.dismiss) var dismiss
    @State private var draft = Shortcut()
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(index == 0 ? "Switch symbols" : "Shrink active note").font(.headline)
            HStack {
                Toggle("⌘", isOn: $draft.command); Toggle("⌥", isOn: $draft.option)
                Toggle("⌃", isOn: $draft.control); Toggle("⇧", isOn: $draft.shift)
            }.toggleStyle(.checkbox)
            Picker("Key", selection: $draft.key) { ForEach(Shortcut.keys, id: \.1) { Text($0.0).tag($0.1) } }
            Text(draft.label).font(.title3.monospaced())
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("Default") { draft = NoteStore.shortcutDefaults[index] }
                Spacer(); Button("Cancel") { dismiss() }
                Button("Save") {
                    if let message = store.applyShortcut?(index, draft) { error = message }
                    else { dismiss() }
                }.disabled(!draft.valid)
            }
        }.padding(18).frame(width: 300).onAppear { draft = store.shortcuts[index] }
    }
}
enum NoteSearch {
    static func ranges(in text: String, query: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let source = text as NSString
        var result: [NSRange] = []
        var start = 0
        while start < source.length {
            let match = source.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: NSRange(location: start, length: source.length - start))
            guard match.location != NSNotFound, match.length > 0 else { break }
            result.append(match); start = NSMaxRange(match)
        }
        return result
    }
    static func matches(_ note: StickyNote, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return [note.title, note.text, note.compactLabel ?? "", note.tasks.map(\.text).joined(separator: "\n")]
            .contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: Double
    var dark: Bool
    var query: String
    var matchIndex: Int
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextEditor
        var lastQuery = ""
        var lastIndex = -1
        init(_ parent: NoteTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { parent.text = editor.string }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 280, height: 200))
        editor.isRichText = false; editor.allowsUndo = true; editor.drawsBackground = false
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.minSize = .zero; editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 280, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 0, height: 4)
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel("Note text")
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if editor.string != text {
            let selection = editor.selectedRange()
            editor.string = text
            let end = (text as NSString).length
            let location = min(selection.location, end)
            editor.setSelectedRange(NSRange(location: location, length: min(selection.length, end - location)))
        }
        editor.font = NSFont.systemFont(ofSize: fontSize)
        editor.textColor = dark ? .white : .black
        let length = (text as NSString).length
        editor.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
        let matches = NoteSearch.ranges(in: text, query: query)
        for match in matches { editor.layoutManager?.addTemporaryAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.45), forCharacterRange: match) }
        if !matches.isEmpty, context.coordinator.lastQuery != query || context.coordinator.lastIndex != matchIndex {
            let range = matches[min(max(0, matchIndex), matches.count - 1)]
            editor.setSelectedRange(range); editor.scrollRangeToVisible(range)
        }
        context.coordinator.lastQuery = query; context.coordinator.lastIndex = matchIndex
    }
}
struct StickyEditor: View {
    @ObservedObject var store: NoteStore
    let id: UUID
    var compact: () -> Void
    var minimize: () -> Void
    var delete: () -> Void
    @State private var confirmDelete = false
    @State private var settings = false
    @State private var symbolCategory = "All"
    @State private var newTask = ""
    @State private var searching = false
    @State private var query = ""
    @State private var matchIndex = 0
    @FocusState private var searchFocused: Bool
    var matches: [NSRange] { NoteSearch.ranges(in: note.text, query: query) }
    var visibleTasks: [NoteTask] { note.tasks.filter { query.isEmpty || $0.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil } }
    var note: StickyNote { store.notes.first { $0.id == id } ?? StickyNote() }
    var body: some View {
        VStack(spacing: 8) {
            WindowDragHandle().frame(height: 12).help("Drag to move note")
            HStack(spacing: 6) {
                TextField("Title", text: store.binding(id, \.title, fallback: "Note")).font(.system(size: 13, weight: .semibold)).textFieldStyle(.plain)
                Button(action: compact) { Text(note.compactDisplay).font(.system(size: note.hasCompactLabel ? 11 : 14)).lineLimit(1).frame(maxWidth: note.hasCompactLabel ? 90 : nil).truncationMode(.tail) }.help("Shrink to a floating symbol")
                Button { searching.toggle(); if !searching { query = "" }; searchFocused = searching } label: { Image(systemName: "magnifyingglass") }.help("Find in note (⌘F)").keyboardShortcut("f", modifiers: .command)
                Button { if store.confirmsDeletion { confirmDelete = true } else { delete() } } label: { Image(systemName: "trash") }.help("Delete note")
                Button(action: minimize) { Image(systemName: "minus") }.help("Minimize to Dock")
                Button { settings.toggle() } label: { Image(systemName: "slider.horizontal.3") }.help("Note appearance")
                    .popover(isPresented: $settings) { appearance }
            }.buttonStyle(.plain)
            if searching {
                HStack(spacing: 5) {
                    TextField("Find in note…", text: $query).textFieldStyle(.roundedBorder).focused($searchFocused)
                        .onChange(of: query) { _ in matchIndex = 0 }
                    if note.kind == "Text" {
                        Text(matches.isEmpty ? "0" : "\(min(matchIndex + 1, matches.count))/\(matches.count)").font(.caption2)
                        Button { if !matches.isEmpty { matchIndex = (matchIndex + matches.count - 1) % matches.count } } label: { Image(systemName: "chevron.up") }.disabled(matches.isEmpty).help("Previous match")
                        Button { if !matches.isEmpty { matchIndex = (matchIndex + 1) % matches.count } } label: { Image(systemName: "chevron.down") }.disabled(matches.isEmpty).help("Next match")
                    }
                    Button { searching = false; query = "" } label: { Image(systemName: "xmark") }.help("Close search")
                }.buttonStyle(.plain)
                if note.kind == "Image" { Text("Search all notes by title or label in the Notes list. Text inside images isn’t searchable.").font(.caption).foregroundStyle(.secondary) }
            }
            if note.kind == "Checklist" {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(visibleTasks) { task in
                            HStack {
                                Toggle("", isOn: Binding(get: { task.done }, set: { value in store.update(id) { note in if let i = note.tasks.firstIndex(where: { $0.id == task.id }) { note.tasks[i].done = value } } })).labelsHidden()
                                TextField("Task", text: Binding(get: { task.text }, set: { value in store.update(id) { note in if let i = note.tasks.firstIndex(where: { $0.id == task.id }) { note.tasks[i].text = value } } })).textFieldStyle(.plain).strikethrough(task.done)
                                Button { store.update(id) { $0.tasks.removeAll { $0.id == task.id } } } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain).help("Remove task")
                            }
                        }
                        HStack {
                            TextField("Add a task…", text: $newTask).textFieldStyle(.plain).onSubmit(addTask)
                            Button(action: addTask) { Image(systemName: "plus") }.buttonStyle(.plain).disabled(newTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }.font(.system(size: note.fontSize))
                }
            } else if note.kind == "Image" {
                if let filename = note.imageFile, let image = NSImage(contentsOf: store.imageURL(filename)) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    Button("Replace image…") { store.importImage(id) }.buttonStyle(.plain).font(.caption)
                } else { Spacer(); Button("Choose image…") { store.importImage(id) }; Spacer() }
            } else {
                NoteTextEditor(text: store.binding(id, \.text, fallback: ""), fontSize: note.fontSize, dark: note.color == "Graphite", query: query, matchIndex: matchIndex)
            }
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(12).foregroundStyle(note.color == "Graphite" ? Color.white : Color.black.opacity(0.85))
        .background(note.background)
        .frame(minWidth: 240, minHeight: 150)
        .overlay(alignment: .bottomTrailing) { ResizeGrip().frame(width: 18, height: 18).padding(3).help("Drag to resize note") }
        .alert("Delete this note?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: delete)
        } message: { Text("This removes the note and its saved content.") }
    }
    func addTask() {
        let text = newTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.update(id) { $0.tasks.append(NoteTask(text: text)) }; newTask = ""
    }
    var appearance: some View {
        ScrollView { VStack(alignment: .leading, spacing: 12) {
            Picker("Type", selection: store.binding(id, \.kind, fallback: "Text")) { Text("Text").tag("Text"); Text("Checklist").tag("Checklist"); Text("Image").tag("Image") }
            Text("Each type keeps its own content when you switch.").font(.caption).foregroundStyle(.secondary)
            Picker("Color", selection: store.binding(id, \.color, fallback: "Sky")) { ForEach(StickyNote.colors, id: \.self) { Text($0) } }
            Menu("Make \(note.color) the default") {
                Button("Future notes only") { store.setDefaultColor(note.color, applyToAll: false) }
                Button("All existing and future notes") { store.setDefaultColor(note.color, applyToAll: true) }
            }
            Text("Default for new notes: \(store.defaultColor)").font(.caption).foregroundStyle(.secondary)
            Toggle("Confirm before deleting notes", isOn: $store.confirmsDeletion)

            Text("Opacity · \(Int(note.opacity * 100))%")
            Slider(value: store.binding(id, \.opacity, fallback: 0.95), in: 0.25...1)
            Text("Text size · \(Int(note.fontSize))")
            Slider(value: store.binding(id, \.fontSize, fallback: 14), in: 11...28, step: 1)
            Text("Floating icon or label").font(.headline)
            TextField("Custom name or text (optional)", text: Binding(
                get: { note.compactLabel ?? "" },
                set: { value in store.update(id) { $0.compactLabel = String(value.prefix(40)) } }
            )).textFieldStyle(.roundedBorder)
            Text("Leave blank to use an icon. Labels stay fully opaque too.").font(.caption).foregroundStyle(.secondary)
            Picker("Symbols", selection: $symbolCategory) { Text("All").tag("All"); Text("Smileys").tag("Smileys") }.pickerStyle(.segmented)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                    ForEach(symbolCategory == "Smileys" ? StickyNote.smileys : StickyNote.symbols, id: \.self) { symbol in
                        Button { store.update(id) { $0.symbol = symbol; $0.compactLabel = nil } } label: {
                            Text(symbol).font(.system(size: 22)).frame(width: 27, height: 31)
                                .background(note.symbol == symbol && (note.compactLabel ?? "").isEmpty ? Color.accentColor.opacity(0.2) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain).accessibilityLabel("Floating icon " + symbol)
                    }
                }
            }.frame(height: 135)

        }.padding(16) }.frame(width: 320, height: 530)
    }
}
final class NoteWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
final class NoteSymbolView: NSView {
    // Compact labels handle their own drag, including the first click from another app.
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
    private func screenPoint(_ event: NSEvent) -> NSPoint {
        event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }
    override func accessibilityPerformPress() -> Bool { expand?(); return true }
    var highlighted = false { didSet { needsDisplay = true } }
    var symbol = "🦩"
    var isTextLabel = false
    var expand: (() -> Void)?
    var minimize: (() -> Void)?
    var delete: (() -> Void)?
    private var start = NSPoint.zero
    private var origin = NSPoint.zero
    private var moved = false
    override func draw(_ dirtyRect: NSRect) {
        if highlighted {
            NSColor.systemBlue.setStroke()
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 12, yRadius: 12)
            outline.lineWidth = 3; outline.stroke()
        }
        let isLabel = isTextLabel
        let font = NSFont.systemFont(ofSize: isLabel ? 14 : 33, weight: isLabel ? .semibold : .regular)
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
        let height = (symbol as NSString).size(withAttributes: [.font: font]).height
        (symbol as NSString).draw(in: NSRect(x: 7, y: (bounds.height - height) / 2, width: bounds.width - 14, height: height),
            withAttributes: [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
    }
    override func mouseDown(with event: NSEvent) { start = screenPoint(event); origin = window?.frame.origin ?? .zero; moved = false }
    override func mouseDragged(with event: NSEvent) {
        let point = screenPoint(event)
        if hypot(point.x - start.x, point.y - start.y) > 3 { moved = true }
        window?.setFrameOrigin(NSPoint(x: origin.x + point.x - start.x, y: origin.y + point.y - start.y))
    }
    override func mouseUp(with event: NSEvent) { if !moved { expand?() } }
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open note", action: #selector(openNote), keyEquivalent: ""); open.target = self; menu.addItem(open)
        let dock = NSMenuItem(title: "Minimize to Dock", action: #selector(dockNote), keyEquivalent: ""); dock.target = self; menu.addItem(dock)
        menu.addItem(.separator())
        let remove = NSMenuItem(title: "Delete note", action: #selector(deleteNote), keyEquivalent: ""); remove.target = self; menu.addItem(remove)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc func openNote() { expand?() }
    @objc func dockNote() { minimize?() }
    @objc func deleteNote() { delete?() }
}
enum NotePlacement {
    static func expandedFrame(size: NSSize, beside icon: NSRect, within screen: NSRect) -> NSRect {
        let size = NSSize(width: min(size.width, screen.width), height: min(size.height, screen.height))
        return NSRect(x: max(screen.minX, min(icon.minX, screen.maxX - size.width)),
                      y: max(screen.minY, min(icon.maxY - size.height, screen.maxY - size.height)),
                      width: size.width, height: size.height)
    }
}
@MainActor final class NotesController: NSObject, NSWindowDelegate {
    let store: NoteStore
    var windows: [UUID: NSWindow] = [:]
    var manager: NSWindow?
    var switcher: NoteSwitcherPanel?
    let selection = NoteSelection()
    var compactNotes: [StickyNote] { store.notes.filter { $0.state == "compact" } }
    func showSwitcher() {
        if switcher?.isVisible == true { moveSelection(1); return }
        selection.id = compactNotes.first?.id
        let panel = NoteSwitcherPanel(title: "Switch note symbols", size: NSSize(width: 430, height: 300))
        panel.title = "Switch note symbols"
        panel.onHide = { [weak self] in self?.highlightSelection(clear: true) }
        panel.contentViewController = NSHostingController(rootView: NoteSwitcherView(store: store, selection: selection, choose: { [weak self] id in self?.selection.id = id; self?.openSelected() }))
        switcher = panel; panel.center(); NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
        highlightSelection()
    }
    func highlightSelection(clear: Bool = false) {
        for (id, window) in windows { (window.contentView as? NoteSymbolView)?.highlighted = !clear && id == selection.id }
    }
    func moveSelection(_ delta: Int) {
        let list = compactNotes
        guard !list.isEmpty else { selection.id = nil; highlightSelection(); return }
        let current = list.firstIndex { $0.id == selection.id } ?? 0
        selection.id = list[(current + delta % list.count + list.count) % list.count].id
        highlightSelection()
    }
    func openSelected() {
        guard let id = selection.id, compactNotes.contains(where: { $0.id == id }) else { return }
        switcher?.orderOut(nil); show(id)
    }
    func shrinkActiveNote(window: NSWindow? = nil) {
        guard let key = window ?? NSApp.keyWindow, let id = windows.first(where: { $0.value === key })?.key,
              store.notes.contains(where: { $0.id == id && $0.state == "open" }) else { return }
        show(id, compact: true)
    }
    func handleSwitcherKey(_ event: NSEvent) -> Bool {
        guard event.window === switcher else { return false }
        switch event.keyCode {
        case 48: moveSelection(event.modifierFlags.contains(.shift) ? -1 : 1)
        case 123, 126: moveSelection(-1)
        case 124, 125: moveSelection(1)
        case 36, 76: openSelected()
        case 53: switcher?.orderOut(nil)
        default: return false
        }
        return true
    }
    var changing = false
    var refresh: Any?
    var activateDock: (() -> Void)?
    init(store: NoteStore? = nil) {
        self.store = store ?? NoteStore()
        super.init()
        refresh = self.store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateAppearance() }
        }
    }
    func updateAppearance() {
        for note in store.notes {
            windows[note.id]?.alphaValue = note.state == "compact" ? 1 : max(0.25, min(1, note.opacity))
            windows[note.id]?.title = note.title.isEmpty ? "Pocket Note" : note.title
        }
    }
    func restore() {
        for note in store.notes where note.state != "hidden" {
            show(note.id, compact: note.state == "compact", activate: false)
            if note.state == "minimized" { minimize(note.id) }
        }
    }
    func newNote(_ kind: String = "Text") {
        guard let id = store.add(kind: kind) else { showManager(); return }
        show(id)
    }
    func show(_ id: UUID, compact: Bool = false, activate: Bool = true) {
        guard store.notes.contains(where: { $0.id == id }) else { return }
        let wasCompact = store.notes.first(where: { $0.id == id })?.state == "compact"
        let hadWindow = windows[id] != nil
        changing = true
        defer { changing = false }
        if let previous = windows[id] {
            store.update(id) { current in
                if current.state == "compact" { current.compactFrame = NSStringFromRect(previous.frame) }
                else { current.frame = NSStringFromRect(previous.frame) }
            }
            previous.delegate = nil; previous.close()
        }
        let note = store.notes.first(where: { $0.id == id })!
        let window = NoteWindow(contentRect: NSRect(x: 240, y: 300, width: 310, height: 300), styleMask: compact ? [.borderless] : [.borderless, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.title = note.title
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.isMovableByWindowBackground = !compact
        window.alphaValue = compact ? 1 : max(0.25, min(1, note.opacity))
        window.delegate = self
        windows[id] = window
        if compact {
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
            let view = NoteSymbolView(frame: NSRect(x: 0, y: 0, width: 58, height: 58)); view.symbol = note.compactDisplay; view.isTextLabel = note.hasCompactLabel
            view.autoresizingMask = [.width, .height]
            view.setAccessibilityElement(true); view.setAccessibilityRole(.button); view.setAccessibilityLabel("Open note: " + note.title)
            view.toolTip = "Click to open · drag to move · right-click for options"
            view.expand = { [weak self] in self?.show(id) }; view.minimize = { [weak self] in self?.minimize(id) }; view.delete = { [weak self] in self?.requestDelete(id) }
            window.contentView = view
            let frame = note.compactFrame.map(NSRectFromString) ?? note.frame.map(NSRectFromString) ?? window.frame
            let labelWidth = (note.compactDisplay as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold)]).width + 18
            let size = NSSize(width: note.hasCompactLabel ? min(240, max(58, labelWidth)) : 58, height: note.hasCompactLabel ? 36 : 58)
            let expanded = note.frame.map(NSRectFromString) ?? frame
            let origin = hadWindow && !wasCompact ? NSPoint(x: expanded.minX, y: expanded.maxY - size.height) : frame.origin
            window.setFrame(NSRect(origin: origin, size: size), display: false)
        } else {
            window.minSize = NSSize(width: 240, height: 185)
            window.contentViewController = NSHostingController(rootView: StickyEditor(store: store, id: id, compact: { [weak self] in self?.show(id, compact: true) }, minimize: { [weak self] in self?.minimize(id) }, delete: { [weak self] in self?.delete(id) }).clipShape(RoundedRectangle(cornerRadius: 16)))
            if let frame = note.frame { window.setFrame(NSRectFromString(frame), display: false) }
            else { window.setContentSize(NSSize(width: 310, height: 300)); window.center(); window.setFrameOrigin(NSPoint(x: window.frame.minX + CGFloat(windows.count % 6) * 20, y: window.frame.minY - CGFloat(windows.count % 6) * 20)) }
            if wasCompact, let savedIcon = note.compactFrame {
                let icon = NSRectFromString(savedIcon)
                let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: icon.midX, y: icon.midY)) }) ?? NSScreen.main
                if let screen { window.setFrame(NotePlacement.expandedFrame(size: window.frame.size, beside: icon, within: screen.visibleFrame), display: false) }
            }
        }
        // Bring notes back onto a connected screen after monitor changes.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) { window.center() }
        store.update(id) {
            $0.state = compact ? "compact" : "open"
            if compact { $0.compactFrame = NSStringFromRect(window.frame) }
            else { $0.frame = NSStringFromRect(window.frame) }
        }
        if activate { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
        else { window.orderFront(nil) }
        store.save()
    }
    func minimize(_ id: UUID) {
        if store.notes.first(where: { $0.id == id })?.state == "compact" { show(id) }
        activateDock?()
        windows[id]?.miniaturize(nil)
        store.update(id) { $0.state = "minimized" }; store.save()
    }
    func identify(_ notification: Notification) -> UUID? { windows.first { $0.value === notification.object as? NSWindow }?.key }
    func windowDidMove(_ notification: Notification) { remember(notification) }
    func windowDidResize(_ notification: Notification) { remember(notification) }
    func remember(_ notification: Notification) {
        guard !changing, let id = identify(notification), let window = windows[id] else { return }
        store.update(id) { note in
            if note.state == "compact" { note.compactFrame = NSStringFromRect(window.frame) }
            else { note.frame = NSStringFromRect(window.frame) }
        }
    }
    func windowWillClose(_ notification: Notification) {
        guard !changing, let id = identify(notification) else { return }
        store.update(id) { $0.state = "hidden" }; store.save(); windows.removeValue(forKey: id)
    }
    func windowDidMiniaturize(_ notification: Notification) { if let id = identify(notification) { store.update(id) { $0.state = "minimized" }; store.save() } }
    func windowDidDeminiaturize(_ notification: Notification) { if let id = identify(notification) { store.update(id) { $0.state = "open" }; store.save() } }
    func requestDelete(_ id: UUID) {
        guard store.notes.contains(where: { $0.id == id }) else { return }
        if store.confirmsDeletion {
            let alert = NSAlert(); alert.messageText = "Delete this note?"
            alert.informativeText = "This removes the note and its saved content."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Delete")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        delete(id)
    }
    func delete(_ id: UUID) {
        changing = true; windows[id]?.delegate = nil; windows[id]?.close(); windows.removeValue(forKey: id); changing = false
        store.notes.removeAll { $0.id == id }; store.save()
    }
    func showManager() {
        if manager == nil {
            let window = PocketPanel(title: "Pocket Notes", size: NSSize(width: 430, height: 430), resizable: true)
            window.minSize = NSSize(width: 390, height: 350)
            window.title = "Pocket Notes"; window.isReleasedWhenClosed = false; window.center()
            window.contentViewController = NSHostingController(rootView: NotesList(store: store, controller: self).clipShape(RoundedRectangle(cornerRadius: 20)))
            manager = window
        }
        NSApp.activate(ignoringOtherApps: true); manager?.makeKeyAndOrderFront(nil)
    }
}
struct NotesList: View {
    @ObservedObject var store: NoteStore
    let controller: NotesController
    @State private var pending: UUID?
    @State private var showSettings = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    var filteredNotes: [StickyNote] { store.notes.filter { NoteSearch.matches($0, query: query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FeatureGlyph(feature: PocketFeature.all[1], size: 34); Text("Sticky Notes").font(.system(size: 22, weight: .bold, design: .rounded)); Spacer()
                Button { showSettings.toggle() } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Notes settings")
                    .popover(isPresented: $showSettings) { NotesSettings(store: store) }
                Menu("New note") { Button("Text note") { controller.newNote() }; Button("Checklist") { controller.newNote("Checklist") }; Button("Image note") { controller.newNote("Image") } }
            }
            Text("Your notes stay saved here. Open one to keep it in sight.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search titles and note contents…", text: $query).textFieldStyle(.plain).focused($searchFocused)
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("Clear search") }
            }.padding(9).background(Color.primary.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 9))
            if let error = store.error { Text(error).foregroundStyle(.red) }
            if store.notes.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Text("🦩").font(.system(size: 46))
                    Text("Keep a thought nearby").font(.headline)
                    Text("Start a note, make a checklist, or pin an image.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Create your first note") { controller.newNote() }.buttonStyle(.borderedProminent).tint(.orange)
                }.frame(maxWidth: .infinity)
                Spacer()
            }
            else if filteredNotes.isEmpty {
                Spacer(); Text("No matching notes").foregroundStyle(.secondary).frame(maxWidth: .infinity); Spacer()
            }
            else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(filteredNotes) { note in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(note.compactDisplay).font(.system(size: note.hasCompactLabel ? 11 : 14)).lineLimit(1).frame(maxWidth: note.hasCompactLabel ? 80 : nil)
                                    Text(note.title.isEmpty ? "Untitled note" : note.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Spacer()
                                }
                                Button { controller.show(note.id) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        if note.kind == "Image", let name = note.imageFile, let image = NSImage(contentsOf: store.imageURL(name)) {
                                            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity)
                                        } else if note.kind == "Checklist" {
                                            ForEach(Array(note.tasks.prefix(3))) { task in Label(task.text, systemImage: task.done ? "checkmark.circle.fill" : "circle").lineLimit(1) }
                                        } else { Text(note.text.isEmpty ? "Add a thought…" : note.text).lineLimit(4).multilineTextAlignment(.leading) }
                                        Spacer(minLength: 0)
                                    }.font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).frame(height: 68).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("Open " + note.title)
                                HStack {
                                    Text(note.kind).font(.system(size: 10)).foregroundStyle(.secondary)
                                    Spacer()
                                    Button { if store.confirmsDeletion { pending = note.id } else { controller.delete(note.id) } } label: { Image(systemName: "trash").font(.system(size: 10)) }.buttonStyle(.plain).help("Delete note")
                                }
                            }.padding(12).background(note.background.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(note.background.opacity(0.20), lineWidth: 1))
                        }
                    }
                }

            }
        }.padding(18).frame(minWidth: 390, minHeight: 350).background(PocketSurface())
        .alert("Delete this note?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Cancel", role: .cancel) { pending = nil }
            Button("Delete", role: .destructive) { if let id = pending { controller.delete(id) }; pending = nil }
        } message: { Text("This removes the note and its contents permanently.") }
    }
}

@MainActor final class NoteSelection: ObservableObject { @Published var id: UUID? }
final class NoteSwitcherPanel: PocketPanel {
    var onHide: (() -> Void)?
    override func orderOut(_ sender: Any?) { onHide?(); super.orderOut(sender) }
}
struct NoteSwitcherView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var selection: NoteSelection
    let choose: (UUID) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your note symbols").font(.headline)
            Text("Tab or arrows to choose · Enter to open · Esc to dismiss").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                    ForEach(store.notes.filter { $0.state == "compact" }) { note in
                        Button { choose(note.id) } label: {
                            VStack(spacing: 6) {
                                Text(note.compactDisplay).font(.system(size: note.hasCompactLabel ? 14 : 30)).lineLimit(1)
                                Text(note.title).font(.caption).lineLimit(1)
                            }.frame(maxWidth: .infinity).frame(height: 76)
                            .background(selection.id == note.id ? Color.blue.opacity(0.25) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selection.id == note.id ? Color.blue : Color.clear, lineWidth: 2))
                        }.buttonStyle(.plain)
                    }
                }
                if !store.notes.contains(where: { $0.state == "compact" }) {
                    Text("Shrink a note into its symbol first.").foregroundStyle(.secondary).padding(24)
                }
            }
        }.padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
