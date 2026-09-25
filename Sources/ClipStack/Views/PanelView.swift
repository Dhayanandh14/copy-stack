import AppKit
import SwiftUI

struct PanelView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: Settings
    @FocusState private var searchFocused: Bool

    private var bg: Color {
        settings.useCustomColors ? settings.bgColor : Color(nsColor: .windowBackgroundColor)
    }

    /// Slightly lighter than the background, the way a hairline etched into a
    /// dark surface reads.
    private var separatorColor: Color {
        settings.useCustomColors ? settings.textColor.opacity(0.13) : Color.primary.opacity(0.13)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            toolbar
            modeTabs
            Divider()
            searchBar
            Divider()
            if model.clips.isEmpty {
                emptyState
            } else {
                list
            }
            permissionBanner
        }
        .background(bg)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear { searchFocused = true }
    }

    /// Without Accessibility, picking a clip only copies it. That has to be
    /// visible, or the app just looks broken.
    @ViewBuilder
    private var permissionBanner: some View {
        if settings.pasteOnSelect && !Paster.hasAccessibility {
            Divider()
            Button {
                Paster.requestAccessibility()
                Paster.openAccessibilitySettings()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Auto-paste is off")
                            .font(.system(size: 11, weight: .medium))
                        Text("Clips are copied only. Tap to grant Accessibility.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.orange)
        }
    }

    /// The window's close/minimise/zoom buttons are drawn by AppKit over the
    /// top-left of this strip; the title sits centred so they never collide.
    private var titleBar: some View {
        Text("ClipStack")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            toolButton("Copy", "doc.on.doc") {
                guard let clip = model.selectedClip else { return }
                model.finishUsing(clip) { Paster.write(clip, plainText: false) }
            }
            toolButton("Direct Paste", "arrow.down.doc") {
                guard let clip = model.selectedClip else { return }
                model.finishUsing(clip) { Paster.paste(clip, plainText: false) }
            }
            toolButton("Quick Look", "eye") {
                guard let clip = model.selectedClip else { return }
                QuickLook.show(clip)
            }
            Spacer(minLength: 0)
            Menu {
                Button("Paste as Plain Text") { model.activateSelected(plainText: true) }
                Button("Save…") {
                    if let clip = model.selectedClip { ClipExporter.save(clip) }
                }
                Button("Rename…") {
                    if let clip = model.selectedClip { model.renamingID = clip.id }
                }
                Button("Delete") {
                    if let clip = model.selectedClip { model.delete(clip) }
                }
                Divider()
                Button("Settings…") {
                    PanelController.shared.hide()
                    AppDelegate.shared?.openSettings()
                }
                Button("Clear History") {
                    Store.shared.clearHistory()
                    ThumbnailCache.shared.dropAll()
                    model.reload()
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 16, weight: .regular))
                        .frame(height: 18)
                    // An invisible twin of the tool labels, so the chevron sits
                    // level with the icons rather than centred on the whole row.
                    Text(" ")
                        .font(.system(size: 9))
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .foregroundStyle(.secondary)
            .frame(width: 40)

            .padding(.trailing, 10)
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
        .padding(.leading, 6)
    }

    private func toolButton(_ label: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .regular))
                    .frame(height: 18)
                Text(label)
                    .font(.system(size: 9))
            }
            .frame(width: 74)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.selectedClip == nil ? Color.secondary.opacity(0.4) : Color.secondary)
        .disabled(model.selectedClip == nil)
    }

    // MARK: Tabs

    private var modeTabs: some View {
        HStack(spacing: 0) {
            ForEach(PanelMode.allCases) { m in
                Button {
                    model.mode = m
                } label: {
                    Text(m.rawValue)
                        .font(.system(size: 12, weight: model.mode == m ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(model.mode == m ? Color.primary.opacity(0.10) : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: settings.fontSize))
                .focused($searchFocused)
                .onSubmit { model.activateSelected() }
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text("\(model.clips.count)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    // MARK: List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.clips.enumerated()), id: \.element.id) { index, clip in
                        VStack(spacing: 0) {
                            ClipRowView(clip: clip, index: index, selected: index == model.selection)
                                .onTapGesture {
                                    // Reading clickCount off the live event lets a single
                                    // gesture serve both roles, so selection is immediate
                                    // instead of waiting for a possible second click.
                                    if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                                        model.activate(clip)
                                    } else {
                                        model.select(index, scroll: false)
                                    }
                                }
                                .contextMenu { contextMenu(for: clip) }
                            // Inset to line up with the text column, so the
                            // icons sit in a clean left margin.
                            DottedLine(color: separatorColor)
                                .padding(.leading, 74)
                                .padding(.trailing, 12)
                        }
                        .id(clip.id)
                    }
                }
            }
            .onChange(of: model.selection) { _ in
                guard model.autoScroll, let clip = model.selectedClip else { return }
                proxy.scrollTo(clip.id, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for clip: Clip) -> some View {
        Button("Paste") { model.activate(clip) }
        Button("Paste as Plain Text") { model.activate(clip, plainText: true) }
        Button("Copy Only") {
            PanelController.shared.hide()
            Paster.write(clip, plainText: false)
        }
        Divider()
        Button("Quick Look") { QuickLook.show(clip) }
        Button("Save…") { ClipExporter.save(clip) }
        Button(clip.favorite ? "Remove from Favorites" : "Add to Favorites") {
            model.toggleFavorite(clip)
        }
        // Custom icons are a favorites-only affordance: they're for the handful
        // of clips you keep around and want to recognise at a glance.
        if clip.favorite {
            Button("Change Icon…") {
                IconPicker.choose(for: clip) { model.reload() }
            }
            if clip.hasCustomIcon {
                Button("Reset Icon") {
                    IconPicker.clear(for: clip)
                    model.reload()
                }
            }
        }
        Button("Rename…") { model.renamingID = clip.id }
        Divider()
        Button("Delete", role: .destructive) { model.delete(clip) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(emptyMessage)
                .font(.system(size: settings.fontSize - 1))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        if !model.query.isEmpty { return "No clips match “\(model.query)”" }
        return model.mode == .favorites
            ? "No favorites yet — tap the star on any clip"
            : "Nothing captured yet.\nCopy something."
    }
}
