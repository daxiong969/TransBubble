import SwiftUI
import SwiftData
import Photos

// MARK: - 翻译预览页（核心）
// 底层原图固定不变，上层译文精准叠加；支持缩放拖动、双语对比、单块操作、导出、朗读、框选识别、编辑原文
struct CapturePreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemScheme
    @ObservedObject var vm: TranslateViewModel
    let image: UIImage

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var editBlock: TextBlock?
    @State private var selectMode = false            // 手动框选模式
    @State private var selectRect: CGRect?           // 框选区域（归一化）
    @State private var dragStart: CGPoint?
    @State private var showExport = false
    @State private var toast: String?

    let settings = AppSettings()

    var body: some View {
        VStack(spacing: 0) {
            // ===== 图像 + 译文叠加区 =====
            GeometryReader { geo in
                ZStack {
                    // 底层原图
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                    // 译文叠加层（跟随同一缩放/偏移）
                    overlayLayer(canvasSize: geo.size)
                        .scaleEffect(scale)
                        .offset(offset)
                    // 框选矩形
                    if selectMode, let r = selectRect {
                        Rectangle()
                            .strokeBorder(Color.yellow, lineWidth: 2)
                            .background(Color.yellow.opacity(0.15))
                            .frame(width: r.width * geo.size.width, height: r.height * geo.size.height)
                            .position(x: r.midX * geo.size.width, y: r.midY * geo.size.height)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                // 双指缩放
                .gesture(MagnificationGesture()
                    .onChanged { scale = max(1, min(5, $0)) }
                    .onEnded { _ in }
                )
                // 拖动移动
                .simultaneousGesture(DragGesture()
                    .onChanged { g in
                        if scale > 1 { offset = CGSize(width: g.translation.width, height: g.translation.height) }
                    }
                    .onEnded { _ in }
                )
                // 框选手势
                .simultaneousGesture(selectMode ?
                    DragGesture(minimumDistance: 5)
                        .onChanged { g in
                            if dragStart == nil { dragStart = g.startLocation }
                            let s = dragStart ?? g.startLocation
                            let x1 = min(s.x, g.location.x) / geo.size.width
                            let y1 = min(s.y, g.location.y) / geo.size.height
                            let x2 = max(s.x, g.location.x) / geo.size.width
                            let y2 = max(s.y, g.location.y) / geo.size.height
                            selectRect = CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
                        }
                        .onEnded { _ in dragStart = nil }
                    : nil)
            }
            // ===== 工具栏 =====
            toolBar
            // ===== 双语对比面板（左右分栏） =====
            if vm.compareMode {
                comparePanel
                    .frame(maxHeight: 220)
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("翻译预览")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("关闭") { vm.tts.stop(); dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("重新翻译") {
                    Task { await vm.retranslate(context: modelContext) }
                }
            }
        }
        // 苹果系统翻译 session（iOS 17.4+）
        .modifier(AppleTranslationTaskModifier(coordinator: vm.appleCoordinator))
        // 编辑原文
        .sheet(item: $editBlock) { block in
            EditOriginalSheet(block: block) { newText in
                if let i = vm.blocks.firstIndex(where: { $0.id == block.id }) {
                    vm.blocks[i].original = newText
                    vm.retranslateBlock(vm.blocks[i], context: modelContext)
                }
            }
        }
        // 导出菜单
        .confirmationDialog("导出图片", isPresented: $showExport) {
            Button("保存合成图（当前引擎译文叠加）") { exportImage(provider: settings.defaultEngine) }
            Button("保存原始截图") { exportImage(provider: "original") }
            Button("保存对比图（左DeepL右苹果）") { exportImage(provider: "compare") }
            Button("取消", role: .cancel) {}
        }
        .toast(message: $toast)
        .onAppear { vm.compareMode = settings.compareModeDefault }
    }

    // MARK: 译文叠加层
    @ViewBuilder
    private func overlayLayer(canvasSize: CGSize) -> some View {
        let style = settings.style(for: systemScheme == .dark)
        let dark = systemScheme == .dark
        ZStack {
            ForEach(vm.blocks) { block in
                if !block.ignored && !block.hidden && inSelection(block) {
                    // 低置信度标注（黄色感叹角标）
                    ZStack(alignment: .topLeading) {
                        // 译文文本块
                        Text(pickText(block))
                            .font(.system(size: style.fontSize, weight: .medium))
                            .foregroundColor(colorFromHex(style.textColorHex))
                            .padding(4)
                            .frame(width: block.bounding.width * canvasSize.width,
                                   height: block.bounding.height * canvasSize.height,
                                   alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(colorFromHex(style.bgHex).opacity(style.bgOpacity))
                            )
                            .lineLimit(6)
                            .minimumScaleFactor(0.5)
                        // 低置信度提醒角标
                        if settings.lowConfidenceAlert && vm.lowConfidenceIds.contains(block.id) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                                .offset(x: -8, y: -8)
                        }
                        // 朗读高亮标记
                        if vm.tts.currentIndex != nil && vm.tts.isSpeaking {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.orange, lineWidth: 2)
                        }
                    }
                    .id(block.id)
                    .contextMenu {
                        Button("复制原文") { UIPasteboard.general.string = block.original; toast = "已复制原文" }
                        Button("复制译文") { UIPasteboard.general.string = pickText(block); toast = "已复制译文" }
                        Button("朗读原文") { vm.speakBlock(block, translated: false) }
                        Button("朗读译文") { vm.speakBlock(block, translated: true) }
                        Button("重新识别（修改原文）") { editBlock = block }
                        Button(block.hidden ? "显示该译文" : "隐藏该译文") {
                            if let i = vm.blocks.firstIndex(where: { $0.id == block.id }) {
                                vm.blocks[i].hidden.toggle()
                            }
                        }
                        Button("忽略该文字块", role: .destructive) {
                            if let i = vm.blocks.firstIndex(where: { $0.id == block.id }) {
                                vm.blocks[i].ignored = true
                            }
                        }
                    }
                    .opacity(vm.tts.isSpeaking ? 1 : 1)
                }
            }
            // 加载状态（两个翻译源独立）
            if vm.deeplBusy || vm.appleBusy {
                VStack {
                    ProgressView(vm.deeplBusy ? "DeepL 翻译中…" : "苹果翻译中…")
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    /// 当前显示的译文（主引擎）
    private func pickText(_ b: TextBlock) -> String {
        let engine = settings.defaultEngine
        let t = engine == "apple" ? b.apple : b.deepl
        return t.isEmpty ? b.original : t
    }

    /// 框选过滤：仅显示/翻译选中区域内的块
    private func inSelection(_ b: TextBlock) -> Bool {
        guard let r = selectRect else { return true }
        return b.bounding.intersects(r)
    }

    // MARK: 工具栏
    private var toolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // 对比模式
                Button {
                    vm.compareMode.toggle()
                } label: {
                    Label(vm.compareMode ? "对比:开" : "对比:关", systemImage: "square.split.1x2")
                }
                .buttonStyle(.bordered)
                // 框选模式
                Button {
                    selectMode.toggle()
                    if !selectMode { selectRect = nil }
                } label: {
                    Label(selectMode ? "框选:开" : "框选", systemImage: "rectangle.dashed")
                }
                .buttonStyle(.bordered)
                .tint(selectMode ? .yellow : .blue)
                // 只翻译选中区域
                if selectMode && selectRect != nil {
                    Button("只翻译选中区域") {
                        // 忽略区域外所有块，对区域内强制重译
                        for i in vm.blocks.indices {
                            vm.blocks[i].ignored = !inSelection(vm.blocks[i])
                        }
                        Task { await vm.retranslate(context: modelContext) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                // 切换引擎重译
                Menu {
                    Button("用 DeepL 重译") { Task { await vm.retranslate(context: modelContext, engine: "deepl") } }
                    Button("用苹果翻译重译") { Task { await vm.retranslate(context: modelContext, engine: "apple") } }
                } label: {
                    Label("切换引擎", systemImage: "arrow.triangle.2.circlepath")
                }
                // 朗读
                Menu {
                    Button("朗读全部原文") { vm.speakAll(translated: false) }
                    Button("朗读全部译文") { vm.speakAll(translated: true) }
                    if vm.tts.isSpeaking {
                        Button(vm.tts.isPaused ? "继续朗读" : "暂停朗读") {
                            vm.tts.isPaused ? vm.tts.resume() : vm.tts.pause()
                        }
                        Button("停止朗读", role: .destructive) { vm.tts.stop() }
                    }
                } label: {
                    Label("朗读", systemImage: "speaker.wave.2")
                }
                // 复制全部
                Menu {
                    Button("复制全部原文") {
                        UIPasteboard.general.string = vm.blocks.filter { !$0.ignored }.map { $0.original }.joined(separator: "\n")
                        toast = "已复制全部原文"
                    }
                    Button("复制全部译文") {
                        UIPasteboard.general.string = vm.blocks.filter { !$0.ignored }.map { pickText($0) }.joined(separator: "\n")
                        toast = "已复制全部译文"
                    }
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                // 导出
                Button {
                    showExport = true
                } label: {
                    Label("导出", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    // MARK: 双语对比面板（左右分栏，独立样式区分两个翻译源）
    private var comparePanel: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text("双语对比（左 DeepL / 右 苹果翻译）")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(vm.blocks.filter { !$0.ignored }) { b in
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.original).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            Text(b.deepl.isEmpty ? "…" : b.deepl)
                                .font(.caption)
                                .padding(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.blue.opacity(0.12)))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.original).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            Text(b.apple.isEmpty ? "…" : b.apple)
                                .font(.caption)
                                .padding(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.green.opacity(0.12)))
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: 导出图片到相册
    private func exportImage(provider: String) {
        let ui: UIImage?
        if provider == "original" { ui = image }
        else {
            let style = settings.style(for: systemScheme == .dark)
            ui = vm.compositedImage(style: style, provider: provider)
        }
        guard let img = ui else { toast = "导出失败"; return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { toast = "相册权限被拒绝，请到设置开启" }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: img)
            } completionHandler: { ok, _ in
                DispatchQueue.main.async { toast = ok ? "已保存到相册" : "保存失败" }
            }
        }
    }
}

// MARK: - 苹果翻译 Task 修饰器（iOS 17.4+，低版本空实现）
struct AppleTranslationTaskModifier: ViewModifier {
    let coordinator: AppleTranslateCoordinator

    func body(content: Content) -> some View {
        if #available(iOS 17.4, *) {
            content.translationTask(coordinator.configuration) { session in
                await coordinator.perform(session: session)
            }
        } else {
            content
        }
    }
}

// MARK: - 编辑原文弹窗
struct EditOriginalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let block: TextBlock
    let onSubmit: (String) -> Void
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("识别原文（可手动修改后重新翻译）") {
                    TextEditor(text: $text)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("修改原文")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("重新翻译") {
                        onSubmit(text)
                        dismiss()
                    }
                }
            }
            .onAppear { text = block.original }
        }
    }
}

// MARK: - 轻提示 Toast
extension View {
    func toast(message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
struct ToastModifier: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let msg = message {
                Text(msg)
                    .padding(10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 30)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            withAnimation { message = nil }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: message)
    }
}
