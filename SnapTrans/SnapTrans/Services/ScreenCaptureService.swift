import Foundation
import ReplayKit
import UIKit

// MARK: - 屏幕截图服务（ReplayKit 单帧截取，不做持续录屏）
// 说明：RPScreenRecorder.captureImage 在用户授予「屏幕录制」权限后，
// 可在触发瞬间截取一张全屏画面（包含其他 App 的内容），符合"仅点击瞬间截取一张画面"的流程约束。
final class ScreenCaptureService {
    static let shared = ScreenCaptureService()
    private init() {}

    /// 单次截取一帧屏幕画面
    func captureSingleFrame() async throws -> UIImage {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            throw TranslateError.captureFailed("屏幕录制服务不可用（可能在其他 App 正在占用录屏）")
        }
        return try await withCheckedThrowingContinuation { cont in
            recorder.captureImage { image, error in
                if let image {
                    cont.resume(returning: image)
                } else {
                    let msg = error?.localizedDescription ?? "未知原因；请到「设置 → 控制中心」添加「屏幕录制」，并在弹窗中允许"
                    cont.resume(throwing: TranslateError.captureFailed(msg))
                }
            }
        }
    }
}
