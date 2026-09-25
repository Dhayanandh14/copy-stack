import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Puts clips back on the pasteboard and, when allowed, drives ⌘V in whatever
/// app was frontmost before the panel appeared.
enum Paster {
    /// The app that was active when the panel opened, so we can hand focus back.
    static var previousApp: NSRunningApplication?

    static func rememberFrontmostApp() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }
    }

    /// Whether we're allowed to synthesise keystrokes. Auto-paste needs this;
    /// copy-only does not.
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Opens the System Settings pane where the user grants the permission.
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Writes a clip to the system pasteboard. `plainText` strips formatting.
    static func write(_ clip: Clip, plainText: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch clip.kind {
        case .image:
            if let blob = clip.loadBlob() {
                pb.setData(blob, forType: .png)
            }
        case .rtf:
            if !plainText, let rtf = clip.loadBlob() {
                pb.setData(rtf, forType: .rtf)
            }
            pb.setString(clip.text, forType: .string)
        case .fileURL:
            let urls = clip.text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            if !plainText, !urls.isEmpty {
                pb.writeObjects(urls as [NSURL])
            } else {
                pb.setString(clip.text, forType: .string)
            }
        case .text:
            pb.setString(clip.text, forType: .string)
        }

        // Don't let our own write come back in as a fresh clip.
        ClipboardMonitor.shared.suppressCurrentChange()
        // Reordering on use means the clip you just picked is never where you
        // left it, so this is opt-in.
        if Settings.shared.promoteOnPaste {
            Store.shared.touch(id: clip.id)
        }
    }

    /// Writes the clip, returns focus to the app you were last in, then sends
    /// Cmd-V there.
    static func paste(_ clip: Clip, plainText: Bool) {
        write(clip, plainText: plainText)

        let target = previousApp
        DebugLog.write("PASTE clip \(clip.id) -> target=\(target?.bundleIdentifier ?? "nil") trusted=\(hasAccessibility)")

        guard hasAccessibility else {
            returnFocusToTarget()
            DebugLog.write("PASTE aborted: no Accessibility permission, clip is on the clipboard only")
            NSLog("ClipStack: no Accessibility permission — copied to clipboard, press Cmd-V yourself")
            DispatchQueue.main.async { announceMissingPermission() }
            return
        }

        guard let target else {
            DebugLog.write("PASTE no target app recorded; sending Cmd-V to whatever is frontmost")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { sendCommandV() }
            return
        }

        // Deactivating first is the part that matters. Activating the target
        // alone leaves our floating panel holding key focus, so the paste lands
        // correctly but the next keystroke goes to the search field.
        if Settings.shared.returnFocusAfterPaste {
            NSApp.deactivate()
        }
        if #available(macOS 14.0, *) {
            target.activate()
        } else {
            target.activate(options: [.activateIgnoringOtherApps])
        }
        // A fixed delay is a guess; wait for the app to actually come forward.
        waitUntilFrontmost(target, attempts: 15)
    }

    /// Hands the keyboard back to the app you were working in, without closing
    /// the panel. Used after a copy-only action, and when a paste degrades.
    static func returnFocusToTarget() {
        guard Settings.shared.returnFocusAfterPaste else { return }
        NSApp.deactivate()
        guard let target = previousApp, !target.isActive else { return }
        if #available(macOS 14.0, *) {
            target.activate()
        } else {
            target.activate(options: [.activateIgnoringOtherApps])
        }
        DebugLog.write("FOCUS returned to \(target.bundleIdentifier ?? "?")")
    }

    /// Polls until the target app is genuinely frontmost before pressing Cmd-V,
    /// so the keystroke can't land in the wrong window.
    private static func waitUntilFrontmost(_ app: NSRunningApplication, attempts: Int) {
        let isFront = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        if isFront || attempts <= 0 {
            DebugLog.write("PASTE target frontmost=\(isFront) after wait; sending Cmd-V")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                sendCommandV()
                ClipboardMonitor.shared.suppressCurrentChange()
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            waitUntilFrontmost(app, attempts: attempts - 1)
        }
    }

    private static var warnedAboutPermission = false

    /// Silently copying instead of pasting looks like the app is broken, so say
    /// so once per launch.
    private static func announceMissingPermission() {
        guard !warnedAboutPermission else { return }
        warnedAboutPermission = true
        let alert = NSAlert()
        alert.messageText = "ClipStack can't paste for you yet"
        alert.informativeText = "The clip is on your clipboard — press Cmd-V to paste it.\n\nTo have ClipStack paste automatically, grant it Accessibility permission."
        alert.addButton(withTitle: "Open Settings…")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            requestAccessibility()
            openAccessibilitySettings()
        }
    }

    private static func sendCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        // Keep the user's physically-held modifiers from mixing into our event.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
