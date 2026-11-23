<p align="center">
  <img src="docs/logo.svg" width="96" height="96" alt="VinylDesk Logo" />
</p>

<h1 align="center">VinylDesk</h1>

<p align="center">
  <strong>把 Apple Music 变成 macOS 桌面上的黑胶唱片摆件、极简毛玻璃挂件或顶部灵动岛。</strong>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README_CN.md">简体中文</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.0%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6" />
  <img src="https://img.shields.io/badge/依赖-零第三方库-2EA44F?style=flat-square" alt="零第三方库" />
  <img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="MIT License" />
</p>

---

> **拒绝 Electron，无需 API Key，不占 Dock 栏——100% 纯原生 SwiftUI + AppKit 打造。**
>
> **VinylDesk** 静静陪伴在你的 macOS 桌面上：既可以是一张自带物理质感、随音乐滑出旋转的黑胶唱片封套摆件，也可以一键切换为带有封面动态氛围光的极简毛玻璃卡片，搭配电影字幕般轻盈悬浮的实时歌词。

<!--
💡 建议：录制一段 10–15 秒的桌面动图保存为 `docs/demo.gif`，取消下方注释即可在首页展示惊艳效果！
<p align="center">
  <img src="docs/demo.gif" width="760" alt="VinylDesk 效果演示" />
</p>
-->

---

## ✨ 核心亮点

### 💿 三形态美学（一键切换）
- **黑胶唱片摆件**：左侧方形实体唱片封套 + 右侧半露旋转黑胶（细密沟槽纹理 + 固定光源高光扫光 + 旋转盘心贴纸）。播放时黑胶顺滑滑出并匀速旋转；暂停时按惯性减速停在当前角度并微微缩回封套。平时纯净无字，仅在鼠标悬停时浮现歌名、歌手与播控。
- **极简桌面小挂件**：原生 `NSVisualEffectView` 横向毛玻璃卡片，自动提取专辑封面主色调生成柔和氛围光，支持超长歌名平滑跑马灯、极细可拖拽进度条与悬停播控。
- **灵动岛模式（适配刘海屏 / 外接屏）**：自动贴合 MacBook 刘海（无刘海屏自动贴合顶部居中），平时紧凑展示迷你封面与随封面取色的动态声波条，下方轻盈悬浮单行歌词；鼠标悬停即刻以弹性动效丝滑展开为完整灵动岛播放器（含时间轴拖拽、播控、歌词与一键切回黑胶/卡片）。

### 🎬 电影字幕感实时歌词 & 字体特效
- **3 种歌词文字特效**：默认 **电影字幕（无底框）**——纯文字 + 双层自适应柔和投影，在亮色与暗色壁纸下皆清晰通透；另可选 **封面流光柔晕** 与 **轻雾毛玻璃底框**。
- **3 种精选字体风格**：菜单栏或右键菜单实时切换 **复古黑胶衬线**（New York / 宋体）、**现代极简无衬线**（SF Pro / 苹方）与 **柔和圆体**。
- **多源匹配 + 双语翻译 + 本地缓存**：优先开源 **LRCLIB**，未命中自动兜底中文曲库歌词源，支持一键开关双语翻译，匹配后本地持久化缓存。

### 🪶 原生 macOS 级体验打磨
- **不抢工作焦点**：采用非激活 `NSPanel`，写代码或看网页时点切歌、暂停、拖进度条，绝不打断当前窗口焦点。
- **置顶 / 贴桌面随心切换**：默认悬浮置顶，随时可切为贴桌面层（全桌面 Space 可见）；支持 1:1 丝滑拖动、位置锁定，Apple Music 退出时自动淡出隐藏。
- **高清封面双级兜底**：优先读取 Apple Music 本地封面，云端流媒体曲目自动通过免费 iTunes Search API 拉取 `600×600` 高清封面并缓存。
- **极致轻量**：纯原生 Swift 编译、零第三方依赖、仅顶部菜单栏一个小图标，暂停时 CPU 占用近乎为 0。

---

## 📦 安装方式

### 方式一：直接下载安装包（推荐）
1. 前往 [**Releases**](https://github.com/Marbacj/VinylDesk/releases) 下载最新版 `VinylDesk-macOS.zip`。
2. 解压后将 `VinylDesk.app` 拖入 `/Applications`（应用程序）文件夹。
3. 打开后若系统提示「VinylDesk 想要控制“音乐”」，点击 **允许** 即可。

> **关于未公证应用首次打开提示**：由于本项目为免费开源、未使用付费 Apple Developer ID 公证，首次打开若遇到 macOS 安全提示，可右键 `VinylDesk.app` 选择 **打开**，或在终端执行：
> ```bash
> xattr -cr /Applications/VinylDesk.app
> ```

### 方式二：源码一键编译（需 macOS 14+ & Xcode / Swift 6）
```bash
git clone https://github.com/Marbacj/VinylDesk.git
cd VinylDesk
./scripts/build-app.sh

# 安装到应用程序并启动
cp -R build/VinylDesk.app /Applications/
open /Applications/VinylDesk.app
```

---

## 🎛 交互一览

| 操作 | 触发方式 |
| :--- | :--- |
| **移动挂件位置** | 按住黑胶、封套或卡片任意非按钮区域拖动 |
| **打开 Apple Music** | 轻点专辑封面 |
| **切歌 / 播放暂停** | 鼠标悬停在封套或卡片上 |
| **拖动播放进度** | 极简卡片模式下直接点击或拖动极细进度条 |
| **形态 / 字体 / 特效 / 歌词设置** | 右键点击挂件，或点击顶部菜单栏黑胶图标 |
| **开机自动启动** | 菜单栏图标 → **开机自动启动**（建议放进 `/Applications` 后开启） |

---

## 🗺 后续规划（Roadmap）

- [x] 黑胶封套 + 半露旋转黑胶（物理惯性减速停转与滑出/缩回动效）
- [x] 极简毛玻璃卡片 + 封面动态取色氛围光 + 可拖拽进度条
- [x] 多源实时歌词 + 双语翻译 + 本地缓存
- [x] 电影字幕 / 封面流光 / 轻雾底框文字特效 + 3 套字体风格
- [ ] 纯唱机模式（可选金属唱针落针/抬针动效）
- [ ] 全局快捷键（显隐挂件、一键切形态、红心收藏）
- [ ] 扩展支持 Spotify / 网易云音乐
- [ ] 支持 Homebrew 一键安装（`brew install --cask vinyldesk`）

---

## 🤝 参与贡献

欢迎提 Issue 反馈建议或直接提交 PR！本地运行测试：

```bash
swift test --disable-sandbox
```

---

## 📄 开源协议

基于 [MIT License](LICENSE) 开源。如果 VinylDesk 让你的 Mac 桌面更好看了一点，欢迎点一颗 ⭐ 支持！
