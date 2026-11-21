import Foundation
import SwiftUI
import AVFoundation

// MARK: - 截图翻译流程 ViewModel
// 严格流程：触发 → 截图一次 → OCR 识别 → 缓存判断 → 翻译（DeepL/苹果按需调用）
@MainActor
final class TranslateViewModel: ObservableObject {
    // 流程状态
    enum Phase: Equatable {
        case idle
        case capturing       // 截图中
        case recognizing     // OCR 中
        case translating     // 翻译中
        case done            // 完成
        case failed(String)  // 失败（附错误提示）
    }

    @Published var phase: Phase = .idle
    @Published var screenshot: UIImage?
    @Published var blocks: [TextBlock] = []
    @Published var errorMessage: String?
    @Published var lowConfidenceIds: Set<UUID> = []   // 低置信度文字块（标注提醒）
    @Published var hitCacheAny = false                // 本次是否命中过缓存
    // 对比模式
    @Published var compareMode = false
    @Published var deeplBusy = false
    @Published var appleBusy = false

    // 翻译引擎
    let deeplService = DeepLTranslateService()
    let appleCoordinator = AppleTranslateCoordinator() // 跨版本包装，iOS 18+ 才有真实实现

    // 朗读
    let tts = TTSService()

    private var settings = AppSettings()
    private var translateTask: Task<Void, Never>?   // 防抖任务
    /// 流程完成回调（携带截图，用于弹出预览页）
    var pipelinePreviewHook: ((UIImage) -> Void)?

    // MARK: 主流程入口（悬浮球 / 快捷指令 / 手动按钮统一调用）
    func startFlow() async {
        phase = .capturing
        errorMessage = nil
        do {
            // 1. 截图一次（单帧，不持续录屏）
            let image = try await ScreenCaptureService.shared.captureSingleFrame()
            screenshot = image
            // 2. OCR 识别
            phase = .recognizing
            let ocr = OCRService()
            let textBlocks = try await ocr.recognize(image: image, language: settings.ocrLanguage)
            guard !textBlocks.isEmpty else {
                phase = .failed("未识别到文字。请确认截图中包含文字，或到「设置 → OCR 识别语种」切换语种。")
                return
            }
            // 低置信度标注（阈值 0.5）
            if settings.lowConfidenceAlert {
                lowConfidenceIds = Set(textBlocks.filter { $0.confidence < 0.5 }.map { $0.id })
            }
            blocks = textBlocks
            phase = .translating
            // 3~4. 缓存判断 → 翻译
            await translateAll()
        } catch let e as TranslateError {
            phase = .failed(e.errorDescription ?? "流程失败")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: 批量翻译（缓存优先，未命中的调用对应引擎）
    func translateAll(force: Bool = false, engineOverride: String? = nil) async {
        guard !blocks.isEmpty else { return }
        let engine = engineOverride ?? settings.defaultEngine
        let target = settings.targetLang
        let cache = CacheService.shared
        hitCacheAny = false

        // 过滤掉被忽略的块
        var working = blocks
        // ---------- DeepL 引擎 ----------
        if engine == "deepl" || compareMode {
            deeplBusy = true
            let apiKey = KeychainService.load()
            var miss: [(Int, String, String)] = [] // (下标, 原文, 缓存key)
            for i in working.indices where !working[i].ignored {
                let key = makeCacheKey(working[i].original, source: settings.sourceLang,
                                       target: target, provider: "deepl")
                if !force, let cached = cache.lookup(key: key, policy: settings.cacheExpiry) {
                    working[i].deepl = cached
                    working[i].fromCache = true
                    hitCacheAny = true
                } else {
                    miss.append((i, working[i].original, key))
                }
            }
            // 未命中 → 调 DeepL（一次批量请求）
            if !miss.isEmpty {
                do {
                    let src = LangDefs.deeplSource(settings.sourceLang)
                    let results = try await deeplService.translate(
                        texts: miss.map { $0.1 },
                        source: src,
                        target: LangDefs.deeplTarget(target),
                        apiKey: apiKey,
                        timeout: settings.requestTimeout
                    )
                    for (idx, (i, _, key)) in miss.enumerated() {
                        working[i].deepl = results[idx]
                        working[i].fromCache = false
                        cache.save(key: key, provider: "deepl", translation: results[idx])
                    }
                } catch let e as TranslateError {
                    deeplBusy = false
                    blocks = working
                    if engine == "deepl" { phase = .failed(e.errorDescription ?? "翻译失败") }
                    return
                } catch {
                    deeplBusy = false
                    blocks = working
                    return
                }
            }
            deeplBusy = false
        }
        // ---------- 苹果系统翻译 ----------
        if engine == "apple" || compareMode {
            if !AppleTranslateService.isSupported {
                appleBusy = false
                blocks = working
                if engine == "apple" {
                    phase = .failed(TranslateError.appleUnavailable.errorDescription ?? "")
                }
                return
            }
            appleBusy = true
            var pending: [ApplePendingItem] = []
            for i in working.indices where !working[i].ignored {
                let key = makeCacheKey(working[i].original, source: settings.sourceLang,
                                       target: target, provider: "apple")
                if !force, let cached = cache.lookup(key: key, policy: settings.cacheExpiry) {
                    working[i].apple = cached
                    working[i].fromCache = true
                    hitCacheAny = true
                } else if working[i].apple.isEmpty {
                    pending.append(ApplePendingItem(key: key, text: working[i].original))
                }
            }
            if pending.isEmpty {
                appleBusy = false
            } else {
                // 交给视图层的 translationTask 执行；结果回调在此处更新
                let sourceLang = settings.sourceLang == "auto" ? nil :
                    Locale.Language(identifier: LangDefs.ttsLocale(settings.sourceLang))
                let targetLang = Locale.Language(identifier: LangDefs.ttsLocale(target))
                appleCoordinator.onResult = { [weak self] key, text in
                    Task { @MainActor in
                        cache.save(key: key, provider: "apple", translation: text)
                        if let self,
                           let i = self.blocks.firstIndex(where: {
                               makeCacheKey($0.original, source: self.settings.sourceLang,
                                            target: self.settings.targetLang, provider: "apple") == key
                           }) {
                            self.blocks[i].apple = text
                        }
                    }
                }
                appleCoordinator.onError = { [weak self] err in
                    Task { @MainActor in
                        self?.appleBusy = false
                        self?.errorMessage = err.errorDescription
                    }
                }
                blocks = working
                appleCoordinator.enqueue(items: pending, source: sourceLang, target: targetLang)
                appleBusy = false
            }
        }
        blocks = working
        // 5. 保存历史记录（含叠加预览图）
        let overlay = compositedImage(style: settings.style(for: UITraitCollection.current.userInterfaceStyle == .dark),
                                      provider: engine)
        let anyCache = blocks.contains { $0.fromCache }
        _ = HistoryService.shared.add(
            image: screenshot ?? UIImage(),
            overlay: overlay,
            blocks: blocks.filter { !$0.ignored },
            targetLang: target,
            usedCache: anyCache,
            engine: engine
        )
        phase = .done
        // 弹出预览页（悬浮球/快捷指令触发时）
        if let img = screenshot { pipelinePreviewHook?(img) }
        // 自动朗读（可选）
        if settings.ttsAutoSpeak {
            speakAll(translated: true)
        }
    }

    // MARK: 单块重新翻译（修改原文后 / 单块重译，带 300ms 防抖）
    func retranslateBlock(_ block: TextBlock) {
        translateTask?.cancel()
        let snapshot = block
        translateTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            let cache = CacheService.shared
            let target = self.settings.targetLang
            let engine = self.settings.defaultEngine
            let key = makeCacheKey(snapshot.original, source: self.settings.sourceLang, target: target, provider: engine)
            if let cached = cache.lookup(key: key, policy: self.settings.cacheExpiry) {
                self.applyBlockTranslation(id: snapshot.id, engine: engine, text: cached, fromCache: true)
            } else if engine == "deepl" {
                do {
                    let r = try await self.deeplService.translate(
                        texts: [snapshot.original],
                        source: LangDefs.deeplSource(self.settings.sourceLang),
                        target: LangDefs.deeplTarget(target),
                        apiKey: KeychainService.load(),
                        timeout: self.settings.requestTimeout)
                    self.applyBlockTranslation(id: snapshot.id, engine: "deepl", text: r[0], fromCache: false)
                    cache.save(key: key, provider: "deepl", translation: r[0])
                } catch let e as TranslateError {
                    self.errorMessage = e.errorDescription
                } catch {}
            } else {
                // 苹果引擎走 Coordinator
                let item = ApplePendingItem(key: key, text: snapshot.original)
                let src = self.settings.sourceLang == "auto" ? nil :
                    Locale.Language(identifier: LangDefs.ttsLocale(self.settings.sourceLang))
                self.appleCoordinator.onResult = { [weak self] k, t in
                    Task { @MainActor in
                        cache.save(key: k, provider: "apple", translation: t)
                        self?.applyBlockTranslation(id: snapshot.id, engine: "apple", text: t, fromCache: false)
                    }
                }
                self.appleCoordinator.enqueue(items: [item],
                                              source: src,
                                              target: Locale.Language(identifier: LangDefs.ttsLocale(target)))
            }
        }
    }

    /// 应用单块译文
    private func applyBlockTranslation(id: UUID, engine: String, text: String, fromCache: Bool) {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        if engine == "deepl" { blocks[i].deepl = text } else { blocks[i].apple = text }
        blocks[i].fromCache = fromCache
    }

    // MARK: 一键重新翻译（可换目标语言/引擎）
    func retranslate(engine: String? = nil) async {
        phase = .translating
        await translateAll(force: true, engineOverride: engine)
    }

    // MARK: 朗读
    func speakAll(translated: Bool) {
        let texts = blocks.filter { !$0.ignored }.map { translated ? ($0.deepl.isEmpty ? $0.apple : $0.deepl) : $0.original }
        let lang = translated ? LangDefs.ttsLocale(settings.targetLang) : LangDefs.ttsLocale(settings.sourceLang == "auto" ? "en" : settings.sourceLang)
        tts.speak(texts: texts, locale: lang, rate: settings.ttsRate, voiceIdentifier: settings.ttsVoiceID)
    }
    func speakBlock(_ b: TextBlock, translated: Bool) {
        let text = translated ? (b.deepl.isEmpty ? b.apple : b.deepl) : b.original
        let lang = translated ? LangDefs.ttsLocale(settings.targetLang) : LangDefs.ttsLocale(settings.sourceLang == "auto" ? "en" : settings.sourceLang)
        tts.speak(texts: [text], locale: lang, rate: settings.ttsRate, voiceIdentifier: settings.ttsVoiceID)
    }

    // MARK: 导出合成图片（译文叠加到原图对应位置）
    /// provider: "deepl" | "apple" | "compare"（左右分栏对比图）
    func compositedImage(style: OverlayStyle, provider: String) -> UIImage? {
        guard let base = screenshot else { return nil }
        let size = base.size
        if provider == "compare" {
            // 左右分栏：左 DeepL / 右 苹果
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size.width * 2, height: size.height))
            return renderer.image { ctx in
                base.draw(at: .zero)
                drawOverlay(base: base, blocks: blocks, style: style, pick: { $0.deepl }, in: ctx.cgContext)
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: size.width, y: 0)
                base.draw(at: .zero)
                drawOverlay(base: base, blocks: blocks, style: style, pick: { $0.apple }, in: ctx.cgContext)
                ctx.cgContext.restoreGState()
            }
        } else {
            let pick: (TextBlock) -> String = provider == "apple" ? { $0.apple } : { $0.deepl }
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                base.draw(at: .zero)
                drawOverlay(base: base, blocks: blocks, style: style, pick: pick, in: ctx.cgContext)
            }
        }
    }

    /// 在指定 context 绘制译文块
    private func drawOverlay(base: UIImage, blocks: [TextBlock], style: OverlayStyle,
                             pick: (TextBlock) -> String, in cg: CGContext) {
        let W = base.size.width, H = base.size.height
        let font = UIFont.systemFont(ofSize: style.fontSize * (W / 390.0)) // 按截图宽度缩放字号
        let textColor = UIColor(colorFromHex(style.textColorHex))
        let bgColor = UIColor(colorFromHex(style.bgHex)).withAlphaComponent(CGFloat(style.bgOpacity))
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor, .paragraphStyle: para]

        for b in blocks where !b.hidden && !b.ignored {
            let text = pick(b)
            guard !text.isEmpty else { continue }
            let rect = CGRect(x: b.bounding.minX * W, y: b.bounding.minY * H,
                              width: b.bounding.width * W, height: b.bounding.height * H)
            // 背景圆角矩形
            let bgRect = rect.insetBy(dx: -4, dy: -2)
            let path = UIBezierPath(roundedRect: bgRect, cornerRadius: 6)
            cg.saveGState()
            cg.setFillColor(bgColor.cgColor)
            path.fill()
            cg.restoreGState()
            // 文字（自动换行、垂直居中）
            let textRect = rect.insetBy(dx: 4, dy: 2)
            let drawn = text.boundingRect(with: textRect.size,
                                          options: [.usesLineFragmentOrigin, .usesFontLeading],
                                          attributes: attrs, context: nil)
            let originY = textRect.midY - drawn.height / 2
            (text as NSString).draw(in: CGRect(x: textRect.minX, y: originY,
                                               width: textRect.width, height: max(textRect.height, drawn.height)),
                                    withAttributes: attrs)
        }
    }
}
