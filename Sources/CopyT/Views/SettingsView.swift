import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ClipStore

    @AppStorage(Preferences.Key.retentionDays) private var retentionDays = 0
    @AppStorage(Preferences.Key.maxImageMB) private var maxImageMB = 20
    @AppStorage(Preferences.Key.ignoredApps) private var ignoredApps = Preferences.defaultIgnoredApps
    @AppStorage(Preferences.Key.hotKeyEnabled) private var hotKeyEnabled = true

    @EnvironmentObject private var ui: SettingsState

    var body: some View {
        Form {
            Section {
                LabeledContent("位置") {
                    Text(store.rootURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(store.rootURL.path)
                }
                LabeledContent("占用空间") {
                    Text(ui.storageSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "计算中…")
                        .monospacedDigit()
                }
                Toggle("更改位置时移动现有数据", isOn: $ui.moveExisting)
                HStack {
                    Button("更改位置…", action: chooseLocation)
                    Button("在访达中打开") { NSWorkspace.shared.open(store.rootURL) }
                    Button("恢复默认位置") { changeLocation(to: Preferences.defaultStorageURL) }
                        .disabled(store.rootURL.standardizedFileURL.path == Preferences.defaultStorageURL.standardizedFileURL.path)
                }
            } header: {
                Text("存储")
            } footer: {
                Text("数据库为 copyt.sqlite，图片与富文本按日期保存在 media/年/月/日/ 下。可放在 iCloud Drive 或外置硬盘中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("记录") {
                Picker("保留时长", selection: $retentionDays) {
                    Text("永久").tag(0)
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                    Text("90 天").tag(90)
                    Text("1 年").tag(365)
                }
                Stepper(value: $maxImageMB, in: 1...200) {
                    LabeledContent("单张图片上限", value: "\(maxImageMB) MB")
                }
                Text("超过保留时长的记录会自动删除，收藏的记录永远保留。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextEditor(text: $ignoredApps)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80)
                Button("添加最近使用的应用…", action: addFrontmostApp)
            } header: {
                Text("隐私：不记录以下应用（每行一个 Bundle ID）")
            } footer: {
                Text("另外，密码管理器标记为“隐藏”的内容（org.nspasteboard.ConcealedType）始终不会被记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("通用") {
                Toggle("登录时自动启动", isOn: $ui.launchAtLogin)
                    .onChange(of: ui.launchAtLogin) { on in
                        do { try LaunchAtLogin.set(on) } catch {
                            ui.message = "设置开机启动失败：\(error.localizedDescription)\n请确认 CopyT.app 位于“应用程序”文件夹中。"
                            ui.launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                Toggle("全局快捷键 \(HotKeyManager.displayString) 打开历史记录", isOn: $hotKeyEnabled)
            }

            Section("维护") {
                HStack {
                    Button("立即清理过期记录") {
                        store.cleanupExpired()
                        refreshSize()
                    }
                    .disabled(retentionDays == 0)
                    Spacer()
                    Button("清空历史（保留收藏）…", role: .destructive) { ui.confirmClear = true }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 640)
        .task { refreshSize() }
        .onChange(of: retentionDays) { _ in store.cleanupExpired() }
        .confirmationDialog("确定清空所有未收藏的记录吗？", isPresented: $ui.confirmClear) {
            Button("清空", role: .destructive) {
                store.clearUnpinned()
                refreshSize()
            }
        } message: {
            Text("此操作无法撤销，对应的图片文件也会被删除。")
        }
        .alert("提示", isPresented: Binding(get: { ui.message != nil }, set: { if !$0 { ui.message = nil } })) {
            Button("好") {}
        } message: {
            Text(ui.message ?? "")
        }
    }

    private func refreshSize() {
        let url = store.rootURL
        let ui = self.ui
        ui.storageSize = nil
        Task.detached(priority: .utility) {
            let size = ClipStore.directorySize(url)
            await MainActor.run { ui.storageSize = size }
        }
    }

    private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "选择 CopyT 的数据存放位置"
        panel.directoryURL = store.rootURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        changeLocation(to: url)
    }

    private func changeLocation(to url: URL) {
        do {
            switch try store.changeStorage(to: url, moveExisting: ui.moveExisting) {
            case .moved: ui.message = "已将数据移动到新位置。"
            case .switchedToExisting: ui.message = "新位置已有 CopyT 资料库，已切换为使用该资料库（原位置的数据保持不变）。"
            case .switchedToEmpty: ui.message = "已切换到新位置（原位置的数据保持不变）。"
            case .unchanged: break
            }
        } catch {
            ui.message = "更改位置失败：\(error.localizedDescription)"
        }
        refreshSize()
    }

    private func addFrontmostApp() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
        let menu = NSMenu()
        for app in apps.sorted(by: { ($0.localizedName ?? "") < ($1.localizedName ?? "") }) {
            guard let bid = app.bundleIdentifier else { continue }
            let item = NSMenuItem(title: "\(app.localizedName ?? bid)  (\(bid))", action: nil, keyEquivalent: "")
            item.image = app.icon.map { icon in
                let copy = icon.copy() as! NSImage
                copy.size = NSSize(width: 16, height: 16)
                return copy
            }
            item.representedObject = bid
            menu.addItem(item)
        }
        let handler = MenuActionHandler { bid in
            var lines = ignoredApps.split(separator: "\n").map(String.init)
            if !lines.contains(bid) { lines.append(bid) }
            ignoredApps = lines.joined(separator: "\n")
        }
        menu.items.forEach { $0.target = handler; $0.action = #selector(MenuActionHandler.pick(_:)) }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        _ = handler // 菜单是同步弹出的，期间保持 handler 存活
    }
}

/// NSMenu 选择回调
private final class MenuActionHandler: NSObject {
    let onPick: (String) -> Void
    init(_ onPick: @escaping (String) -> Void) { self.onPick = onPick }
    @objc func pick(_ sender: NSMenuItem) {
        if let bid = sender.representedObject as? String { onPick(bid) }
    }
}
