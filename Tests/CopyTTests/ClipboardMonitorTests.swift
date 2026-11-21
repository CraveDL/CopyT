import AppKit
import XCTest
@testable import CopyT

final class ClipboardMonitorTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        Preferences.registerDefaults()
    }

    @MainActor
    private func capture(_ pb: NSPasteboard, maxImageBytes: Int = 50_000_000) -> Capture? {
        ClipboardMonitor.makeCapture(from: pb, types: Set(pb.types ?? []), sourceApp: "Test",
                                     maxImageBytes: maxImageBytes)
    }

    // MARK: - 解析各种剪贴板内容

    @MainActor
    func testPlainText() {
        let pb = makePasteboard(self)
        pb.clearContents()
        pb.setString("你好 CopyT\n第二行", forType: .string)
        let c = capture(pb)
        XCTAssertEqual(c?.kind, .text)
        XCTAssertEqual(c?.text, "你好 CopyT\n第二行")
        XCTAssertEqual(c?.sourceApp, "Test")
        XCTAssertNil(c?.data)
    }

    @MainActor
    func testWhitespaceOnlyIsIgnored() {
        let pb = makePasteboard(self)
        pb.clearContents()
        pb.setString("  \n\t ", forType: .string)
        XCTAssertNil(capture(pb))
    }

    @MainActor
    func testRTF() {
        let pb = makePasteboard(self)
        pb.clearContents()
        let rtf = makeRTF("Bold")
        pb.setData(rtf, forType: .rtf)
        pb.setString("Bold", forType: .string)
        let c = capture(pb)
        XCTAssertEqual(c?.kind, .richText)
        XCTAssertEqual(c?.fileExtension, "rtf")
        XCTAssertEqual(c?.data, rtf)
        XCTAssertEqual(c?.text, "Bold")
    }

    @MainActor
    func testHTML() {
        let pb = makePasteboard(self)
        pb.clearContents()
        pb.setString("<b>Hi</b>", forType: .html)
        pb.setString("Hi", forType: .string)
        let c = capture(pb)
        XCTAssertEqual(c?.kind, .richText)
        XCTAssertEqual(c?.fileExtension, "html")
        XCTAssertEqual(c?.text, "Hi")
    }

    @MainActor
    func testSameTextPlainAndRichDedupHash() {
        let pb = makePasteboard(self)
        pb.clearContents(); pb.setString("same", forType: .string)
        let plain = capture(pb)
        pb.clearContents(); pb.setData(makeRTF("same"), forType: .rtf); pb.setString("same", forType: .string)
        let rich = capture(pb)
        XCTAssertEqual(plain?.hash, rich?.hash)
    }

    @MainActor
    func testPNGImage() {
        let pb = makePasteboard(self)
        pb.clearContents()
        let png = makePNG()
        pb.setData(png, forType: .png)
        let c = capture(pb)
        XCTAssertEqual(c?.kind, .image)
        XCTAssertEqual(c?.data, png)
        XCTAssertEqual(c?.fileExtension, "png")
        XCTAssertEqual(c?.byteSize, png.count)
    }

    @MainActor
    func testTIFFImageConvertedToPNG() throws {
        let pb = makePasteboard(self)
        pb.clearContents()
        let tiff = try XCTUnwrap(NSImage(data: makePNG(width: 5, height: 7))?.tiffRepresentation)
        pb.setData(tiff, forType: .tiff)
        let c = try XCTUnwrap(capture(pb))
        XCTAssertEqual(c.kind, .image)
        let data = try XCTUnwrap(c.data)
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "应转换为 PNG")
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(rep.pixelsWide, 5)
        XCTAssertEqual(rep.pixelsHigh, 7)
    }

    @MainActor
    func testWriteObjectsNSImage() {
        let pb = makePasteboard(self)
        pb.clearContents()
        pb.writeObjects([NSImage(data: makePNG())!])
        XCTAssertEqual(capture(pb)?.kind, .image)
    }

    @MainActor
    func testImageOverLimitIgnored() {
        let pb = makePasteboard(self)
        pb.clearContents()
        pb.setData(makePNG(width: 64, height: 64), forType: .png)
        XCTAssertNil(capture(pb, maxImageBytes: 10))
    }

    @MainActor
    func testFilesPreferredOverTextAndIcon() throws {
        let dir = try makeTempDir(self)
        let a = dir.appendingPathComponent("a.txt"), b = dir.appendingPathComponent("图 片.png")
        try "a".write(to: a, atomically: true, encoding: .utf8)
        try makePNG().write(to: b)
        let pb = makePasteboard(self)
        pb.clearContents()
        pb.writeObjects([a as NSURL, b as NSURL])
        pb.addTypes([.string, .tiff], owner: nil)
        pb.setString("a.txt", forType: .string)
        pb.setData(NSImage(data: makePNG())!.tiffRepresentation!, forType: .tiff)

        let c = try XCTUnwrap(capture(pb))
        XCTAssertEqual(c.kind, .file)
        let paths = c.text?.split(separator: "\n").map(String.init) ?? []
        XCTAssertEqual(paths.map { ($0 as NSString).lastPathComponent }, ["a.txt", "图 片.png"])
        XCTAssertEqual(paths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
                       [a, b].map { $0.resolvingSymlinksInPath().path })
    }

    @MainActor
    func testTextPreferredOverImagePreview() {
        // 例如 Office / Excel 复制文字时会附带图片预览
        let pb = makePasteboard(self)
        pb.clearContents()
        pb.setString("A1\tB1", forType: .string)
        pb.setData(makePNG(), forType: .png)
        XCTAssertEqual(capture(pb)?.kind, .text)
    }

    @MainActor
    func testEmptyPasteboard() {
        let pb = makePasteboard(self)
        pb.clearContents()
        XCTAssertNil(capture(pb))
    }

    // MARK: - 轮询、隐私与暂停

    @MainActor
    private func makeMonitor(_ pb: NSPasteboard, bundleID: String? = "com.apple.TextEdit") -> (ClipboardMonitor, () -> [Capture]) {
        let monitor = ClipboardMonitor(pasteboard: pb)
        monitor.settleDelay = 0
        monitor.frontmostApp = { ("App", bundleID) }
        // 不读写全局 UserDefaults：测试并行运行时会共用同一份设置而互相干扰
        monitor.isPaused = { false }
        monitor.ignoredBundleIDs = { Preferences.parseBundleIDs(Preferences.defaultIgnoredApps) }
        var got: [Capture] = []
        monitor.onCapture = { got.append($0) }
        return (monitor, { got })
    }

    @MainActor
    func testPollCapturesOnlyOnChange() {
        let pb = makePasteboard(self)
        let (m, got) = makeMonitor(pb)
        m.poll()
        XCTAssertEqual(got().count, 0, "启动时已有内容不记录")

        pb.clearContents(); pb.setString("one", forType: .string)
        m.poll(); m.poll()
        XCTAssertEqual(got().map(\.text), ["one"])

        pb.clearContents(); pb.setString("two", forType: .string)
        m.poll()
        XCTAssertEqual(got().map(\.text), ["one", "two"])
        XCTAssertEqual(got().last?.sourceApp, "App")
    }

    @MainActor
    func testConcealedAndTransientTypesSkipped() {
        let pb = makePasteboard(self)
        let (m, got) = makeMonitor(pb)
        for type in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
                     "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword"] {
            pb.clearContents()
            pb.setString("secret-password", forType: .string)
            pb.setData(Data(), forType: NSPasteboard.PasteboardType(type))
            m.poll()
        }
        XCTAssertTrue(got().isEmpty, "密码管理器标记的内容不应被记录")
    }

    @MainActor
    func testIgnoredAppsSkipped() {
        let pb = makePasteboard(self)
        let (m, got) = makeMonitor(pb, bundleID: "com.1password.1password")
        pb.clearContents(); pb.setString("from 1password", forType: .string)
        m.poll()
        XCTAssertTrue(got().isEmpty)

        let custom = Preferences.parseBundleIDs("com.example.a, com.example.secret\n")
        let (m2, got2) = makeMonitor(pb, bundleID: "com.example.secret")
        m2.ignoredBundleIDs = { custom }
        pb.clearContents(); pb.setString("x", forType: .string)
        m2.poll()
        XCTAssertTrue(got2().isEmpty)
        let (m3, got3) = makeMonitor(pb, bundleID: "com.1password.1password")
        m3.ignoredBundleIDs = { custom }
        pb.clearContents(); pb.setString("y", forType: .string)
        m3.poll()
        XCTAssertEqual(got3().count, 1, "自定义列表替换默认列表后，1Password 不再被忽略")
    }

    @MainActor
    func testPausedSkipsButResumes() {
        let pb = makePasteboard(self)
        let (m, got) = makeMonitor(pb)
        var paused = true
        m.isPaused = { paused }
        pb.clearContents(); pb.setString("while paused", forType: .string)
        m.poll()
        XCTAssertTrue(got().isEmpty)

        paused = false
        m.poll()
        XCTAssertTrue(got().isEmpty, "暂停期间的内容恢复后也不补记")
        pb.clearContents(); pb.setString("after", forType: .string)
        m.poll()
        XCTAssertEqual(got().map(\.text), ["after"])
    }

    @MainActor
    func testOwnWriteNotRecorded() {
        let pb = makePasteboard(self)
        let (m, got) = makeMonitor(pb)
        pb.clearContents(); pb.setString("written by CopyT", forType: .string)
        m.markOwnWrite()
        m.poll()
        XCTAssertTrue(got().isEmpty)
    }

    @MainActor
    func testManyFilesAllCaptured() throws {
        let dir = try makeTempDir(self)
        let urls = (1...12).map { dir.appendingPathComponent("文件 \($0).txt") }
        for u in urls { try "x".write(to: u, atomically: true, encoding: .utf8) }
        let pb = makePasteboard(self)
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        XCTAssertEqual(ClipboardMonitor.fileURLs(pb).count, 12)
        let c = try XCTUnwrap(capture(pb))
        XCTAssertEqual(c.text?.split(separator: "\n").count, 12)
    }

    @MainActor
    func testSettleDelayWaitsForWriterToFinish() {
        let pb = makePasteboard(self)
        let (m, got) = makeMonitor(pb)
        m.settleDelay = 0.2
        pb.clearContents()
        m.poll() // 只看到 clearContents，内容还没写入
        pb.setString("complete content", forType: .string) // 同一个 changeCount 内写完
        let exp = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(got().map(\.text), ["complete content"])
    }

    @MainActor
    func testSettleDelayDropsSupersededChange() {
        let pb = makePasteboard(self)
        let (m, got) = makeMonitor(pb)
        m.settleDelay = 0.2
        pb.clearContents(); pb.setString("old", forType: .string)
        m.poll()
        pb.clearContents(); pb.setString("new", forType: .string)
        let exp = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { m.poll() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(got().map(\.text), ["new"], "被覆盖的中间状态不记录，只记录最终内容")
    }

    @MainActor
    func testConcealedMarkerOnSecondItemStillSkipped() {
        let pb = makePasteboard(self)
        let (m, got) = makeMonitor(pb)
        pb.clearContents()
        let a = NSPasteboardItem(); a.setString("visible", forType: .string)
        let b = NSPasteboardItem(); b.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pb.writeObjects([a, b])
        m.poll()
        XCTAssertTrue(got().isEmpty)
    }

    @MainActor
    func testTimerDrivenCapture() {
        let pb = makePasteboard(self)
        let (m, got) = makeMonitor(pb)
        m.settleDelay = 0.15
        m.start(interval: 0.05)
        defer { m.stop() }
        pb.clearContents(); pb.setString("timer", forType: .string)
        let exp = expectation(description: "captured")
        func check() {
            if !got().isEmpty { exp.fulfill() } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { check() }
            }
        }
        check()
        wait(for: [exp], timeout: 3)
        XCTAssertEqual(got().map(\.text), ["timer"])
    }

    // MARK: - 写回后再读取，内容一致

    @MainActor
    func testRoundTripThroughPasteboard() throws {
        let root = try makeTempDir(self)
        let store = ClipStore(rootURL: root)
        store.persistsStorageLocation = false
        let pb = makePasteboard(self)
        store.pasteboard = pb
        let png = makePNG()
        for c in [Captures.text("rt text"), Captures.rich("rt rich"), Captures.image(png), Captures.files(["/tmp/rt-file"])] {
            store.add(c)
        }
        for item in store.items {
            XCTAssertTrue(PasteboardWriter.write(item, root: root, to: pb), "\(item.kind)")
            let back = try XCTUnwrap(capture(pb), "\(item.kind)")
            XCTAssertEqual(back.kind, item.kind)
            XCTAssertEqual(back.hash, item.hash, "\(item.kind) 写回后再次复制应被识别为同一条")
        }
    }
}
