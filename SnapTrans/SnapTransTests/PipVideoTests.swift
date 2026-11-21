import XCTest
import AVFoundation
@testable import SnapTrans

// MARK: - 悬浮球 PiP 视频生成测试（回归：视频未写完就被播放导致 PiP 无法启动）
final class PipVideoTests: XCTestCase {

    /// 生成的视频文件必须存在、非空，且包含可播放的视频轨道
    func testBallVideoIsValidAndPlayable() async throws {
        // 生成（首次会全新生成，之后读缓存）
        let url = PipManager.makeBallVideoIfNeeded(size: 64)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "视频文件应存在")
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(fileSize, 1024, "视频文件不应为空")

        // 异步加载资源信息，验证可播放
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 1.0, "视频时长应大于 1 秒（预期 3 秒循环动画）")
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1, "应包含 1 条视频轨道")
    }
}
