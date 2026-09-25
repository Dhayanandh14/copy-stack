import AppKit
import SwiftUI

@main
enum ClipStackMain {
    static func main() {
        let app = NSApplication.shared
        // Offscreen render mode: draw the UI to PNGs and exit, no menu bar item.
        if let dir = ProcessInfo.processInfo.environment["CLIPSTACK_RENDER_SHOTS"] {
            app.setActivationPolicy(.accessory)
            Screenshots.run(outputDir: dir)
            exit(0)
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        // Menu-bar only: no Dock icon, no app switcher entry.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var hotKeyIDs: [UInt32] = []
    private let settings = Settings.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        setUpStatusItem()
        rebindHotKeys()

        ClipboardMonitor.shared.onNewClip = { [weak self] in
            self?.refreshStatusTitle()
            if PanelController.shared.isVisible { AppModel.shared.reload() }
        }
        ClipboardMonitor.shared.start()
        AppModel.shared.reload()
        installRemoteTriggers()
        trackFrontmostApp()

        // First run: explain the one permission that matters, once.
        if !UserDefaults.standard.bool(forKey: "didShowWelcome") {
            UserDefaults.standard.set(true, forKey: "didShowWelcome")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.showWelcome() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.shared.stop()
        HotKeyCenter.shared.unregisterAll()
    }

    /// The panel now outlives focus changes, so the paste target has to be
    /// followed continuously — whatever you clicked into last is where a clip
    /// should land.
    private func trackFrontmostApp() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier
            else { return }
            Paster.previousApp = app
        }
    }

    /// Lets other processes open the panel or settings, e.g.
    /// `clipstack-trigger settings`. Handy for scripting and for testing
    /// without reaching for the menu bar.
    private func installRemoteTriggers() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("local.clipstack.openSettings"),
                           object: nil, queue: .main) { [weak self] _ in
            self?.openSettings()
        }
        center.addObserver(forName: .init("local.clipstack.openPanel"),
                           object: nil, queue: .main) { _ in
            PanelController.shared.show()
        }
    }

    /// Re-opening the app from Finder or `open -a` shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        PanelController.shared.show()
        return true
    }

    // MARK: Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                     accessibilityDescription: "ClipStack")
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            PanelController.shared.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open ClipStack  \(settings.mainHotKey.display)",
                     action: #selector(openPanel), keyEquivalent: "").target = self
        menu.addItem(.separator())

        let recent = Store.shared.fetch(query: "", favoritesOnly: false, limit: 8)
        if recent.isEmpty {
            let empty = menu.addItem(withTitle: "No clips yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
        } else {
            for (i, clip) in recent.enumerated() {
                let title = String(clip.displayLabel.prefix(48))
                let mi = menu.addItem(withTitle: "\(i + 1).  \(title)",
                                      action: #selector(pasteFromMenu(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = Int(clip.id)
            }
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Clear History", action: #selector(clearHistory), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClipStack", action: #selector(quit), keyEquivalent: "q").target = self

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil   // restore left-click-opens-panel behaviour
    }

    private func refreshStatusTitle() {
        // Intentionally icon-only; hook for a future count badge.
    }

    // MARK: Menu actions

    @objc private func openPanel() { PanelController.shared.show() }

    @objc private func pasteFromMenu(_ sender: NSMenuItem) {
        let id = Int64(sender.tag)
        guard let clip = Store.shared.fetch(query: "", favoritesOnly: false, limit: 500)
            .first(where: { $0.id == id }) else { return }
        if settings.pasteOnSelect {
            Paster.paste(clip, plainText: false)
        } else {
            Paster.write(clip, plainText: false)
        }
    }

    @objc private func clearHistory() {
        Store.shared.clearHistory()
        AppModel.shared.reload()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: SettingsView().environmentObject(settings))
        let window = NSWindow(contentViewController: host)
        window.title = "ClipStack Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showWelcome() {
        let alert = NSAlert()
        alert.messageText = "ClipStack is running"
        alert.informativeText = """
        Press \(settings.mainHotKey.display) anywhere to open your clipboard history, \
        or click the clipboard icon in the menu bar.

        To have ClipStack paste for you automatically, grant Accessibility \
        permission. Without it everything still works — the clip goes on your \
        clipboard and you press ⌘V.
        """
        alert.addButton(withTitle: "Grant Accessibility…")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Paster.requestAccessibility()
            Paster.openAccessibilitySettings()
        }
    }

    // MARK: Hotkeys

    func rebindHotKeys() {
        for id in hotKeyIDs { HotKeyCenter.shared.unregister(id) }
        hotKeyIDs.removeAll()

        if let id = HotKeyCenter.shared.register(settings.mainHotKey, action: {
            PanelController.shared.toggle()
        }) { hotKeyIDs.append(id) }

        if let id = HotKeyCenter.shared.register(settings.plainHotKey, action: {
            let rows = Store.shared.fetch(query: "", favoritesOnly: false, limit: 1)
            guard let top = rows.first else { return }
            if Settings.shared.pasteOnSelect {
                Paster.rememberFrontmostApp()
                Paster.paste(top, plainText: true)
            } else {
                Paster.write(top, plainText: true)
            }
        }) { hotKeyIDs.append(id) }

        if settings.numberedRecentEnabled {
            bindDigits(modifiers: controlKeyMask | cmdKeyMask, favorites: false)
        }
        if settings.numberedFavoritesEnabled {
            bindDigits(modifiers: controlKeyMask | optionKeyMask, favorites: true)
        }
    }

    private func bindDigits(modifiers: UInt32, favorites: Bool) {
        for (index, keyCode) in HotKeySpec.digitKeyCodes.enumerated() {
            let spec = HotKeySpec(keyCode: keyCode, modifiers: modifiers)
            if let id = HotKeyCenter.shared.register(spec, action: {
                Paster.rememberFrontmostApp()
                AppModel.shared.quickPaste(index: index, favorites: favorites)
            }) { hotKeyIDs.append(id) }
        }
    }
}
