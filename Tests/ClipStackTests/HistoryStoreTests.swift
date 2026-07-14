import XCTest
@testable import ClipStackCore

final class HistoryStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipStackTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeStore(max: Int = 300) throws -> HistoryStore {
        try HistoryStore(directory: dir, maxItems: max)
    }

    private func textItem(_ s: String, pinned: Bool = false, date: Date = Date()) -> ClipItem {
        ClipItem(
            kind: .text,
            contentHash: ClipItem.hashOfText(s),
            plainText: s,
            createdAt: date,
            pinned: pinned,
            byteSize: s.utf8.count
        )
    }

    // MARK: basics

    func testAddInsertsAtFront() throws {
        let store = try makeStore()
        store.add(textItem("first"))
        store.add(textItem("second"))
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items[0].plainText, "second")
        XCTAssertEqual(store.items[1].plainText, "first")
    }

    func testDuplicateContentPromotesInsteadOfDuplicating() throws {
        let store = try makeStore()
        store.add(textItem("aaa"))
        store.add(textItem("bbb"))
        store.togglePin(id: store.items[1].id) // pin "aaa"
        store.add(textItem("aaa"))             // re-copy same content
        XCTAssertEqual(store.items.count, 2, "re-copy must not create a duplicate")
        XCTAssertEqual(store.items[0].plainText, "aaa", "re-copied entry moves to front")
        XCTAssertTrue(store.items[0].pinned, "pin state survives promotion")
    }

    func testPromoteIfExists() throws {
        let store = try makeStore()
        store.add(textItem("one"))
        store.add(textItem("two"))
        XCTAssertFalse(store.promoteIfExists(hash: ClipItem.hashOfText("missing")))
        XCTAssertTrue(store.promoteIfExists(hash: ClipItem.hashOfText("one")))
        XCTAssertEqual(store.items[0].plainText, "one")
    }

    // MARK: trimming

    func testTrimEvictsOldestUnpinned() throws {
        let store = try makeStore(max: 3)
        store.add(textItem("a", pinned: true))
        store.add(textItem("b"))
        store.add(textItem("c"))
        store.add(textItem("d")) // over capacity → oldest unpinned ("b") evicted
        XCTAssertEqual(store.items.count, 3)
        let texts = store.items.compactMap(\.plainText)
        XCTAssertEqual(texts, ["d", "c", "a"])
    }

    func testTrimDropsOldestWhenEverythingPinned() throws {
        let store = try makeStore(max: 2)
        store.add(textItem("a", pinned: true))
        store.add(textItem("b", pinned: true))
        store.add(textItem("c", pinned: true))
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.compactMap(\.plainText), ["c", "b"])
    }

    // MARK: persistence

    func testPersistenceRoundtrip() throws {
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4])
        var reloadedItems: [ClipItem] = []
        do {
            let store = try makeStore()
            store.add(textItem("hello\n\tworld")) // real newline + tab survive
            let fileName = try store.storeImagePNG(pngBytes)
            store.add(ClipItem(
                kind: .image,
                contentHash: ClipItem.hashOfImage(pngBytes),
                imageFileName: fileName,
                imagePixelWidth: 2,
                imagePixelHeight: 2,
                byteSize: pngBytes.count
            ))
        }
        let reloaded = try makeStore()
        reloadedItems = reloaded.items
        XCTAssertEqual(reloadedItems.count, 2)
        XCTAssertEqual(reloadedItems[0].kind, .image)
        XCTAssertEqual(reloaded.imageData(for: reloadedItems[0]), pngBytes)
        XCTAssertEqual(reloadedItems[1].plainText, "hello\n\tworld")
    }

    func testDeleteRemovesImageFile() throws {
        let store = try makeStore()
        let pngBytes = Data([9, 9, 9])
        let fileName = try store.storeImagePNG(pngBytes)
        let item = ClipItem(
            kind: .image,
            contentHash: ClipItem.hashOfImage(pngBytes),
            imageFileName: fileName,
            byteSize: pngBytes.count
        )
        store.add(item)
        let path = store.imagesDirectory.appendingPathComponent(fileName).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        store.delete(id: store.items[0].id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertTrue(store.items.isEmpty)
    }

    func testClearKeepsPinned() throws {
        let store = try makeStore()
        store.add(textItem("keep", pinned: true))
        store.add(textItem("drop1"))
        store.add(textItem("drop2"))
        store.clear(keepPinned: true)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].plainText, "keep")
        store.clear(keepPinned: false)
        XCTAssertTrue(store.items.isEmpty)
    }

    // MARK: notifications & hashing

    func testOnChangeFires() throws {
        let store = try makeStore()
        var fired = 0
        store.onChange = { fired += 1 }
        store.add(textItem("x"))
        store.togglePin(id: store.items[0].id)
        store.delete(id: store.items[0].id)
        XCTAssertEqual(fired, 3)
    }

    func testHashStability() {
        XCTAssertEqual(ClipItem.hashOfText("同一段文本"), ClipItem.hashOfText("同一段文本"))
        XCTAssertNotEqual(ClipItem.hashOfText("a"), ClipItem.hashOfText("b"))
        XCTAssertNotEqual(
            ClipItem.hashOfFiles(["/a", "/b"]),
            ClipItem.hashOfFiles(["/a/b"]),
            "path list hashing must not collide on concatenation"
        )
    }

    func testPreviewLineFlattensNewlines() {
        let item = ClipItem(
            kind: .text,
            contentHash: ClipItem.hashOfText("line1\nline2"),
            plainText: "line1\nline2"
        )
        XCTAssertFalse(item.previewLine.contains("\n"))
        XCTAssertTrue(item.previewLine.contains("line1"))
    }
}
