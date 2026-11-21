# TransBubble 悬浮翻译（iOS）

一个带**悬浮球翻译**的 iOS App：内置浏览器里任意网页可一键翻译成中文，同时附带一个 **Safari 浏览器扩展**，可在系统 Safari 中翻译任何网页。翻译引擎使用 Google 免费接口，**无需任何 API Key**，支持 100+ 语言自动检测 → 简体中文。

---

## 功能

| 模式 | 说明 |
|------|------|
| 内置浏览器悬浮球 | App 内置浏览器，右侧蓝色「译」悬浮球可拖拽，点击后自动抓取页面文字（优先抓取选中的文字），译文以底部浮层展示，支持复制 |
| Safari 扩展 | 在系统 Safari 中，任意网页自动注入蓝色「译」悬浮球，点击翻译，译文面板可关闭/复制；也可通过工具栏图标弹窗触发 |
| 翻译引擎 | `translate.googleapis.com` 免费接口（client=gtx），自动检测源语言，逐段分块请求，最长支持 2 万字 |

> ⚠️ 免费接口地址在国内直连可能超时，建议手机网络可访问 Google（代理/Wi-Fi 环境下正常）。

## 项目结构

```
TransBubble/
├── project.yml                  # XcodeGen 工程定义（运行后自动生成 .xcodeproj）
├── build_ipa.sh                 # 一键构建 IPA 脚本（签名 / 免签名两种模式）
├── TransBubble/                 # 主 App（SwiftUI）
│   ├── TransBubbleApp.swift     # App 入口
│   ├── ContentView.swift        # 地址栏 + 浏览器 + 工具栏 + 翻译流程编排
│   ├── BrowserView.swift        # WKWebView 封装 + 页面文字抓取 JS
│   ├── FloatingBubble.swift     # 可拖拽悬浮球
│   ├── TranslateOverlay.swift   # 译文浮层（加载/成功/失败三态）
│   ├── TranslationService.swift # 免费翻译接口封装（自动分块）
│   └── Assets.xcassets/         # 图标与主题色
└── TransBubbleExtension/        # Safari Web Extension
    ├── SafariWebExtensionHandler.swift  # 原生桥
    ├── manifest.json            # MV3 扩展清单
    ├── content.js               # 注入悬浮球与译文面板
    ├── background.js            # 后台翻译请求（绕过页面 CORS）
    ├── popup.html / popup.js    # 工具栏弹窗
    └── Info.plist               # 由 XcodeGen 生成
```

## 如何构建 IPA（需要一台 Mac）

1. 打开终端，进入本项目目录；
2. 运行下面任一命令（脚本会自动安装 XcodeGen 并生成工程）：

```bash
# 方式 A：签名构建（有 Apple 开发者账号 / 免费 Apple ID）
TEAM_ID=你的团队ID ./build_ipa.sh

# 方式 B：免签名构建（产出 unsigned IPA，之后用工具自签）
UNSIGNED=1 ./build_ipa.sh
```

3. 产物在 `build/` 目录下：
   - 签名构建：`build/export/*.ipa`（可直接装到真机）
   - 免签名构建：`build/TransBubble-unsigned.ipa`（用 AltStore / Sideloadly / TrollStore 自签安装）

### 获取 Team ID
免费 Apple ID 即可：Xcode → Settings → Accounts 登录后，在账号详情里能看到 Team ID（10 位字母数字）。

### 手动构建（不用脚本）
```bash
brew install xcodegen
xcodegen generate
open TransBubble.xcodeproj   # Xcode 里选真机，Cmd+R 运行；Product → Archive 导出 IPA
```

## 安装后启用 Safari 扩展

1. 首次打开 App，会提示去 Safari 设置（或手动：**设置 → Safari → 扩展 → TransBubble**）；
2. 打开「TransBubble 悬浮翻译」的开关，并授予「所有网站」权限；
3. 任意网页右下角即出现蓝色「译」悬浮球。

## 已知限制（iOS 平台规则，非实现缺陷）

- **iOS 不允许普通 App 悬浮在其他 App 之上读取屏幕内容**（无 Android 式无障碍服务），因此「悬浮翻译」的作用范围是：本 App 内置浏览器 + Safari 网页。微信/抖音等第三方 App 内的页面无法翻译，这是苹果系统级安全限制。
- 上架 App Store 需要开发者账号（$99/年）并通过审核；Safari 扩展在 iOS 上必须随 App 一起分发。
- 免费翻译接口无官方 SLA，高并发或被限流时可能偶发失败（App 内已做失败重试提示）。

## 自定义

- **换翻译引擎**：改 `TranslationService.swift` 里的 `endpoint`（DeepL / 百度 / 腾讯等，需按对应 API 格式改 `parseResponse`）；
- **改目标语言**：把默认参数 `target: String = "zh-CN"` 换成 `en`、`ja` 等；
- **换悬浮球样式**：`FloatingBubble.swift`（App 内）/ `content.js` 顶部 CSS（Safari 扩展）。
