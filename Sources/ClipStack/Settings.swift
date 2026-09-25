import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// Everything the user can tune, persisted in UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()

    private let d = UserDefaults.standard

    // MARK: Appearance
    @Published var fontSize: Double { didSet { d.set(fontSize, forKey: "fontSize") } }
    @Published var rowHeight: Double { didSet { d.set(rowHeight, forKey: "rowHeight") } }
    @Published var opacity: Double { didSet { d.set(opacity, forKey: "opacity") } }
    /// Panel geometry. Written both by the Appearance sliders and by dragging
    /// the window's resize handle, so the two stay in step.
    @Published var panelWidth: Double { didSet { d.set(panelWidth, forKey: "panelWidth"); PanelController.shared.applyStoredSize() } }
    @Published var panelHeight: Double { didSet { d.set(panelHeight, forKey: "panelHeight"); PanelController.shared.applyStoredSize() } }
    @Published var useCustomColors: Bool { didSet { d.set(useCustomColors, forKey: "useCustomColors") } }
    @Published var bgColor: Color { didSet { d.setColor(bgColor, forKey: "bgColor") } }
    @Published var textColor: Color { didSet { d.setColor(textColor, forKey: "textColor") } }
    @Published var accentColor: Color { didSet { d.setColor(accentColor, forKey: "accentColor") } }

    // MARK: Behaviour
    /// 0 means unlimited — the whole point of building this ourselves.
    @Published var maxHistory: Int { didSet { d.set(maxHistory, forKey: "maxHistory") } }
    @Published var pollInterval: Double { didSet { d.set(pollInterval, forKey: "pollInterval") } }
    @Published var pasteOnSelect: Bool { didSet { d.set(pasteOnSelect, forKey: "pasteOnSelect") } }
    @Published var captureImages: Bool { didSet { d.set(captureImages, forKey: "captureImages") } }
    @Published var maxImageMB: Double { didSet { d.set(maxImageMB, forKey: "maxImageMB") } }
    @Published var ignoreConcealed: Bool { didSet { d.set(ignoreConcealed, forKey: "ignoreConcealed") } }
    /// Bundle IDs whose copies are never recorded, one per line.
    @Published var excludedApps: String { didSet { d.set(excludedApps, forKey: "excludedApps") } }
    @Published var showNumberBadges: Bool { didSet { d.set(showNumberBadges, forKey: "showNumberBadges") } }
    /// Off by default: the panel stays up when you click into another app, so
    /// you can put the caret where you want it and then pick a clip.
    @Published var closeOnFocusLoss: Bool { didSet { d.set(closeOnFocusLoss, forKey: "closeOnFocusLoss") } }
    /// Off by default: pasting one clip is rarely the whole job, so the panel
    /// stays up until you close it.
    @Published var closeAfterPaste: Bool { didSet { d.set(closeAfterPaste, forKey: "closeAfterPaste") } }
    /// On by default: after using a clip, the keyboard belongs to the app you
    /// pasted into, not to the panel's search field.
    @Published var returnFocusAfterPaste: Bool { didSet { d.set(returnFocusAfterPaste, forKey: "returnFocusAfterPaste") } }
    /// Off by default: using a clip shouldn't reshuffle the list underneath
    /// you. Clips stay in the order they were copied.
    @Published var promoteOnPaste: Bool { didSet { d.set(promoteOnPaste, forKey: "promoteOnPaste") } }

    @Published var launchAtLogin: Bool {
        didSet {
            d.set(launchAtLogin, forKey: "launchAtLogin")
            applyLaunchAtLogin()
        }
    }

    // MARK: Hotkeys (stored as keyCode + Carbon modifier mask)
    @Published var mainHotKey: HotKeySpec { didSet { d.setHotKey(mainHotKey, forKey: "mainHotKey") } }
    @Published var plainHotKey: HotKeySpec { didSet { d.setHotKey(plainHotKey, forKey: "plainHotKey") } }
    @Published var numberedRecentEnabled: Bool { didSet { d.set(numberedRecentEnabled, forKey: "numberedRecentEnabled") } }
    @Published var numberedFavoritesEnabled: Bool { didSet { d.set(numberedFavoritesEnabled, forKey: "numberedFavoritesEnabled") } }

    private init() {
        d.register(defaults: [
            "fontSize": 13.0,
            "rowHeight": 80.0,
            "opacity": 1.0,
            "panelWidth": 400.0,
            "panelHeight": 720.0,
            "useCustomColors": true,
            "maxHistory": 500,
            "pollInterval": 0.25,
            "pasteOnSelect": true,
            "captureImages": true,
            "maxImageMB": 64.0,
            "ignoreConcealed": true,
            "excludedApps": "",
            "showNumberBadges": true,
            "closeOnFocusLoss": false,
            "closeAfterPaste": false,
            "returnFocusAfterPaste": true,
            "promoteOnPaste": false,
            "launchAtLogin": false,
            "numberedRecentEnabled": true,
            "numberedFavoritesEnabled": true,
        ])
        fontSize = d.double(forKey: "fontSize")
        // 30 was the old compact layout's default and is far too short for the
        // current row; anything that small is a stale value, not a choice.
        let storedRowHeight = d.double(forKey: "rowHeight")
        rowHeight = storedRowHeight < 56 ? 80 : storedRowHeight
        opacity = d.double(forKey: "opacity")
        panelWidth = d.double(forKey: "panelWidth")
        panelHeight = d.double(forKey: "panelHeight")
        useCustomColors = d.bool(forKey: "useCustomColors")
        // Sampled from the look this was modelled on: a dark slate that is
        // slightly cooler than the system grey.
        bgColor = d.color(forKey: "bgColor") ?? Color(red: 37/255, green: 41/255, blue: 43/255)
        textColor = d.color(forKey: "textColor") ?? Color(red: 228/255, green: 228/255, blue: 229/255)
        accentColor = d.color(forKey: "accentColor") ?? Color(red: 45/255, green: 111/255, blue: 212/255)
        maxHistory = d.integer(forKey: "maxHistory")
        pollInterval = d.double(forKey: "pollInterval")
        pasteOnSelect = d.bool(forKey: "pasteOnSelect")
        captureImages = d.bool(forKey: "captureImages")
        maxImageMB = d.double(forKey: "maxImageMB")
        ignoreConcealed = d.bool(forKey: "ignoreConcealed")
        excludedApps = d.string(forKey: "excludedApps") ?? ""
        showNumberBadges = d.bool(forKey: "showNumberBadges")
        closeOnFocusLoss = d.bool(forKey: "closeOnFocusLoss")
        closeAfterPaste = d.bool(forKey: "closeAfterPaste")
        returnFocusAfterPaste = d.bool(forKey: "returnFocusAfterPaste")
        promoteOnPaste = d.bool(forKey: "promoteOnPaste")
        launchAtLogin = d.bool(forKey: "launchAtLogin")
        numberedRecentEnabled = d.bool(forKey: "numberedRecentEnabled")
        numberedFavoritesEnabled = d.bool(forKey: "numberedFavoritesEnabled")
        // Defaults: Cmd-Shift-V opens the panel, Cmd-Shift-Opt-V pastes as plain text.
        mainHotKey = d.hotKey(forKey: "mainHotKey") ?? HotKeySpec(keyCode: 9, modifiers: cmdKeyMask | shiftKeyMask)
        plainHotKey = d.hotKey(forKey: "plainHotKey") ?? HotKeySpec(keyCode: 9, modifiers: cmdKeyMask | shiftKeyMask | optionKeyMask)
    }

    /// With a custom background, the panel has to stop following the system's
    /// light/dark setting — otherwise secondary text and controls resolve for
    /// the wrong appearance and disappear against it. Picking the appearance
    /// from the background's own brightness keeps everything legible.
    var panelAppearance: NSAppearance? {
        guard useCustomColors else { return nil }
        let ns = NSColor(bgColor).usingColorSpace(.sRGB) ?? .black
        let luminance = 0.299 * ns.redComponent + 0.587 * ns.greenComponent + 0.114 * ns.blueComponent
        return NSAppearance(named: luminance < 0.5 ? .darkAqua : .aqua)
    }

    var excludedBundleIDs: Set<String> {
        Set(excludedApps
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty })
    }

    private func applyLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("ClipStack: launch-at-login change failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - UserDefaults helpers

extension UserDefaults {
    func setColor(_ color: Color, forKey key: String) {
        let ns = NSColor(color)
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: ns, requiringSecureCoding: true)
        else { return }
        set(data, forKey: key)
    }

    func color(forKey key: String) -> Color? {
        guard let data = data(forKey: key),
              let ns = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        else { return nil }
        return Color(nsColor: ns)
    }

    func setHotKey(_ spec: HotKeySpec, forKey key: String) {
        set(["k": Int(spec.keyCode), "m": Int(spec.modifiers)], forKey: key)
    }

    func hotKey(forKey key: String) -> HotKeySpec? {
        guard let dict = dictionary(forKey: key),
              let k = dict["k"] as? Int, let m = dict["m"] as? Int
        else { return nil }
        return HotKeySpec(keyCode: UInt32(k), modifiers: UInt32(m))
    }
}
