import AppKit
import CryptoKit
import SwiftUI

/// Renders the real UI offscreen to PNGs, for the README and for eyeballing
/// layout changes without having to drive the app by hand.
/// Triggered by `CLIPSTACK_RENDER_SHOTS=<output dir>`.
enum Screenshots {
    static func run(outputDir: String) {
        let dir = URL(fileURLWithPath: outputDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        seedSampleData()
        AppModel.shared.reload()
        AppModel.shared.selection = 1

        for (name, appearance) in [("light", NSAppearance(named: .aqua)),
                                   ("dark", NSAppearance(named: .darkAqua))] {
            let panel = PanelView()
                .environmentObject(AppModel.shared)
                .environmentObject(Settings.shared)
            capture(AnyView(panel), size: NSSize(width: 400, height: 720),
                    appearance: appearance, to: dir.appendingPathComponent("panel-\(name).png"))
        }

        let settings = SettingsView().environmentObject(Settings.shared)
        capture(AnyView(settings), size: NSSize(width: 516, height: 436),
                appearance: NSAppearance(named: .aqua),
                to: dir.appendingPathComponent("settings-light.png"))

        print("rendered to \(dir.path)")
    }

    /// Offscreen window + cacheDisplay. AppKit-backed SwiftUI (HSplitView,
    /// ScrollView, segmented controls) needs a real window to lay out, so an
    /// ImageRenderer pass isn't enough here.
    private static func capture(_ view: AnyView, size: NSSize,
                                appearance: NSAppearance?, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = appearance

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000)) // offscreen
        window.setIsVisible(true)
        window.displayIfNeeded()

        // Let SwiftUI settle: async layout, image decode, icon loading.
        for _ in 0..<60 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            print("  \(url.lastPathComponent)  \(rep.pixelsWide)×\(rep.pixelsHigh)")
        }
        window.setIsVisible(false)
    }

    // MARK: Sample content

    private static func seedSampleData() {
        Store.shared.clearEverything()

        let samples: [(ClipKind, String, String?, String?, String?)] = [
            (.text, "https://github.com/anthropics/claude-code/releases/tag/v2.1.4", nil, "Safari", "com.apple.Safari"),
            (.text, "docker compose -f infra/docker-compose.yml up -d postgres redis", nil, "Terminal", "com.apple.Terminal"),
            (.text, "Hey — can you take a look at the auth PR before standup? Blocking two other tickets.", nil, "Slack", "com.tinyspeck.slackmacgap"),
            (.text, "ENG-4821", "Linear ticket — token refresh", "Linear", "com.linear"),
            (.text, "SELECT user_id, COUNT(*) AS sessions\nFROM events\nWHERE created_at > now() - interval '7 days'\nGROUP BY 1\nORDER BY 2 DESC\nLIMIT 50;", "Weekly active query", "TablePlus", "com.tinyapp.TablePlus"),
            (.text, "alex@example.com", "Work email", "Notes", "com.apple.Notes"),
            (.image, "Size: 1280x720", nil, "Preview", "com.apple.Preview"),
            (.text, "npm run build && npm run test:e2e -- --headed", nil, "Terminal", "com.apple.Terminal"),
            (.fileURL, "/Users/you/Projects/ClipStack/README.md", nil, "Finder", "com.apple.finder"),
            (.text, "The quarterly numbers landed 12% above forecast, driven mostly by the enterprise tier.", nil, "Mail", "com.apple.mail"),
            (.image, "Size: 397x905", nil, "Safari", "com.apple.Safari"),
            (.text, "git rebase -i HEAD~4", nil, "Terminal", "com.apple.Terminal"),
        ]

        for (index, s) in samples.enumerated() {
            let (kind, text, title, appName, bundleID) = s
            var blob: Data?
            if kind == .image {
                blob = sampleImagePNG(portrait: text.contains("397"))
            }
            let digest = SHA256.hash(data: Data("\(index)-\(text)".utf8))
                .map { String(format: "%02x", $0) }.joined()
            let id = Store.shared.insert(kind: kind, text: text, appName: appName,
                                         appBundleID: bundleID, blob: blob, digest: digest)
            if let title { Store.shared.setTitle(id: id, title) }
            if index == 3 || index == 5 { Store.shared.setFavorite(id: id, true) }
            // Newest first, spread over the last couple of days.
            Store.shared.backdate(id: id, bySeconds: sampleAges[index])
        }
    }

    private static let sampleAges: [TimeInterval] = [
        18, 95, 240, 780, 1_500, 3_400, 7_200, 14_000, 32_000, 61_000, 104_000, 180_000,
    ]

    /// A neutral gradient stand-in for "someone copied a screenshot".
    private static func sampleImagePNG(portrait: Bool = false) -> Data? {
        let size = portrait ? NSSize(width: 180, height: 320) : NSSize(width: 320, height: 180)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.35, green: 0.48, blue: 0.78, alpha: 1),
            NSColor(calibratedRed: 0.62, green: 0.40, blue: 0.72, alpha: 1),
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 35)
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
