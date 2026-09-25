import AppKit
import Carbon.HIToolbox

let cmdKeyMask: UInt32 = UInt32(cmdKey)
let shiftKeyMask: UInt32 = UInt32(shiftKey)
let optionKeyMask: UInt32 = UInt32(optionKey)
let controlKeyMask: UInt32 = UInt32(controlKey)

struct HotKeySpec: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    var isEmpty: Bool { keyCode == 0 && modifiers == 0 }

    /// Human-readable form, e.g. "⌘⇧V".
    var display: String {
        guard !isEmpty else { return "none" }
        var s = ""
        if modifiers & controlKeyMask != 0 { s += "⌃" }
        if modifiers & optionKeyMask != 0 { s += "⌥" }
        if modifiers & shiftKeyMask != 0 { s += "⇧" }
        if modifiers & cmdKeyMask != 0 { s += "⌘" }
        return s + (HotKeySpec.keyNames[keyCode] ?? "key\(keyCode)")
    }

    static func from(event: NSEvent) -> HotKeySpec? {
        var mods: UInt32 = 0
        if event.modifierFlags.contains(.command) { mods |= cmdKeyMask }
        if event.modifierFlags.contains(.shift) { mods |= shiftKeyMask }
        if event.modifierFlags.contains(.option) { mods |= optionKeyMask }
        if event.modifierFlags.contains(.control) { mods |= controlKeyMask }
        // A bare key with no modifier would swallow normal typing system-wide.
        guard mods != 0 else { return nil }
        return HotKeySpec(keyCode: UInt32(event.keyCode), modifiers: mods)
    }

    static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    /// Key codes for 1,2,3…9,0 — used by the numbered quick-paste shortcuts.
    static let digitKeyCodes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
}

/// Thin wrapper over Carbon's `RegisterEventHotKey`. Carbon is the only API that
/// gives a real system-wide hotkey without needing Accessibility permission.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var installed = false

    private init() {}

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            DispatchQueue.main.async {
                HotKeyCenter.shared.handlers[hkID.id]?()
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Registers `spec` and returns an opaque id you can pass to `unregister`.
    @discardableResult
    func register(_ spec: HotKeySpec, action: @escaping () -> Void) -> UInt32? {
        guard !spec.isEmpty else { return nil }
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x434C_5053), id: id) // 'CLPS'
        let status = RegisterEventHotKey(spec.keyCode, spec.modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("ClipStack: hotkey \(spec.display) unavailable (status \(status)) — probably taken by another app")
            return nil
        }
        handlers[id] = action
        refs[id] = ref
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs[id] { UnregisterEventHotKey(ref) }
        refs[id] = nil
        handlers[id] = nil
    }

    func unregisterAll() {
        for id in refs.keys { unregister(id) }
    }
}
