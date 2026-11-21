import SwiftUI
import AVFoundation

// MARK: - 设置页（完整选项）
struct SettingsView: View {
    @EnvironmentObject var theme: ThemeManager

    @State private var deeplKey = KeychainService.load()
    @State private var showKey = false
    @State private var cacheClearedToast: String?

    // 用 @AppStorage 绑定所有设置项
    @AppStorage("defaultEngine") private var defaultEngine = "deepl"
    @AppStorage("sourceLang") private var sourceLang = "auto"
    @AppStorage("targetLang") private var targetLang = "zh-Hans"
    @AppStorage("compareModeDefault") private var compareModeDefault = false
    @AppStorage("requestTimeout") private var requestTimeout = 15.0
    @AppStorage("pipSize") private var pipSize = 64.0
    @AppStorage("pipOpacity") private var pipOpacity = 0.9
    @AppStorage("pipDoubleTap") private var pipDoubleTap = true
    @AppStorage("ocrLanguage") private var ocrLanguage = "en-US"
    @AppStorage("lowConfidenceAlert") private var lowConfidenceAlert = true
    @AppStorage("cacheExpiry") private var cacheExpiry = "never"
    @AppStorage("ttsRate") private var ttsRate = 0.5
    @AppStorage("ttsVoiceID") private var ttsVoiceID = ""
    @AppStorage("ttsAutoSpeak") private var ttsAutoSpeak = false
    @AppStorage("allowIntentTrigger") private var allowIntentTrigger = true
    @AppStorage("themeMode") private var themeMode = "system"

    var body: some View {
        Form {
            deepLSection
            translateSection
            pipSection
            styleSection
            ttsSection
            cacheSection
            ocrSection
            compareSection
            intentSection
            themeSection
            privacySection
        }
        .navigationTitle("设置")
        .toast(message: $cacheClearedToast)
    }

    // MARK: DeepL 密钥
    private var deepLSection: some View {
        Section {
            HStack {
                Group {
                    if showKey { TextField("请输入 DeepL API Key", text: $deeplKey) }
                    else { SecureField("请输入 DeepL API Key", text: $deeplKey) }
                }
                Button { showKey.toggle() } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                }.buttonStyle(.plain)
            }
            HStack {
                Button("保存密钥") {
                    let trimmed = deeplKey.trimmingCharacters(in: .whitespaces)
                    KeychainService.save(trimmed)
                    // 保存后回读验证，给出真实结果
                    let saved = KeychainService.load()
                    cacheClearedToast = (saved == trimmed && !trimmed.isEmpty)
                        ? "密钥已加密保存到 Keychain ✓"
                        : (trimmed.isEmpty ? "请先输入密钥再保存" : "保存失败，请重试")
                }
                // 关键修复：List 同一行多个按钮必须显式指定 buttonStyle，
                // 否则点任意按钮会触发本行所有按钮（保存后立刻被清空）
                .buttonStyle(.borderless)
                Spacer()
                Button("清空", role: .destructive) {
                    deeplKey = ""
                    KeychainService.clear()
                    cacheClearedToast = "密钥已清空"
                }
                .buttonStyle(.borderless)
            }
            .font(.footnote)
            Text("密钥使用 iOS Keychain 本地加密保存，不会上传。免费密钥可在 deepl.com 免费注册获取（每月 50 万字符）。")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("DeepL API Key")
        }
    }

    // MARK: 翻译
    private var translateSection: some View {
        Section("翻译") {
            Picker("默认翻译引擎", selection: $defaultEngine) {
                Text("DeepL").tag("deepl")
                Text("苹果系统翻译（免费）").tag("apple")
            }
            Picker("默认源语言", selection: $sourceLang) {
                ForEach(LangDefs.sourceLangs, id: \.code) { Text($0.name).tag($0.code) }
            }
            Picker("目标语言", selection: $targetLang) {
                ForEach(LangDefs.targetLangs, id: \.code) { Text($0.name).tag($0.code) }
            }
            Stepper("请求超时：\(Int(requestTimeout)) 秒", value: $requestTimeout, in: 5...60, step: 1)
            Text("DeepL 不可用时（无网络/无密钥），苹果翻译若已下载离线包仍可本地翻译；OCR 始终本地识别。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: 悬浮球
    private var pipSection: some View {
        Section("悬浮球设置") {
            VStack(alignment: .leading) {
                Text("大小：\(Int(pipSize)) pt")
                Slider(value: $pipSize, in: 40...120, step: 4)
            }
            VStack(alignment: .leading) {
                Text("透明度：\(Int(pipOpacity * 100))%")
                Slider(value: $pipOpacity, in: 0.4...1.0, step: 0.05)
            }
            Toggle("双击悬浮球打开主界面", isOn: $pipDoubleTap)
        }
    }

    // MARK: 译文样式（浅/深两套独立）
    private var styleSection: some View {
        Section("译文样式") {
            StyleEditorRow(modeName: "浅色预设", dark: false)
            StyleEditorRow(modeName: "深色预设", dark: true)
        }
    }

    // MARK: TTS
    private var ttsSection: some View {
        Section("朗读（TTS）") {
            VStack(alignment: .leading) {
                Text("语速：\(String(format: "%.1f", ttsRate))")
                Slider(value: $ttsRate, in: 0.1...1.0, step: 0.1)
            }
            Picker("语音", selection: $ttsVoiceID) {
                Text("系统默认").tag("")
                ForEach(availableVoices(), id: \.identifier) { v in
                    Text("\(v.name)（\(v.language)）").tag(v.identifier)
                }
            }
            Toggle("翻译完成后自动朗读", isOn: $ttsAutoSpeak)
        }
    }

    // MARK: 缓存
    private var cacheSection: some View {
        Section("缓存") {
            Picker("缓存有效期", selection: $cacheExpiry) {
                Text("永久").tag("never")
                Text("7 天").tag("7d")
                Text("30 天").tag("30d")
            }
            Button("清空全部缓存", role: .destructive) {
                CacheService.shared.clearAll()
                cacheClearedToast = "已清空全部缓存"
            }
            Text("缓存 key = 原文+源语言+目标语言+翻译服务商；两个翻译源独立缓存；命中缓存不调用翻译 API。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: OCR
    private var ocrSection: some View {
        Section("OCR 识别") {
            Picker("识别语种", selection: $ocrLanguage) {
                Text("英文（默认）").tag("en-US")
                Text("日文").tag("ja-JP")
                Text("韩文").tag("ko-KR")
                Text("中文").tag("zh-Hans")
            }
            Toggle("低置信度文字提醒", isOn: $lowConfidenceAlert)
            Text("OCR 由 Apple Vision 本地完成，不上传图片。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: 对比
    private var compareSection: some View {
        Section("翻译对比") {
            Toggle("预览页默认开启对比模式", isOn: $compareModeDefault)
            Text("对比模式下 DeepL 与苹果翻译并列展示、独立加载、独立缓存。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: 快捷指令
    private var intentSection: some View {
        Section("快捷指令联动") {
            Toggle("允许快捷指令/小白点外部触发翻译", isOn: $allowIntentTrigger)
            NavigationLink("快捷指令配置教程") { ShortcutsGuideView() }
        }
    }

    // MARK: 主题
    private var themeSection: some View {
        Section("主题") {
            Picker("外观", selection: $themeMode) {
                Text("跟随系统").tag("system")
                Text("浅色").tag("light")
                Text("深色").tag("dark")
            }
        }
    }

    // MARK: 权限与隐私
    private var privacySection: some View {
        Section("权限说明 / 隐私") {
            NavigationLink("权限与隐私声明") { PrivacyPolicyView() }
        }
    }
}

// MARK: - 译文样式编辑行（字体大小/文字颜色/背景色/背景透明度）
struct StyleEditorRow: View {
    let modeName: String
    let dark: Bool
    @AppStorage("styleLight") private var styleLightRaw = ""
    @AppStorage("styleDark") private var styleDarkRaw = ""

    @State private var style = OverlayStyle.light()
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(modeName)
            HStack {
                Text("字号 \(Int(style.fontSize))")
                Slider(value: Binding(
                    get: { Double(style.fontSize) },
                    set: { style.fontSize = CGFloat($0) }), in: 9...22, step: 1)
            }
            HStack {
                Text("文字色")
                ColorPicker("", selection: Binding(
                    get: { colorFromHex(style.textColorHex) },
                    set: { style.textColorHex = $0.hexString() }), supportsOpacity: false)
                    .labelsHidden()
                Text("背景色")
                ColorPicker("", selection: Binding(
                    get: { colorFromHex(style.bgHex) },
                    set: { style.bgHex = $0.hexString() }), supportsOpacity: false)
                    .labelsHidden()
            }
            HStack {
                Text("背景不透明度 \(Int(style.bgOpacity * 100))%")
                Slider(value: Binding(
                    get: { style.bgOpacity },
                    set: { style.bgOpacity = $0 }), in: 0.2...1.0, step: 0.05)
            }
            // 预览
            Text("译文预览")
                .font(.system(size: style.fontSize))
                .foregroundColor(colorFromHex(style.textColorHex))
                .padding(6)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 6).fill(colorFromHex(style.bgHex).opacity(style.bgOpacity)))
        }
        .onAppear {
            if !loaded {
                let s = AppSettings()
                style = s.style(for: dark)
                loaded = true
            }
        }
        .onDisappear {
            let s = AppSettings()
            s.setStyle(style, dark: dark)
        }
    }
}

// Color -> hex
extension Color {
    func hexString() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - 权限与隐私声明页
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    Text("屏幕录制权限").font(.headline)
                    Text("仅在点击悬浮球/快捷指令触发时截取单次屏幕画面，不会持续录制屏幕。截图仅用于本地 OCR 文字识别，原图不会上传至任何服务器；只有识别提取后的文本会发送给 DeepL 用于翻译；苹果翻译可在本地离线完成。")
                }
                Group {
                    Text("相册权限").font(.headline)
                    Text("用于将带译文的图片导出到相册，仅使用「仅添加」权限，可自主选择是否授权。")
                }
                Group {
                    Text("隐私承诺").font(.headline)
                    Text("无登录、无广告、无埋点、不收集任何用户行为数据。截图与历史记录全部保存在本机（JSON 文件存储），DeepL 密钥保存在系统 Keychain。")
                }
            }
            .padding()
        }
        .navigationTitle("权限与隐私")
    }
}
