import AppKit
import SwiftUI

struct ToolboxPage: View {
    var model: ToolboxModel
    var projectDirectory: URL?
    @Environment(\.palette) private var palette
    @State private var selection: ToolboxPlugin = .ports
    @State private var confirmPhone = false

    var body: some View {
        ZStack {
            HStack(alignment: .top, spacing: 0) {
                pluginList
                Rectangle()
                    .fill(palette.line)
                    .frame(width: 1)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if confirmPhone {
                PhoneEnableDialog(offersEnable: true) {
                    PhoneUseLocation.introSeen = true
                    model.setPlugin(.phone, enabled: true)
                } onClose: {
                    confirmPhone = false
                }
            }
        }
    }

    private var pluginList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("工具箱"))
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 4)
                pluginSection(L("项目跑起来"), ToolboxPlugin.allCases.filter(\.startsEnabled))
                pluginSection(L("按需启用"), ToolboxPlugin.allCases.filter { !$0.startsEnabled })
            }
            .padding(16)
        }
        .frame(width: 248)
        .onChange(of: selection) { _, plugin in
            if plugin == .phone, !model.enabledPlugins.contains(.phone) {
                confirmPhone = true
            }
        }
    }

    private func pluginSection(_ title: String, _ plugins: [ToolboxPlugin]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .textSecondaryStyle()
                .padding(.horizontal, 8)
            ForEach(plugins) { plugin in
                pluginRow(plugin)
            }
        }
    }

    private func pluginRow(_ plugin: ToolboxPlugin) -> some View {
        let on = model.enabledPlugins.contains(plugin)
        return HStack(spacing: 8) {
            Button {
                selection = plugin
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: plugin.icon)
                        .frame(width: 16)
                    Text(plugin.title)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 13, weight: selection == plugin ? .semibold : .regular))
                .foregroundStyle(on ? palette.ink : palette.textSecondary)
            }
            .buttonStyle(PlainPressStyle())
            Toggle("", isOn: Binding(
                get: { on },
                set: { update(plugin, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .help(on ? L("停用") : L("启用"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(selection == plugin ? palette.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 10))
    }

    private var detail: some View {
        FeatureHelpHost(reset: selection.rawValue) {
            Group {
                if model.enabledPlugins.contains(selection) {
                    ToolboxToolScreen(plugin: selection, model: model, projectDirectory: projectDirectory)
                } else {
                    disabledTool
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }

    private var disabledTool: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: selection.title, subtitle: selection.summary, help: helpText(selection))
            Text(L("这个工具默认没有打开。启用后会出现在左侧导航，版本管理不受影响。"))
                .font(.system(size: 13))
                .textSecondaryStyle()
            Button(L("启用%@", selection.title)) {
                update(selection, enabled: true)
            }
            .buttonStyle(TintCapsuleStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func update(_ plugin: ToolboxPlugin, enabled isOn: Bool) {
        if plugin == .phone, isOn, !model.enabledPlugins.contains(.phone) {
            confirmPhone = true
            return
        }
        model.setPlugin(plugin, enabled: isOn)
    }

    private func helpText(_ plugin: ToolboxPlugin) -> String {
        switch plugin {
        case .ports: FeatureHelp.ports
        case .processes: FeatureHelp.processes
        case .services: FeatureHelp.services
        case .hosts: FeatureHelp.hosts
        case .secrets: FeatureHelp.secrets
        case .git: FeatureHelp.git
        case .proxy: FeatureHelp.proxy
        case .snippets: FeatureHelp.snippets
        case .utilities: FeatureHelp.utilities
        case .images: FeatureHelp.images
        case .phone: FeatureHelp.phone
        case .machine:
            [
                L("本机把内存分布、卸载应用、清理缓存、启动磁盘和优化速度放在同一页。"),
                L("启用后，每一块标题旁都有问号，可以单独看它会做什么。"),
            ].joined(separator: "\n")
        }
    }
}

struct ToolboxToolScreen: View {
    var plugin: ToolboxPlugin
    var model: ToolboxModel
    var projectDirectory: URL?

    var body: some View {
        FeatureHelpHost(reset: plugin.rawValue) {
            switch plugin {
            case .ports:
                PortsTool(ownedPIDs: model.ownedPIDs)
            case .processes:
                ProcessesTool(ownedPIDs: model.ownedPIDs)
            case .services:
                ServicesTool(model: model, projectDirectory: projectDirectory)
            case .hosts:
                HostsTool(model: model)
            case .secrets:
                SecretsTool()
            case .git:
                GitTool()
            case .proxy:
                ProxyTool(model: model)
            case .snippets:
                SnippetsTool(model: model)
            case .utilities:
                UtilitiesTool(model: model)
            case .images:
                ImageTool()
            case .phone:
                PhoneTasksTool()
            case .machine:
                MachineCareTool()
            }
        }
    }
}

struct ToolTextField: View {
    var title: String
    @Binding var text: String
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .textSecondaryStyle()
            TextField(title, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(palette.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

enum LocalPasteboard {
    static func copy(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    static func string() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}
