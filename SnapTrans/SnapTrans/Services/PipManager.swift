import Foundation
import AVKit
import UIKit

// MARK: - PiP 画中画悬浮球管理器
// iOS 无全局悬浮权限，采用 PiP（画中画）实现可悬浮的触发按钮：
// 1. 首次启动用 AVAssetWriter 生成一段"悬浮球"循环视频；
// 2. AVPlayer 无限循环播放该视频，启动 PiP 后窗口悬浮于其他 App 之上；
// 3. 用户点击 PiP 窗口时系统会切换播放/暂停状态，通过 KVO 监听该变化判定为"点击触发"；
// 4. 触发后回调 onTap → 截图一次 → OCR → 翻译（不持续录屏）。
final class PipManager: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    static let shared = PipManager()

    @Published var isActive = false
    /// 悬浮球被点击（主线程回调）
    var onTap: (() -> Void)?
    /// 双击（短时间两次 rate 变化）回调
    var onDoubleTap: (() -> Void)?

    private var window: UIWindow?
    private var player: AVPlayer?
    private var pipController: AVPictureInPictureController?
    private var rateObserver: NSKeyValueObservation?
    private var lastTapTime: Date = .distantPast

    // MARK: 开启悬浮球
    @MainActor
    func start(size: Double, opacity: Double) {
        guard !isActive else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        let videoURL = Self.makeBallVideoIfNeeded(size: size)

        let playerItem = AVPlayerItem(url: videoURL)
        // 无限循环：播放到结尾后重播
        let player = AVPlayer(playerItem: playerItem)
        player.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(self, selector: #selector(loopVideo),
                                               name: .AVPlayerItemDidPlayToEndTime, object: playerItem)

        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = false
        // 视频视图透明度 = 悬浮球不透明度
        vc.view.alpha = CGFloat(opacity)

        // 创建独立窗口承载播放器（随后启动 PiP 即可移出）
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: -2000, y: 0, width: 10, height: 10) // 移出屏幕外，仅用于承载
        window.rootViewController = vc
        window.isHidden = false
        self.window = window

        let pip = AVPictureInPictureController(playerLayer: player.layer)
        pip.delegate = self
        self.pipController = pip
        self.player = player

        // KVO 监听播放状态变化 = PiP 窗口被点击（系统会切换播放/暂停）
        rateObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            DispatchQueue.main.async {
                guard let self, self.isActive else { return }
                if p.timeControlStatus == .paused {
                    self.handleTap()
                    // 恢复播放，维持循环视频
                    p.play()
                }
            }
        }

        player.play()
        // 延迟启动 PiP，确保播放器就绪
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.pipController?.startPictureInPicture()
        }
    }

    /// 停止悬浮球
    @MainActor
    func stop() {
        rateObserver?.invalidate()
        rateObserver = nil
        pipController?.stopPictureInPicture()
        player?.pause()
        player = nil
        pipController = nil
        window?.isHidden = true
        window = nil
        isActive = false
    }

    // MARK: 点击判定（区分单击 / 双击）
    private func handleTap() {
        let now = Date()
        let isDouble = now.timeIntervalSince(lastTapTime) < 0.4
        lastTapTime = now
        if isDouble {
            onDoubleTap?()
        } else {
            onTap?()
        }
    }

    @objc private func loopVideo() {
        player?.seek(to: .zero)
        player?.play()
    }

    // MARK: PiP 代理
    func pictureInPictureControllerDidStartPictureInPicture(_ pipController: AVPictureInPictureController) {
        DispatchQueue.main.async { self.isActive = true }
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ pipController: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.isActive = false
            self.player?.pause()
            self.window?.isHidden = true
            self.window = nil
        }
    }

    // MARK: 生成悬浮球循环视频（首次生成，之后缓存到 tmp）
    private static var cachedURL: URL?
    static func makeBallVideoIfNeeded(size: Double) -> URL {
        if let url = cachedURL, FileManager.default.fileExists(atPath: url.path) { return url }
        // 3 秒 30fps 的圆形悬浮球动画视频（深色底 + 蓝色球 + 呼吸缩放）
        let dim = 240
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pip_ball.mp4")
        try? FileManager.default.removeItem(at: url)

        let writer = try! AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: dim,
            AVVideoHeightKey: dim,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: dim,
                kCVPixelBufferHeightKey as String: dim,
            ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let fps = 30, seconds = 3
        for frame in 0..<(fps * seconds) {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            let pb = Self.pixelBuffer(dim: dim, frame: frame)
            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
            adaptor.append(pb, withPresentationTime: time)
        }
        input.markAsFinished()
        writer.finishWriting { }
        cachedURL = url
        return url
    }

    /// 绘制一帧：深灰底 + 居中蓝色"译"球（呼吸缩放）
    private static func pixelBuffer(dim: Int, frame: Int) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, dim, dim, kCVPixelFormatType_32BGRA, nil, &pb)
        guard let buffer = pb else { fatalError() }
        CVPixelBufferLockBaseAddress(buffer, [])
        let ctx = UIGraphicsImageRenderer(size: CGSize(width: dim, height: dim)).cgContext
        // 深色背景
        ctx.setFillColor(UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: dim, height: dim))
        // 呼吸缩放的蓝色球
        let phase = CGFloat(frame % 30) / 30.0
        let scale = 1.0 + 0.06 * sin(phase * .pi * 2)
        let r = CGFloat(dim) * 0.3 * scale
        let center = CGPoint(x: dim / 2, y: dim / 2)
        ctx.setFillColor(UIColor(red: 0.12, green: 0.53, blue: 0.90, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        // 中心白色"译"字
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: CGFloat(dim) * 0.2, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        let s = NSAttributedString(string: "译", attributes: attrs)
        let sz = s.size()
        s.draw(at: CGPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2))
        // 写入像素
        let image = UIGraphicsImageRenderer(size: CGSize(width: dim, height: dim)).image { $0.cgContext = ctx }
        let outCtx = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                               width: dim, height: dim,
                               bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        outCtx?.clear(CGRect(x: 0, y: 0, width: dim, height: dim))
        outCtx?.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: dim, height: dim))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}
