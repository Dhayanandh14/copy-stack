import AppKit
import Combine
import SwiftUI

enum PanelMode: String, CaseIterable, Identifiable {
    case history = "History"
    case favorites = "Favorites"
    var id: String { rawValue }
    var symbol: String { self == .history ? "clock" : "star.fill" }
}

/// View model behind the panel: holds the visible rows, the query and the
/// selection, and turns user intent into Store/Paster calls.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var clips: [Clip] = []
    @Published var query: String = "" { didSet { scheduleSearch() } }
    @Published var mode: PanelMode = .history { didSet { reload() } }
    @Published var selection: Int = 0
    /// Keyboard moves scroll the list; mouse clicks must not.
    private(set) var autoScroll = true
    @Published var renamingID: Int64?
    /// False while another app has the keyboard. Drives the muted selection
    /// colour, the way every native macOS list behaves.
    @Published var panelIsKey: Bool = true

    private let searchQueue = DispatchQueue(label: "net.local.clipstack.search", qos: .userInitiated)
    private var pendingSearch: DispatchWorkItem?
    private var searchGeneration = 0

    private init() {}

    var selectedClip: Clip? {
        clips.indices.contains(selection) ? clips[selection] : nil
    }

    func reload() {
        // An empty query is an indexed range read — fast at any size, and doing
        // it inline keeps the panel from flashing stale rows when it opens.
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingSearch?.cancel()
            searchGeneration += 1
            apply(Store.shared.fetch(query: "", favoritesOnly: mode == .favorites))
        } else {
            scheduleSearch(delay: 0)
        }
    }

    /// Searching never runs on the main thread. However expensive a query turns
    /// out to be — a term matching nearly every clip is the costly shape — the
    /// UI keeps accepting keystrokes while it runs.
    private func scheduleSearch(delay: TimeInterval = 0.12) {
        pendingSearch?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        let text = query
        let favoritesOnly = mode == .favorites

        let work = DispatchWorkItem { [weak self] in
            let rows = Store.shared.fetch(query: text, favoritesOnly: favoritesOnly)
            DispatchQueue.main.async {
                guard let self, generation == self.searchGeneration else { return }
                self.apply(rows)
            }
        }
        pendingSearch = work
        searchQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func apply(_ rows: [Clip]) {
        clips = rows
        if selection >= rows.count { selection = max(0, rows.count - 1) }
    }

    func resetForOpen() {
        query = ""
        selection = 0
        renamingID = nil
        reload()
    }

    // MARK: Selection movement

    func select(_ index: Int, scroll: Bool) {
        guard clips.indices.contains(index), selection != index else { return }
        autoScroll = scroll
        selection = index
    }

    func moveSelection(_ delta: Int) {
        guard !clips.isEmpty else { return }
        autoScroll = true
        selection = min(max(0, selection + delta), clips.count - 1)
    }

    func selectFirst() { autoScroll = true; selection = 0 }
    func selectLast() { autoScroll = true; selection = max(0, clips.count - 1) }

    // MARK: Actions

    func activate(_ clip: Clip, plainText: Bool = false) {
        finishUsing(clip) {
            if Settings.shared.pasteOnSelect {
                Paster.paste(clip, plainText: plainText)
            } else {
                Paster.write(clip, plainText: plainText)
            }
        }
    }

    /// Runs a clip action, then either closes the panel or leaves it up with
    /// the highlight still on that clip. Using a clip bumps it to the top of
    /// the history, so the selection has to follow it by id, not by index.
    func finishUsing(_ clip: Clip, _ action: () -> Void) {
        if Settings.shared.closeAfterPaste {
            PanelController.shared.hide()
            action()
            if Settings.shared.promoteOnPaste { reload() }
            return
        }
        action()
        // Nothing moved unless the clip was promoted, so skip the reload and
        // the re-render that comes with it.
        if Settings.shared.promoteOnPaste {
            reload(keepingSelectionOn: clip.id)
        }
        // paste() manages focus itself; this covers copy-only actions.
        if !Settings.shared.pasteOnSelect {
            Paster.returnFocusToTarget()
        }
    }

    func reload(keepingSelectionOn id: Int64) {
        reload()
        if let index = clips.firstIndex(where: { $0.id == id }) {
            autoScroll = false
            selection = index
        }
    }

    func activateSelected(plainText: Bool = false) {
        guard let clip = selectedClip else { return }
        activate(clip, plainText: plainText)
    }

    func toggleFavorite(_ clip: Clip) {
        Store.shared.setFavorite(id: clip.id, !clip.favorite)
        reload()
    }

    func delete(_ clip: Clip) {
        Store.shared.delete(id: clip.id)
        let old = selection
        reload()
        selection = min(old, max(0, clips.count - 1))
    }

    func rename(_ clip: Clip, to title: String) {
        Store.shared.setTitle(id: clip.id, title.trimmingCharacters(in: .whitespacesAndNewlines))
        renamingID = nil
        reload()
    }

    /// Quick-paste by position — backs the ⌃⌘1…0 / ⌃⌥1…0 shortcuts.
    func quickPaste(index: Int, favorites: Bool) {
        let rows = Store.shared.fetch(query: "", favoritesOnly: favorites, limit: 10)
        guard rows.indices.contains(index) else { return }
        PanelController.shared.hide()
        if Settings.shared.pasteOnSelect {
            Paster.paste(rows[index], plainText: false)
        } else {
            Paster.write(rows[index], plainText: false)
        }
    }
}
