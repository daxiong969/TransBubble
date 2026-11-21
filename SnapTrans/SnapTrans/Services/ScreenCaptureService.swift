import Foundation
import ReplayKit
import UIKit
import CoreMedia
import CoreVideo
import CoreImage

// MARK: - 屏幕截图服务（ReplayKit 抓取单帧，不做持续录屏）
// 说明：iOS 的 RPScreenRecorder 没有单帧截图接口（captureImage 仅 macOS 有），
// 这里用 startCapture 启动视频捕获，拿到第一帧视频数据后立即停止，等效"单次截图"。
final class ScreenCaptureService {
    static let shared = ScreenCaptureService()
    private init() {}

    /// 单次截取一帧屏幕画面
    func captureSingleFrame() async throws -> UIImage {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            throw TranslateError.captureFailed("屏幕录制服务不可用（可能被其他 App 占用）")
        }
        // 先确保已停止旧会话
        if recorder.isRecording {
            try? await stopQuietly(recorder)
        }
        return try await withCheckedThrowingContinuation { cont in
            var resumed = false
            let videoHandler: (CMSampleBuffer, RPSampleBufferType, Error?) -> Void = { sample, type, error in
                guard type == .video, !resumed else { return }
                resumed = true
                // 拿到第一帧后立即停止捕获
                recorder.stopCapture { _ in }
                if let image = Self.imageFromSample(sample) {
                    cont.resume(returning: image)
                } else {
                    cont.resume(throwing: TranslateError.captureFailed("无法解析屏幕画面数据"))
                }
            }
            recorder.startCapture(with: videoHandler, audioHandler: nil) { startError in
                guard !resumed else { return }
                if let startError {
                    resumed = true
                    let msg = startError.localizedDescription
                    cont.resume(throwing: TranslateError.captureFailed("\(msg)；请到「设置 → 控制中心」添加「屏幕录制」并允许"))
                }
            }
            // 10 秒超时保护
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                if !resumed {
                    resumed = true
                    recorder.stopCapture { _ in }
                    cont.resume(throwing: TranslateError.captureFailed("截屏超时，请重试"))
                }
            }
        }
    }

    private func stopQuietly(_ recorder: RPScreenRecorder) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            recorder.stopCapture { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    /// CMSampleBuffer -> UIImage
    static func imageFromSample(_ sample: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
