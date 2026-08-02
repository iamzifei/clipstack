import SwiftUI
import ClipStackCore

/// View-model behind the switcher panel: search filter + keyboard selection.
final class SwitcherModel: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { selectionIndex = 0 } }
    }
    @Published var selectionIndex = 0
    /// Bumped whenever the underlying store mutates, to force a re-render.
    @Published private(set) var revision = 0
    /// When on, the panel stays visible above other apps after it loses focus
    /// or copies an entry — so it can serve as a reference sheet / notepad
    /// while typing somewhere else. Persisted across launches.
    @Published var keepOnTop = UserDefaults.standard.bool(forKey: PrefKey.keepOnTop) {
        didSet {
            guard keepOnTop != oldValue else { return }
            UserDefaults.standard.set(keepOnTop, forKey: PrefKey.keepOnTop)
        }
    }

    let store: HistoryStore
    var onCommit: ((ClipItem) -> Void)?
    var onClose: (() -> Void)?

    init(store: HistoryStore) {
        self.store = store
    }

    var filtered: [ClipItem] {
        _ = revision
        let all = store.orderedItems
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.searchText.localizedCaseInsensitiveContains(query)
                || ($0.sourceApp?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var selected: ClipItem? {
        let list = filtered
        guard list.indices.contains(selectionIndex) else { return nil }
        return list[selectionIndex]
    }

    func moveSelection(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selectionIndex = min(max(0, selectionIndex + delta), count - 1)
    }

    func commitSelection() {
        if let item = selected { onCommit?(item) }
    }

    func commit(atVisibleIndex index: Int) {
        let list = filtered
        guard list.indices.contains(index) else { return }
        onCommit?(list[index])
    }

    func deleteSelection() {
        guard let item = selected else { return }
        store.delete(id: item.id)
        let count = filtered.count
        if selectionIndex >= count { selectionIndex = max(0, count - 1) }
    }

    func togglePinSelection() {
        guard let item = selected else { return }
        store.togglePin(id: item.id)
        // Pinning re-orders the list (pinned entries float to the top), so
        // follow the item to its new row instead of leaving the highlight
        // sitting on whatever slid into the old index.
        if let newIndex = filtered.firstIndex(where: { $0.id == item.id }) {
            selectionIndex = newIndex
        }
    }

    func refresh() {
        revision += 1
        let count = filtered.count
        if selectionIndex >= count { selectionIndex = max(0, count - 1) }
    }
}
