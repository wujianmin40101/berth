import SwiftUI

enum CatalogStatus: String, CaseIterable, Identifiable {
    case all
    case installed
    case missing
    case lts
    case stable
    case deprecated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L("全部")
        case .installed: L("已安装")
        case .missing: L("未安装")
        case .lts: "LTS"
        case .stable: L("稳定")
        case .deprecated: L("已弃用")
        }
    }
}

enum CatalogScope: String, CaseIterable, Identifiable {
    case all
    case latestLine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L("全部发布")
        case .latestLine: L("各主版本最新")
        }
    }
}

struct VersionsPage: View {
    var model: AppModel
    @State private var query = ""
    @State private var status: CatalogStatus = .all
    @State private var scope: CatalogScope = .all
    @State private var visibleKind: RuntimeKind
    @State private var contentFading = false
    @State private var swapToken = 0
    /// 筛选结果。类实例放在 State 里，排序时改它的字段，不会让整页再刷新一遍。
    @State private var prepared = PreparedRows()
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: AppModel) {
        self.model = model
        _visibleKind = State(initialValue: model.selectedKind)
    }

    private var kind: RuntimeKind { visibleKind }

    private var snapshot: RuntimeSnapshot? { model.snapshots[kind] }

    private var source: [RuntimeVersion] {
        (snapshot?.versions ?? []).filter { $0.name != "system" }
    }

    private var rowKey: String {
        let revision = model.catalogRevision[kind] ?? 0
        return "\(kind.rawValue)|\(revision)|\(status.rawValue)|\(scope.rawValue)|\(query)"
    }

    private var rows: [RuntimeVersion] {
        let key = rowKey
        if prepared.key == key { return prepared.rows }
        let items = filteredRows()
        prepared.key = key
        prepared.rows = items
        prepared.latest = Self.newestName(in: source)
        return items
    }

    private var latestName: String? {
        if prepared.key == rowKey { return prepared.latest }
        return Self.newestName(in: source)
    }

    private func filteredRows() -> [RuntimeVersion] {
        var items = source
        if scope == .latestLine {
            items = latestPerLine(items)
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !needle.isEmpty {
            items = items.filter {
                $0.name.lowercased().contains(needle) || $0.title.lowercased().contains(needle)
            }
        }
        switch status {
        case .all:
            break
        case .installed:
            items = items.filter(\.isInstalled)
        case .missing:
            items = items.filter { !$0.isInstalled }
        case .lts:
            items = items.filter { $0.channel == .lts }
        case .stable:
            items = items.filter { $0.channel == .stable }
        case .deprecated:
            items = items.filter { $0.channel == .deprecated }
        }
        let ranked = items.map { RankedVersion(version: $0, parts: VersionOrder.parts($0.name)) }
        return ranked.sorted { VersionOrder.isNewer($0.parts, than: $1.parts) }.map(\.version)
    }

    private var current: RuntimeVersion? {
        snapshot?.versions.first(where: \.isCurrent)
    }

    private var canOperate: Bool {
        guard let snapshot else { return false }
        return snapshot.canSwitch && !model.session.isRunning && !model.switching.contains(kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PageHeader(title: L("版本"), subtitle: L("为下一次构建选对运行时。"))
            RuntimeKindBar(model: model)
            catalogBody
                .opacity(contentFading ? 0 : 1)
                .offset(y: contentFading && !reduceMotion ? 4 : 0)
                .animation(nil, value: visibleKind)
                .allowsHitTesting(!contentFading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onChange(of: model.selectedKind) { _, next in
            present(next)
        }
        .padding(.horizontal, 28)
        .padding(.top, 2)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var catalogBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let failure = model.failures[kind] {
                failureBanner(failure)
            }
            if let notice = model.projectNotice {
                Text(notice)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            globalCard
            catalogHeader
            catalogTools
            GeometryReader { proxy in
                catalogTable()
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
        }
    }

    private func present(_ next: RuntimeKind) {
        swapToken += 1
        let token = swapToken
        guard next != visibleKind else {
            withAnimation(fadeIn) { contentFading = false }
            return
        }
        withAnimation(fadeOut) { contentFading = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard swapToken == token else { return }
            var swap = Transaction()
            swap.disablesAnimations = true
            withTransaction(swap) { visibleKind = next }
            DispatchQueue.main.async {
                guard swapToken == token else { return }
                withAnimation(fadeIn) { contentFading = false }
            }
        }
    }

    private var fadeOut: Animation {
        reduceMotion ? .linear(duration: 0.12) : .timingCurve(0.22, 1, 0.36, 1, duration: 0.18)
    }

    private var fadeIn: Animation {
        reduceMotion ? .linear(duration: 0.12) : .timingCurve(0.16, 1, 0.3, 1, duration: 0.2)
    }

    private var globalCard: some View {
        Group {
            if snapshot == nil {
                cardSkeleton
            } else {
                cardDetails
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var cardDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Text(kind.monogram)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.ink)
                    .frame(width: 52, height: 52)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel(kind.title)

                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.map { L("%@ · 全局环境", $0.backend.title) } ?? L("全局环境"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .help(snapshot?.backend.footnote ?? "")
                    HStack(spacing: 8) {
                        Text(current.map(catalogTitle) ?? (snapshot == nil ? "—" : L("未设置")))
                            .font(.system(size: 30, weight: .bold))
                            .accessibilityIdentifier("global-version")
                        if current != nil {
                            Text(L("当前"))
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(palette.accent, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    if let footnote = snapshot?.backend.footnote, !footnote.isEmpty {
                        Text(footnote)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help(footnote)
                    }
                }
                statBox(value: countText(source.filter(\.isInstalled).count), label: L("已安装"))
                    .fixedSize()
                statBox(value: countText(source.count), label: L("版本"))
                    .fixedSize()
            }

            if snapshot?.remoteFailed == true {
                HStack(spacing: 10) {
                    Text(L("远端版本目录没有读到。"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if (model.mirrors[kind] ?? .official) == .official {
                        Button(L("改用国内镜像")) {
                            model.setMirror(.china, for: kind)
                        }
                        .buttonStyle(TintCapsuleStyle())
                    }
                }
            }
        }
    }

    private var cardSkeleton: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.surface.opacity(0.72))
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 8) {
                skeletonBone(width: 88, height: 10)
                skeletonBone(width: 148, height: 22, radius: 7)
                skeletonBone(width: 240, height: 10)
            }
            skeletonBone(width: 96, height: 52, radius: 14)
            skeletonBone(width: 96, height: 52, radius: 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay { DiagonalSweep(active: model.loading.contains(kind) && !reduceMotion) }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("正在读取版本目录"))
    }

    private var catalogHeader: some View {
        HStack(spacing: 8) {
            Text(L("版本目录"))
                .font(.system(size: 16, weight: .semibold))
            Text(catalogCount)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var catalogCount: String {
        guard snapshot != nil else { return "—" }
        let filtered = rows.count != source.count || scope != .all || status != .all || !query.isEmpty
        if filtered {
            return L("%lld / %lld 个版本", rows.count, source.count)
        }
        return L("%lld 个版本", source.count)
    }

    private var catalogTools: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L("搜索版本"), text: $query)
                    .textFieldStyle(.plain)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 220)
            .background(palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            filterMenu(
                title: status == .all ? L("状态") : status.title,
                icon: "line.3.horizontal.decrease",
                options: CatalogStatus.allCases.map { ($0.title, $0 == status) },
                select: { index in status = CatalogStatus.allCases[index] }
            )

            filterMenu(
                title: L("视图"),
                icon: "square.grid.2x2",
                options: CatalogScope.allCases.map { ($0.title, $0 == scope) },
                select: { index in scope = CatalogScope.allCases[index] }
            )

            Button {
                query = ""
                status = .all
                scope = .all
                model.refresh(kind)
            } label: {
                Label(L("刷新"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(FieldMenuStyle())
            .disabled(model.loading.contains(kind))
            .keyboardShortcut("r", modifiers: .command)
            .help(L("重新读取版本目录。终端执行 nvmd 之后，点这里才会更新显示。"))

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func catalogTable() -> some View {
        Group {
            if snapshot == nil {
                tablePlaceholder()
            } else {
                filledTable()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if model.loading.contains(kind), snapshot != nil, !reduceMotion {
                DiagonalSweep(active: true)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.line)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func filledTable() -> some View {
        let visible = rows
        let newest = latestName
        return VStack(spacing: 0) {
            columnHeader()
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 40)
                .background(palette.field.opacity(0.7))

            if visible.isEmpty {
                Text(query.isEmpty ? L("这个筛选下没有版本。") : L("没有匹配的版本。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { version in
                            catalogRow(version, newest: newest)
                            Rectangle()
                                .fill(palette.line)
                                .frame(height: 1)
                                .padding(.leading, 16)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func tablePlaceholder() -> some View {
        VStack(spacing: 0) {
            columnHeader()
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 40)
                .background(palette.field.opacity(0.7))
                .opacity(0.45)

            if snapshot == nil, !model.loading.contains(kind) {
                Text(L("还没有版本数据"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { _ in
                        skeletonRow()
                        Rectangle()
                            .fill(palette.line)
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .overlay { DiagonalSweep(active: !reduceMotion) }
                .clipped()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("正在读取版本目录"))
            }
        }
    }

    private func skeletonRow() -> some View {
        let columns = kind == .node ? 6 : 4
        return HStack(spacing: 0) {
            ForEach(0..<columns, id: \.self) { column in
                Group {
                    if column == columns - 1 {
                        Capsule()
                            .fill(palette.field)
                            .frame(width: 72, height: 28)
                    } else {
                        skeletonBone(width: column == 0 ? 88 : 56, height: 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: column == columns - 1 ? .trailing : .leading)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private func skeletonBone(width: CGFloat, height: CGFloat, radius: CGFloat = 6) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(palette.field)
            .frame(width: width, height: height)
    }

    @ViewBuilder
    private func columnHeader() -> some View {
        if kind == .node {
            EqualColumns {
                headerLabel(L("版本"))
                headerLabel("V8")
                headerLabel("NPM")
                headerLabel(L("发布日期"))
                headerLabel(L("状态"))
                headerLabel(L("操作"), trailing: true)
            }
        } else {
            EqualColumns {
                headerLabel(L("版本"))
                headerLabel(L("通道"))
                headerLabel(L("状态"))
                headerLabel(L("操作"), trailing: true)
            }
        }
    }

    private func headerLabel(_ title: String, trailing: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.trailing, trailing ? 4 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: trailing ? .trailing : .leading)
    }

    private func catalogRow(_ version: RuntimeVersion, newest: String?) -> some View {
        Group {
            if kind == .node {
                EqualColumns {
                    versionCell(version, newest: newest)
                    metaText(version.v8)
                    metaText(version.npm)
                    metaText(NodeIndex.displayDate(version.releasedOn))
                    statusCell(version)
                    operationCell(version)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                EqualColumns {
                    versionCell(version, newest: newest)
                    metaText(version.channel == .unknown ? "—" : version.channel.title)
                    statusCell(version)
                    operationCell(version)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(model.selection[kind] == version.id ? palette.accentSoft.opacity(0.45) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            model.selection[kind] = version.id
        }
        .accessibilityElement(children: .combine)
    }

    private func versionCell(_ version: RuntimeVersion, newest: String?) -> some View {
        HStack(spacing: 6) {
            Text(catalogTitle(version))
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            if version.name == newest {
                Text(L("最新"))
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(palette.accentSoft, in: Capsule())
                    .foregroundStyle(palette.accent)
            }
            if kind == .node, version.channel != .unknown {
                Text(version.channel.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func metaText(_ value: String?) -> some View {
        Text((value?.isEmpty == false ? value : nil) ?? "—")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func statusCell(_ version: RuntimeVersion) -> some View {
        let installed = version.isInstalled
        let symbol = version.isCurrent ? "checkmark.circle.fill" : (installed ? "checkmark.circle" : "circle")
        let label = version.isCurrent ? L("当前") : (installed ? L("已安装") : L("未安装"))
        return HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(label)
        }
        .font(.system(size: 13))
        .foregroundStyle(version.isCurrent ? palette.accent : Color.secondary)
    }

    private func operationCell(_ version: RuntimeVersion) -> some View {
        HStack(spacing: 6) {
            if version.isCurrent {
                Text(L("使用中"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    model.selection[kind] = version.id
                    model.performPrimary(kind)
                } label: {
                    Label(version.isInstalled ? L("使用") : L("安装"), systemImage: version.isInstalled ? "checkmark" : "square.and.arrow.down")
                }
                .buttonStyle(TintCapsuleStyle())
                .disabled(!canOperate)
            }

            if version.isInstalled {
                Menu {
                    Button(model.projectDirectory.map { L("绑定到 %@", $0.lastPathComponent) } ?? L("绑定到项目")) {
                        model.selection[kind] = version.id
                        model.requestBind(kind, version: version.name)
                    }
                    Button(L("卸载"), role: .destructive) {
                        model.selection[kind] = version.id
                        model.requestUninstall(kind)
                    }
                    .disabled(!canOperate)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .semibold))
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(width: 96, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func failureBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(L("关闭")) { model.failures[kind] = nil }
                .buttonStyle(PlainPressStyle())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.accent)
        }
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func filterMenu(
        title: String,
        icon: String,
        options: [(String, Bool)],
        select: @escaping (Int) -> Void
    ) -> some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    select(index)
                } label: {
                    if option.1 {
                        Label(option.0, systemImage: "checkmark")
                    } else {
                        Text(option.0)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .buttonStyle(FieldMenuStyle())
        .fixedSize()
    }

    private func countText(_ count: Int) -> String {
        snapshot == nil ? "—" : "\(count)"
    }

    private func latestPerLine(_ versions: [RuntimeVersion]) -> [RuntimeVersion] {
        var best: [String: RankedVersion] = [:]
        for version in versions {
            let key = lineKey(version)
            let ranked = RankedVersion(version: version, parts: VersionOrder.parts(version.name))
            if let existing = best[key], !VersionOrder.isNewer(ranked.parts, than: existing.parts) {
                continue
            }
            best[key] = ranked
        }
        return best.values.map(\.version)
    }

    private func lineKey(_ version: RuntimeVersion) -> String {
        if kind == .python || kind == .go || kind == .rust, let minor = VersionOrder.minorKey(version.name) {
            return minor
        }
        if let major = VersionOrder.major(version.name) {
            return "\(major)"
        }
        return version.name
    }

    private static func newestName(in versions: [RuntimeVersion]) -> String? {
        var bestName: String?
        var bestParts: [Int] = []
        for version in versions {
            let parts = VersionOrder.parts(version.name)
            if bestName == nil || VersionOrder.isNewer(parts, than: bestParts) {
                bestName = version.name
                bestParts = parts
            }
        }
        return bestName
    }
}

private final class PreparedRows {
    var key = ""
    var rows: [RuntimeVersion] = []
    var latest: String?
}

private struct RankedVersion {
    var version: RuntimeVersion
    var parts: [Int]
}

private struct RuntimeKindBar: View {
    var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tabFrames: [RuntimeKind: CGRect] = [:]
    @State private var pillMoves = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(RuntimeKind.allCases) { item in
                    Button(item.title) {
                        model.selectedKind = item
                    }
                    .buttonStyle(RuntimePickStyle(selected: model.selectedKind == item))
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: RuntimeTabFrames.self,
                                value: [item: proxy.frame(in: .named("runtimeTabs"))]
                            )
                        }
                    }
                    .accessibilityAddTraits(model.selectedKind == item ? .isSelected : [])
                    .onKeyPress(.leftArrow) {
                        stepKind(-1)
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        stepKind(1)
                        return .handled
                    }
                }
            }
            .padding(3)
            .coordinateSpace(name: "runtimeTabs")
            .onPreferenceChange(RuntimeTabFrames.self) { frames in
                guard !tabFrames.matches(frames) else { return }
                tabFrames = frames
            }
            .background(alignment: .topLeading) {
                if let rect = tabFrames[model.selectedKind], rect.width > 1 {
                    Capsule()
                        .fill(palette.surface)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                        .animation(
                            pillMoves && !reduceMotion ? .timingCurve(0.16, 1, 0.3, 1, duration: 0.26) : nil,
                            value: model.selectedKind
                        )
                }
            }
            .background(palette.field, in: Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L("运行时"))

            if let selected = model.snapshots[model.selectedKind] {
                Text(selected.backend.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Button {
                model.refresh(model.selectedKind)
            } label: {
                Label(L("更新数据"), systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(TintCapsuleStyle())
            .disabled(model.loading.contains(model.selectedKind))
            Spacer(minLength: 0)
        }
        .onAppear {
            DispatchQueue.main.async { pillMoves = true }
        }
    }

    private func stepKind(_ delta: Int) {
        let kinds = Array(RuntimeKind.allCases)
        guard let index = kinds.firstIndex(of: model.selectedKind) else { return }
        let next = (index + delta + kinds.count) % kinds.count
        model.selectedKind = kinds[next]
    }
}

private struct EqualColumns: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let column = width / CGFloat(max(subviews.count, 1))
        let height = subviews
            .map { $0.sizeThatFits(ProposedViewSize(width: column, height: proposal.height)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let column = bounds.width / CGFloat(max(subviews.count, 1))
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + CGFloat(index) * column, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: column, height: bounds.height)
            )
        }
    }
}

private struct RuntimeTabFrames: PreferenceKey {
    static var defaultValue: [RuntimeKind: CGRect] = [:]

    static func reduce(
        value: inout [RuntimeKind: CGRect],
        nextValue: () -> [RuntimeKind: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private extension Dictionary where Key == RuntimeKind, Value == CGRect {
    func matches(_ other: [RuntimeKind: CGRect]) -> Bool {
        guard count == other.count else { return false }
        for (key, rect) in self {
            guard let next = other[key],
                  abs(rect.minX - next.minX) < 0.5,
                  abs(rect.minY - next.minY) < 0.5,
                  abs(rect.width - next.width) < 0.5,
                  abs(rect.height - next.height) < 0.5 else {
                return false
            }
        }
        return true
    }
}

private struct RuntimePickStyle: ButtonStyle {
    var selected: Bool
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? palette.ink : Color.secondary)
            .pressFeedback(pressed: configuration.isPressed)
    }
}
