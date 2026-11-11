import AppKit
import SwiftUI

struct CacheCleanTool: View {
    @State private var targets: [CacheTarget] = []
    @State private var loading = false
    @State private var cleaning = false
    @State private var message = ""
    @State private var confirm = false

    private var selected: [CacheTarget] { targets.filter(\.selected) }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(
                title: L("清理缓存"),
                subtitle: L("只清理可以重新生成的缓存、日志和废纸篓。个人文件不在这里。"),
                help: FeatureHelp.caches,
                actionTitle: L("刷新"),
                actionIcon: "arrow.clockwise",
                actionDisabled: loading || cleaning
            ) {
                Task { await reload() }
            }
            if !message.isEmpty {
                Text(message).font(.system(size: 12)).textSecondaryStyle()
            }
            WorkspacePanel {
                VStack(alignment: .leading, spacing: 10) {
                    if targets.isEmpty, !loading {
                        Text(L("没有找到可清理的内容。"))
                            .font(.system(size: 13))
                            .textSecondaryStyle()
                    }
                    if loading, targets.isEmpty {
                        Text(L("正在统计缓存、日志和废纸篓。"))
                            .font(.system(size: 13))
                            .textSecondaryStyle()
                    }
                    ForEach($targets) { $target in
                        Toggle(isOn: $target.selected) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(target.title)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(target.detail)
                                        .font(.system(size: 12))
                                        .textSecondaryStyle()
                                }
                                Spacer()
                                Text(target.pending ? L("计算中") : (target.partial ? L("约 ") : "") + ByteText.string(target.bytes))
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .textSecondaryStyle()
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                    Button(cleaning ? L("正在清理") : L("清理选中")) { confirm = true }
                        .buttonStyle(TintCapsuleStyle())
                        .disabled(selected.isEmpty || cleaning || selected.contains(where: \.pending))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(L("清理选中的内容"), isPresented: $confirm, titleVisibility: .visible) {
            Button(L("清理"), role: .destructive) { Task { await clean() } }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(selected.isEmpty ? "" : L("将删除：%@。这些内容可以重新生成。", selected.map(\.title).joined(separator: L("、"))))
        }
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        let found = await Task.detached { CacheClean.existing() }.value
        targets = found
        loading = false
        let ids = found.map(\.id)
        let control = AllocatedSize.ScanControl()
        await withTaskCancellationHandler {
            await withTaskGroup(of: (String, UInt64, Bool).self) { group in
                var next = 0
                for _ in 0..<min(2, ids.count) {
                    let id = ids[next]
                    next += 1
                    group.addTask {
                        let measured = await Task.detached { CacheClean.measure(id: id, control: control) }.value
                        return (id, measured.bytes, measured.complete)
                    }
                }
                for await item in group {
                    if Task.isCancelled { break }
                    if let index = targets.firstIndex(where: { $0.id == item.0 }) {
                        targets[index].bytes = item.1
                        targets[index].partial = !item.2
                        targets[index].pending = false
                    }
                    if next < ids.count {
                        let id = ids[next]
                        next += 1
                        group.addTask {
                            let measured = await Task.detached { CacheClean.measure(id: id, control: control) }.value
                            return (id, measured.bytes, measured.complete)
                        }
                    }
                }
            }
        } onCancel: {
            control.stop()
        }
    }

    private func clean() async {
        let ids = Set(selected.map(\.id))
        cleaning = true
        do {
            let freed = try await Task.detached { try CacheClean.clean(ids: ids) }.value
            message = L("已清理 %@。", ByteText.string(freed))
        } catch let error as ToolError {
            message = error.text
        } catch {
            message = error.localizedDescription
        }
        cleaning = false
        await reload()
    }
}
