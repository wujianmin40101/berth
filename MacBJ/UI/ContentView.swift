import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model: AppModel
    @State private var toolbox = ToolboxModel()
    @State private var chooseProject = false
    @State private var page: WorkspacePage = .versions
    @State private var navForward = true
    @State private var theme: ColorScheme? = AppearanceStore.saved
    @State private var themeHost = ThemeHost()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: AppModel = AppModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        let resolved = theme ?? colorScheme
        let palette = WorkspacePalette(scheme: resolved)
        HStack(spacing: 0) {
            WorkspaceRailColumn(
                page: Binding(get: { page }, set: { show($0) }),
                tools: ToolboxPlugin.allCases.filter { toolbox.enabledPlugins.contains($0) },
                isDark: resolved == .dark,
                host: themeHost,
                toggleTheme: toggleTheme
            )
            .zIndex(1)
            WorkspaceStage(
                page: page,
                forward: navForward,
                model: model,
                toolbox: toolbox,
                chooseProject: $chooseProject
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(palette.canvas)
        .environment(\.palette, palette)
        .environment(\.locale, LanguageStore.shared.locale)
        .preferredColorScheme(theme)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                WorkspaceBreadcrumb(page: page, palette: palette)
                    .environment(\.colorScheme, resolved)
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.session.isPresented {
                CommandOutputBar(session: model.session)
            }
        }
        .task {
            guard model.loadsOnAppear else { return }
            model.refreshAll()
        }
        .onChange(of: toolbox.enabledPlugins) { _, plugins in
            guard case .tool(let plugin) = page, !plugins.contains(plugin) else { return }
            show(.toolbox)
        }
        .fileImporter(isPresented: $chooseProject, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                model.addProject(url)
                show(.projects)
            }
        }
        .alert(
            L("绑定版本"),
            isPresented: Binding(
                get: { model.bindPrompt != nil },
                set: { if !$0 { model.bindPrompt = nil } }
            ),
            presenting: model.bindPrompt
        ) { prompt in
            switch prompt {
            case .needProject:
                Button(L("新增项目")) {
                    show(.projects)
                    chooseProject = true
                }
                Button(L("取消"), role: .cancel) {}
            case .confirm(let kind, let version):
                Button(L("绑定")) { model.writeProjectPin(kind, version: version) }
                Button(L("取消"), role: .cancel) {}
            }
        } message: { prompt in
            switch prompt {
            case .needProject:
                Text(L("还没有选中的项目。新增一个目录后，才能把版本写进去。"))
            case .confirm(let kind, let version):
                let folder = model.projectDirectory?.lastPathComponent ?? L("项目")
                let file = ProjectPins.fileName(for: kind) ?? L("版本文件")
                Text(L("把 %@ %@ 写入「%@」的 %@。", kind.title, version, folder, file))
            }
        }
        .alert(
            L("从列表移除项目"),
            isPresented: Binding(
                get: { model.removingProject != nil },
                set: { if !$0 { model.removingProject = nil } }
            ),
            presenting: model.removingProject
        ) { record in
            Button(L("移除"), role: .destructive) { model.removeProject(record) }
            Button(L("取消"), role: .cancel) {}
        } message: { record in
            Text(L("只从列表里去掉「%@」。磁盘上的目录和版本文件都会保留。", record.name))
        }
        .confirmationDialog(L("卸载当前默认版本"), isPresented: $model.confirmUninstall, titleVisibility: .visible) {
            Button(L("仍要卸载"), role: .destructive) { model.uninstallSelected() }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("这是新终端会使用的版本。卸载后，离开项目目录时可能没有这个运行时。"))
        }
        .sheet(isPresented: $model.showAliases) {
            AliasEditor(
                aliases: model.aliases[model.selectedKind] ?? [],
                name: $model.aliasName,
                version: $model.aliasVersion,
                onAdd: model.addAlias,
                onRemove: model.removeAlias
            )
        }
        .sheet(isPresented: $model.showHook) {
            HookConfirmView(status: model.hookStatus, onInstall: model.installHook)
        }
    }

    private func toggleTheme() {
        let current = theme ?? colorScheme
        let next: ColorScheme = current == .dark ? .light : .dark
        guard themeHost.curtain == nil else { return }
        guard !reduceMotion,
              let button = themeHost.button,
              let window = button.window,
              let surface = window.contentView?.superview ?? window.contentView,
              let image = ThemeCapture.cgImage(of: surface)
        else {
            theme = next
            AppearanceStore.save(next)
            return
        }
        let curtain = ThemeCurtainView(frame: surface.bounds)
        curtain.autoresizingMask = [.width, .height]
        surface.addSubview(curtain)
        let center = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: curtain)
        let endRadius = hypot(
            max(center.x, curtain.bounds.width - center.x),
            max(center.y, curtain.bounds.height - center.y)
        ) + 8
        curtain.prepare(
            image: image,
            center: center,
            endRadius: endRadius,
            expanding: next == .dark
        )
        themeHost.curtain = curtain
        curtain.onFinish = { [themeHost] in
            themeHost.curtain = nil
        }
        theme = next
        AppearanceStore.save(next)
        curtain.play()
    }

    private func show(_ next: WorkspacePage) {
        guard next != page else { return }
        let transaction = Transaction(animation: pageAnimation)
        withTransaction(transaction) {
            navForward = navIndex(next) >= navIndex(page)
            page = next
        }
    }

    /// 往下点，新页面从右侧进来；往上点则反过来。减弱动态效果时只做淡入淡出。
    private var pageAnimation: Animation {
        reduceMotion ? Motion.reduced : Motion.pageIn
    }

    private func navIndex(_ item: WorkspacePage) -> Int {
        switch item {
        case .versions: 0
        case .projects: 1
        case .toolbox: 2
        case .tool(let plugin):
            3 + (ToolboxPlugin.allCases.firstIndex(of: plugin) ?? 0)
        case .settings: 80
        }
    }
}

private struct WorkspaceStage: View {
    var page: WorkspacePage
    var forward: Bool
    var model: AppModel
    var toolbox: ToolboxModel
    @Binding var chooseProject: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            pageContent
                .id(page)
                .transition(pageMove)
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private var pageMove: AnyTransition {
        let travel: CGFloat = reduceMotion ? 0 : 12
        let insertion = AnyTransition.modifier(
            active: PageSlide(opacity: 0, x: forward ? travel : -travel),
            identity: PageSlide(opacity: 1, x: 0)
        )
        .animation(reduceMotion ? Motion.reduced : Motion.pageIn)
        let removal = AnyTransition.modifier(
            active: PageSlide(opacity: 0, x: forward ? -travel : travel),
            identity: PageSlide(opacity: 1, x: 0)
        )
        .animation(reduceMotion ? Motion.reduced : Motion.pageOut)
        return .asymmetric(insertion: insertion, removal: removal)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .versions:
            VersionsPage(model: model)
        case .projects:
            ProjectsPage(model: model, chooseProject: $chooseProject)
        case .toolbox:
            ToolboxPage(model: toolbox, projectDirectory: model.projectDirectory)
        case .tool(let plugin):
            ToolboxToolScreen(plugin: plugin, model: toolbox, projectDirectory: model.projectDirectory)
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .settings:
            SettingsPage(model: model)
        }
    }
}

private struct PageSlide: ViewModifier, @preconcurrency Animatable {
    var opacity: Double
    var x: CGFloat

    var animatableData: AnimatablePair<Double, CGFloat> {
        get { AnimatablePair(opacity, x) }
        set {
            opacity = newValue.first
            x = newValue.second
        }
    }

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(x: x)
    }
}

enum AppearanceStore {
    private static let key = "macbj.appearance"

    static var saved: ColorScheme? {
        switch UserDefaults.standard.string(forKey: key) {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }

    static func save(_ scheme: ColorScheme) {
        UserDefaults.standard.set(scheme == .dark ? "dark" : "light", forKey: key)
    }
}

#Preview {
    ContentView(model: .preview)
}
