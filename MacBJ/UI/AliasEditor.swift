import SwiftUI

struct AliasEditor: View {
    var aliases: [VersionAlias]
    @Binding var name: String
    @Binding var version: String
    var onAdd: () -> Void
    var onRemove: (VersionAlias) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("版本别名"))
                .font(.headline)
            Text(L("脚本里可以用这个名字代替版本号。default 仍然用「设为全局默认」。"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField(L("名称"), text: $name)
                TextField(L("版本"), text: $version)
                Button(L("添加"), action: onAdd)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || version.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if aliases.isEmpty {
                Text(L("还没有别名。"))
                    .foregroundStyle(.secondary)
            } else {
                List(aliases) { alias in
                    HStack {
                        Text(alias.name)
                        Spacer()
                        Text(alias.version)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                        Button(L("删除")) { onRemove(alias) }
                            .buttonStyle(PlainPressStyle())
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 280)
    }
}

struct HookConfirmView: View {
    var status: HookStatus
    var onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(status == .outdated ? L("更新目录切换") : L("启用目录切换"))
                .font(.headline)
            Text(L("写入前会把 ~/.zshrc 备份为 ~/.zshrc.macbj-bak。进入有 .nvmrc 或 .python-version 的目录时切到对应版本，离开后回到全局默认。已经打开的终端要新开一个，或再 cd 一次。"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(ShellHook.script)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            HStack {
                Spacer()
                Button(L("写入 ~/.zshrc"), action: onInstall)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

struct CommandOutputBar: View {
    var session: CommandSession
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.isRunning ? L("正在执行") : L("刚才执行的命令"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(session.command)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(4)
                .textSelection(.enabled)
            ScrollView {
                Text(session.output.isEmpty ? L("正在执行…") : session.output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 88)
            HStack {
                Spacer()
                if session.isRunning {
                    Button(session.isCancelling ? L("正在取消") : L("取消")) { session.cancel() }
                        .buttonStyle(TintCapsuleStyle())
                        .disabled(session.isCancelling)
                } else {
                    Button(L("关闭")) { session.dismiss() }
                        .buttonStyle(TintCapsuleStyle())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.line).frame(height: 1)
        }
    }
}
