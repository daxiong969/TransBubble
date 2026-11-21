import SwiftUI

struct ContentView: View {
    @StateObject private var webViewModel = WebViewModel()

    @State private var addressField = ""
    @State private var translationState: TranslationState = .idle
    @State private var showOverlay = false

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            Divider()
            BrowserView(viewModel: webViewModel)
            toolBar
        }
        .overlay {
            FloatingBubble(isTranslating: isTranslating) {
                translateCurrentPage()
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay {
            if showOverlay {
                TranslateOverlay(state: translationState,
                                 onClose: { showOverlay = false },
                                 onRetry: { translateCurrentPage() })
            }
        }
        .onReceive(webViewModel.$urlString) { value in
            if addressField.isEmpty || !isEditingAddress { addressField = value }
        }
    }

    private var isTranslating: Bool {
        if case .loading = translationState { return true }
        return false
    }

    // MARK: - 子视图

    @State private var isEditingAddress = false

    private var addressBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                TextField("输入网址或搜索", text: $addressField)
                    .font(.subheadline)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { webViewModel.urlString = addressField; webViewModel.load() }
                    .onTapGesture { isEditingAddress = true }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .clipShape(Capsule())

            Button {
                webViewModel.urlString = addressField
                webViewModel.load()
                isEditingAddress = false
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var toolBar: some View {
        HStack {
            Button { webViewModel.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!webViewModel.canGoBack)
            Spacer()
            Button { webViewModel.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!webViewModel.canGoForward)
            Spacer()
            Button { webViewModel.reload() } label: { Image(systemName: "arrow.clockwise") }
            Spacer()
            Button { translateCurrentPage() } label: {
                Label("翻译", systemImage: "character.bubble")
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    // MARK: - 翻译流程

    private func translateCurrentPage() {
        showOverlay = true
        translationState = .loading
        Task {
            let text = await webViewModel.extractPageText()
            do {
                let result = try await TranslationService.shared.translate(text)
                translationState = .success(result)
            } catch {
                translationState = .failure(error.localizedDescription)
            }
        }
    }
}
