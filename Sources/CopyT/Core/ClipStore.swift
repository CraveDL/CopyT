import AppKit
import Combine

enum Scope: Hashable {
    case all
    case pinned
    case day(String)
}

/// 历史记录的读写中心：数据库 + 媒体文件 + 当前筛选状态
@MainActor
final class ClipStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var dayCounts: [DayCount] = []
    @Published private(set) var totalCount = 0
    @Published private(set) var rootURL: URL
    /// 每次数据变化 +1，供其他视图刷新
    @Published private(set) var revision = 0
    @Published var lastError: String?

    @Published var scope: Scope? = .all { didSet { reload() } }
    @Published var kindFilter: ClipKind? { didSet { reload() } }
    @Published var searchText = ""

    /// 自己写剪贴板后通知监视器跳过
    var onOwnPasteboardWrite: (() -> Void)?

    private var db: Database?
    private var cancellables = Set<AnyCancellable>()
    private let listLimit = 3000

    /// 写回剪贴板的目标（测试时替换为私有剪贴板）
    var pasteboard: NSPasteboard = .general
    /// 更改存储位置后是否写入用户设置（测试时关闭）
    var persistsStorageLocation = true

    init(rootURL: URL = Preferences.storageURL) {
        self.rootURL = rootURL
        openDatabase()
        $searchText
            .removeDuplicates()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
        reload()
    }

    // MARK: - 数据库

    private var mediaRoot: URL { rootURL.appendingPathComponent("media", isDirectory: true) }

    private func openDatabase() {
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            db = try Database(url: rootURL.appendingPathComponent(Database.fileName))
        } catch {
            db = nil
            lastError = error.localizedDescription
        }
    }

    func reload() {
        guard let db else {
            items = []; dayCounts = []; totalCount = 0
            return
        }
        var f = ClipFilter()
        f.search = searchText
        f.kind = kindFilter
        switch scope ?? .all {
        case .all: break
        case .pinned: f.pinnedOnly = true
        case .day(let d): f.day = d
        }
        do {
            items = try db.items(f, limit: listLimit)
            dayCounts = try db.dayCounts()
            totalCount = try db.totalCount()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 菜单栏弹窗用的快速查询（不影响历史窗口的筛选状态）
    func quickSearch(_ text: String, limit: Int = 50) -> [ClipItem] {
        guard let db else { return [] }
        var f = ClipFilter()
        f.search = text
        return (try? db.items(f, limit: limit)) ?? []
    }

    private func changed() {
        revision += 1
        reload()
    }

    // MARK: - 写入

    func add(_ capture: Capture, at now: Date = Date()) {
        guard let db else { return }
        do {
            if let existing = try db.item(withHash: capture.hash) {
                try db.touch(id: existing.id, date: now, sourceApp: capture.sourceApp)
            } else {
                var relPath: String?
                if let data = capture.data, let ext = capture.fileExtension {
                    relPath = try writeMedia(data, ext: ext, date: now)
                }
                try db.insert(capture, dataPath: relPath, date: now)
            }
            changed()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 媒体文件按日期归档：media/2026/11/17/<uuid>.png
    private func writeMedia(_ data: Data, ext: String, date: Date) throws -> String {
        let rel = "media/\(DayFormatter.folder.string(from: date))/\(UUID().uuidString).\(ext)"
        let url = rootURL.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return rel
    }

    func fileURL(for item: ClipItem) -> URL? {
        item.dataPath.map { rootURL.appendingPathComponent($0) }
    }

    // MARK: - 操作

    func copy(_ item: ClipItem) {
        guard PasteboardWriter.write(item, root: rootURL, to: pasteboard) else {
            lastError = "无法复制：原始数据或文件已不存在"
            return
        }
        onOwnPasteboardWrite?()
        try? db?.touch(id: item.id, date: Date(), sourceApp: nil)
        changed()
    }

    func togglePin(_ item: ClipItem) {
        try? db?.setPinned(id: item.id, !item.pinned)
        changed()
    }

    func delete(_ items: [ClipItem]) {
        guard let db else { return }
        for item in items {
            try? db.delete(id: item.id)
            removeMedia(of: item)
        }
        changed()
    }

    func reveal(_ item: ClipItem) {
        if item.kind == .file {
            let urls = item.filePaths.map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        } else if let url = fileURL(for: item) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func removeMedia(of item: ClipItem) {
        guard let url = fileURL(for: item) else { return }
        try? FileManager.default.removeItem(at: url)
        // 清理空的日期目录
        var dir = url.deletingLastPathComponent()
        while dir.path.hasPrefix(mediaRoot.path), dir.path != mediaRoot.path {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? ["x"]
            guard contents.filter({ $0 != ".DS_Store" }).isEmpty else { break }
            try? FileManager.default.removeItem(at: dir)
            dir = dir.deletingLastPathComponent()
        }
    }

    // MARK: - 清理

    /// 按"保留时长"删除过期且未收藏的记录
    func cleanupExpired(retentionDays days: Int = Preferences.retentionDays, now: Date = Date()) {
        guard days > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        purgeUnpinned(before: cutoff)
    }

    /// 清空所有未收藏的记录
    func clearUnpinned() {
        purgeUnpinned(before: nil)
    }

    private func purgeUnpinned(before date: Date?) {
        guard let db else { return }
        do {
            let victims = try db.unpinnedItems(before: date)
            guard !victims.isEmpty else { return }
            try db.deleteUnpinned(before: date)
            for item in victims { removeMedia(of: item) }
            changed()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - 更改存放位置

    enum StorageChangeResult {
        case moved, switchedToExisting, switchedToEmpty, unchanged
    }

    /// 更改存储目录。
    /// - moveExisting: 是否把现有数据库和媒体文件移动到新目录
    /// - 若新目录里已有 CopyT 资料库，直接切换过去使用（不覆盖）
    @discardableResult
    func changeStorage(to newRoot: URL, moveExisting: Bool) throws -> StorageChangeResult {
        let fm = FileManager.default
        let oldRoot = rootURL.standardizedFileURL
        let newRoot = newRoot.standardizedFileURL
        guard newRoot.path != oldRoot.path else { return .unchanged }
        if newRoot.path.hasPrefix(oldRoot.path + "/") {
            throw StorageError.nested
        }

        try fm.createDirectory(at: newRoot, withIntermediateDirectories: true)
        let targetHasLibrary = fm.fileExists(atPath: newRoot.appendingPathComponent(Database.fileName).path)

        let names = [Database.fileName, Database.fileName + "-wal", Database.fileName + "-shm", "media"]
        if moveExisting && !targetHasLibrary {
            // 移动前先检查冲突，避免移动到一半失败
            if fm.fileExists(atPath: newRoot.appendingPathComponent("media").path) {
                throw StorageError.conflict(newRoot.appendingPathComponent("media").path)
            }
        }

        db?.checkpoint()
        db?.close()
        db = nil

        var result: StorageChangeResult = targetHasLibrary ? .switchedToExisting : .switchedToEmpty
        do {
            if moveExisting && !targetHasLibrary {
                for name in names {
                    let src = oldRoot.appendingPathComponent(name)
                    guard fm.fileExists(atPath: src.path) else { continue }
                    try fm.moveItem(at: src, to: newRoot.appendingPathComponent(name))
                }
                result = .moved
            }
        } catch {
            // 移动失败：回到旧目录
            openDatabase()
            changed()
            throw error
        }

        rootURL = newRoot
        if persistsStorageLocation { Preferences.storageURL = newRoot }
        openDatabase()
        changed()
        return result
    }

    enum StorageError: LocalizedError {
        case nested
        case conflict(String)
        var errorDescription: String? {
            switch self {
            case .nested: return "新位置不能位于当前存储目录内部。"
            case .conflict(let p): return "目标位置已存在同名文件夹：\(p)"
            }
        }
    }

    /// 存储目录占用空间
    nonisolated static func directorySize(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in e {
            let v = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            total += Int64(v?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
