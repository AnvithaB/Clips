import AppKit

// Small Dock entry that forwards opening/reopening to its parent app.
@main struct LauncherMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = LauncherDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
@MainActor final class LauncherDelegate: NSObject, NSApplicationDelegate {
    var feature: String { Bundle.main.object(forInfoDictionaryKey: "PocketFeature") as? String ?? "clipboard" }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: icon) { NSApp.applicationIconImage = image }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(quit), name: NSNotification.Name("local.pocket.quitLaunchers"), object: nil)
        if !ProcessInfo.processInfo.arguments.contains("--background") { openTool() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openTool(); return false }
    func openTool() {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "local.clips.app").isEmpty {
            DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("local.pocket.openFeature"), object: feature, userInfo: nil, deliverImmediately: true)
            return
        }
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--feature", feature]
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: parent, configuration: configuration) { _, _ in }
    }
    @objc func quit(_ notification: Notification) {
        if notification.object as? String == "all" || notification.object as? String == feature { NSApp.terminate(nil) }
    }
}
