import XCTest
@testable import CopyT

final class DatabaseTests: XCTestCase {
    @MainActor
    private func makeDB() throws -> Database {
        let dir = try makeTempDir(self)
        return try Database(url: dir.appendingPathComponent(Database.fileName))
    }

    @MainActor
    func testInsertQueryOrderedNewestFirst() throws {
        let db = try makeDB()
        try db.insert(Captures.text("a"), dataPath: nil, date: date("2026-01-01 10:00:00"))
        try db.insert(Captures.text("b"), dataPath: nil, date: date("2026-01-03 10:00:00"))
        try db.insert(Captures.text("c"), dataPath: nil, date: date("2026-01-02 10:00:00"))

        let items = try db.items(ClipFilter(), limit: 100)
        XCTAssertEqual(items.map(\.text), ["b", "c", "a"])
        XCTAssertEqual(items.map(\.day), ["2026-01-03", "2026-01-02", "2026-01-01"])
        XCTAssertEqual(try db.totalCount(), 3)
        XCTAssertEqual(try db.items(ClipFilter(), limit: 2).count, 2)
    }

    @MainActor
    func testRoundTripsAllFields() throws {
        let db = try makeDB()
        let c = Captures.image()
        let d = date("2026-05-06 07:08:09")
        let id = try db.insert(c, dataPath: "media/2026/05/06/x.png", date: d)
        let item = try XCTUnwrap(try db.item(withHash: c.hash))
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.kind, .image)
        XCTAssertNil(item.text)
        XCTAssertEqual(item.dataPath, "media/2026/05/06/x.png")
        XCTAssertEqual(item.sourceApp, "Preview")
        XCTAssertEqual(item.createdAt.timeIntervalSince1970, d.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(item.day, "2026-05-06")
        XCTAssertEqual(item.byteSize, c.byteSize)
        XCTAssertFalse(item.pinned)
    }

    @MainActor
    func testSearchKeywordsChineseAndEscaping() throws {
        let db = try makeDB()
        let now = Date()
        for s in ["hello world", "hello there", "100% sure", "1000 sure", "a_b", "axb", "你好，世界", "back\\slash"] {
            try db.insert(Captures.text(s), dataPath: nil, date: now)
        }
        try db.insert(Captures.text("from safari", app: "Safari"), dataPath: nil, date: now)

        func search(_ q: String) throws -> Set<String> {
            var f = ClipFilter(); f.search = q
            return Set(try db.items(f, limit: 100).compactMap(\.text))
        }
        XCTAssertEqual(try search("hello"), ["hello world", "hello there"])
        XCTAssertEqual(try search("hello world"), ["hello world"], "多个关键词需同时匹配")
        XCTAssertEqual(try search("  world   hello "), ["hello world"])
        XCTAssertEqual(try search("HELLO"), ["hello world", "hello there"], "英文不区分大小写")
        XCTAssertEqual(try search("%"), ["100% sure"], "% 必须按字面匹配")
        XCTAssertEqual(try search("_"), ["a_b"], "_ 必须按字面匹配")
        XCTAssertEqual(try search("\\"), ["back\\slash"])
        XCTAssertEqual(try search("世界"), ["你好，世界"])
        XCTAssertEqual(try search("Safari"), ["from safari"], "可按来源应用搜索")
        XCTAssertEqual(try search("不存在"), [])
        XCTAssertEqual(try search("").count, 9)
    }

    @MainActor
    func testFiltersKindDayPinned() throws {
        let db = try makeDB()
        let t = try db.insert(Captures.text("t"), dataPath: nil, date: date("2026-02-01 09:00:00"))
        try db.insert(Captures.image(), dataPath: "m.png", date: date("2026-02-01 10:00:00"))
        try db.insert(Captures.files(["/tmp/a"]), dataPath: nil, date: date("2026-02-02 10:00:00"))
        try db.setPinned(id: t, true)

        var f = ClipFilter(); f.kind = .image
        XCTAssertEqual(try db.items(f, limit: 10).map(\.kind), [.image])
        f = ClipFilter(); f.day = "2026-02-01"
        XCTAssertEqual(try db.items(f, limit: 10).count, 2)
        f = ClipFilter(); f.pinnedOnly = true
        XCTAssertEqual(try db.items(f, limit: 10).map(\.id), [t])
        f = ClipFilter(); f.day = "2026-02-01"; f.kind = .file
        XCTAssertEqual(try db.items(f, limit: 10).count, 0)

        try db.setPinned(id: t, false)
        f = ClipFilter(); f.pinnedOnly = true
        XCTAssertTrue(try db.items(f, limit: 10).isEmpty)
    }

    @MainActor
    func testDayCounts() throws {
        let db = try makeDB()
        try db.insert(Captures.text("1"), dataPath: nil, date: date("2026-03-01 23:59:59"))
        try db.insert(Captures.text("2"), dataPath: nil, date: date("2026-03-02 00:00:00"))
        try db.insert(Captures.text("3"), dataPath: nil, date: date("2026-03-02 12:00:00"))
        XCTAssertEqual(try db.dayCounts(), [DayCount(day: "2026-03-02", count: 2), DayCount(day: "2026-03-01", count: 1)])
    }

    @MainActor
    func testTouchMovesToNewDayAndKeepsSourceWhenNil() throws {
        let db = try makeDB()
        let id = try db.insert(Captures.text("x"), dataPath: nil, date: date("2026-01-01 08:00:00"))
        try db.insert(Captures.text("y"), dataPath: nil, date: date("2026-01-02 08:00:00"))
        try db.touch(id: id, date: date("2026-01-05 08:00:00"), sourceApp: nil)
        let items = try db.items(ClipFilter(), limit: 10)
        XCTAssertEqual(items.first?.text, "x")
        XCTAssertEqual(items.first?.day, "2026-01-05")
        XCTAssertEqual(items.first?.sourceApp, "TestApp")
        try db.touch(id: id, date: date("2026-01-06 08:00:00"), sourceApp: "Notes")
        XCTAssertEqual(try db.items(ClipFilter(), limit: 1).first?.sourceApp, "Notes")
    }

    @MainActor
    func testDeleteAndDeleteUnpinnedBefore() throws {
        let db = try makeDB()
        let old = try db.insert(Captures.text("old"), dataPath: nil, date: date("2025-01-01 00:00:00"))
        let oldPinned = try db.insert(Captures.text("oldPinned"), dataPath: nil, date: date("2025-01-01 00:00:00"))
        try db.insert(Captures.text("new"), dataPath: nil, date: date("2026-01-01 00:00:00"))
        try db.setPinned(id: oldPinned, true)

        let cutoff = date("2025-06-01 00:00:00")
        XCTAssertEqual(try db.unpinnedItems(before: cutoff).map(\.id), [old])
        try db.deleteUnpinned(before: cutoff)
        XCTAssertEqual(Set(try db.items(ClipFilter(), limit: 10).compactMap(\.text)), ["oldPinned", "new"])

        try db.deleteUnpinned(before: nil)
        XCTAssertEqual(try db.items(ClipFilter(), limit: 10).compactMap(\.text), ["oldPinned"])

        try db.delete(id: oldPinned)
        XCTAssertEqual(try db.totalCount(), 0)
    }

    @MainActor
    func testPersistsAcrossReopen() throws {
        let dir = try makeTempDir(self)
        let url = dir.appendingPathComponent(Database.fileName)
        do {
            let db = try Database(url: url)
            try db.insert(Captures.text("persist me"), dataPath: nil, date: Date())
            db.checkpoint()
            db.close()
        }
        let db2 = try Database(url: url)
        XCTAssertEqual(try db2.items(ClipFilter(), limit: 10).first?.text, "persist me")
    }

    @MainActor
    func testLargeTextAndManyRows() throws {
        let db = try makeDB()
        let big = String(repeating: "长文本", count: 200_000)
        try db.insert(Captures.text(big), dataPath: nil, date: Date())
        for i in 0..<2000 {
            try db.insert(Captures.text("row \(i)"), dataPath: nil, date: Date(timeIntervalSinceNow: Double(i)))
        }
        XCTAssertEqual(try db.totalCount(), 2001)
        var f = ClipFilter(); f.search = "长文本"
        XCTAssertEqual(try db.items(f, limit: 5).first?.text?.count, big.count)
        measure {
            var f = ClipFilter(); f.search = "row 1999"
            _ = try? db.items(f, limit: 100)
        }
    }

    func testOpenFailureThrows() {
        XCTAssertThrowsError(try Database(url: URL(fileURLWithPath: "/nonexistent-dir-\(UUID())/x.sqlite")))
    }
}
