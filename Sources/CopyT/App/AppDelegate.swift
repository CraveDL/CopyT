import AppKit
import SwiftUI

@main
enum CopyTMain {
    @MainActor
    static func main() {
        Preferences.registerDefaults()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // 只在菜单栏显示
        app.run()
        _ = delegate
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = ClipStore()
    let monitor = ClipboardMonitor()
    private let historyState = HistoryState()
    private let settingsState = SettingsState()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var maintenanceTimer: Timer?
    private var lastPaused: Bool?
    private var lastHotKey: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()

        monitor.onCapture = { [weak self] capture in self?.store.add(capture) }
        store.onOwnPasteboardWrite = { [weak self] in self?.monitor.markOwnWrite() }
        monitor.start()

        store.cleanupExpired()
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.cleanupExpired() }
        }

        HotKeyManager.shared.action = { [weak self] in self?.toggleHistory() }
        applyPreferences()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applyPreferences() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showHistory()
        return true
    }

    /// 设置变化时更新快捷键与菜单栏图标
    private func applyPreferences() {
        let hotKey = Preferences.hotKeyEnabled
        if hotKey != lastHotKey {
            HotKeyManager.shared.setEnabled(hotKey)
            lastHotKey = hotKey
        }
        let paused = Preferences.paused
        if paused != lastPaused {
            statusItem.button?.image = NSImage(
                systemSymbolName: paused ? "pause.circle" : "doc.on.clipboard",
                accessibilityDescription: "CopyT")
            statusItem.button?.toolTip = paused ? "CopyT（已暂停记录）" : "CopyT 剪贴板历史"
            lastPaused = paused
        }
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "CopyT")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient
        popover.animates = false
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        let root = MenuPopoverView(
            onClose: { [weak self] in self?.popover.performClose(nil) },
            onOpenHistory: { [weak self] in self?.showHistory() },
            onOpenSettings: { [weak self] in self?.showSettings() }
        )
        .environmentObject(store)
        .environmentObject(PopoverState())
        popover.contentViewController = NSHostingController(rootView: root)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开历史记录", action: #selector(showHistoryAction), keyEquivalent: "")
        let pause = menu.addItem(withTitle: "暂停记录", action: #selector(togglePause), keyEquivalent: "")
        pause.state = Preferences.paused ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(showSettingsAction), keyEquivalent: "")
        menu.addItem(withTitle: "退出 CopyT", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.items.filter { $0.action != #selector(NSApplication.terminate(_:)) }.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func togglePause() {
        UserDefaults.standard.set(!Preferences.paused, forKey: Preferences.Key.paused)
    }

    @objc private func showHistoryAction() { showHistory() }
    @objc private func showSettingsAction() { showSettings() }

    // MARK: - 窗口

    private func toggleHistory() {
        if let w = historyWindow, w.isVisible, w.isKeyWindow, NSApp.isActive {
            w.close()
        } else {
            showHistory()
        }
    }

    func showHistory() {
        popover.performClose(nil)
        if historyWindow == nil {
            let host = NSHostingController(rootView: HistoryView().environmentObject(store).environmentObject(historyState))
            host.sizingOptions = []
            let w = NSWindow(contentViewController: host)
            w.title = "CopyT 剪贴板历史"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.toolbarStyle = .unified
            w.setContentSize(NSSize(width: 1000, height: 640))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            w.setFrameAutosaveName("CopyTHistoryWindow")
            historyWindow = w
        }
        present(historyWindow)
    }

    @objc func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView().environmentObject(store).environmentObject(settingsState))
            let w = NSWindow(contentViewController: host)
            w.title = "CopyT 设置"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            settingsWindow = w
        }
        present(settingsWindow)
    }

    /// 打开窗口时临时显示 Dock 图标，便于 ⌘Tab 切换；全部关闭后恢复为菜单栏应用
    private func present(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        Task { @MainActor in
            let others = [self.historyWindow, self.settingsWindow].compactMap { $0 }
                .filter { $0 !== closing && $0.isVisible }
            if others.isEmpty { NSApp.setActivationPolicy(.accessory) }
        }
    }

    // MARK: - 主菜单（让 ⌘C / ⌘V / ⌘A 等在文本框中可用）

    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 CopyT", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 CopyT", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 CopyT", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }
}
