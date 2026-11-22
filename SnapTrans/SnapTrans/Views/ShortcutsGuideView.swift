import SwiftUI

// MARK: - 快捷指令配置教程页（小白点一键截图翻译主流程）
struct ShortcutsGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                step(title: "第一步：创建快捷指令",
                     body: "打开系统「快捷指令」App → 右上角「+」新建 → 添加动作【截图】（系统动作）→ 再点添加动作，搜索「译拍通」，添加【翻译截图】→ 把「截图」的输出拖到「翻译截图」的输入（默认自动连接）→ 命名为「一键截图翻译」保存。")
                step(title: "第二步：绑定辅助触控（小白点）",
                     body: "设置 → 辅助功能 → 触控 → 辅助触控 → 打开开关 → 「自定操作」选择「单点」→ 下拉到「快捷指令」→ 选择「一键截图翻译」。完成后，在任意页面单击小白点即自动截图翻译。")
                step(title: "第三步（可选）：更多触发方式",
                     body: "① 轻点背面：设置 → 辅助功能 → 触控 → 轻点背面 → 轻点两下/三下 → 选「一键截图翻译」；② Siri：对 Siri 说「一键截图翻译」；③ 主屏幕图标：快捷指令详情页 → 添加到主屏幕。")
                note("触发后流程：系统截取当前页面 → 译拍通自动打开 → OCR 识别 → 翻译成中文 → 直接弹出译文叠加页。单次截图，不持续录屏。")
                note("首次运行快捷指令会请求授权，请允许（快捷指令 App 内点允许即可）。")
                note("若无法触发，检查：App「设置 → 快捷指令联动 → 允许外部触发翻译」开关是否开启；快捷指令里「翻译截图」动作是否正确接收到截图输入。")
                note("备选方案「画中画悬浮球」：开启后会浮窗于其他 App 之上，但点击会先弹播放控制条，再点暂停才触发翻译；窗口可双指捏合缩小。日常使用更推荐小白点方案。")
            }
            .padding()
        }
        .navigationTitle("快捷指令配置")
    }

    @ViewBuilder
    private func step(title: String, body text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    private func note(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.caption).foregroundStyle(.secondary)
    }
}
