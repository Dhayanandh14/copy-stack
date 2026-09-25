import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            AppearanceTab().tabItem { Label("Appearance", systemImage: "paintbrush") }
            ShortcutsTab().tabItem { Label("Shortcuts", systemImage: "command") }
            PrivacyTab().tabItem { Label("Privacy", systemImage: "hand.raised") }
            StorageTab().tabItem { Label("Storage", systemImage: "internaldrive") }
        }
        .frame(width: 500, height: 430)
        .padding(14)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @EnvironmentObject var settings: Settings
    @State private var trusted = Paster.hasAccessibility

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Paste directly into the active app", isOn: $settings.pasteOnSelect)
                Toggle("Close the panel when it loses focus", isOn: $settings.closeOnFocusLoss)
                Toggle("Close the panel after pasting", isOn: $settings.closeAfterPaste)
                Toggle("Return keyboard focus after pasting", isOn: $settings.returnFocusAfterPaste)
                Toggle("Move a clip to the top when you use it", isOn: $settings.promoteOnPaste)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paste directly — off means selecting a clip only puts it on the clipboard and you press ⌘V yourself.")
                    Text("Close on focus loss — off means the panel stays up while you click into another app, so you can place the caret first and then pick a clip.")
                    Text("Close after pasting — off means the panel stays open so you can paste several clips in a row.")
                    Text("Return focus — on means typing after a paste goes to the app you pasted into. Turn it off to keep typing in the panel's search box.")
                    Text("Move to top — off means clips stay in the order they were copied, so the one you just used is still where you found it.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                HStack(spacing: 10) {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(trusted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trusted ? "Accessibility granted" : "Accessibility not granted")
                            .font(.system(size: 12, weight: .medium))
                        Text(trusted
                             ? "Direct paste is working."
                             : "Needed only for direct paste. Everything else works without it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if !trusted {
                        Button("Open…") {
                            Paster.requestAccessibility()
                            Paster.openAccessibilitySettings()
                        }
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("Permission")
            }

            Section {
                Picker("Check clipboard every", selection: $settings.pollInterval) {
                    Text("0.1 s (fastest)").tag(0.1)
                    Text("0.25 s (recommended)").tag(0.25)
                    Text("0.5 s").tag(0.5)
                    Text("1 s (lightest)").tag(1.0)
                }
                .onChange(of: settings.pollInterval) { _ in ClipboardMonitor.shared.restart() }
            }
        }
        .formStyle(.grouped)
        .onAppear { trusted = Paster.hasAccessibility }
    }
}

// MARK: - Appearance

private struct AppearanceTab: View {
    @EnvironmentObject var settings: Settings

    var body: some View {
        Form {
            Section {
                sliderRow("Font size", value: $settings.fontSize, range: 10...20, step: 1,
                          readout: "\(Int(settings.fontSize)) pt")
                sliderRow("Row height", value: $settings.rowHeight, range: 56...150, step: 2,
                          readout: "\(Int(settings.rowHeight)) px")
                sliderRow("Opacity", value: $settings.opacity, range: 0.4...1.0, step: 0.05,
                          readout: "\(Int(settings.opacity * 100))%")
                Toggle("Show position numbers", isOn: $settings.showNumberBadges)
            } header: {
                Text("Panel")
            }

            Section {
                sliderRow("Width", value: $settings.panelWidth, range: 320...900, step: 10,
                          readout: "\(Int(settings.panelWidth)) px")
                sliderRow("Height", value: $settings.panelHeight, range: 300...1200, step: 10,
                          readout: "\(Int(settings.panelHeight)) px")
                HStack {
                    Spacer()
                    Button("Reset to 400 \u{00D7} 720") {
                        settings.panelWidth = 400
                        settings.panelHeight = 720
                    }
                }
            } header: {
                Text("Size")
            } footer: {
                Text("Dragging the panel's edge updates these, and the size and position are restored next time you open it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Toggle("Use custom colors", isOn: $settings.useCustomColors)
                Group {
                    ColorPicker("Background", selection: $settings.bgColor)
                    ColorPicker("Text", selection: $settings.textColor)
                    ColorPicker("Selection", selection: $settings.accentColor)
                }
                .disabled(!settings.useCustomColors)
                .opacity(settings.useCustomColors ? 1 : 0.45)
            } header: {
                Text("Colors")
            } footer: {
                Text("Off by default, so the panel follows your system light/dark appearance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// One row: label, slider, current value. The slider carries no label of
    /// its own, which previously produced a duplicate row per control.
    private func sliderRow(_ label: String, value: Binding<Double>,
                           range: ClosedRange<Double>, step: Double,
                           readout: String) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                Slider(value: value, in: range, step: step)
                Text(readout)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
        } label: {
            Text(label)
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsTab: View {
    @EnvironmentObject var settings: Settings

    var body: some View {
        Form {
            Section {
                LabeledContent("Open ClipStack") {
                    HotKeyRecorder(spec: $settings.mainHotKey)
                }
                LabeledContent("Paste last as plain text") {
                    HotKeyRecorder(spec: $settings.plainHotKey)
                }
            } header: {
                Text("Global")
            } footer: {
                Text("If a combination doesn't take, another app already owns it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("⌃⌘1…0 pastes the 10 most recent", isOn: $settings.numberedRecentEnabled)
                Toggle("⌃⌥1…0 pastes the top 10 favorites", isOn: $settings.numberedFavoritesEnabled)
            } header: {
                Text("Quick paste")
            }

            Section {
                inPanel("↑ ↓", "Move selection")
                inPanel("↩", "Paste")
                inPanel("⌘↩", "Paste as plain text")
                inPanel("⌘1…⌘0", "Paste that row")
                inPanel("⌘F", "Toggle favorite")
                inPanel("⌘R", "Rename")
                inPanel("⇥", "Switch History / Favorites")
                inPanel("⌘⌫", "Delete clip")
                inPanel("⎋", "Close")
            } header: {
                Text("Inside the panel")
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.mainHotKey) { _ in AppDelegate.shared?.rebindHotKeys() }
        .onChange(of: settings.plainHotKey) { _ in AppDelegate.shared?.rebindHotKeys() }
        .onChange(of: settings.numberedRecentEnabled) { _ in AppDelegate.shared?.rebindHotKeys() }
        .onChange(of: settings.numberedFavoritesEnabled) { _ in AppDelegate.shared?.rebindHotKeys() }
    }

    private func inPanel(_ key: String, _ label: String) -> some View {
        HStack(spacing: 10) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(width: 64, alignment: .leading)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Privacy

private struct PrivacyTab: View {
    @EnvironmentObject var settings: Settings

    var body: some View {
        Form {
            Section {
                Toggle("Ignore passwords and transient copies", isOn: $settings.ignoreConcealed)
            } header: {
                Text("Secrets")
            } footer: {
                Text("Respects the marker password managers set on copied secrets. Leave this on unless you have a reason not to.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Toggle("Capture images", isOn: $settings.captureImages)
                LabeledContent("Skip images larger than", value: "\(Int(settings.maxImageMB)) MB")
                Slider(value: $settings.maxImageMB, in: 1...50, step: 1)
                    .disabled(!settings.captureImages)
            } header: {
                Text("Images")
            }

            Section {
                TextEditor(text: $settings.excludedApps)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.15)))
            } header: {
                Text("Never record copies from these apps")
            } footer: {
                Text("One bundle identifier per line, e.g. com.apple.keychainaccess")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Storage

private struct StorageTab: View {
    @EnvironmentObject var settings: Settings
    @State private var stats: (total: Int, favorites: Int, bytes: Int64) = (0, 0, 0)
    @State private var limitText = ""
    @State private var confirmingClearAll = false
    @State private var showSaved = false
    @FocusState private var limitFocused: Bool

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Text("Maximum clips to keep")
                    Spacer()
                    // In a Form, a TextField's first argument is its LABEL, not
                    // placeholder text — passing "500" there rendered a stray
                    // label above the box. The hint belongs in `prompt`.
                    TextField("", text: $limitText, prompt: Text("500"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .focused($limitFocused)
                        .onSubmit { commitLimit() }
                    Text("clips")
                        .foregroundStyle(.secondary)
                    Button("Save") { commitLimit() }
                        .disabled(!hasUnsavedChange)
                }

                HStack(spacing: 6) {
                    if showSaved {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Saved")
                            .foregroundStyle(.green)
                    } else if hasUnsavedChange {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(.orange)
                        Text(overLimit > 0
                             ? "Not saved yet \u{2014} saving will remove \(overLimit) older \(overLimit == 1 ? "clip" : "clips")."
                             : "Not saved yet.")
                            .foregroundStyle(.orange)
                    } else {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.secondary)
                        Text(settings.maxHistory == 0
                             ? "Currently keeping every clip."
                             : "Currently keeping up to \(settings.maxHistory) clips.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("History limit")
            } footer: {
                Text("Type a number, then press Return or click Save. 0 means unlimited. Favorites are never pruned, whatever this is set to.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                LabeledContent("Clips stored", value: "\(stats.total)")
                LabeledContent("Favorites", value: "\(stats.favorites)")
                LabeledContent("Database size",
                               value: ByteCountFormatter.string(fromByteCount: stats.bytes, countStyle: .file))
            } header: {
                Text("On disk")
            }

            Section {
                HStack {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Store.databaseURL])
                    }
                    Spacer()
                    Button("Clear History") {
                        Store.shared.clearHistory()
                        ThumbnailCache.shared.dropAll()
                        AppModel.shared.reload()
                        refresh()
                    }
                    Button("Delete Everything\u{2026}", role: .destructive) {
                        confirmingClearAll = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            limitText = settings.maxHistory == 0 ? "0" : "\(settings.maxHistory)"
            refresh()
        }
        .alert("Delete every clip, including favorites?", isPresented: $confirmingClearAll) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                Store.shared.clearEverything()
                ThumbnailCache.shared.dropAll()
                AppModel.shared.reload()
                refresh()
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    /// True when the box holds a valid number that isn't the saved one.
    private var hasUnsavedChange: Bool {
        guard let typed = Int(limitText.trimmingCharacters(in: .whitespaces)), typed >= 0 else { return false }
        return typed != settings.maxHistory
    }

    /// How many non-favorite clips the current box would discard.
    private var overLimit: Int {
        guard let typed = Int(limitText.trimmingCharacters(in: .whitespaces)), typed > 0 else { return 0 }
        return max(0, (stats.total - stats.favorites) - typed)
    }

    /// Accepts the typed number, ignoring anything that isn't one so a stray
    /// keystroke can't silently wipe history.
    private func commitLimit() {
        let raw = limitText.trimmingCharacters(in: .whitespaces)
        guard let typed = Int(raw), typed >= 0 else {
            limitText = "\(settings.maxHistory)"   // put the real value back
            return
        }
        let clamped = min(typed, 1_000_000)
        limitText = "\(clamped)"
        guard clamped != settings.maxHistory else {
            flashSaved()
            return
        }
        settings.maxHistory = clamped
        Store.shared.prune(to: clamped)
        ThumbnailCache.shared.dropAll()
        AppModel.shared.reload()
        refresh()
        flashSaved()
    }

    /// A brief confirmation, so saving isn't silent.
    private func flashSaved() {
        withAnimation { showSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSaved = false }
        }
    }

    private func refresh() { stats = Store.shared.count() }
}
