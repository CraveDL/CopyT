import SwiftUI

/// 点击菜单栏图标弹出的快速面板
struct MenuPopoverView: View {
    @EnvironmentObject private var store: ClipStore
    @AppStorage(Preferences.Key.paused) private var paused = false
    @EnvironmentObject private var ui: PopoverState
    @FocusState private var searchFocused: Bool

    var onClose: () -> Void
    var onOpenHistory: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索剪贴板历史", text: $ui.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { if let first = ui.results.first { pick(first) } }
                if !ui.query.isEmpty {
                    Button { ui.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)

            Divider()

            if ui.results.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard").font(.largeTitle).foregroundStyle(.tertiary)
                    Text(ui.query.isEmpty ? "还没有记录，复制点什么试试" : "没有匹配的记录")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(ui.results) { item in
                            HoverRow(hovering: ui.hoveredID == item.id,
                                     onHover: { inside in
                                         if inside { ui.hoveredID = item.id }
                                         else if ui.hoveredID == item.id { ui.hoveredID = nil }
                                     }) {
                                ClipRowView(item: item, compact: true)
                            }
                                .onTapGesture { pick(item) }
                                .contextMenu {
                                    Button("复制") { pick(item) }
                                    Button(item.pinned ? "取消收藏" : "收藏") { store.togglePin(item) }
                                    Divider()
                                    Button("删除", role: .destructive) { store.delete([item]) }
                                }
                        }
                    }
                    .padding(6)
                }
            }

            Divider()

            HStack(spacing: 12) {
                Toggle(isOn: $paused) { Text("暂停记录").font(.caption) }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                Spacer()
                Button(action: onOpenHistory) { Image(systemName: "clock.arrow.circlepath") }
                    .help("历史记录（\(HotKeyManager.displayString)）")
                Button(action: onOpenSettings) { Image(systemName: "gearshape") }
                    .help("设置")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("退出 CopyT")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: 380, height: 480)
        .onAppear {
            reload()
            searchFocused = true
        }
        .onChange(of: ui.query) { _ in reload() }
        .onReceive(store.$revision) { _ in reload() }
    }

    private func reload() {
        ui.results = store.quickSearch(ui.query, limit: 60)
    }

    private func pick(_ item: ClipItem) {
        store.copy(item)
        onClose()
    }
}
