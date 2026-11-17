# CopyT

[![Build & Test](https://github.com/CraveDL/CopyT/actions/workflows/build.yml/badge.svg)](https://github.com/CraveDL/CopyT/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/CraveDL/CopyT)](https://github.com/CraveDL/CopyT/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

为 **Apple Silicon（M 系列芯片）Mac** 原生构建的剪贴板历史工具。它常驻菜单栏，自动记录你复制过的文本、富文本、图片和文件，支持搜索、按日期浏览和自定义存放位置。

免费、开源，所有数据只保存在你自己的 Mac 上，不联网。

> A native clipboard history app for Apple Silicon Macs. It lives in the menu bar and records copied text, rich text, images and files, with search, per-day browsing and a configurable storage location. Free and open source (MIT); everything stays on your Mac. The interface is in Simplified Chinese.

## 下载安装

**[⬇️ 下载最新版本](https://github.com/CraveDL/CopyT/releases/latest)**（选择 `.dmg` 文件）

系统要求：Apple Silicon（M1 及以后）的 Mac，macOS 13 Ventura 或更高版本。暂不提供 Intel 版本。

1. 打开下载的 `.dmg`，把 **CopyT** 拖到 **Applications（应用程序）**。
2. 在「应用程序」中打开 CopyT。**第一次打开需要手动放行**（见下）。
3. 打开后屏幕顶部菜单栏会出现一个剪贴板图标，CopyT 不会出现在程序坞中。

### 第一次打开时被系统拦截

CopyT 没有购买 Apple 的开发者签名与公证，所以 macOS 第一次会拦截它。任选一种方式放行，只需要做一次：

**方式 A：系统设置**

1. 双击 CopyT，出现无法打开的提示后点「完成」。
2. 打开「系统设置 → 隐私与安全性」，滚动到「安全性」一栏，找到关于 CopyT 的提示，点「仍要打开」，再输入密码确认。

macOS 13 / 14 也可以右键点击 CopyT →「打开」→ 再点「打开」。

**方式 B：终端**

```bash
xattr -dr com.apple.quarantine /Applications/CopyT.app
```

如果你不放心直接运行下载的安装包，可以核对发布页上的 SHA-256 校验值，或者[从源码自己构建](#从源码构建)。

## 功能

| 功能 | 说明 |
| --- | --- |
| 自动记录 | 文本、富文本（RTF / HTML）、图片（截图、浏览器复制的图片等）、文件（Finder 中复制的文件 / 文件夹） |
| 检索 | 搜索文本内容、文件路径、来源应用；空格分隔多个关键词；可按类型筛选 |
| 按日期保存 | 侧边栏按天分组浏览；图片等媒体文件按 `media/年/月/日/` 归档保存 |
| 收藏 | 收藏的记录永不被自动清理 |
| 更改存放位置 | 可迁移到任意文件夹（如 iCloud Drive、外置硬盘），可选择移动现有数据 |
| 自动清理 | 保留时长：永久 / 7 天 / 30 天 / 90 天 / 1 年 |
| 导出 | 把当前列表（可先筛选某一天）导出为 Markdown，图片一并导出 |
| 快捷键 | 全局 `⌃⌥V` 打开 / 关闭历史窗口 |
| 隐私 | 不记录密码管理器标记为隐藏的内容；可设置不记录的应用；随时暂停记录 |
| 去重 | 再次复制相同内容时不会重复存储，而是移到最新 |
| 开机启动 | 可在设置中开启「登录时自动启动」 |

## 使用说明

**菜单栏图标**

- 左键点击：打开快速面板。输入关键词搜索，点击某条记录（或按回车选第一条）即复制到剪贴板，然后在目标应用中按 `⌘V` 粘贴。
- 右键点击：打开历史记录、暂停记录、设置、退出。

**历史窗口**（`⌃⌥V`，即 Control + Option + V）

- 左侧选择「全部记录 / 收藏 / 某一天」。
- 顶部可以搜索，或按类型（文本 / 富文本 / 图片 / 文件）筛选。
- 双击记录或按 `⌘↩` 复制；按 `⌫` 删除；按住 `⌘` 或 `⇧` 多选；右键有更多操作。
- 工具栏的「导出」会把当前列表导出为 Markdown。

**设置**（菜单栏图标右键 →「设置…」）

- **存储**：查看和更改数据存放位置。勾选「更改位置时移动现有数据」会把现有记录一起搬过去；如果新位置已经有 CopyT 的资料库，会直接切换使用它，不会覆盖。
- **记录**：保留时长、单张图片大小上限（超过的图片不记录）。
- **隐私**：不记录的应用列表（每行一个 Bundle ID，可从正在运行的应用中添加）。
- **通用**：登录时自动启动、全局快捷键开关。
- **维护**：立即清理过期记录、清空历史（保留收藏）。

## 数据与隐私

- **只存本机，不联网**。CopyT 没有任何联网代码，不收集、不上传任何数据，也没有统计或广告。
- **默认存放位置**：`~/Library/Application Support/CopyT/`

  ```
  CopyT/
  ├── copyt.sqlite            # 所有记录（文本内容、元数据）
  └── media/
      └── 2026/11/17/
          ├── 3F2A….png       # 图片
          └── 8C1D….rtf       # 富文本原始格式
  ```

- **记录未加密**。数据库和图片以普通文件保存，能访问你这个 macOS 账户的人或程序都可以读取。请不要在共用账户上记录敏感内容。如果你把存放位置改到 iCloud Drive 等同步文件夹，这些记录也会随之同步到云端。
- **不会记录的内容**：
  - 密码管理器按 [nspasteboard.org](http://nspasteboard.org) 约定标记为隐藏或临时的内容；
  - 来自忽略列表中应用的内容，默认包含 1Password、Bitwarden、钥匙串访问、密码 App；
  - 暂停记录期间复制的内容；
  - 超过大小上限的图片。
- **仍然可能被记录的敏感内容**：没有使用上述标记的应用里复制的密码、验证码、身份证号等。复制这类内容前可以先暂停记录，或者事后在历史中删除。
- 复制文件时只记录文件路径，不保存文件副本。
- CopyT 不需要「辅助功能」等特殊权限。较新的 macOS 可能会询问是否允许 CopyT 读取剪贴板，请选择允许，否则无法记录。

## 卸载

1. 右键点击菜单栏图标 →「退出 CopyT」，把 `CopyT.app` 从「应用程序」拖到废纸篓。
2. 如果开启过「登录时自动启动」，请先在设置中关闭它，或到「系统设置 → 通用 → 登录项」中移除。
3. 需要同时删除历史记录和设置时，执行：

   ```bash
   rm -rf ~/Library/Application\ Support/CopyT
   ```

   ```bash
   defaults delete io.github.cravedl.copyt
   ```

   如果在设置里改过存放位置，请删除你选择的那个文件夹。

## 常见问题

**打开后什么都没出现？**
CopyT 只显示在菜单栏。如果菜单栏图标太多被刘海挡住，可以按 `⌃⌥V` 直接打开历史窗口。

**复制的内容没有被记录？**
检查是否开启了「暂停记录」（图标会变成暂停样式），来源应用是否在忽略列表中，以及系统是否拒绝了 CopyT 读取剪贴板。

**连续快速复制，只记到了一部分？**
CopyT 每 0.5 秒检查一次剪贴板，间隔更短的连续复制只会记录到其中一部分，最后一次复制的内容一定会记录。

**能自动粘贴到当前应用吗？能改快捷键吗？**
目前都不能，见[更新日志](CHANGELOG.md)中的已知限制。

**「登录时自动启动」打不开？**
请先把 CopyT 放进「应用程序」文件夹再开启。

## 从源码构建

需要 macOS 13+，以及 Xcode 15+ **或** 仅安装 Command Line Tools（`xcode-select --install`）。

```bash
git clone https://github.com/CraveDL/CopyT.git
cd CopyT
./scripts/build-app.sh          # 生成 build/CopyT.app（arm64）
open build/CopyT.app
```

- 生成安装包：`VERSION=0.1.0 ./scripts/package.sh`，输出在 `dist/`。
- 开发调试：`swift run`，或 `open Package.swift` 用 Xcode 打开。
- `ARCH=universal ./scripts/build-app.sh` 可以构建同时支持 Intel 的通用包，但这个配置没有经过测试。

项目使用纯 Swift / SwiftUI + AppKit，没有第三方依赖，存储使用系统自带的 SQLite。

> 代码中刻意没有使用 `@State` / `@StateObject`：新版 SDK 里它们依赖只随 Xcode 提供的 SwiftUI 宏插件，只装 Command Line Tools 时会报 `plugin for module 'SwiftUIMacros' not found`。界面状态统一放在 `Views/ViewState.swift` 中。

### 测试

```bash
swift test                                       # 单元测试（需要完整的 Xcode）
./scripts/build-app.sh && ./scripts/e2e/run.sh   # 端到端测试（会启动真实应用）
```

每次推送代码，GitHub Actions 会在 Apple Silicon 的 macOS runner 上运行这两套测试。测试覆盖范围和手动测试清单见 [TESTING.md](TESTING.md)。

### 发布新版本

在 `CHANGELOG.md` 中加上新版本一节，然后推送标签：

```bash
git tag v0.2.0 && git push origin v0.2.0
```

[Release 工作流](.github/workflows/release.yml)会运行测试、打包 DMG、对安装包里的应用再跑一遍端到端测试，然后发布到 Releases。

### 项目结构

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
Tests/CopyTTests/               # 单元测试
scripts/                        # 构建、打包、端到端测试
```

## 反馈与贡献

发现问题或有建议，请到 [Issues](https://github.com/CraveDL/CopyT/issues) 提交，并尽量附上 macOS 版本、CopyT 版本和复现步骤。提交前请确认截图和日志里没有你的隐私内容。欢迎提交 Pull Request。

## 许可与声明

**许可证**　Copyright © 2026 CraveDL。本项目以 [MIT 许可证](LICENSE) 发布：你可以免费使用、复制、修改和再分发本软件（包括用于商业用途），前提是在副本中保留上述版权声明和许可声明。

**免责声明**　本软件按「原样」提供，不附带任何明示或暗示的担保，包括但不限于适销性、特定用途适用性和不侵权。因使用或无法使用本软件造成的任何损失（包括数据丢失或泄露），作者不承担责任。请自行备份重要数据。

**使用须知**　剪贴板中可能包含密码、个人信息等敏感内容，以及他人拥有权利的内容。请只在你自己的设备和账户上使用 CopyT，并自行确保对所记录内容的保存和使用符合当地法律和你所在组织的规定。请勿用它在他人不知情的情况下记录其剪贴板。

**商标**　Apple、Mac、macOS、Finder、iCloud 是 Apple Inc. 的商标。1Password、Bitwarden 等名称归各自所有者所有。CopyT 是独立的开源项目，与上述公司没有关联，也未获其认可或赞助。
