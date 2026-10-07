import AppKit
import SwiftUI

/// Borderless floating panel. NSPanel refuses key status by default, so we
/// override it — the search field needs to receive typing.
final class ClipPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PanelController: NSObject, NSWindowDelegate {
    static let shared = PanelController()

    private var panel: ClipPanel?
    private let model = AppModel.shared
    private var localMonitor: Any?

    var isVisible: Bool { panel?.isVisible ?? false }

    /// The panel window, for attaching sheets.
    var hostWindow: NSWindow? { panel?.isVisible == true ? panel : nil }

    private override init() { super.init() }

    // MARK: Lifecycle

    private func makePanel() -> ClipPanel {
        let p = ClipPanel(
            contentRect: NSRect(x: 0, y: 0,
                                width: Settings.shared.panelWidth,
                                height: Settings.shared.panelHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable,
                        .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            p.standardWindowButton(button)?.isHidden = false
        }
        p.delegate = self
        p.minSize = NSSize(width: 330, height: 360)

        let host = NSHostingView(rootView: PanelView().environmentObject(model).environmentObject(Settings.shared))
        host.frame = p.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        p.contentView = host
        return p
    }

    func show() {
        Paster.rememberFrontmostApp()
        model.resetForOpen()

        let p = panel ?? makePanel()
        panel = p
        p.alphaValue = CGFloat(Settings.shared.opacity)
        p.appearance = Settings.shared.panelAppearance
        // Frame size, not content size: saveGeometry records the frame, and
        // mixing the two makes the panel drift by the titlebar height on every
        // open/resize cycle.
        var sized = p.frame
        sized.size = NSSize(width: Settings.shared.panelWidth,
                            height: Settings.shared.panelHeight)
        p.setFrame(sized, display: false)
        DebugLog.write("GEOMETRY restored \(Int(sized.width))x\(Int(sized.height))")
        if !restoreSavedOrigin(p) {
            positionOnActiveScreen(p)
        }

        // A miniaturised panel reports isVisible == false, so the hotkey would
        // otherwise appear to do nothing.
        if p.isMiniaturized { p.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        installLocalMonitor()
    }

    func hide() {
        removeLocalMonitor()
        panel?.orderOut(nil)
    }

    /// Brings an already-open panel back to the front without resetting the
    /// query or the selection.
    func raise() {
        guard let panel, panel.isVisible else { return }
        panel.orderFrontRegardless()
    }

    func toggle() {
        if isVisible, panel?.isMiniaturized == false {
            hide()
        } else {
            show()
        }
    }

    private static let originKey = "panelOrigin"

    /// Puts the panel back where you left it. A frame saved on a monitor that
    /// is no longer attached is ignored rather than opening off-screen.
    private func restoreSavedOrigin(_ p: NSPanel) -> Bool {
        guard let raw = UserDefaults.standard.string(forKey: Self.originKey) else { return false }
        let origin = NSPointFromString(raw)
        let frame = NSRect(origin: origin, size: p.frame.size)
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        guard visible else { return false }
        p.setFrameOrigin(origin)
        return true
    }

    private func saveGeometry() {
        guard let panel, panel.isVisible else { return }
        DebugLog.write("GEOMETRY save \(Int(panel.frame.width))x\(Int(panel.frame.height)) applying=\(isApplyingStoredSize)")
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.originKey)
        // Dragging the resize handle should move the Appearance sliders too.
        let size = panel.frame.size
        guard !isApplyingStoredSize else { return }
        if abs(Settings.shared.panelWidth - Double(size.width)) > 0.5 {
            Settings.shared.panelWidth = Double(size.width)
        }
        if abs(Settings.shared.panelHeight - Double(size.height)) > 0.5 {
            Settings.shared.panelHeight = Double(size.height)
        }
    }

    private var isApplyingStoredSize = false

    /// Opacity and window appearance live on the NSPanel, not in SwiftUI, so
    /// they need pushing across whenever the relevant settings change —
    /// otherwise an open panel keeps its old look until it is reopened.
    func applyLiveAppearance() {
        guard let panel else { return }
        panel.alphaValue = CGFloat(Settings.shared.opacity)
        panel.appearance = Settings.shared.panelAppearance
        panel.invalidateShadow()
    }

    /// Called when the Appearance sliders change the stored size.
    func applyStoredSize() {
        guard let panel, panel.isVisible else { return }
        let target = NSSize(width: Settings.shared.panelWidth, height: Settings.shared.panelHeight)
        guard abs(panel.frame.width - target.width) > 0.5
                || abs(panel.frame.height - target.height) > 0.5 else { return }
        isApplyingStoredSize = true
        var frame = panel.frame
        // Grow downward from the top-left so the panel doesn't crawl up-screen.
        frame.origin.y += frame.height - target.height
        frame.size = target
        panel.setFrame(frame, display: true, animate: false)
        isApplyingStoredSize = false
    }

    /// Centres the panel horizontally on whichever screen holds the pointer,
    /// a third of the way down — roughly where Spotlight puts itself.
    private func positionOnActiveScreen(_ p: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = p.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2 + frame.height * 0.08
        )
        p.setFrameOrigin(origin)
    }

    // MARK: Key handling

    /// SwiftUI's focus machinery swallows arrow keys inside a TextField, so the
    /// navigation keys are intercepted before they reach the field.
    private func installLocalMonitor() {
        removeLocalMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeLocalMonitor() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        // Quick Look's text editor needs every keystroke — Return, arrows and
        // Cmd-keys included. Intercepting them here would make typing in it
        // trigger list navigation instead.
        if let ql = QuickLook.currentWindow, ql.isKeyWindow {
            if event.keyCode == 53 {            // Escape still closes it
                QuickLook.close()
                return true
            }
            return false
        }

        // While renaming, let the rename field have every key except Escape.
        if model.renamingID != nil {
            if event.keyCode == 53 { model.renamingID = nil; return true }
            return false
        }

        let cmd = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)

        switch event.keyCode {
        case 53: // Escape
            hide()
            QuickLook.close()
            return true

        case 125: // Down
            model.moveSelection(1)
            return true
        case 126: // Up
            model.moveSelection(-1)
            return true
        case 121: // Page Down
            model.moveSelection(8)
            return true
        case 116: // Page Up
            model.moveSelection(-8)
            return true
        case 115: // Home
            model.selectFirst()
            return true
        case 119: // End
            model.selectLast()
            return true
        case 36, 76: // Return / Enter
            model.activateSelected(plainText: cmd || shift)
            return true
        case 51 where cmd: // Cmd-Delete
            if let clip = model.selectedClip { model.delete(clip) }
            return true
        case 48: // Tab switches History <-> Favorites
            model.mode = model.mode == .history ? .favorites : .history
            return true
        default:
            break
        }

        if cmd, let chars = event.charactersIgnoringModifiers?.lowercased() {
            switch chars {
            case "f" where !shift:
                if let clip = model.selectedClip { model.toggleFavorite(clip) }
                return true
            case "r":
                if let clip = model.selectedClip { model.renamingID = clip.id }
                return true
            case "y":
                if let clip = model.selectedClip { QuickLook.show(clip) }
                return true
            case ",":
                hide()
                AppDelegate.shared?.openSettings()
                return true
            case "1", "2", "3", "4", "5", "6", "7", "8", "9":
                if let n = Int(chars), model.clips.indices.contains(n - 1) {
                    model.activate(model.clips[n - 1])
                    return true
                }
            case "0":
                if model.clips.indices.contains(9) {
                    model.activate(model.clips[9])
                    return true
                }
            default:
                break
            }
        }
        return false
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // The titlebar close button doesn't route through hide(), so clean up
        // the key monitor here too.
        removeLocalMonitor()
    }

    func windowDidResize(_ notification: Notification) { saveGeometry() }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveGeometry()
        UserDefaults.standard.synchronize()
        DebugLog.write("GEOMETRY committed \(Int(Settings.shared.panelWidth))x\(Int(Settings.shared.panelHeight))")
    }

    func windowDidMove(_ notification: Notification) { saveGeometry() }

    func windowDidBecomeKey(_ notification: Notification) {
        model.panelIsKey = true
    }

    func windowDidResignKey(_ notification: Notification) {
        model.panelIsKey = false
        // Staying open is the point: you click into a text field somewhere
        // else, put the caret where you want it, then pick a clip.
        guard Settings.shared.closeOnFocusLoss, model.renamingID == nil else { return }
        hide()
    }
}
