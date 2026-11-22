import ReplayKit
import SwiftUI
import UserNotifications

// MARK: - 直播翻译（录屏广播）主 App 侧支持
enum BroadcastService {
    /// 广播扩展的 bundle id（必须与主 App bundle id 前缀一致）
    static let extensionBundleID = "com.daxiong969.SnapTrans.Broadcast"

    /// 开播前把当前配置同步给扩展：
    /// 扩展是独立进程，读不到主 App 的 Keychain 与 UserDefaults
    static func syncConfigToShared() {
        let s = AppSettings()
        let cfg = BroadcastShared.Config(
            deeplKey: KeychainService.load(),
            sourceLang: s.sourceLang,
            targetLang: s.targetLang,
            ocrLanguage: s.ocrLanguage)
        BroadcastShared.saveConfig(cfg)
    }

    /// 取出扩展保存的最新画面（未消费过才返回，取走即标记已消费）
    static func consumePendingFrame() -> UIImage? {
        guard let frame = BroadcastShared.loadFrame(), !frame.info.consumed,
              let img = UIImage(data: frame.data) else { return nil }
        BroadcastShared.markFrameConsumed()
        return img
    }

    /// 请求通知权限（悬浮球在后台触发时，用通知告知翻译结果）
    static func requestNotificationAuth() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

// MARK: - 系统录屏广播选择器
// RPSystemBroadcastPickerView 是系统提供的唯一开播入口：
// 用户在弹窗里选择「译拍通」→ 点「开始直播」→ 本 App 的广播扩展启动
struct BroadcastPickerSheet: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        BroadcastService.syncConfigToShared()
        let vc = UIViewController()
        vc.view.backgroundColor = .systemBackground
        vc.title = "屏幕直播"

        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 300, height: 140))
        picker.preferredExtension = BroadcastService.extensionBundleID
        picker.showsMicrophoneButton = false
        picker.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(picker)

        let tip = UILabel()
        tip.text = "点击上方按钮 → 选择「译拍通」→ 开始直播"
        tip.textAlignment = .center
        tip.font = .preferredFont(forTextStyle: .subheadline)
        tip.textColor = .secondaryLabel
        tip.numberOfLines = 0
        tip.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(tip)

        NSLayoutConstraint.activate([
            picker.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            picker.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor, constant: -30),
            tip.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 20),
            tip.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            tip.leadingAnchor.constraint(greaterThanOrEqualTo: vc.view.leadingAnchor, constant: 24),
            vc.view.trailingAnchor.constraint(greaterThanOrEqualTo: tip.trailingAnchor, constant: 24),
        ])
        return vc
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
