import Foundation
import AVFoundation

// MARK: - TTS 朗读服务（AVFoundation，朗读段落高亮回调）
@MainActor
final class TTSService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var currentIndex: Int?   // 当前朗读段落（用于高亮标记）

    private let synthesizer = AVSpeechSynthesizer()
    private var queueCount = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// 朗读一组文本
    /// - Parameters:
    ///   - texts: 段落列表
    ///   - locale: 语言代码（zh-CN / en / ja-JP 等）
    ///   - rate: 语速 0~1（映射到 AVSpeechUtterance 语速）
    ///   - voiceIdentifier: 指定语音（空=系统默认）
    func speak(texts: [String], locale: String, rate: Double, voiceIdentifier: String) {
        stop()
        guard !texts.isEmpty else { return }
        queueCount = texts.count
        // 语速映射：AVSpeech 默认 0.5，范围约 0.1~1.0
        let avRate = max(0.1, min(1.0, rate * 0.9 + 0.1))
        let language = locale
        for (i, text) in texts.enumerated() {
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = Float(avRate)
            // 语言通过语音设置（AVSpeechUtterance 无 locale 属性）
            if !voiceIdentifier.isEmpty,
               let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
                utterance.voice = voice
            } else if let voice = AVSpeechSynthesisVoice(language: language) {
                utterance.voice = voice
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            }
            utterance.postUtteranceDelay = 0.1
            synthesizer.speak(utterance)
        }
        isSpeaking = true
        isPaused = false
        currentIndex = 0
    }

    /// 暂停
    func pause() {
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    /// 继续
    func resume() {
        synthesizer.continueSpeaking()
        isPaused = false
    }

    /// 停止
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        currentIndex = nil
    }

    // MARK: AVSpeechSynthesizerDelegate - 段落高亮推进
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.isSpeaking else { return }
            if let cur = self.currentIndex, cur + 1 < self.queueCount {
                self.currentIndex = cur + 1
            } else {
                self.isSpeaking = false
                self.currentIndex = nil
            }
        }
    }
}

// MARK: - 获取系统可用 TTS 语音列表（设置页语音选择）
func availableVoices() -> [AVSpeechSynthesisVoice] {
    return AVSpeechSynthesisVoice.speechVoices()
        .filter { ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"].contains($0.language) }
        .sorted { $0.language < $1.language }
}
