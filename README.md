# ☁️ 清风网盘 iOS

原生 SwiftUI 重写的清风网盘 iOS 客户端，Material Design 3 风格 UI。

![Version](https://img.shields.io/badge/version-3.4.4-blue)
![Platform](https://img.shields.io/badge/platform-iOS%2026%2B-green)
![Language](https://img.shields.io/badge/language-SwiftUI-orange)

## 📥 下载安装

**最新版本：v3.4.4**

- **本地构建**：本仓库 Actions 会自动构建 IPA（见下方「自动构建」）
- **安装方法**：
  - 越狱用户：直接用 AppSync 或 TrollStore 安装
  - 非越狱用户：用 AltStore / Sideloadly /轻松签 自签安装

> 注意：本 IPA 未签名，需要自己签名后才能安装。

## ✨ 功能特性

- 📁 **文件管理**：浏览、搜索、上传、下载、重命名、删除
- 🖼️ **在线预览**：图片、视频、音频、文本、QuickLook
- 📤 **分片上传**：5MB 分片，支持断点续传
- 📥 **带进度下载**：实时显示下载进度
- 🔗 **分享链接**：生成分享链接，支持密码保护
- 🗑️ **回收站**：删除文件可还原
- 👤 **会员中心**：查看等级、空间配额
- ⚙️ **自定义服务器**：可修改服务器地址和分享码
- 👥 **多账号管理**（v3.2.1 新增）：
  - 登录成功自动记住账号（密码存 Keychain）
  - 登录页点按已保存账号一键登录
  - 「我的」页一键切换账号，无需重新输密码
  - 每个账号都可以删除（点垃圾桶或长按），删除当前账号会同时退出登录
- 🫧 **iOS 26 液态玻璃**（v3.2.1 新增）：底栏 Dock 使用系统 Liquid Glass 材质（`glassEffect`），选中态弹性胶囊指示器；iOS 16–25 自动回退 MD3 卡片风格
- 🎨 **Material Design 3**：原生 MD3 风格 UI

## 🖼️ 界面预览

（待添加截图）

## 🛠️ 技术栈

- **语言**：Swift 5.9
- **UI**：SwiftUI + Material Design 3
- **最低系统**：iOS 16.0（液态玻璃需要 iOS 26+）
- **架构**：MVVM + ObservableObject
- **存储**：Keychain + UserDefaults

## 📂 项目结构

```
qingfeng-netdisk-ios/
├── QingFengNetDisk/
│   ├── AppEntry.swift              # App 入口 + 主框架
│   ├── Theme.swift                 # MD3 色板组件 + iOS 26 液态玻璃底栏
│   ├── Models.swift                # 数据模型
│   ├── Credentials.swift           # Keychain 存储 + 多账号存储
│   ├── ApiClient.swift             # API 客户端（24 个端点）
│   ├── Services.swift              # 传输服务 / 会话 / 账号切换
│   ├── LoginView.swift             # 登录 / 注册 / 已保存账号快登
│   ├── HomeView.swift              # 首页
│   ├── FilesView.swift             # 文件浏览
│   ├── PreviewView.swift           # 文件预览
│   ├── TransferView.swift          # 传输
│   ├── TrashView.swift             # 回收站
│   ├── MemberSheet.swift           # 会员中心
│   ├── MineView.swift              # 我的（含账号管理）
│   └── SettingsView.swift          # 设置
├── QingFengNetDisk.xcodeproj/
└── .github/workflows/build-ipa.yml # Actions 自动构建 IPA
```

## 🤖 自动构建（GitHub Actions）

推送到 `main` 分支或打 `v*` 标签时自动构建未签名 IPA：

1. 构建流程：选 Xcode 27.1 → 重新生成工程 → 模拟器自检 → Release 真机架构构建 → 打包 IPA
2. 构建产物在 Actions 的 Artifacts 中下载（`QingFengNetDisk-IPA`）
3. 打 `v*` 标签还会自动创建 Release 并附上 IPA

手动触发：Actions 页面 → Build IPA → Run workflow

## 📄 许可证

MIT License
