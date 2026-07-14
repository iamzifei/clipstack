import Foundation

/// Persistent clipboard history.
///
/// Storage layout under `directory`:
///   history.json   — JSON array of `ClipItem` (newest first)
///   images/*.png   — image payloads referenced by `ClipItem.imageFileName`
///
/// NOT thread-safe by design: the app only touches it from the main thread
/// (pasteboard polling timer, menu actions and the switcher panel all run
/// on the main run loop). Tests are single-threaded too.
public final class HistoryStore {
    public private(set) var items: [ClipItem] = []
    public let maxItems: Int
    public let directory: URL
    /// Called after every mutation, on the caller's thread. Used by the UI.
    public var onChange: (() -> Void)?

    public var imagesDirectory: URL { directory.appendingPathComponent("images", isDirectory: true) }
    private var historyFile: URL { directory.appendingPathComponent("history.json") }

    public init(directory: URL, maxItems: Int = 300) throws {
        self.directory = directory
        self.maxItems = max(1, maxItems)
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try fm.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        load()
    }

    // MARK: mutations

    /// If an entry with the same content already exists, move it to the front
    /// (refreshing its timestamp) instead of inserting a duplicate.
    @discardableResult
    public func promoteIfExists(hash: String, date: Date = Date()) -> Bool {
        guard let idx = items.firstIndex(where: { $0.contentHash == hash }) else { return false }
        var item = items.remove(at: idx)
        item.createdAt = date
        items.insert(item, at: 0)
        persistAndNotify()
        return true
    }

    /// Insert a new entry at the front, de-duplicating against existing content.
    public func add(_ item: ClipItem) {
        if let idx = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            // Same content re-copied: keep the existing entry (and its pin
            // state), just bump it to the front. Drop any freshly written
            // image file belonging to the duplicate.
            if let newName = item.imageFileName, newName != items[idx].imageFileName {
                try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(newName))
            }
            var existing = items.remove(at: idx)
            existing.createdAt = item.createdAt
            if let source = item.sourceApp { existing.sourceApp = source }
            items.insert(existing, at: 0)
        } else {
            items.insert(item, at: 0)
            trimIfNeeded()
        }
        persistAndNotify()
    }

    public func contains(hash: String) -> Bool {
        items.contains { $0.contentHash == hash }
    }

    public func delete(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        removeSideFiles(items[idx])
        items.remove(at: idx)
        persistAndNotify()
    }

    public func togglePin(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].pinned.toggle()
        persistAndNotify()
    }

    /// Remove entries; pinned ones survive unless `keepPinned` is false.
    public func clear(keepPinned: Bool = true) {
        let victims = keepPinned ? items.filter { !$0.pinned } : items
        victims.forEach(removeSideFiles)
        items = keepPinned ? items.filter { $0.pinned } : []
        persistAndNotify()
    }

    // MARK: image payloads

    /// Persist PNG bytes and return the generated file name for `imageFileName`.
    public func storeImagePNG(_ data: Data) throws -> String {
        let name = UUID().uuidString + ".png"
        try data.write(to: imagesDirectory.appendingPathComponent(name), options: .atomic)
        return name
    }

    public func imageData(for item: ClipItem) -> Data? {
        guard let name = item.imageFileName else { return nil }
        return try? Data(contentsOf: imagesDirectory.appendingPathComponent(name))
    }

    // MARK: persistence

    public func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: historyFile, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: historyFile) else { return }
        if let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) {
            items = decoded
        }
    }

    // MARK: internals

    private func trimIfNeeded() {
        while items.count > maxItems {
            // Evict the oldest unpinned entry first; if everything is pinned,
            // fall back to dropping the oldest entry outright.
            if let idx = items.lastIndex(where: { !$0.pinned }) {
                removeSideFiles(items[idx])
                items.remove(at: idx)
            } else {
                removeSideFiles(items.removeLast())
            }
        }
    }

    private func removeSideFiles(_ item: ClipItem) {
        guard let name = item.imageFileName else { return }
        try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(name))
    }

    private func persistAndNotify() {
        save()
        onChange?()
    }
}
