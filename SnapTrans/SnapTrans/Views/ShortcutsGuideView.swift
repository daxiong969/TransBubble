import SwiftUI

// MARK: - 快捷指令配置教程页
struct ShortcutsGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                step(title: "第一步：添加快捷指令",
                     body: "打开系统「快捷指令」App → 「+」新建 → 搜索并添加 App 动作「一键截图翻译」（译拍通提供）→ 命名保存。")
                step(title: "第二步：绑定辅助触控（小白点）",
                     body: "设置 → 辅助功能 → 触控 → 辅助触控 → 打开开关 → 自定义顶层菜单 → 添加一个图标并选择「快捷指令」→ 选择刚创建的「一键截图翻译」。之后点击小白点即可一键截图翻译。")
                step(title: "第三步（可选）：Siri / 双击背面触发",
                     body: "也可以把该快捷指令绑定到：Siri（说\"截图翻译\"）、设置 → 辅助功能 → 触控 → 轻点背面（轻点两下触发）。")
                note("触发逻辑与悬浮球一致：单次截图 → OCR → 翻译，不会持续录屏。")
                note("若快捷指令无法触发，请检查：设置页「允许快捷指令/小白点外部触发翻译」开关是否开启；快捷指令 App 是否已授予译拍通权限。")
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
