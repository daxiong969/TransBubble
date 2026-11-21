import SwiftUI
import SwiftData

// MARK: - 主页面（极简：五个入口）
struct ContentView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var flow: AppFlowManager
    @Environment(\.modelContext) private var modelContext
    @StateObject private var vm = TranslateViewModel()
    @StateObject private var pip = PipManager.shared
    @State private var showHistory = false
    @State private var showFavorites = false
    @State private var showSettings = false
    @State private var showGuide = false
    @AppStorage("pipEnabled") private var pipEnabled = false

    var body: some View {
        NavigationStack {
            List {
                // 截图翻译主操作
                Section {
                    Button {
                        Task { await vm.startFlow(context: modelContext) }
                    } label: {
                        HStack {
                            Image(systemName: "camera.viewfinder")
                                .font(.title2)
                            Text("立即截图翻译")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                }
                // 悬浮球开关
                Section("悬浮触发球") {
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
                            Text("开启后悬浮于任意 App 之上，点击即截图翻译")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("iOS 限制说明：系统不允许普通 App 全局悬浮，本方案使用「画中画(PiP)」窗口实现悬浮球。")
                        .font(.caption).foregroundStyle(.secondary)
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
        // 悬浮球 / 快捷指令触发的结果预览（全屏）
        .fullScreenCover(item: $flow.capturedImage) { image in
            CapturePreviewView(vm: vm, image: image)
        }
        // 快捷指令触发消费
        .onAppear {
            consumeIntentTriggerIfNeeded()
            setupPipCallbacks()
            if pipEnabled {
                let s = AppSettings()
                PipManager.shared.start(size: s.pipSize, opacity: s.pipOpacity)
            }
        }
        .onChange(of: flow.pendingCaptureTrigger) { _, _ in consumeIntentTriggerIfNeeded() }
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

    /// 消费快捷指令触发的标记 → 自动开始截图翻译
    private func consumeIntentTriggerIfNeeded() {
        if UserDefaults.standard.bool(forKey: "pendingIntentTrigger") {
            UserDefaults.standard.set(false, forKey: "pendingIntentTrigger")
            Task { await vm.startFlow(context: modelContext) }
        }
    }

    /// 悬浮球点击回调 → 截图翻译流程；双击 → 打开主界面
    private func setupPipCallbacks() {
        PipManager.shared.onTap = {
            Task { await vm.startFlow(context: modelContext) }
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

// MARK: - UIImage 全屏封面 item 支持
extension UIImage: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}
