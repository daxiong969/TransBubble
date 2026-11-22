import Foundation
import UIKit

// MARK: - 待翻译截图交接存储
// 快捷指令（App Intent）在后台收到系统「截图」动作传来的图片后，
// 写入本文件并置位标记；App 回到前台时消费 → 直接进入 OCR → 翻译流程。
enum PendingImageStore {
    static var hasPending: Bool {
        UserDefaults.standard.bool(forKey: "pendingTranslateImage")
    }

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pending_translate.jpg")
    }

    /// Intent 侧写入（主线程或任意线程均可，写入是原子的）
    static func saveData(_ data: Data) {
        try? data.write(to: fileURL, options: .atomic)
        UserDefaults.standard.set(true, forKey: "pendingTranslateImage")
    }

    /// App 前台消费：读取图片并清除待处理标记
    static func consume() -> UIImage? {
        UserDefaults.standard.set(false, forKey: "pendingTranslateImage")
        guard let data = try? Data(contentsOf: fileURL), let img = UIImage(data: data) else { return nil }
        try? FileManager.default.removeItem(at: fileURL)
        return img
    }
}
