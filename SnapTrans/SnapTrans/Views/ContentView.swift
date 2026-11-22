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
                // 悬浮球开关（PiP 方案，体验受限，作为备选保留）
                Section("画中画悬浮球（备选）") {
                    Toggle(isOn: Binding(
                        get: { pipEnabled },
                        set: { on in
                            pipEnabled = on
                            let s = AppSettings()
                            if on {
                                PipManager.shared.start(size: s.pipSize, opacity: s.pipOpacity)
                            } else {
                                PipManager.shared.stop()
                            }
                        })) {
                        VStack(alignment: .leading) {
                            Text("开启画中画悬浮球")
                            Text("悬浮于其他 App 之上；首次点击弹出播放控制，再点暂停即触发截图翻译")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("说明：PiP 窗口可双指捏合缩小。受系统限制，点击会先显示视频控制条，翻译触发为「暂停播放」动作；更流畅的入口推荐使用上方的小白点快捷指令。")
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

    /// 消费两类外部触发：
    /// 1) 快捷指令传入的待翻译截图（小白点 → 截图 → 翻译截图）
    /// 2) 「选图翻译」指令（打开 App 自动弹出相册选图）
    private func consumeIntentAndPendingIfNeeded() {
        if let img = PendingImageStore.consume() {
            Task { await vm.processImage(img) }
            return
        }
        if UserDefaults.standard.bool(forKey: "pendingOpenPicker") {
            UserDefaults.standard.set(false, forKey: "pendingOpenPicker")
            showPhotoPicker = true
        }
    }

    /// 悬浮球点击回调 → 截图翻译流程；双击 → 打开主界面
    private func setupPipCallbacks() {
        PipManager.shared.onTap = {
            Task { await vm.startFlow() }
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
