import SwiftUI
import PhotosUI

// MARK: - 主页面（极简入口）
struct ContentView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var flow: AppFlowManager
    @StateObject private var vm = TranslateViewModel()
    @StateObject private var pip = PipManager.shared
    @State private var showHistory = false
    @State private var showFavorites = false
    @State private var showSettings = false
    @State private var showGuide = false
    @State private var showPhotoPicker = false
    @State private var showBroadcastSheet = false
    @AppStorage("pipEnabled") private var pipEnabled = false

    var body: some View {
        NavigationStack {
            List {
                // 截图翻译主操作（推荐：小白点/快捷指令触发）
                Section {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.title2)
                            Text("从相册选截图翻译")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                    Text("推荐玩法：按「快捷指令配置」把【截图→翻译截图】绑定到系统小白点（辅助触控）或轻点背面，在任意页面点一下即自动截图翻译，无需打开本 App。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                // 直播翻译：唯一能截取「其他 App 页面」的合法方案（录屏广播扩展）
                Section("直播翻译（截其他 App 页面）") {
                    Button {
                        BroadcastService.requestNotificationAuth()
                        BroadcastService.syncConfigToShared()
                        showBroadcastSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.title2)
                            Text("开启直播翻译")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                    Text("点按后在系统弹窗中选择「译拍通」→ 点「开始直播」（状态栏变红属正常）。随后切到微信、Safari 等任意页面，画面会自动送入译拍通识别翻译；回到本 App 即自动显示最新翻译结果，点红色状态栏可停止。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                // 悬浮球开关（PiP 方案，作为快捷入口保留）
                Section("画中画悬浮球（备选）") {
                    Toggle(isOn: Binding(
                        get: { pipEnabled },
                        set: { on in
                            pipEnabled = on
                            let s = AppSettings()
                            if on {
                                BroadcastService.requestNotificationAuth()
                                PipManager.shared.start(size: s.pipSize, opacity: s.pipOpacity)
                            } else {
                                PipManager.shared.stop()
                            }
                        })) {
                        VStack(alignment: .leading) {
                            Text("开启画中画悬浮球")
                            Text("悬浮于其他 App 之上；点击悬浮球 = 翻译最近一次直播画面，并以通知显示结果")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("说明：悬浮球需配合「直播翻译」使用——先开启直播，再切到任意页面，点一下悬浮球即翻译当前画面（通知形式）。普通截图翻译仍推荐上方的小白点快捷指令。")
                        .font(.caption).foregroundStyle(.secondary)
                    // 悬浮球启动状态提示（准备中/失败原因/已启动）
                    if !pip.statusMessage.isEmpty {
                        Text(pip.statusMessage)
                            .font(.caption)
                            .foregroundStyle(pip.isActive ? Color.green : Color.orange)
                    }
                }
                // 其他入口
                Section {
                    NavigationLink("翻译历史") { HistoryListView(favoritesOnly: false) }
                    NavigationLink("收藏") { HistoryListView(favoritesOnly: true) }
                    NavigationLink("设置") { SettingsView() }
                    NavigationLink("快捷指令配置") { ShortcutsGuideView() }
                }
            }
            .navigationTitle("译拍通")
        }
        // 相册选图（PHPicker，无需相册权限）
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView { image in
                if let image {
                    Task { await vm.processImage(image) }
                }
            }
        }
        // 系统录屏广播选择器（直播翻译开播入口）
        .sheet(isPresented: $showBroadcastSheet) {
            BroadcastPickerSheet()
        }
        // 翻译结果预览（全屏）
        .fullScreenCover(item: $flow.capturedImage) { image in
            CapturePreviewView(vm: vm, image: image)
        }
        .onAppear {
            setupPipCallbacks()
            consumeIntentAndPendingIfNeeded()
            if pipEnabled {
                let s = AppSettings()
                PipManager.shared.start(size: s.pipSize, opacity: s.pipOpacity)
            }
        }
        // App 从后台回到前台（快捷指令刚写入待翻译截图）→ 立即消费
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification)) { _ in
            consumeIntentAndPendingIfNeeded()
        }
        // 流程错误提示
        .alert("提示", isPresented: Binding(
            get: { if case .failed = vm.phase { return true }; return false },
            set: { if !$0 { vm.phase = .idle } })) {
            Button("知道了", role: .cancel) {}
        } message: {
            if case let .failed(msg) = vm.phase { Text(msg) }
        }
        .onDisappear { vm.tts.stop() }
    }

    /// 消费三类外部触发：
    /// 1) 快捷指令传入的待翻译截图（小白点 → 截图 → 翻译截图）
    /// 2) 直播翻译扩展保存的最新画面（从其他 App 回到本 App 时自动处理）
    /// 3) 「选图翻译」指令（打开 App 自动弹出相册选图）
    private func consumeIntentAndPendingIfNeeded() {
        if let img = PendingImageStore.consume() {
            Task { await vm.processImage(img) }
            return
        }
        if let frameImg = BroadcastService.consumePendingFrame() {
            Task { await vm.processImage(frameImg) }
            return
        }
        if UserDefaults.standard.bool(forKey: "pendingOpenPicker") {
            UserDefaults.standard.set(false, forKey: "pendingOpenPicker")
            showPhotoPicker = true
        }
    }

    /// 悬浮球点击回调：翻译最近一次直播画面（后台运行，结果以通知呈现）；双击 → 打开主界面
    private func setupPipCallbacks() {
        PipManager.shared.onTap = {
            Task { @MainActor in
                if let img = BroadcastService.consumePendingFrame() {
                    await vm.processImage(img)
                    let translated = vm.blocks
                        .filter { !$0.ignored }
                        .map { $0.deepl.isEmpty ? $0.apple : $0.deepl }
                        .filter { !$0.isEmpty }
                        .joined(separator: "；")
                    BroadcastService.postNotification(
                        title: "译拍通 · 翻译完成",
                        body: translated.isEmpty
                            ? "识别完成但暂无译文，请检查 DeepL Key 配置"
                            : String(translated.prefix(120)))
                } else {
                    BroadcastService.postNotification(
                        title: "译拍通 · 暂无直播画面",
                        body: "请先在 App 内开启「直播翻译」，之后任意页面均可点悬浮球翻译")
                }
            }
        }
        PipManager.shared.onDoubleTap = {
            // 双击：仅取消触发（主界面已在前台时无额外动作；从 PiP 回到 App 即主界面）
        }
        // 流程完成后展示预览
        vm.pipelinePreviewHook = { image in
            flow.capturedImage = image
        }
    }
}

// MARK: - PHPicker 相册选图封装（iOS 16+，无需申请相册权限）
struct PhotoPickerView: UIViewControllerRepresentable {
    var onPick: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerView
        init(_ parent: PhotoPickerView) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            defer { parent.dismiss() }
            guard let item = results.first?.itemProvider,
                  item.canLoadObject(ofClass: UIImage.self) else {
                parent.onPick(nil)
                return
            }
            item.loadObject(ofClass: UIImage.self) { [parent] obj, _ in
                DispatchQueue.main.async {
                    parent.onPick(obj as? UIImage)
                }
            }
        }
    }
}

// MARK: - UIImage 全屏封面 item 支持
extension UIImage: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}
