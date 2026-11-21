#!/usr/bin/env node
// 由 Resources/AppIcon.svg 生成 Resources/AppIcon.iconset（各尺寸 PNG）。
// 只在修改图标时需要运行；需要 Node.js 和 Playwright（npm i playwright）。
// 构建时 scripts/build-app.sh 会用系统自带的 iconutil 把 iconset 打包成 AppIcon.icns。
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const root = path.join(__dirname, '..');
const svg = fs.readFileSync(path.join(root, 'Resources/AppIcon.svg'), 'utf8');
const outDir = path.join(root, 'Resources/AppIcon.iconset');

// iconutil 要求的文件名与像素尺寸
const variants = [
  ['icon_16x16.png', 16], ['icon_16x16@2x.png', 32],
  ['icon_32x32.png', 32], ['icon_32x32@2x.png', 64],
  ['icon_128x128.png', 128], ['icon_128x128@2x.png', 256],
  ['icon_256x256.png', 256], ['icon_256x256@2x.png', 512],
  ['icon_512x512.png', 512], ['icon_512x512@2x.png', 1024],
];

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch();
  for (const [name, size] of variants) {
    const page = await browser.newPage({ viewport: { width: size, height: size }, deviceScaleFactor: 1 });
    await page.setContent(
      `<style>html,body{margin:0;background:transparent}svg{display:block;width:${size}px;height:${size}px}</style>${svg}`);
    await page.screenshot({ path: path.join(outDir, name), omitBackground: true });
    await page.close();
    console.log(`${name}  ${size}×${size}`);
  }
  await browser.close();
})();
