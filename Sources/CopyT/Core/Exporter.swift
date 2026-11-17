import Foundation

/// 把一组记录导出为 Markdown + 附件文件夹
enum Exporter {
    static func export(_ items: [ClipItem], root: URL, to folder: URL) throws -> URL {
        let fm = FileManager.default
        let stamp: String = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd-HHmmss"
            return f.string(from: Date())
        }()
        let dir = folder.appendingPathComponent("CopyT导出-\(stamp)", isDirectory: true)
        let assets = dir.appendingPathComponent("assets", isDirectory: true)
        try fm.createDirectory(at: assets, withIntermediateDirectories: true)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        var md = "# CopyT 剪贴板导出\n\n共 \(items.count) 条记录\n\n"
        let grouped = Dictionary(grouping: items, by: \.day)
        for day in grouped.keys.sorted(by: >) {
            let dayItems = (grouped[day] ?? []).sorted { $0.createdAt > $1.createdAt }
            md += "## \(DayCount(day: day, count: dayItems.count).displayName)（\(day)）\n\n"
            for item in dayItems {
                var meta = [timeFormatter.string(from: item.createdAt), item.kind.label]
                if let app = item.sourceApp { meta.append(app) }
                if item.pinned { meta.append("⭐️") }
                md += "### \(meta.joined(separator: " · "))\n\n"

                switch item.kind {
                case .text, .richText:
                    md += "````text\n\(item.text ?? "")\n````\n\n"
                case .image:
                    if let rel = item.dataPath {
                        let src = root.appendingPathComponent(rel)
                        let name = "\(item.day)-\(item.id).\(src.pathExtension)"
                        if (try? fm.copyItem(at: src, to: assets.appendingPathComponent(name))) != nil {
                            md += "![图片](assets/\(name))\n\n"
                        } else {
                            md += "_（图片文件丢失）_\n\n"
                        }
                    }
                case .file:
                    md += item.filePaths.map { "- `\($0)`" }.joined(separator: "\n") + "\n\n"
                }
            }
        }
        try md.write(to: dir.appendingPathComponent("记录.md"), atomically: true, encoding: .utf8)
        return dir
    }
}
