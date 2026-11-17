import SwiftUI
import UniformTypeIdentifiers

/// 历史记录主窗口：侧边栏（全部 / 收藏 / 按日期） + 列表 + 详情
struct HistoryView: View {
    @EnvironmentObject private var store: ClipStore
    @State private var selection = Set<ClipItem.ID>()
    @State private var exportMessage: String?

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } content: {
            itemList
                .navigationSplitViewColumnWidth(min: 280, ideal: 360)
        } detail: {
            if let item = singleSelection {
                ClipDetailView(item: item)
            } else if selection.count > 1 {
                placeholder("已选择 \(selection.count) 条记录", symbol: "square.stack")
            } else {
                placeholder("选择一条记录查看详情\n双击即可复制", symbol: "doc.on.clipboard")
            }
        }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "搜索文本、文件路径、来源应用")
        .toolbar {
            ToolbarItem {
                Picker("类型", selection: $store.kindFilter) {
                    Text("全部类型").tag(ClipKind?.none)
                    Divider()
                    ForEach(ClipKind.allCases) { kind in
                        Label(kind.label, systemImage: kind.symbol).tag(ClipKind?.some(kind))
                    }
                }
                .pickerStyle(.menu)
                .help("按类型筛选")
            }
            ToolbarItem {
                Button(action: exportCurrent) {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .help("把当前列表导出为 Markdown（图片一并导出）")
                .disabled(store.items.isEmpty)
            }
        }
        .frame(minWidth: 820, minHeight: 480)
        .alert("提示", isPresented: Binding(get: { exportMessage != nil || store.lastError != nil },
                                          set: { if !$0 { exportMessage = nil; store.lastError = nil } })) {
            Button("好") {}
        } message: {
            Text(exportMessage ?? store.lastError ?? "")
        }
        .onChange(of: store.items) { items in
            let ids = Set(items.map(\.id))
            selection = selection.intersection(ids)
        }
    }

    private var itemList: some View {
        List(selection: $selection) {
            ForEach(store.items) { item in
                ClipRowView(item: item)
            }
        }
        .contextMenu(forSelectionType: ClipItem.ID.self) { ids in
            let items = store.items.filter { ids.contains($0.id) }
            if items.count == 1, let item = items.first {
                Button("复制") { store.copy(item) }
                Button(item.pinned ? "取消收藏" : "收藏") { store.togglePin(item) }
                if item.kind != .text {
                    Button("在访达中显示") { store.reveal(item) }
                }
                Divider()
            }
            if !items.isEmpty {
                Button(items.count > 1 ? "删除 \(items.count) 条记录" : "删除", role: .destructive) {
                    store.delete(items)
                }
            }
        } primaryAction: { ids in
            if ids.count == 1, let item = store.items.first(where: { ids.contains($0.id) }) {
                store.copy(item)
            }
        }
        .onDeleteCommand {
            store.delete(store.items.filter { selection.contains($0.id) })
        }
        .overlay {
            if store.items.isEmpty {
                placeholder(store.searchText.isEmpty ? "这里还没有记录" : "没有匹配的记录", symbol: "tray")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("\(store.items.count) 条").monospacedDigit()
                Spacer()
                Text("共 \(store.totalCount) 条记录").monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    private var singleSelection: ClipItem? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return store.items.first { $0.id == id }
    }

    private func placeholder(_ text: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 36)).foregroundStyle(.tertiary)
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func exportCurrent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "导出到这里"
        panel.message = "选择导出文件夹（将导出当前列表中的 \(store.items.count) 条记录）"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            let dir = try Exporter.export(store.items, root: store.rootURL, to: folder)
            NSWorkspace.shared.activateFileViewerSelecting([dir])
        } catch {
            exportMessage = "导出失败：\(error.localizedDescription)"
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var store: ClipStore

    var body: some View {
        List(selection: $store.scope) {
            Section("资料库") {
                Label("全部记录", systemImage: "tray.full").tag(Scope.all)
                Label("收藏", systemImage: "star").tag(Scope.pinned)
            }
            Section("按日期") {
                ForEach(store.dayCounts) { dc in
                    HStack {
                        Label(dc.displayName, systemImage: "calendar")
                        Spacer()
                        Text("\(dc.count)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .tag(Scope.day(dc.day))
                }
            }
        }
        .listStyle(.sidebar)
    }
}
