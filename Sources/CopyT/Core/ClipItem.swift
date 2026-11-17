import Foundation
import UniformTypeIdentifiers

/// 剪贴板记录的类型
enum ClipKind: String, CaseIterable, Identifiable {
    case text
    case richText
    case image
    case file

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: return "文本"
        case .richText: return "富文本"
        case .image: return "图片"
        case .file: return "文件"
        }
    }

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .richText: return "textformat"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
}

/// 一条剪贴板记录
struct ClipItem: Identifiable, Hashable {
    let id: Int64
    var kind: ClipKind
    /// 纯文本内容；文件类型时为换行分隔的文件路径
    var text: String?
    /// 存储目录下的相对路径（图片 / 富文本数据）
    var dataPath: String?
    var sourceApp: String?
    var createdAt: Date
    /// yyyy-MM-dd，用于按日期归档
    var day: String
    var hash: String
    var byteSize: Int
    var pinned: Bool

    var filePaths: [String] {
        guard kind == .file, let text else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    /// 列表中显示的标题
    var previewTitle: String {
        switch kind {
        case .text, .richText:
            // 只看开头一段，避免超长文本拖慢列表
            let head = (text ?? "").prefix(2000)
            let firstLines = head.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .prefix(2)
                .joined(separator: " ")
            return firstLines.count > 200 ? String(firstLines.prefix(200)) + "…" : firstLines
        case .image:
            return "图片 · " + ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
        case .file:
            let paths = filePaths
            let names = paths.prefix(3).map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            return paths.count > 3 ? "\(names) 等 \(paths.count) 个文件" : names
        }
    }
}

/// 来自剪贴板、尚未入库的一次捕获
struct Capture {
    var kind: ClipKind
    var text: String?
    var data: Data?
    var fileExtension: String?
    var sourceApp: String?
    var hash: String
    var byteSize: Int
}

struct DayCount: Identifiable, Hashable {
    var day: String
    var count: Int
    var id: String { day }

    var displayName: String {
        guard let date = DayFormatter.date(from: day) else { return day }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        return DayFormatter.display.string(from: date)
    }
}

enum DayFormatter {
    static let key: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let display: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 EEE"
        return f
    }()

    static let folder: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy/MM/dd"
        return f
    }()

    static func string(_ date: Date) -> String { key.string(from: date) }
    static func date(from day: String) -> Date? { key.date(from: day) }
}

extension String {
    var isImageFilePath: Bool {
        let ext = (self as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image)
    }
}
