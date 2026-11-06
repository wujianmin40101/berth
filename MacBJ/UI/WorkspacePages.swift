import SwiftUI

struct ProjectsPage: View {
    var model: AppModel
    @Binding var chooseProject: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: L("项目"),
                    subtitle: L("每个目录各自记住版本。可以新增、移除，选中后再绑定。")
                )

                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Text(L("项目"))
                                .font(.system(size: 13, weight: .semibold))
                            Spacer(minLength: 8)
                            Button(L("新增项目")) { chooseProject = true }
                                .buttonStyle(TintCapsuleStyle())
                        }
                        if model.projects.isEmpty {
                            Text(L("还没有项目。新增一个目录后，可以分别绑定 Node、Python、Go、Java 和 Rust。"))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(model.projects) { record in
                                projectRow(record)
                                if record.path != model.projects.last?.path {
                                    Rectangle().fill(palette.line).frame(height: 1)
                                }
                            }
                        }
                    }
                }

                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Text(L("版本绑定"))
                                .font(.system(size: 13, weight: .semibold))
                            Spacer(minLength: 8)
                            Button(L("刷新")) { model.reloadPins() }
                                .buttonStyle(FieldMenuStyle())
                                .help(L("重新读取项目里的版本文件。终端执行 nvmd use --project 之后，点这里才会更新显示。"))
                        }
                        Text(L("Node 写入 .nvmrc，Python 写入 .python-version，Go、Java、Rust 分别写入 .go-version、.java-version、.rust-version。pyproject.toml 里的版本要求只读。"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        if let notice = model.projectNotice {
                            Text(notice)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(palette.accent)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(RuntimeKind.allCases) { kind in
                            pinRow(kind)
                            if kind != RuntimeKind.allCases.last {
                                Rectangle().fill(palette.line).frame(height: 1)
                            }
                        }
                    }
                }

                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("进入目录自动切换"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(hookDetail)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(model.hookStatus.title) { model.showHook = true }
                            .buttonStyle(TintCapsuleStyle())
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }

    private var hookDetail: String {
        switch model.hookStatus {
        case .missing:
            L("还没有写进 ~/.zshrc。写上之后，cd 进有版本文件的目录会切换，离开后恢复全局。")
        case .installed:
            L("已经写进 ~/.zshrc。新开一个终端后才会生效。")
        case .outdated:
            L("shell 里的脚本比现在这份旧。更新后，新开的终端会用新脚本。")
        }
    }

    private func pinRow(_ kind: RuntimeKind) -> some View {
        let installed = (model.snapshots[kind]?.versions ?? []).filter { $0.isInstalled && $0.name != "system" }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(pinSummary(kind))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            bindControl(kind, installed: installed)
        }
        .padding(.vertical, 4)
    }

    private func projectRow(_ record: ProjectRecord) -> some View {
        let selected = model.selectedProjectPath == record.path
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected ? palette.accent : Color.primary)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.accent)
                    }
                }
                Text(record.path)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(model.projectSummaries[record.path] ?? L("还没有绑定"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(L("移除")) { model.removingProject = record }
                .buttonStyle(PlainPressStyle())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(selected ? palette.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { model.selectProject(path: record.path) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(record.name)
    }

    private func bindControl(_ kind: RuntimeKind, installed: [RuntimeVersion]) -> some View {
        Group {
            if model.projectDirectory == nil {
                Button(L("绑定")) { model.bindPrompt = .needProject }
                    .buttonStyle(TintCapsuleStyle())
            } else {
                Menu {
                    if installed.isEmpty {
                        Button(L("还没有已安装的版本")) {}
                            .disabled(true)
                    } else {
                        ForEach(installed) { version in
                            Button(catalogTitle(version)) {
                                model.requestBind(kind, version: version.name)
                            }
                        }
                    }
                } label: {
                    Text(L("绑定"))
                }
                .buttonStyle(TintCapsuleStyle())
                .help(L("选择版本后会先确认，再写入当前项目。"))
            }
        }
    }

    private func pinSummary(_ kind: RuntimeKind) -> String {
        guard model.projectDirectory != nil else { return L("先选择项目") }
        guard let pin = model.pins[kind] else { return L("这个项目没有绑定") }
        let mode = pin.writable ? "" : L("，只读")
        return L("%@ · %@%@", pin.fileName, pin.version, mode)
    }
}

struct SettingsPage: View {
    var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: L("设置"),
                    subtitle: L("镜像只影响这里发起的安装，不会改你的 shell 配置。")
                )

                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("语言"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(L("默认和这台 Mac 的语言一致。也可以固定为中文或英文。"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        LanguageSegment()
                    }
                }

                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("命令行"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(L("nvmd install、list、use、current、uninstall、which。use --project 把版本写进当前目录的 .nvmrc。"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L("命令在 ~/.local/bin/nvmd。终端改完后，版本页和项目页要点「刷新」才会更新显示。"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L("镜像源"))
                            .font(.system(size: 13, weight: .semibold))
                        ForEach(RuntimeKind.allCases) { kind in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(kind.title)
                                    .font(.system(size: 13, weight: .medium))
                                Picker(kind.title, selection: mirrorBinding(kind)) {
                                    ForEach(MirrorChoice.allCases) { choice in
                                        Text(mirrorLabel(choice, kind: kind)).tag(choice)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                            }
                        }
                        Text(L("Node 国内源是 npmmirror，Python 是清华源或 npmmirror，Go 是 golang.google.cn，Java 是清华 Adoptium，Rust 是中科大。Volta 不使用这个镜像。"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("别名"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(L("给版本起一个名字，脚本和目录切换都能用。default 仍然表示全局默认。"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(RuntimeKind.allCases) { kind in
                                Button(L("%@ 别名", kind.title)) {
                                    model.selectedKind = kind
                                    model.showAliases = true
                                }
                                .buttonStyle(TintCapsuleStyle())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }

    private func mirrorBinding(_ kind: RuntimeKind) -> Binding<MirrorChoice> {
        Binding(
            get: { model.mirrors[kind] ?? .official },
            set: { model.setMirror($0, for: kind) }
        )
    }

    private func mirrorLabel(_ choice: MirrorChoice, kind: RuntimeKind) -> String {
        switch (kind, choice) {
        case (.node, .china): "npmmirror"
        case (.python, .china): L("清华 / npmmirror")
        case (.go, .china): "golang.google.cn"
        case (.java, .china): L("清华")
        case (.rust, .china): L("中科大")
        case (_, .official): L("官方")
        case (_, .china): L("国内")
        }
    }
}
