import SwiftUI

/// 可拖拽的悬浮翻译球。拖动改位置，轻点触发翻译。
struct FloatingBubble: View {
    var isTranslating: Bool
    var onTap: () -> Void

    @State private var position: CGPoint?
    @State private var dragStart: CGPoint?

    private let bubbleSize: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            let defaultPosition = CGPoint(x: geo.size.width - bubbleSize - 16,
                                          y: geo.size.height * 0.62)
            bubble
                .frame(width: bubbleSize, height: bubbleSize)
                .position(position ?? defaultPosition)
                .onAppear {
                    if position == nil { position = defaultPosition }
                }
                .onTapGesture { onTap() }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let start = dragStart ?? (position ?? defaultPosition)
                            if dragStart == nil { dragStart = start }
                            position = CGPoint(x: start.x + value.translation.width,
                                               y: start.y + value.translation.height)
                        }
                        .onEnded { _ in dragStart = nil }
                )
        }
    }

    private var bubble: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.52, blue: 0.98),
                                              Color(red: 0.12, green: 0.36, blue: 0.85)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
            if isTranslating {
                ProgressView()
                    .tint(.white)
            } else {
                Text("译")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
}
