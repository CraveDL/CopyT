import SwiftUI

struct ClipDetailView: View {
    let item: ClipItem
    @EnvironmentObject private var store: ClipStore
    @EnvironmentObject private var ui: HistoryState

    private var copied: Bool { ui.copiedID == item.id }

    private static let maxDisplayChars = 100_000

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(item.kind.label, systemImage: item.kind.symbol)
                .font(.headline)
            Spacer()
            Button {
                store.copy(item)
                ui.copiedID = item.id
            } label: {
                Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .help("复制到剪贴板（⌘↩）")

            Button { store.togglePin(item) } label: {
                Image(systemName: item.pinned ? "star.fill" : "star")
            }
            .help(item.pinned ? "取消收藏" : "收藏（收藏的记录不会被自动清理）")

            if item.kind != .text {
                Button { store.reveal(item) } label: { Image(systemName: "folder") }
                    .help("在访达中显示")
            }

            Button(role: .destructive) { store.delete([item]) } label: { Image(systemName: "trash") }
                .help("删除")
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            textView(Text(displayText).font(.system(.body, design: .monospaced)))
        case .richText:
            if let attributed = attributedText {
                textView(Text(attributed))
            } else {
                textView(Text(displayText))
            }
        case .image:
            if let url = store.fileURL(for: item), let image = NSImage(contentsOf: url) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: min(image.size.width, 1600))
                        .padding()
                }
            } else {
                missing("图片文件不存在")
            }
        case .file:
            List(item.filePaths, id: \.self) { path in
                FileRow(path: path)
            }
        }
    }

    private func textView(_ text: Text) -> some View {
        ScrollView {
            text
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding()
        }
    }

    private var displayText: String {
        let t = item.text ?? ""
        guard t.count > Self.maxDisplayChars else { return t }
        return String(t.prefix(Self.maxDisplayChars)) + "\n\n…（内容过长，仅显示前 \(Self.maxDisplayChars) 个字符，复制可获得完整内容）"
    }

    private var attributedText: AttributedString? {
        guard let url = store.fileURL(for: item), url.pathExtension == "rtf",
              let data = try? Data(contentsOf: url), data.count < 2_000_000,
              let ns = NSAttributedString(rtf: data, documentAttributes: nil) else { return nil }
        return try? AttributedString(ns, including: \.appKit)
    }

    private func missing(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Label(item.createdAt.formatted(date: .abbreviated, time: .standard), systemImage: "clock")
            if let app = item.sourceApp {
                Label(app, systemImage: "app")
            }
            Spacer()
            Text(sizeText)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var sizeText: String {
        switch item.kind {
        case .text, .richText:
            return "\(item.text?.count ?? 0) 字符"
        case .image:
            var s = ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file)
            if let url = store.fileURL(for: item), let size = ThumbnailCache.shared.imageSize(for: url) {
                s = "\(Int(size.width))×\(Int(size.height)) · " + s
            }
            return s
        case .file:
            return "\(item.filePaths.count) 个文件"
        }
    }
}

private struct FileRow: View {
    let path: String

    var body: some View {
        let exists = FileManager.default.fileExists(atPath: path)
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text((path as NSString).lastPathComponent)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if !exists {
                Label("已移动或删除", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("在访达中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            .disabled(!exists)
            Button("拷贝路径") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
        }
    }
}
