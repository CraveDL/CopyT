
## 下载与安装

1. 下载下方的 **`.dmg`** 文件（需要 Apple Silicon / M 系列芯片的 Mac，macOS 13 或更高版本）。
2. 打开后把 **CopyT** 拖到 **Applications（应用程序）**。
3. 第一次打开需要手动放行，因为安装包没有经过 Apple 公证：
   - 双击 CopyT，出现无法打开的提示后点「完成」；
   - 打开「系统设置 → 隐私与安全性」，在「安全性」一栏点「仍要打开」。

   或者在终端执行一次：

   ```bash
   xattr -dr com.apple.quarantine /Applications/CopyT.app
   ```

完整说明见 [README](https://github.com/CraveDL/CopyT#readme)。所有记录只保存在本机，CopyT 不联网。

## 校验值（SHA-256）

