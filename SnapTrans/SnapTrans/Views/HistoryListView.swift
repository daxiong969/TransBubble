import SwiftUI
import Photos

// MARK: - 翻译历史列表（支持搜索 / 收藏过滤 / 批量删除）
struct HistoryListView: View {
    let favoritesOnly: Bool

    @State private var items: [AppStore.HistoryEntry] = []
    @State private var keyword = ""
    @State private var editMode = false
    @State private var selected: Set<UUID> = []
    @State private var detailItem: AppStore.HistoryEntry?

    var body: some View {
        Group {
            if items.isEmpty {
                // iOS 16 兼容的空状态（不使用 iOS17 的 ContentUnavailableView）
                VStack(spacing: 10) {
                    Image(systemName: favoritesOnly ? "star" : "clock.arrow.circlepath")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text(favoritesOnly ? "暂无收藏" : "暂无历史记录")
                        .font(.headline)
                    Text(favoritesOnly ? "在历史记录中点击收藏即可添加" : "完成一次截图翻译后自动生成记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(items) { item in
                        row(item)
                    }
                    .onDelete { indexSet in
                        let targets = indexSet.map { items[$0] }
                        HistoryService.shared.delete(targets)
                        refresh()
                    }
                }
            }
        }
        .navigationTitle(favoritesOnly ? "收藏" : "翻译历史")
        .searchable(text: $keyword, prompt: "搜索原文/译文关键词")
        .onChange(of: keyword) { _ in refresh() }
        .onAppear { refresh() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(editMode ? "完成" : "批量删除") {
                    editMode.toggle()
                    if !editMode && !selected.isEmpty {
                        let targets = items.filter { selected.contains($0.id) }
                        HistoryService.shared.delete(targets)
                        selected.removeAll()
                        refresh()
                    }
                }
            }
        }
        .environment(\.editMode, .constant(editMode ? .active : .inactive))
        .sheet(item: $detailItem) { item in
            NavigationStack { HistoryDetailView(item: item, onRefresh: refresh) }
        }
    }

    @ViewBuilder
    private func row(_ item: AppStore.HistoryEntry) -> some View {
        HStack(spacing: 10) {
            if editMode {
                // 批量选择框
                Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(.blue)
                    .onTapGesture {
                        if selected.contains(item.id) {
                            selected.remove(item.id)
                        } else {
                            selected.insert(item.id)
                        }
                    }
            }
            // 缩略图
            if let ui = AppStore.loadImage(item.imageFile) {
                Image(uiImage: ui)
                    .resizable().scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.originals.first ?? "（无文字）")
                    .font(.subheadline).lineLimit(1)
                Text(item.deeplTexts.first ?? item.appleTexts.first ?? "")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.createdAt.formatted(date: .numeric, time: .shortened))
                    Text(item.engine == "deepl" ? "DeepL" : "苹果")
                    if item.usedCache { Text("缓存") }
                    if item.isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if editMode {
                if selected.contains(item.id) {
                    selected.remove(item.id)
                } else {
                    selected.insert(item.id)
                }
            } else {
                detailItem = item
            }
        }
    }

    private func refresh() {
        items = HistoryService.shared.fetch(keyword: keyword, favoritesOnly: favoritesOnly)
    }
}

// MARK: - 历史记录详情（重新查看 / 导出图片 / 导出TXT / 收藏 / 删除）
struct HistoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: AppStore.HistoryEntry
    let onRefresh: () -> Void

    @State private var showShareTXT = false
    @State private var txtContent = ""
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // 截图
                if let ui = AppStore.loadImage(item.overlayFile ?? item.imageFile) {
                    Image(uiImage: ui)
                        .resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                meta
                // 双语记录列表
                ForEach(Array(item.originals.enumerated()), id: \.offset) { i, original in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(original).font(.subheadline)
                        if i < item.deeplTexts.count {
                            Text("DeepL：\(item.deeplTexts[i])").font(.caption).foregroundStyle(.blue)
                        }
                        if i < item.appleTexts.count {
                            Text("苹果翻译：\(item.appleTexts[i])").font(.caption).foregroundStyle(.green)
                        }
                        Divider()
                    }
                }
            }
            .padding()
        }
        .navigationTitle("记录详情")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(item.isFavorite ? "取消收藏" : "收藏") {
                        HistoryService.shared.toggleFavorite(item)
                        onRefresh()
                    }
                    Button("导出图片到相册") { exportImage() }
                    Button("导出TXT（仅译文）") { exportTXT(compare: false) }
                    Button("导出TXT（双源对比）") { exportTXT(compare: true) }
                    Button("删除记录", role: .destructive) {
                        HistoryService.shared.delete(item)
                        onRefresh()
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showShareTXT) {
            ShareSheet(items: [txtContent])
        }
        .toast(message: $toast)
    }

    private var meta: some View {
        HStack {
            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
            Spacer()
            Text(item.engine == "deepl" ? "DeepL" : "苹果翻译")
            Text(item.usedCache ? "命中缓存" : "")
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func exportImage() {
        guard let img = AppStore.loadImage(item.overlayFile ?? item.imageFile) else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: img)
            } completionHandler: { ok, _ in
                DispatchQueue.main.async { toast = ok ? "已保存到相册" : "保存失败" }
            }
        }
    }

    private func exportTXT(compare: Bool) {
        txtContent = HistoryService.exportTXT(item, withCompare: compare)
        showShareTXT = true
    }
}

// MARK: - 系统分享面板（导出 TXT 用）
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
