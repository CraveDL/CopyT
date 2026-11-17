# CopyT

一个为 **Apple Silicon（M 系列芯片）Mac** 原生构建的剪贴板历史工具：常驻菜单栏，自动记录文本、富文本、图片和文件，支持全文检索、按日期浏览和自定义存放位置。

纯 Swift / SwiftUI + AppKit 编写，**零第三方依赖**（存储使用系统自带的 SQLite）。

## 功能

| 功能 | 说明 |
| --- | --- |
| 📋 自动记录 | 文本、富文本（RTF / HTML）、图片（截图、浏览器复制的图片等）、文件（Finder 中复制的文件 / 文件夹） |
| 🔍 检索 | 搜索文本内容、文件路径、来源应用；空格分隔多个关键词；可按类型筛选 |
| 📅 按日期保存 | 侧边栏按天分组浏览；图片等媒体文件按 `media/年/月/日/` 归档保存 |
| ⭐️ 收藏 | 收藏的记录永不被自动清理 |
| 📁 更改存放位置 | 可迁移到任意文件夹（如 iCloud Drive、外置硬盘），可选择移动现有数据；若目标已有资料库则直接切换使用 |
| 🧹 自动清理 | 保留时长：永久 / 7 天 / 30 天 / 90 天 / 1 年 |
| 📤 导出 | 把当前列表（可先筛选某一天）导出为 Markdown，图片一并导出 |
| ⌨️ 快捷键 | 全局 `⌃⌥V` 打开 / 关闭历史窗口 |
| 🔒 隐私 | 自动忽略密码管理器标记的隐藏内容；可配置不记录的应用（默认含 1Password、Bitwarden、钥匙串、密码 App）；随时暂停记录 |
| 🔁 去重 | 再次复制相同内容时不会重复存储，而是移到最新 |
| 🚀 开机启动 | 基于 `SMAppService` |

## 使用

- **左键点击菜单栏图标**：快速面板，输入关键词搜索，点击或回车即复制到剪贴板。
- **右键点击菜单栏图标**：打开历史记录、暂停记录、设置、退出。
- **历史窗口**（`⌃⌥V`）：
  - 侧边栏选择「全部 / 收藏 / 某一天」
  - 双击记录或 `⌘↩` 复制；`⌫` 删除；右键更多操作；支持多选
- 复制后在目标应用中 `⌘V` 粘贴即可。

## 构建

需要 macOS 13+，以及 Xcode 15+ **或** 仅安装 Command Line Tools（`xcode-select --install`）即可。

> 代码中刻意没有使用 `@State` / `@StateObject`：新版 SDK 里它们依赖只随 Xcode 提供的 SwiftUI 宏插件，只装 Command Line Tools 时会报 `plugin for module 'SwiftUIMacros' not found`。界面状态统一放在 `Views/ViewState.swift` 中。

```bash
git clone https://github.com/CraveDL/copyT.git
cd copyT
./scripts/build-app.sh          # 生成 build/CopyT.app（arm64）
open build/CopyT.app
```

- 通用包（同时支持 Intel）：`ARCH=universal ./scripts/build-app.sh`
- 开发调试：`swift run`，或 `open Package.swift` 用 Xcode 打开。
- 建议把 `CopyT.app` 拖到「应用程序」文件夹后再开启「登录时自动启动」。
- 应用使用 ad-hoc 签名。从别处下载的版本首次打开若被拦截，请右键 →「打开」，或执行 `xattr -dr com.apple.quarantine /Applications/CopyT.app`。

每次推送代码后，GitHub Actions 会在 Apple Silicon 的 runner 上编译，并把 `CopyT.zip` 作为构建产物上传。

## 数据存放

默认位置：`~/Library/Application Support/CopyT/`

```
CopyT/
├── copyt.sqlite            # 所有记录（文本内容、元数据）
└── media/
    └── 2026/11/17/
        ├── 3F2A….png       # 图片
        └── 8C1D….rtf       # 富文本原始格式
```

文件类型的记录只保存路径（不复制文件本身），原文件被移动或删除后会在详情中提示。

## 项目结构

```
Sources/CopyT/
├── App/AppDelegate.swift       # 入口、菜单栏图标、窗口管理
├── Core/
│   ├── ClipItem.swift          # 数据模型
│   ├── Database.swift          # SQLite 存储
│   ├── ClipStore.swift         # 增删查、媒体文件、清理、迁移存储位置
│   ├── ClipboardMonitor.swift  # 剪贴板监听与写回
│   ├── Exporter.swift          # Markdown 导出
│   ├── Preferences.swift       # 设置项
│   └── Support.swift           # 缩略图、全局快捷键、开机启动
└── Views/                      # SwiftUI 界面
```

## 待办

- [ ] 自定义全局快捷键
- [ ] 选中后自动粘贴到当前应用（需要辅助功能权限）
- [ ] 图片 OCR 文字检索（Vision）
- [ ] 小文件可选保存副本
