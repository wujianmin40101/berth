import SwiftUI

struct VersionCatalogTable: View {
    var model: AppModel
    var kind: RuntimeKind
    var snapshot: RuntimeSnapshot?
    var rows: [RuntimeVersion]
    var latestName: String?
    var query: String
    var canOperate: Bool
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View { catalogTable() }

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
                    .textSecondaryStyle()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
                    .textSecondaryStyle()
                    .multilineTextAlignment(.center)
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
            .textSecondaryStyle()
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
        .background(model.selection[kind] == version.id ? palette.accentSoft : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            model.selection[kind] = version.id
        }
        .accessibilityElement(children: .combine)
    }

    private func versionCell(_ version: RuntimeVersion, newest: String?) -> some View {
        HStack(spacing: 6) {
            Text(catalogTitle(version))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if version.name == newest {
                Text(L("最新"))
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(palette.accentInk)
                    .background(palette.accentSoft, in: Capsule())
            }
            if kind == .node, version.channel != .unknown {
                Text(version.channel.title)
                    .font(.system(size: 11, weight: .medium))
                    .textSecondaryStyle()
                    .lineLimit(1)
            }
        }
    }

    private func metaText(_ value: String?) -> some View {
        Text((value?.isEmpty == false ? value : nil) ?? "—")
            .font(.system(size: 13))
            .textSecondaryStyle()
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
        .foregroundStyle(version.isCurrent ? palette.accentInk : palette.textSecondary)
    }

    private func operationCell(_ version: RuntimeVersion) -> some View {
        HStack(spacing: 6) {
            if version.isCurrent {
                Text(L("使用中"))
                    .font(.system(size: 13))
                    .textSecondaryStyle()
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
                        .frame(width: 44, height: 44)
                        .textSecondaryStyle()
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }
}

struct EqualColumns: Layout {
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
