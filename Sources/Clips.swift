import AppKit
import SwiftUI
import ServiceManagement
import Carbon
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

struct Shortcut: Codable, Equatable {
    var key: UInt32 = UInt32(kVK_ANSI_E)
    var command = true
    var option = false
    var control = false
    var shift = false
    static let keys: [(String, UInt32)] = [
        ("A",0),("B",11),("C",8),("D",2),("E",14),("F",3),("G",5),
        ("H",4),("I",34),("J",38),("K",40),("L",37),("M",46),("N",45),
        ("O",31),("P",35),("Q",12),("R",15),("S",1),("T",17),("U",32),
        ("V",9),("W",13),("X",7),("Y",16),("Z",6),
        ("0",29),("1",18),("2",19),("3",20),("4",21),("5",23),("6",22),("7",26),("8",28),("9",25)
    ]
    var valid: Bool { (command || option || control) && Self.keys.contains { $0.1 == key } }
    var modifiers: UInt32 {
        (command ? UInt32(cmdKey) : 0) | (option ? UInt32(optionKey) : 0) |
        (control ? UInt32(controlKey) : 0) | (shift ? UInt32(shiftKey) : 0)
    }
    var label: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") +
        (command ? "⌘" : "") + (Self.keys.first { $0.1 == key }?.0 ?? "?")
    }
    static func load() -> Shortcut {
        guard let data = UserDefaults.standard.data(forKey: "keyboardShortcut"),
              let value = try? JSONDecoder().decode(Shortcut.self, from: data), value.valid else { return Shortcut() }
        return value
    }
}
struct Clip: Codable, Identifiable {
    var id = UUID()
    var text: String
    var imageFile: String?
    var date = Date()
    var favorite = false
}
struct Archive: Codable {
    var clips: [Clip] = []
    var limit = 100
    var paused = false
    mutating func trim() {
        var count = 0
        clips = clips.filter { item in
            if item.favorite { return true }
            count += 1
            return count <= limit
        }
    }
    mutating func addImage(_ filename: String) {
        if let i = clips.firstIndex(where: { $0.imageFile == filename }) {
            var clip = clips.remove(at: i); clip.date = Date(); clips.insert(clip, at: 0)
        } else { clips.insert(Clip(text: "Image", imageFile: filename), at: 0) }
        trim()
    }
    mutating func add(_ text: String) {
        if let index = clips.firstIndex(where: { $0.imageFile == nil && $0.text == text }) {
            var item = clips.remove(at: index)
            item.date = Date()
            clips.insert(item, at: 0)
        } else { clips.insert(Clip(text: text), at: 0) }
        trim()
    }
}
@MainActor
final class Store: ObservableObject {
    @Published var archive = Archive()
    @Published var error: String?
    @Published var shortcut = Shortcut.load()
    var applyShortcut: ((Shortcut) -> String?)?
    var configureFeatures: (() -> Void)?
    private var thumbnails: [String: NSImage] = [:]
    var imageDirectory: URL { file.deletingLastPathComponent().appendingPathComponent("Images", isDirectory: true) }
    func imageURL(_ name: String) -> URL { imageDirectory.appendingPathComponent(URL(fileURLWithPath: name).lastPathComponent) }
    func thumbnail(_ name: String) -> NSImage? {
        if let cached = thumbnails[name] { return cached }
        guard let source = CGImageSourceCreateWithURL(imageURL(name) as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 180] as CFDictionary) else { return nil }
        let result = NSImage(cgImage: cg, size: .zero); thumbnails[name] = result; return result
    }
    static func png(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
    @discardableResult func recordImage(_ data: Data, manual: Bool = false, favorite: Bool = false) -> Bool {
        guard !captureBlocked, manual || !archive.paused else { return false }
        guard data.count <= 50_000_000 else { error = "This image is larger than the 50 MB history limit per image."; return false }
        let name = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + ".png"
        do {
            try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: imageURL(name), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: imageURL(name).path)
            archive.addImage(name)
            if favorite { archive.clips[0].favorite = true }
            return save()
        } catch { self.error = "Could not save image: \(error.localizedDescription)"; return false }
    }
    func addTextManually(_ text: String, favorite: Bool) -> String? {
        guard !captureBlocked else { return "Saved history needs repair before adding items." }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Enter some text first." }
        guard text.utf8.count <= 1_000_000 else { return "Text must be smaller than 1 MB." }
        archive.add(text)
        if favorite { archive.clips[0].favorite = true }
        return save() ? nil : (error ?? "Could not save that entry.")
    }
    func addImageManually(_ data: Data, favorite: Bool) -> String? {
        guard !captureBlocked else { return "Saved history needs repair before adding items." }
        return recordImage(data, manual: true, favorite: favorite) ? nil : (error ?? "Could not add that image.")
    }
    @Published var login = SMAppService.mainApp.status == .enabled
    private let board: NSPasteboard
    private var change: Int
    private var timer: Timer?
    private var captureBlocked = false
    let file: URL
    init(file customFile: URL? = nil, board: NSPasteboard = .general, startTimer: Bool = true) {
        self.board = board
        change = board.changeCount
        file = customFile ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clips", isDirectory: true).appendingPathComponent("history.json")
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: file))
                if ![50,100,200,500,1000].contains(archive.limit) { archive.limit = 100 }
                archive.trim()
            } catch { self.error = "Saved history could not be read. New copies will not be recorded until you restart after repairing the history file."; archive.paused = true; captureBlocked = true }
        }
        if startTimer { timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        } }
    }
    func flushBeforeQuit() -> Bool { captureBlocked || save() }
    @discardableResult func save() -> Bool {
        guard !captureBlocked else { return false }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(archive).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let retained = Set(archive.clips.compactMap(\.imageFile))
            for url in (try? FileManager.default.contentsOfDirectory(at: imageDirectory, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "png" && !retained.contains(url.lastPathComponent) {
                try? FileManager.default.removeItem(at: url)
                thumbnails.removeValue(forKey: url.lastPathComponent)
            }
            return true
        } catch { self.error = "Could not save clipboard history: \(error.localizedDescription)"; return false }
    }
    func poll() {
        guard board.changeCount != change else { return }
        change = board.changeCount
        guard !archive.paused, !captureBlocked else { return }
        let excluded = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword"]
        guard !(board.types ?? []).contains(where: { excluded.contains($0.rawValue) }) else { return }
        if let png = board.data(forType: .png), NSImage(data: png) != nil { recordImage(png); return }
        if let image = NSImage(pasteboard: board), let png = Self.png(image) {
            recordImage(png); return
        }
        guard let text = board.string(forType: .string), !text.isEmpty,
              text.utf8.count <= 1_000_000 else { return }
        archive.add(text); save()
    }
    func copy(_ clip: Clip) {
        let p = board
        if let name = clip.imageFile {
            guard let data = try? Data(contentsOf: imageURL(name)) else { error = "This saved image could not be read."; return }
            p.clearContents(); p.setData(data, forType: .png)
        } else { p.clearContents(); p.setString(clip.text, forType: .string) }
        change = p.changeCount
    }
    func favorite(_ clip: Clip) {
        guard let i = archive.clips.firstIndex(where: { $0.id == clip.id }) else { return }
        archive.clips[i].favorite.toggle(); archive.trim(); save()
    }
    func remove(_ clip: Clip) { archive.clips.removeAll { $0.id == clip.id }; save() }
    func setLimit(_ value: Int) { archive.limit = value; archive.trim(); save() }
    func pause(_ value: Bool) { archive.paused = value; change = board.changeCount; save() }
    func setLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            login = SMAppService.mainApp.status == .enabled
            if value && !login { error = "Approve Pocket under System Settings → General → Login Items." }
        } catch { self.error = error.localizedDescription }
    }
}
struct FrostedBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.alphaValue = 0.72
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
struct ResizeGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> GripView { GripView() }
    func updateNSView(_ view: GripView, context: Context) {}
}
final class GripView: NSView {
    private var start = NSPoint.zero
    private var initial = NSRect.zero
    override var mouseDownCanMoveWindow: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        for offset in [CGFloat(0), 5, 10] {
            path.move(to: NSPoint(x: 5 + offset, y: 3))
            path.line(to: NSPoint(x: 16, y: 14 - offset))
        }
        path.stroke()
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        start = NSEvent.mouseLocation
        initial = window?.frame ?? .zero
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let point = NSEvent.mouseLocation
        let screen = window.screen?.visibleFrame ?? initial
        let width = max(window.minSize.width, min(initial.width + point.x - start.x, screen.maxX - initial.minX))
        let height = max(window.minSize.height, min(initial.height - point.y + start.y, initial.maxY - screen.minY))
        window.setFrame(NSRect(x: initial.minX, y: initial.maxY - height, width: width, height: height), display: true)
    }
    override func mouseUp(with event: NSEvent) { if window is ClipboardPanel { window?.saveFrame(usingName: "ClipsHistoryWindow") } }
}
struct ShortcutSettings: View {
    @ObservedObject var store: Store
    var onDone: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Shortcut()
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clipboard shortcut").font(.headline)
            HStack {
                Toggle("⌘", isOn: $draft.command)
                Toggle("⌥", isOn: $draft.option)
                Toggle("⌃", isOn: $draft.control)
                Toggle("⇧", isOn: $draft.shift)
            }.toggleStyle(.checkbox)
            Picker("Key", selection: $draft.key) {
                ForEach(Shortcut.keys, id: \.1) { Text($0.0).tag($0.1) }
            }
            Text(draft.label).font(.title3.monospaced())
            Text("Choose Command, Option, or Control plus a key. This replaces that combination in other apps while Pocket runs.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Default") { draft = Shortcut(); error = nil }
                Spacer()
                Button("Cancel") { dismiss(); onDone?() }
                Button("Save") {
                    let message = store.applyShortcut?(draft)
                    if let message { error = message } else { dismiss(); onDone?() }
                }.disabled(!draft.valid)
            }
        }.padding(16).frame(width: 280)
        .onAppear { loadDraft() }
    }
    func loadDraft() {
        draft = store.shortcut
    }
}
struct ClipboardView: View {
    @ObservedObject var store: Store
    var close: () -> Void
    @State private var query = ""
    @State private var confirmClear = false
    @State private var shortcutSettings = false
    @State private var addingItem = false
    @State private var pendingDelete: Set<UUID> = []
    @State private var selected: Set<UUID> = []
    @State private var selectionAnchor: UUID?
    func select(_ id: UUID, checked: Bool) {
        let order = items.map(\.id)
        if NSEvent.modifierFlags.contains(.shift), let anchor = selectionAnchor,
           let start = order.firstIndex(of: anchor), let end = order.firstIndex(of: id) {
            selected.formUnion(order[min(start, end)...max(start, end)])
        } else {
            if checked { selected.insert(id) } else { selected.remove(id) }
            selectionAnchor = id
        }
    }
    @State private var confirmDelete = false
    func delete(_ clip: Clip) { requestDelete([clip.id]) }
    func requestDelete(_ ids: Set<UUID>) {
        let existing = ids.intersection(Set(store.archive.clips.map(\.id)))
        guard !existing.isEmpty else { return }
        if store.archive.clips.contains(where: { existing.contains($0.id) && $0.favorite }) {
            pendingDelete = existing; confirmDelete = true
        } else { remove(existing) }
    }
    func remove(_ ids: Set<UUID>) {
        store.archive.clips.removeAll { ids.contains($0.id) }
        selected.subtract(ids)
        store.save()
    }
    var items: [Clip] {
        let matching = store.archive.clips.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }
        return matching.filter { $0.favorite } + matching.filter { !$0.favorite }
    }
    var body: some View {
        VStack(spacing: 7) {
            WindowDragHandle().frame(height: 12).help("Drag to move clipboard")
            HStack {
                FeatureGlyph(feature: PocketFeature.all[0], size: 23)
                Text("Clipboard").font(.system(size: 13, weight: .semibold))
                if store.archive.paused { Text("Paused").foregroundStyle(.secondary) }
                Spacer()
                Button { addingItem = true } label: { Image(systemName: "plus") }.buttonStyle(.plain).help("Add text or an image").accessibilityLabel("Add item")
                Menu {
                    Button("Add item…") { addingItem = true }
                    Picker("History limit", selection: Binding(get: { store.archive.limit }, set: store.setLimit)) {
                        ForEach([50,100,200,500,1000], id: \.self) { Text("\($0) recent items").tag($0) }
                    }
                    Button("Features & Icons…") { store.configureFeatures?() }
                    Button("Keyboard Shortcuts…") { shortcutSettings = true }
                    Toggle("Pause history", isOn: Binding(get: { store.archive.paused }, set: store.pause))
                    Toggle("Start at login", isOn: Binding(get: { store.login }, set: store.setLogin))
                    Button("Clear recent history…") { confirmClear = true }
                    Divider()
                    Button("Quit Pocket") { NSApp.terminate(nil) }
                } label: { Image(systemName: "gearshape") }.menuStyle(.borderlessButton).frame(width: 28)
            }
            TextField("Search history", text: $query).textFieldStyle(.roundedBorder)
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if items.isEmpty {
                Spacer()
                Image(systemName: "doc.on.clipboard").font(.largeTitle).foregroundStyle(.secondary)
                Text(query.isEmpty ? "Copy text or an image to get started." : "No matching clips.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { clip in
                            HStack(alignment: .center, spacing: 4) {
                                Toggle("Select item", isOn: Binding(
                                    get: { selected.contains(clip.id) },
                                    set: { select(clip.id, checked: $0) }
                                )).toggleStyle(.checkbox).labelsHidden().controlSize(.mini)
                                    .accessibilityLabel("Select item").padding(.leading, 5)
                                Button {
                                    store.copy(clip); close()
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        if let name = clip.imageFile, let image = store.thumbnail(name) {
                                            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, alignment: .leading).frame(height: 48).accessibilityLabel("Copied image")
                                        } else { Text(clip.text).font(.system(size: 11)).lineLimit(2).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                                    }.padding(.vertical, 3).padding(.horizontal, 2).contentShape(Rectangle())
                                }.buttonStyle(.plain).help("Copy this item, then paste with ⌘V")
                                Button { delete(clip) } label: {
                                    Image(systemName: "trash").font(.system(size: 10)).foregroundStyle(.secondary)
                                }.buttonStyle(.plain).help("Delete item").accessibilityLabel("Delete item")
                                Button { store.favorite(clip) } label: {
                                    Image(systemName: clip.favorite ? "star.fill" : "star").foregroundStyle(clip.favorite ? Color.yellow : Color.secondary)
                                }.buttonStyle(.plain).font(.system(size: 11)).help(clip.favorite ? "Remove favorite" : "Keep as favorite")
                            }.padding(.trailing, 7).background(Color.primary.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 8))
                            .contextMenu { Button("Delete item", role: .destructive) { delete(clip) } }
                        }
                    }
                }
            }
            Divider()
            HStack {
                if selected.isEmpty {
                    Text("Click to copy · ⌘V to paste").foregroundStyle(.secondary)
                } else {
                    Button("Deselect") { selected.removeAll(); selectionAnchor = nil }.buttonStyle(.plain)
                    Spacer()
                    Button("Delete selected (\(selected.count))") { requestDelete(selected) }
                        .buttonStyle(.borderless)
                }
            }.font(.caption).frame(height: 16)
            Text("\(store.archive.clips.filter { !$0.favorite }.count)/\(store.archive.limit) recent · \(store.archive.clips.filter { $0.favorite }.count) favorites kept")
                .font(.caption2).foregroundStyle(.secondary)
        }.font(.system(size: 11)).padding(10).frame(minWidth: 260, maxWidth: .infinity, minHeight: 220, maxHeight: .infinity)
        .background(FrostedBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .bottomTrailing) { ResizeGrip().frame(width: 18, height: 18).padding(3) }
        .onChange(of: query) { _ in selected.removeAll(); selectionAnchor = nil }
        .onChange(of: store.archive.clips.map(\.id)) { ids in selected.formIntersection(Set(ids)) }
        .sheet(isPresented: $addingItem) { AddClipboardItem(store: store) }
        .sheet(isPresented: $shortcutSettings) { ShortcutSettings(store: store) }
        .alert("Delete selected favorites?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) { pendingDelete.removeAll() }
            Button("Delete", role: .destructive) {
                remove(pendingDelete)
                pendingDelete.removeAll()
            }
        } message: { Text("Delete \(pendingDelete.count) selected item(s), including saved favorites? This cannot be undone.") }
        .alert("Clear recent history?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { store.archive.clips.removeAll { !$0.favorite }; store.save() }
        } message: { Text("Favorites will stay saved. This does not clear the current system clipboard.") }
    }
}
final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var dismissClipboard: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { dismissClipboard?() }
}
@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var panel: NSPanel!
    var notesItem: NSStatusItem!
    var access = AccessPreferences.load()
    let notes = NotesController()
    var welcomeWindow: NSWindow?
    var chooserWindow: NSWindow?
    var shortcutWindow: NSWindow?
    var store: Store!
    var noteHotKeys: [Int: EventHotKeyRef] = [:]
    var hotKey: EventHotKeyRef?
    var handler: EventHandlerRef?
    var outsideClicks: Any?
    var insideClicks: Any?
    var escapeMonitor: Any?
    var activationObserver: NSObjectProtocol?
    var lastExternalApp: NSRunningApplication?
    var clipboardReturnApp: NSRunningApplication?
    weak var clipboardReturnWindow: NSWindow?
    weak var clipboardReturnResponder: NSResponder?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if NSRunningApplication.runningApplications(withBundleIdentifier: "local.clips.app").contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) { NSApp.terminate(nil); return }
        lastExternalApp = NSWorkspace.shared.frontmostApplication
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.lastExternalApp = app }
        }
        for index in 0...2 { UserDefaults.standard.removeObject(forKey: "captureShortcut-\(index)") }
        store = Store()
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) { NSApp.applicationIconImage = icon }
        installMainMenu()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(featureRequested), name: NSNotification.Name("local.pocket.openFeature"), object: nil)
        notes.activateDock = { NSApp.setActivationPolicy(.regular) }
        store.configureFeatures = { [weak self] in self?.showWelcome() }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Pocket")
        item.button?.toolTip = "Pocket — clipboard history (⌘E)"
        item.button?.target = self; item.button?.action = #selector(toggle)
        panel = ClipboardPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 340),
                        styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        (panel as? ClipboardPanel)?.dismissClipboard = { [weak self] in self?.closeClipboard() }
        panel.title = "Pocket · ⌘E"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 260, height: 220)
        panel.setFrameAutosaveName("ClipsHistoryWindow")
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismissUtilities() }
        }
        insideClicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            if let target = event.window, target.level >= .popUpMenu { return event }
            self?.dismissUtilities(except: event.window)
            return event
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.notes.handleSwitcherKey(event) == true { return nil }
            if event.keyCode == 53, let self, NSApp.modalWindow == nil,
               let current = event.window, self.utilityWindows.contains(where: { $0 === current }), current.attachedSheet == nil {
                if current === self.panel { self.closeClipboard() } else { current.orderOut(nil) }; return nil
            }
            return event
        }
        store.applyShortcut = { [weak self] value in
            guard let self else { return "Shortcut service is unavailable." }
            return self.updateShortcut(value)
        }
        notes.store.applyShortcut = { [weak self] index, value in
            guard let self else { return "Shortcut service is unavailable." }
            return self.updateNoteShortcut(index, value)
        }
        installShortcut()
        makeFeatureIcons()
        configureAccess()
        notes.restore()
        if access.hasNewFeatures { showWelcome() }
        else if let index = CommandLine.arguments.firstIndex(of: "--feature"), CommandLine.arguments.count > index + 1 { openFeature(CommandLine.arguments[index + 1]) }
        else if !store.login { showChooser() }
    }
    func installShortcut() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<Delegate>.fromOpaque(context).takeUnretainedValue()
            var hotID = EventHotKeyID()
            guard let event, GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotID) == noErr else { return OSStatus(eventNotHandledErr) }
            let id = hotID.id
            Task { @MainActor in
                if id == 1 { delegate.toggle() }
                if id == 2 { delegate.dismissUtilities(except: delegate.notes.switcher); delegate.notes.showSwitcher() }
                if id == 3 { delegate.notes.shrinkActiveNote() }
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if installed != noErr {
            store.error = "Keyboard shortcut setup failed. Use the menu-bar icon."
        } else {
            if let message = updateShortcut(store.shortcut) { store.error = message }
            for index in 0..<2 { if let message = updateNoteShortcut(index, notes.store.shortcuts[index]) { notes.store.error = message } }
        }
    }
    func updateNoteShortcut(_ index: Int, _ value: Shortcut) -> String? {
        guard value.valid, handler != nil else { return "Choose a valid shortcut with Command, Option, or Control." }
        guard value != store.shortcut, !notes.store.shortcuts.enumerated().contains(where: { $0.offset != index && $0.element == value }) else { return "That shortcut is already used by another Pocket action." }
        if notes.store.shortcuts[index] == value, noteHotKeys[index] != nil { return nil }
        var replacement: EventHotKeyRef?
        guard RegisterEventHotKey(value.key, value.modifiers, EventHotKeyID(signature: 0x434C4950, id: UInt32(index + 2)), GetApplicationEventTarget(), 0, &replacement) == noErr, let replacement else { return "That shortcut is unavailable. Try another combination." }
        if let old = noteHotKeys[index] { UnregisterEventHotKey(old) }
        noteHotKeys[index] = replacement; notes.store.saveShortcut(index, value); return nil
    }
    func updateShortcut(_ value: Shortcut) -> String? {
        guard !notes.store.shortcuts.contains(value) else { return "That shortcut is already used by a Notes action." }
        guard value.valid else { return "Choose a key and at least Command, Option, or Control." }
        guard handler != nil else { return "Keyboard shortcut setup failed. Restart Pocket to try again." }
        if value == store.shortcut, hotKey != nil { return nil }
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(value.key, value.modifiers,
            EventHotKeyID(signature: 0x434C4950, id: 1), GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr, let replacement else {
            return "That shortcut is unavailable. Try another combination; your previous shortcut is unchanged."
        }
        if let old = hotKey { UnregisterEventHotKey(old) }
        hotKey = replacement
        store.shortcut = value
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "keyboardShortcut") }
        item?.button?.toolTip = "Pocket — clipboard history (\(value.label))"
        panel.title = "Pocket · \(value.label)"
        return nil
    }
    func closeClipboard() {
        panel.orderOut(nil)
        let target = clipboardReturnApp
        let window = clipboardReturnWindow
        let responder = clipboardReturnResponder
        clipboardReturnApp = nil; clipboardReturnWindow = nil; clipboardReturnResponder = nil
        // A click into another app already chose a new destination; never steal it back.
        guard NSApp.isActive else { return }
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            if let responder { window.makeFirstResponder(responder) }
        } else if let target, !target.isTerminated {
            target.activate(options: [])
        }
    }
    func show() {
        if !panel.isVisible {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                clipboardReturnApp = front
                clipboardReturnWindow = nil; clipboardReturnResponder = nil
            } else if let window = NSApp.keyWindow, window !== panel, window !== chooserWindow {
                clipboardReturnWindow = window; clipboardReturnResponder = window.firstResponder
                clipboardReturnApp = nil
            } else {
                clipboardReturnApp = lastExternalApp
                clipboardReturnWindow = nil; clipboardReturnResponder = nil
            }
        }
        dismissUtilities(except: panel)
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main!
        let visible = screen.visibleFrame
        var frame = panel.frame
        panel.contentViewController = NSHostingController(rootView: ClipboardView(store: store,
            close: { [weak self] in self?.closeClipboard() }))
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height - 16)
        // First launch starts comfortably below the menu bar; later opens keep the dragged position.
        if !UserDefaults.standard.bool(forKey: "panelPositioned") {
            frame.origin = NSPoint(x: visible.maxX - frame.width - 24, y: visible.maxY - frame.height - 32)
            UserDefaults.standard.set(true, forKey: "panelPositioned")
        }
        frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
        frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height - 16))
        panel.setFrame(frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    @objc func toggle() { if panel.isVisible && panel.isKeyWindow { closeClipboard() } else { show() } }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if access.hasNewFeatures { showWelcome() } else { showChooser() }; return false }
    @objc func featureRequested(_ notification: Notification) { if let feature = notification.object as? String { openFeature(feature) } }
    func openFeature(_ feature: String) {
        chooserWindow?.orderOut(nil)
        switch feature { case "clipboard": show(); case "notes": showNotes(); default: showChooser() }
    }
    func window<V: View>(_ title: String, _ view: V) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: view)
        window.center(); return window
    }
    func present(_ window: NSWindow?) { NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) }
    @objc func showWelcome() {
        welcomeWindow?.close()
        welcomeWindow = window("Pocket · Features & Icons", WelcomeView(draft: access) { [weak self] value in
            guard let self else { return }
            self.access = value; value.save(); self.configureAccess(); self.welcomeWindow?.close(); self.showChooser()
        })
        present(welcomeWindow)
    }
    @objc func showChooser() {
        if chooserWindow == nil { chooserWindow = window("Pocket", ToolChooser(store: store, open: { [weak self] feature in self?.chooserWindow?.orderOut(nil); self?.openFeature(feature) }, configure: { [weak self] in self?.showWelcome() })) }
        present(chooserWindow)
    }
    @objc func showNotes() { dismissUtilities(); notes.showManager() }
    @objc func newNote() { notes.newNote() }
    @objc func newChecklist() { notes.newNote("Checklist") }
    @objc func newImageNote() { notes.newNote("Image") }
    @objc func showShortcutSettings() {
        shortcutWindow = window("Pocket Shortcuts", ShortcutSettings(store: store, onDone: { [weak self] in self?.shortcutWindow?.close() })); present(shortcutWindow)
    }
    @objc func quitPocket() { NSApp.terminate(nil) }
    func menuItem(_ title: String, _ action: Selector) -> NSMenuItem { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; return item }
    func installMainMenu() {
        let main = NSMenu()
        let appRoot = NSMenuItem(); let appMenu = NSMenu(title: "Pocket")
        appMenu.addItem(menuItem("Features & Icons…", #selector(showWelcome)))
        appMenu.addItem(.separator())
        let quit = menuItem("Quit Pocket", #selector(quitPocket)); quit.keyEquivalent = "q"; appMenu.addItem(quit)
        appRoot.submenu = appMenu; main.addItem(appRoot)
        let editRoot = NSMenuItem(); let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        editRoot.submenu = edit; main.addItem(editRoot)
        let toolsRoot = NSMenuItem(); let tools = NSMenu(title: "Tools")
        tools.addItem(menuItem("Clipboard", #selector(showClipboard))); tools.addItem(menuItem("Sticky Notes", #selector(showNotes))); tools.addItem(menuItem("Switch note symbols…", #selector(switchNotes)))
        toolsRoot.submenu = tools; main.addItem(toolsRoot)
        let windowRoot = NSMenuItem(); let windows = NSMenu(title: "Window")
        windows.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowRoot.submenu = windows; main.addItem(windowRoot)
        NSApp.mainMenu = main; NSApp.windowsMenu = windows
    }
    @objc func switchNotes() { dismissUtilities(except: notes.switcher); notes.showSwitcher() }
    func makeFeatureIcons() {
        notesItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        notesItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Pocket Notes"); notesItem.button?.toolTip = "Pocket Notes"
        let menu = NSMenu(); menu.addItem(menuItem("New text note", #selector(newNote))); menu.addItem(menuItem("New checklist", #selector(newChecklist))); menu.addItem(menuItem("New image note", #selector(newImageNote))); menu.addItem(menuItem("All notes…", #selector(showNotes))); menu.addItem(menuItem("Switch note symbols…", #selector(switchNotes))); menu.addItem(.separator()); menu.addItem(menuItem("Features & Icons…", #selector(showWelcome))); menu.addItem(menuItem("Quit Pocket", #selector(quitPocket)))
        notesItem.menu = menu
    }
    func configureAccess() {
        DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("local.pocket.quitLaunchers"), object: "screenshots", userInfo: nil, deliverImmediately: true)
        item.isVisible = access.inMenu("clipboard"); notesItem.isVisible = access.inMenu("notes")
        let sharedDock = access.dockStyle == "One Pocket icon" && PocketFeature.all.contains(where: { access.inDock($0.id) })
        NSApp.setActivationPolicy(sharedDock ? .regular : .accessory)
        for feature in PocketFeature.all {
            if access.inDock(feature.id) && !sharedDock {
                let title = feature.id == "notes" ? "Notes" : feature.name
                let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Pocket \(title).app")
                let config = NSWorkspace.OpenConfiguration(); config.activates = false; config.arguments = ["--background"]
                NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
                    if let error { Task { @MainActor in self?.store.error = "Could not open Dock launcher: \(error.localizedDescription)" } }
                }
            } else { DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("local.pocket.quitLaunchers"), object: feature.id, userInfo: nil, deliverImmediately: true) }
        }
    }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu(); menu.addItem(menuItem("Clipboard", #selector(showClipboard))); menu.addItem(menuItem("Sticky Notes", #selector(showNotes))); menu.addItem(menuItem("Features & Icons…", #selector(showWelcome))); return menu
    }
    @objc func showClipboard() { show() }
    var utilityWindows: [NSWindow?] { [panel, notes.manager, notes.switcher] }
    func dismissUtilities(except window: NSWindow? = nil) { PanelDismissal.dismiss(utilityWindows, except: window) }
    func applicationDidResignActive(_ notification: Notification) { dismissUtilities() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let historySaved = store?.flushBeforeQuit() ?? true
        let notesSaved = notes.store.flushBeforeQuit()
        guard historySaved && notesSaved else {
            let alert = NSAlert(); alert.messageText = "Pocket couldn’t save your latest changes"
            alert.informativeText = "Pocket will stay open so your unsaved changes are not lost. Check available disk space and try quitting again."
            alert.addButton(withTitle: "Keep Pocket open"); NSApp.activate(ignoringOtherApps: true); alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("local.pocket.quitLaunchers"), object: "all", userInfo: nil, deliverImmediately: true)
        DistributedNotificationCenter.default().removeObserver(self)
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        if let insideClicks { NSEvent.removeMonitor(insideClicks) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        for key in noteHotKeys.values { UnregisterEventHotKey(key) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
@main
struct Main {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--test-windows") { WindowTests.run(); return }
        if CommandLine.arguments.contains("--test") {
            let defaultShortcut = Shortcut()
            precondition(defaultShortcut.valid && defaultShortcut.label == "⌘E" && defaultShortcut.modifiers == UInt32(cmdKey))
            var alternate = Shortcut(key: 8, command: false, option: true, control: true, shift: true)
            precondition(alternate.valid && alternate.label == "⌃⌥⇧C")
            precondition(try! JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(alternate)) == alternate)
            alternate.option = false; alternate.control = false
            precondition(!alternate.valid)
            alternate.command = true; alternate.key = 999
            precondition(!alternate.valid)
            precondition(Set(Shortcut.keys.map { $0.1 }).count == Shortcut.keys.count)
            print("PASS: shortcut defaults, modifier combinations, validation, persistence, unique keys")
            var a = Archive(limit: 50)
            a.add("favorite"); a.clips[0].favorite = true
            for i in 0..<205 { a.add("item \(i)") }
            precondition(a.clips.count == 51 && a.clips.contains { $0.text == "favorite" })
            a.add("favorite"); precondition(a.clips[0].favorite && a.clips.count == 51)
            for i in 0..<60 { a.add("star \(i)"); a.clips[0].favorite = true }
            precondition(a.clips.filter(\.favorite).count == 61)
            a.limit = 100
            for i in 0..<120 { a.add("more \(i)") }
            precondition(a.clips.filter { !$0.favorite }.count == 100)
            a.limit = 50; a.trim()
            precondition(a.clips.count == 111)
            let b = try! JSONDecoder().decode(Archive.self, from: JSONEncoder().encode(a))
            precondition(b.clips.count == 111 && b.clips[0].text == a.clips[0].text)
            a.clips.removeAll { !$0.favorite }; precondition(a.clips.count == 61)
            print("PASS: retention limits, duplicate favorites, unlimited favorites, persistence, clear preserves favorites")
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("Pocket-test-" + UUID().uuidString)
            let board = NSPasteboard.withUniqueName()
            defer { try? FileManager.default.removeItem(at: temp); board.releaseGlobally() }
            let file = temp.appendingPathComponent("history.json")
            let store = Store(file: file, board: board, startTimer: false)
            let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                NSColor.systemTeal.setFill(); rect.fill(); return true
            }
            let png = Store.png(image)!
            board.clearContents(); board.setData(png, forType: .png); store.poll()
            precondition(store.archive.clips.count == 1)
            let name = store.archive.clips[0].imageFile!
            precondition(store.thumbnail(name) != nil)
            store.favorite(store.archive.clips[0])
            board.clearContents(); board.setData(png, forType: .png); store.poll()
            precondition(store.archive.clips.count == 1 && store.archive.clips[0].favorite)
            board.clearContents(); board.setData(image.tiffRepresentation!, forType: .tiff); store.poll()
            precondition(store.archive.clips[0].imageFile != nil)
            if store.archive.clips.count == 2 { store.remove(store.archive.clips[0]) }
            store.copy(store.archive.clips[0]); precondition(NSImage(pasteboard: board) != nil)
            store.poll(); precondition(store.archive.clips.count == 1)
            board.clearContents(); board.setString("mixed text", forType: .string); store.poll()
            precondition(store.archive.clips.count == 2)
            let restored = Store(file: file, board: board, startTimer: false)
            precondition(restored.archive.clips.count == 2 && restored.archive.clips[1].favorite)
            precondition(restored.thumbnail(name) != nil)
            store.pause(true); board.clearContents(); board.setString("skip", forType: .string); store.poll()
            precondition(store.archive.clips.count == 2)
            store.pause(false); board.clearContents(); board.setData(png, forType: .png)
            board.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")); store.poll()
            precondition(store.archive.clips[0].text == "mixed text")
            store.remove(store.archive.clips[1]); precondition(!FileManager.default.fileExists(atPath: store.imageURL(name).path))
            store.pause(true)
            precondition(store.addTextManually("manual favorite", favorite: true) == nil)
            precondition(store.archive.paused && store.archive.clips[0].favorite)
            precondition(store.addImageManually(png, favorite: true) == nil)
            precondition(store.archive.paused && store.archive.clips[0].favorite && store.archive.clips[0].imageFile != nil)
            precondition(store.addTextManually("   ", favorite: false) != nil)
            precondition(store.addTextManually(String(repeating: "x", count: 1_000_001), favorite: false) != nil)
            let old = "{\"clips\":[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"text\":\"old favorite\",\"date\":0,\"favorite\":true}],\"limit\":100,\"paused\":false}"
            let legacy = try! JSONDecoder().decode(Archive.self, from: Data(old.utf8))
            precondition(legacy.clips[0].favorite && legacy.clips[0].imageFile == nil)
            var mixed = Archive(limit: 50)
            mixed.addImage("favorite.png"); mixed.clips[0].favorite = true
            for i in 0..<100 { if i % 2 == 0 { mixed.addImage("\(i).png") } else { mixed.add("\(i)") } }
            precondition(mixed.clips.count == 51 && mixed.clips.contains { $0.favorite })
            precondition(store.flushBeforeQuit())
            let afterQuit = Store(file: file, board: board, startTimer: false)
            precondition(afterQuit.archive.clips.map(\.id) == store.archive.clips.map(\.id))
            precondition(afterQuit.archive.clips.map(\.favorite) == store.archive.clips.map(\.favorite))
            let blockedParent = temp.appendingPathComponent("not-a-directory")
            try! Data("test".utf8).write(to: blockedParent)
            let cannotSave = Store(file: blockedParent.appendingPathComponent("history.json"), board: board, startTimer: false)
            precondition(!cannotSave.flushBeforeQuit() && cannotSave.error != nil)
            FeatureTests.run()
            print("PASS: PNG/TIFF capture, thumbnail, image deduplication, copy back, image favorite persistence, pause, concealed image exclusion, orphan cleanup, legacy migration, mixed retention")
            return
        }
        let app = NSApplication.shared
        let delegate = Delegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
