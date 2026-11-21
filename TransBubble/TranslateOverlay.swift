import SwiftUI

enum TranslationState {
    case idle
    case loading
    case success(TranslationResult)
    case failure(String)
}

/// 翻译结果浮层（半透明卡片，从底部弹出）
struct TranslateOverlay: View {
    let state: TranslationState
    var onClose: () -> Void
    var onRetry: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            card
        }
        .ignoresSafeArea(edges: .bottom)
        .background(CloseOnTapBackground(onTap: onClose))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            switch state {
            case .idle:
                EmptyView()

            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在翻译当前页面…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 28)

            case .success(let result):
                if !result.detectedLanguage.isEmpty {
                    Text("检测语言：\(result.detectedLanguage) → 中文")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ScrollView {
                    Text(result.translatedText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 320)

            case .failure(let message):
                VStack(alignment: .leading, spacing: 10) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.red)
                    Button {
                        onRetry()
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.thinMaterial)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var header: some View {
        HStack {
            Label("悬浮翻译", systemImage: "character.bubble")
                .font(.headline)
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 点击浮层外空白处关闭
private struct CloseOnTapBackground: UIViewRepresentable {
    var onTap: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    final class Coordinator: NSObject {
        let onTap: () -> Void
        init(onTap: @escaping () -> Void) { self.onTap = onTap }
        @objc func handleTap() { onTap() }
    }
}
