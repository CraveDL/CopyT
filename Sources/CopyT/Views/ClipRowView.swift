import SwiftUI

struct ClipThumbnail: View {
    let item: ClipItem
    var size: CGFloat = 36
    @EnvironmentObject private var store: ClipStore

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.1)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var image: NSImage? {
        switch item.kind {
        case .image:
            return store.fileURL(for: item).flatMap { ThumbnailCache.shared.thumbnail(for: $0) }
        case .file:
            guard let first = item.filePaths.first else { return nil }
            if first.isImageFilePath, FileManager.default.fileExists(atPath: first) {
                return ThumbnailCache.shared.thumbnail(for: URL(fileURLWithPath: first))
            }
            return NSWorkspace.shared.icon(forFile: first)
        default:
            return nil
        }
    }
}

struct ClipRowView: View {
    let item: ClipItem
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            ClipThumbnail(item: item, size: compact ? 30 : 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.previewTitle.isEmpty ? "（空白）" : item.previewTitle)
                    .lineLimit(compact ? 1 : 2)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    Text(item.kind.label)
                    if let app = item.sourceApp { Text("· \(app)") }
                    Text("· \(Self.timeText(item.createdAt))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.pinned {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 2)
    }

    static func timeText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month().day().hour().minute())
    }
}

/// 鼠标悬停高亮的行（用于菜单栏弹窗）
struct HoverRow<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? Color.accentColor.opacity(0.18) : .clear)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
