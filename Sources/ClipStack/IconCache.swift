import AppKit

/// `NSWorkspace.urlForApplication` + `icon(forFile:)` hit LaunchServices and the
/// disk. Doing that per row per render made scrolling and selection crawl, so
/// icons are resolved once per bundle id.
final class IconCache {
    static let shared = IconCache()

    private var icons: [String: NSImage?] = [:]
    private let lock = NSLock()

    private init() {}

    func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let hit = icons[bundleID] { return hit }
        var resolved: NSImage?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 42, height: 42)
            resolved = icon
        }
        icons[bundleID] = resolved
        return resolved
    }
}
