import AppKit
import XCTest
@testable import CopyT

/// 每个测试一个独立的临时目录，测试结束自动删除
func makeTempDir(_ test: XCTestCase, _ name: String = "root") throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("CopyTTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    test.addTeardownBlock { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    return url
}

/// 独立的私有剪贴板，不影响系统剪贴板
func makePasteboard(_ test: XCTestCase) -> NSPasteboard {
    let pb = NSPasteboard(name: NSPasteboard.Name("io.github.cravedl.copyt.test.\(UUID().uuidString)"))
    test.addTeardownBlock { pb.releaseGlobally() }
    return pb
}

/// 生成一张小 PNG
func makePNG(width: Int = 4, height: Int = 3, color: NSColor = .systemRed) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    color.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func makeRTF(_ text: String) -> Data {
    let attr = NSAttributedString(string: text, attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
    return try! attr.data(from: NSRange(location: 0, length: attr.length),
                          documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
}

@MainActor
enum Captures {
    static func text(_ s: String, app: String? = "TestApp") -> Capture {
        Capture(kind: .text, text: s, data: nil, fileExtension: nil, sourceApp: app,
                hash: ClipboardMonitor.sha256("text", Data(s.utf8)), byteSize: s.utf8.count)
    }

    static func rich(_ s: String) -> Capture {
        let rtf = makeRTF(s)
        return Capture(kind: .richText, text: s, data: rtf, fileExtension: "rtf", sourceApp: "TextEdit",
                       hash: ClipboardMonitor.sha256("text", Data(s.utf8)), byteSize: rtf.count)
    }

    static func image(_ png: Data = makePNG()) -> Capture {
        Capture(kind: .image, text: nil, data: png, fileExtension: "png", sourceApp: "Preview",
                hash: ClipboardMonitor.sha256("image", png), byteSize: png.count)
    }

    static func files(_ paths: [String]) -> Capture {
        let text = paths.joined(separator: "\n")
        return Capture(kind: .file, text: text, data: nil, fileExtension: nil, sourceApp: "Finder",
                       hash: ClipboardMonitor.sha256("file", Data(text.utf8)), byteSize: 0)
    }
}

func date(_ s: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f.date(from: s)!
}
