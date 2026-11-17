import AppKit
import XCTest
@testable import CopyT

final class ModelTests: XCTestCase {
    private func item(_ kind: ClipKind, text: String?, size: Int = 0) -> ClipItem {
        ClipItem(id: 1, kind: kind, text: text, dataPath: nil, sourceApp: nil, createdAt: Date(),
                 day: "2026-01-01", hash: "h", byteSize: size, pinned: false)
    }

    func testPreviewTitleText() {
        XCTAssertEqual(item(.text, text: "\n\n  第一行\n\n第二行\n第三行  ").previewTitle, "第一行 第二行")
        let long = String(repeating: "a", count: 500)
        XCTAssertEqual(item(.text, text: long).previewTitle.count, 201)
        XCTAssertEqual(item(.text, text: "   ").previewTitle, "")
        XCTAssertEqual(item(.text, text: nil).previewTitle, "")
    }

    func testPreviewTitleFilesAndImage() {
        XCTAssertEqual(item(.file, text: "/a/one.txt\n/b/two.pdf").previewTitle, "one.txt, two.pdf")
        XCTAssertEqual(item(.file, text: "/1\n/2\n/3\n/4\n/5").previewTitle, "1, 2, 3 等 5 个文件")
        XCTAssertEqual(item(.file, text: "/1\n/2").filePaths, ["/1", "/2"])
        XCTAssertEqual(item(.text, text: "/1\n/2").filePaths, [], "非文件类型没有路径")
        XCTAssertTrue(item(.image, text: nil, size: 2048).previewTitle.hasPrefix("图片 · "))
    }

    func testDayFormattingAndDisplayNames() {
        let today = DayFormatter.string(Date())
        let yesterday = DayFormatter.string(Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        XCTAssertEqual(DayCount(day: today, count: 1).displayName, "今天")
        XCTAssertEqual(DayCount(day: yesterday, count: 1).displayName, "昨天")
        XCTAssertTrue(DayCount(day: "2024-02-29", count: 1).displayName.hasPrefix("2024年2月29日"))
        XCTAssertEqual(DayCount(day: "garbage", count: 1).displayName, "garbage")
        XCTAssertEqual(DayFormatter.string(date("2026-12-31 23:59:59")), "2026-12-31")
        XCTAssertEqual(DayFormatter.folder.string(from: date("2026-01-02 00:00:00")), "2026/01/02")
    }

    func testImageFileDetection() {
        XCTAssertTrue("/x/a.PNG".isImageFilePath)
        XCTAssertTrue("/x/a.jpeg".isImageFilePath)
        XCTAssertTrue("/x/a.heic".isImageFilePath)
        XCTAssertFalse("/x/a.mp4".isImageFilePath)
        XCTAssertFalse("/x/folder".isImageFilePath)
    }

    func testPreferenceDefaultsAndParsing() {
        Preferences.registerDefaults()
        let key = Preferences.Key.ignoredApps
        let old = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(old, forKey: key) }

        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(Preferences.ignoredBundleIDs.contains("com.1password.1password"))
        UserDefaults.standard.set(" a.b ,c.d\n\n e.f ", forKey: key)
        XCTAssertEqual(Preferences.ignoredBundleIDs, ["a.b", "c.d", "e.f"])
        XCTAssertGreaterThan(Preferences.maxImageBytes, 0)
        XCTAssertTrue(Preferences.defaultStorageURL.path.hasSuffix("Application Support/CopyT"))
    }
}

final class ExporterTests: XCTestCase {
    @MainActor
    func testExportMarkdownWithImages() throws {
        let store = ClipStore(rootURL: try makeTempDir(self, "lib"))
        store.persistsStorageLocation = false
        store.add(Captures.text("第一天的文字 ```含反引号```"), at: date("2026-09-01 08:00:00"))
        store.add(Captures.image(), at: date("2026-09-01 09:00:00"))
        store.add(Captures.files(["/Users/me/报告.pdf"]), at: date("2026-09-02 10:00:00"))
        store.togglePin(store.items.first { $0.kind == .file }!)

        let out = try makeTempDir(self, "out")
        let dir = try Exporter.export(store.items, root: store.rootURL, to: out)
        let md = try String(contentsOf: dir.appendingPathComponent("记录.md"), encoding: .utf8)

        XCTAssertTrue(md.contains("共 3 条记录"))
        XCTAssertTrue(md.contains("第一天的文字 ```含反引号```"))
        XCTAssertTrue(md.contains("- `/Users/me/报告.pdf`"))
        XCTAssertTrue(md.contains("⭐️"))
        let day2 = try XCTUnwrap(md.range(of: "（2026-09-02）"))
        let day1 = try XCTUnwrap(md.range(of: "（2026-09-01）"))
        XCTAssertLessThan(day2.lowerBound, day1.lowerBound, "新的日期在前")

        let assets = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("assets").path)
        XCTAssertEqual(assets.count, 1)
        XCTAssertTrue(md.contains("![图片](assets/\(assets[0]))"))
    }

    @MainActor
    func testExportMissingImage() throws {
        let store = ClipStore(rootURL: try makeTempDir(self, "lib"))
        store.persistsStorageLocation = false
        store.add(Captures.image())
        try FileManager.default.removeItem(at: store.fileURL(for: store.items[0])!)
        let dir = try Exporter.export(store.items, root: store.rootURL, to: try makeTempDir(self, "out"))
        let md = try String(contentsOf: dir.appendingPathComponent("记录.md"), encoding: .utf8)
        XCTAssertTrue(md.contains("图片文件丢失"))
    }
}
