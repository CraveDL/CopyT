import AppKit
import XCTest
@testable import CopyT

final class ClipStoreTests: XCTestCase {
    @MainActor
    private func makeStore(_ name: String = "root") throws -> ClipStore {
        let store = ClipStore(rootURL: try makeTempDir(self, name))
        store.persistsStorageLocation = false
        store.pasteboard = makePasteboard(self)
        return store
    }

    private var fm: FileManager { .default }

    // MARK: - 记录与去重

    @MainActor
    func testAddAndDedupMovesToTop() throws {
        let store = try makeStore()
        store.add(Captures.text("first"), at: date("2026-01-01 10:00:00"))
        store.add(Captures.text("second"), at: date("2026-01-02 10:00:00"))
        XCTAssertEqual(store.items.map(\.text), ["second", "first"])
        let revision = store.revision

        store.add(Captures.text("first", app: "Notes"), at: date("2026-01-03 10:00:00"))
        XCTAssertEqual(store.items.count, 2, "相同内容不应重复存储")
        XCTAssertEqual(store.items.first?.text, "first")
        XCTAssertEqual(store.items.first?.day, "2026-01-03")
        XCTAssertEqual(store.items.first?.sourceApp, "Notes")
        XCTAssertGreaterThan(store.revision, revision)
        XCTAssertNil(store.lastError)
    }

    @MainActor
    func testMediaSavedInDateFolders() throws {
        let store = try makeStore()
        let png = makePNG()
        store.add(Captures.image(png), at: date("2025-03-04 12:00:00"))
        store.add(Captures.rich("加粗"), at: date("2025-03-05 12:00:00"))

        let image = try XCTUnwrap(store.items.first { $0.kind == .image })
        XCTAssertTrue(image.dataPath?.hasPrefix("media/2025/03/04/") == true, image.dataPath ?? "nil")
        XCTAssertTrue(image.dataPath?.hasSuffix(".png") == true)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(store.fileURL(for: image))), png)

        let rich = try XCTUnwrap(store.items.first { $0.kind == .richText })
        XCTAssertTrue(rich.dataPath?.hasPrefix("media/2025/03/05/") == true)
        XCTAssertTrue(rich.dataPath?.hasSuffix(".rtf") == true)

        // 同一张图片再次复制不应产生第二个文件
        store.add(Captures.image(png), at: date("2025-03-06 12:00:00"))
        let dayDir = store.rootURL.appendingPathComponent("media/2025/03/04")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dayDir.path).count, 1)
        XCTAssertFalse(fm.fileExists(atPath: store.rootURL.appendingPathComponent("media/2025/03/06").path))
    }

    // MARK: - 浏览与检索

    @MainActor
    func testScopesFiltersAndSearch() throws {
        let store = try makeStore()
        store.add(Captures.text("apple pie"), at: date("2026-04-01 10:00:00"))
        store.add(Captures.text("banana"), at: date("2026-04-01 11:00:00"))
        store.add(Captures.image(), at: date("2026-04-02 10:00:00"))
        store.add(Captures.files(["/tmp/apple.txt"]), at: date("2026-04-03 10:00:00"))

        XCTAssertEqual(store.dayCounts.map(\.day), ["2026-04-03", "2026-04-02", "2026-04-01"])
        XCTAssertEqual(store.dayCounts.map(\.count), [1, 1, 2])
        XCTAssertEqual(store.totalCount, 4)

        store.scope = .day("2026-04-01")
        XCTAssertEqual(Set(store.items.compactMap(\.text)), ["apple pie", "banana"])

        store.scope = .all
        store.kindFilter = .image
        XCTAssertEqual(store.items.map(\.kind), [.image])

        store.kindFilter = nil
        store.searchText = "apple"
        store.reload() // 搜索框有 200ms 防抖，这里直接刷新
        XCTAssertEqual(store.items.map(\.kind), [.file, .text])

        store.togglePin(try XCTUnwrap(store.items.last))
        store.searchText = ""
        store.scope = .pinned
        XCTAssertEqual(store.items.compactMap(\.text), ["apple pie"])
        XCTAssertTrue(store.items[0].pinned)

        // 快速搜索不受历史窗口的筛选影响
        XCTAssertEqual(store.quickSearch("").count, 4)
        XCTAssertEqual(store.quickSearch("banana").count, 1)
    }

    @MainActor
    func testSearchDebounce() throws {
        let store = try makeStore()
        store.add(Captures.text("needle"))
        store.add(Captures.text("hay"))
        store.searchText = "needle"
        let exp = expectation(description: "debounced reload")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(store.items.compactMap(\.text), ["needle"])
    }

    // MARK: - 删除与清理

    @MainActor
    func testDeleteRemovesMediaAndEmptyFolders() throws {
        let store = try makeStore()
        store.add(Captures.image(), at: date("2025-07-08 10:00:00"))
        let item = try XCTUnwrap(store.items.first)
        let file = try XCTUnwrap(store.fileURL(for: item))
        XCTAssertTrue(fm.fileExists(atPath: file.path))

        store.delete([item])
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: file.path))
        XCTAssertFalse(fm.fileExists(atPath: store.rootURL.appendingPathComponent("media/2025").path),
                       "空的日期目录应被清理")
        XCTAssertTrue(fm.fileExists(atPath: store.rootURL.appendingPathComponent(Database.fileName).path))
    }

    @MainActor
    func testDeleteKeepsNonEmptyFolders() throws {
        let store = try makeStore()
        store.add(Captures.image(makePNG(color: .red)), at: date("2025-07-08 10:00:00"))
        store.add(Captures.image(makePNG(color: .blue)), at: date("2025-07-08 11:00:00"))
        store.delete([store.items[0]])
        let remaining = try XCTUnwrap(store.items.first)
        XCTAssertTrue(fm.fileExists(atPath: try XCTUnwrap(store.fileURL(for: remaining)).path))
    }

    @MainActor
    func testRetentionCleanupKeepsPinnedAndRecent() throws {
        let store = try makeStore()
        let now = date("2026-06-30 12:00:00")
        store.add(Captures.text("old"), at: date("2026-05-01 12:00:00"))
        store.add(Captures.image(), at: date("2026-05-01 12:00:00"))
        store.add(Captures.text("old but pinned"), at: date("2026-05-01 12:00:00"))
        store.add(Captures.text("recent"), at: date("2026-06-20 12:00:00"))
        store.togglePin(try XCTUnwrap(store.items.first { $0.text == "old but pinned" }))
        let imageFile = try XCTUnwrap(store.fileURL(for: try XCTUnwrap(store.items.first { $0.kind == .image })))

        store.cleanupExpired(retentionDays: 0, now: now)
        XCTAssertEqual(store.totalCount, 4, "0 = 永久保存")

        store.cleanupExpired(retentionDays: 30, now: now)
        XCTAssertEqual(Set(store.items.compactMap(\.text)), ["old but pinned", "recent"])
        XCTAssertFalse(fm.fileExists(atPath: imageFile.path), "过期图片文件也要删除")
    }

    @MainActor
    func testClearUnpinned() throws {
        let store = try makeStore()
        store.add(Captures.text("a"))
        store.add(Captures.text("b"))
        store.togglePin(store.items[0])
        store.clearUnpinned()
        XCTAssertEqual(store.items.count, 1)
        XCTAssertTrue(store.items[0].pinned)
    }

    // MARK: - 复制回剪贴板

    @MainActor
    func testCopyEachKindToPasteboard() throws {
        let store = try makeStore()
        var ownWrites = 0
        store.onOwnPasteboardWrite = { ownWrites += 1 }
        let pb = store.pasteboard

        let realFile = try makeTempDir(self, "files").appendingPathComponent("doc.txt")
        try "x".write(to: realFile, atomically: true, encoding: .utf8)
        let png = makePNG()
        store.add(Captures.text("plain"), at: date("2026-01-01 00:00:01"))
        store.add(Captures.rich("rich"), at: date("2026-01-01 00:00:02"))
        store.add(Captures.image(png), at: date("2026-01-01 00:00:03"))
        store.add(Captures.files([realFile.path]), at: date("2026-01-01 00:00:04"))
        func item(_ k: ClipKind) -> ClipItem { store.items.first { $0.kind == k }! }

        store.copy(item(.text))
        XCTAssertEqual(pb.string(forType: .string), "plain")

        store.copy(item(.richText))
        XCTAssertEqual(pb.string(forType: .string), "rich")
        XCTAssertNotNil(pb.data(forType: .rtf))

        store.copy(item(.image))
        XCTAssertEqual(pb.data(forType: .png), png)
        XCTAssertNotNil(pb.data(forType: .tiff))

        store.copy(item(.file))
        let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(urls?.map(\.standardizedFileURL.path), [realFile.standardizedFileURL.path])

        XCTAssertEqual(ownWrites, 4)
        XCTAssertNil(store.lastError)
        XCTAssertEqual(store.items.first?.kind, .file, "复制后的记录移到最前")
    }

    @MainActor
    func testCopyMissingImageReportsError() throws {
        let store = try makeStore()
        store.add(Captures.image())
        let item = store.items[0]
        try fm.removeItem(at: try XCTUnwrap(store.fileURL(for: item)))
        var ownWrites = 0
        store.onOwnPasteboardWrite = { ownWrites += 1 }
        store.copy(item)
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(ownWrites, 0)
    }

    // MARK: - 更改存放位置

    @MainActor
    func testChangeStorageMovesData() throws {
        let store = try makeStore("old")
        let oldRoot = store.rootURL
        store.add(Captures.text("keep me"))
        store.add(Captures.image(), at: date("2026-08-09 10:00:00"))
        store.togglePin(store.items.first { $0.text == "keep me" }!)

        let newRoot = try makeTempDir(self, "new").appendingPathComponent("sub/CopyT")
        XCTAssertEqual(try store.changeStorage(to: newRoot, moveExisting: true), .moved)

        XCTAssertEqual(store.rootURL.path, newRoot.standardizedFileURL.path)
        XCTAssertFalse(fm.fileExists(atPath: oldRoot.appendingPathComponent(Database.fileName).path))
        XCTAssertFalse(fm.fileExists(atPath: oldRoot.appendingPathComponent("media").path))
        XCTAssertTrue(fm.fileExists(atPath: newRoot.appendingPathComponent(Database.fileName).path))
        XCTAssertEqual(store.totalCount, 2)
        XCTAssertTrue(store.items.first { $0.text == "keep me" }!.pinned)
        let image = store.items.first { $0.kind == .image }!
        XCTAssertTrue(fm.fileExists(atPath: store.fileURL(for: image)!.path))
        XCTAssertTrue(store.fileURL(for: image)!.path.hasPrefix(newRoot.path))

        // 迁移后仍可正常写入
        store.add(Captures.text("after move"))
        XCTAssertEqual(store.totalCount, 3)
        XCTAssertNil(store.lastError)
    }

    @MainActor
    func testChangeStorageWithoutMoveStartsEmptyAndKeepsOld() throws {
        let store = try makeStore("old")
        let oldRoot = store.rootURL
        store.add(Captures.text("stays in old"))
        let newRoot = try makeTempDir(self, "new")

        XCTAssertEqual(try store.changeStorage(to: newRoot, moveExisting: false), .switchedToEmpty)
        XCTAssertEqual(store.totalCount, 0)
        XCTAssertTrue(fm.fileExists(atPath: oldRoot.appendingPathComponent(Database.fileName).path))

        // 切回旧位置，数据还在
        XCTAssertEqual(try store.changeStorage(to: oldRoot, moveExisting: false), .switchedToExisting)
        XCTAssertEqual(store.items.compactMap(\.text), ["stays in old"])
    }

    @MainActor
    func testChangeStorageToExistingLibraryDoesNotOverwrite() throws {
        let other = try makeStore("other")
        other.add(Captures.text("library B"))
        let otherRoot = other.rootURL

        let store = try makeStore("main")
        let mainRoot = store.rootURL
        store.add(Captures.text("library A"))

        XCTAssertEqual(try store.changeStorage(to: otherRoot, moveExisting: true), .switchedToExisting)
        XCTAssertEqual(store.items.compactMap(\.text), ["library B"])
        XCTAssertTrue(fm.fileExists(atPath: mainRoot.appendingPathComponent(Database.fileName).path),
                      "目标已有资料库时不移动、不覆盖原数据")
    }

    @MainActor
    func testChangeStorageRejectsNestedAndSamePath() throws {
        let store = try makeStore()
        store.add(Captures.text("x"))
        XCTAssertEqual(try store.changeStorage(to: store.rootURL, moveExisting: true), .unchanged)
        XCTAssertThrowsError(try store.changeStorage(to: store.rootURL.appendingPathComponent("inner"), moveExisting: true))
        XCTAssertEqual(store.totalCount, 1)
    }

    @MainActor
    func testChangeStorageConflictLeavesOldLibraryWorking() throws {
        let store = try makeStore("old")
        let oldRoot = store.rootURL
        store.add(Captures.image())
        let newRoot = try makeTempDir(self, "new")
        try fm.createDirectory(at: newRoot.appendingPathComponent("media"), withIntermediateDirectories: true)

        XCTAssertThrowsError(try store.changeStorage(to: newRoot, moveExisting: true))
        XCTAssertEqual(store.rootURL.path, oldRoot.standardizedFileURL.path)
        XCTAssertEqual(store.totalCount, 1)
        store.add(Captures.text("still works"))
        XCTAssertEqual(store.totalCount, 2)
    }

    @MainActor
    func testUnwritableStorageReportsError() throws {
        let store = ClipStore(rootURL: URL(fileURLWithPath: "/System/CopyT-\(UUID().uuidString)"))
        XCTAssertNotNil(store.lastError)
        store.add(Captures.text("ignored"))
        XCTAssertTrue(store.items.isEmpty)
    }

    func testDirectorySize() throws {
        let dir = try makeTempDir(self)
        try Data(count: 10_000).write(to: dir.appendingPathComponent("a"))
        XCTAssertGreaterThanOrEqual(ClipStore.directorySize(dir), 10_000)
    }
}
