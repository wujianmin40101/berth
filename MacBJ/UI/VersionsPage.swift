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
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: L("版本"), subtitle: L("为下一次构建选对运行时。"))
                .openingBlock(0)
            RuntimeKindBar(model: model)
                .openingBlock(1)
            catalogBody
                .opacity(contentFading ? 0 : 1)
                .animation(nil, value: visibleKind)
                .allowsHitTesting(!contentFading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onChange(of: model.selectedKind) { _, next in
            present(next)
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var catalogBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let failure = model.failures[kind] {
                failureBanner(failure)
                    .openingBlock(2)
            }
            if let notice = model.projectNotice {
                Text(notice)
                    .font(.system(size: 12))
                    .textSecondaryStyle()
                    .fixedSize(horizontal: false, vertical: true)
                    .openingBlock(2)
            }
            globalCard
                .openingBlock(1)
            VStack(alignment: .leading, spacing: 8) {
                catalogHeader
                catalogTools
                    .openingBlock(1)
                GeometryReader { proxy in
                    VersionCatalogTable(
                        model: model,
                        kind: kind,
                        snapshot: snapshot,
                        rows: rows,
                        latestName: latestName,
                        query: query,
                        canOperate: canOperate
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .openingBlock(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.08 : 0.16)) {
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
        reduceMotion ? Motion.reduced : Motion.exit
    }

    private var fadeIn: Animation {
        reduceMotion ? Motion.reduced : Motion.enter
    }

    private var managerMissing: Bool {
        snapshot?.backend == .missing && !kind.usesOfficialArchive
    }

    private var globalCard: some View {
        WorkspacePanel {
            Group {
                if snapshot == nil {
                    cardSkeleton
                } else {
                    cardDetails
                }
            }
        }
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
                        .font(.system(size: 12))
                        .textSecondaryStyle()
                        .help(snapshot?.backend.footnote ?? "")
                    HStack(spacing: 8) {
                        Text(current.map(catalogTitle) ?? (snapshot == nil ? "—" : L("未设置")))
                            .font(.system(size: 30, weight: .bold))
                            .accessibilityIdentifier("global-version")
                        if current != nil {
                            Text(L("当前"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.accentInk)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(palette.accentSoft, in: Capsule())
                        }
                    }
                    if managerMissing {
                        Text(kind.emptyTitle)
                            .font(.system(size: 13))
                            .textSecondaryStyle()
                            .fixedSize(horizontal: false, vertical: true)
                        Text(kind.emptyDetail)
                            .font(.system(size: 12))
                            .textSecondaryStyle()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let footnote = snapshot?.backend.footnote, !footnote.isEmpty {
                        Text(footnote)
                            .font(.system(size: 12))
                            .textSecondaryStyle()
                            .fixedSize(horizontal: false, vertical: true)
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
                        .textSecondaryStyle()
                        .fixedSize(horizontal: false, vertical: true)
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

    private func skeletonBone(width: CGFloat, height: CGFloat, radius: CGFloat = 6) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(palette.field)
            .frame(width: width, height: height)
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
                .openingBlock(1)
            Text(catalogCount)
                .font(.system(size: 13))
                .textSecondaryStyle()
                .openingBlock(2)
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
                    .textSecondaryStyle()
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

    private func statBox(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .semibold))
            Text(label)
                .font(.system(size: 12))
                .textSecondaryStyle()
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
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(L("关闭")) { model.failures[kind] = nil }
                .buttonStyle(PlainPressStyle())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.accentInk)
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
                    .font(.system(size: 11, weight: .semibold))
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
