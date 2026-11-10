import AppKit
import SwiftUI

struct AppUninstallTool: View {
    @Environment(\.palette) private var palette
    @State private var apps: [InstalledApp] = []
    @State private var query = ""
    @State private var loading = true
    @State private var message = ""
    @State private var pending: InstalledApp?

    private var visible: [InstalledApp] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedStandardContains(text) || $0.bundleID.localizedStandardContains(text)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(
                title: L("卸载应用"),
                subtitle: L("移到废纸篓，并带走用户目录里只属于它的偏好、缓存和支持文件。和别的应用共用的文件会留下。"),
                help: FeatureHelp.uninstall,
                actionTitle: L("刷新"),
                actionIcon: "arrow.clockwise",
                actionDisabled: loading
            ) {
                Task { await reload() }
            }
            TextField(L("搜索应用或包标识"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(palette.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            if !message.isEmpty {
                Text(message).font(.system(size: 12)).textSecondaryStyle()
            }
            if loading && visible.isEmpty {
                UninstallLoading()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { app in
                            appRow(app)
                            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                        }
                    }
                }
                if visible.isEmpty {
                    Text(apps.isEmpty ? L("没有找到应用程序文件夹里的应用。") : L("没有匹配的应用。"))
                        .font(.system(size: 13))
                        .textSecondaryStyle()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(L("卸载这个应用"), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button(L("移到废纸篓"), role: .destructive) {
                if let pending { Task { await uninstall(pending) } }
            }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(pending.map(confirm) ?? "")
        }
        .task { await reload() }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        HStack(alignment: .center, spacing: 12) {
            AppBundleIcon(path: app.path)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail(app))
                    .font(.system(size: 12))
                    .textSecondaryStyle()
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if app.removable {
                Button(L("卸载")) { pending = app }
                    .buttonStyle(FieldMenuStyle())
            } else {
                Text(app.reason ?? L("不能卸载"))
                    .font(.system(size: 12))
                    .textSecondaryStyle()
            }
        }
        .padding(.vertical, 8)
    }

    private func detail(_ app: InstalledApp) -> String {
        let size = app.bytes.map { ByteText.string($0) } ?? L("计算大小")
        let version = app.version.isEmpty ? "" : " · \(app.version)"
        let used = app.lastUsed.map { L("上次使用 %@", LastUsedText.string($0)) } ?? L("没有使用记录")
        let leftover = app.leftovers.isEmpty ? L("没有单独的残留") : L("%lld 项残留", app.leftovers.count)
        return "\(size)\(version) · \(used) · \(leftover)"
    }

    private func confirm(_ app: InstalledApp) -> String {
        if app.leftovers.isEmpty {
            return L("把「%@」移到废纸篓。没有找到只属于它的残留。", app.name)
        }
        let names = app.leftovers.prefix(5).map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: L("、"))
        let more = app.leftovers.count > 5 ? L(" 等 %lld 项", app.leftovers.count) : ""
        return L("把「%@」和这些残留一起移到废纸篓：%@%@。", app.name, names, more)
    }

    private func reload() async {
        loading = true
        message = ""
        let listed = await Task.detached { AppUninstall.inventory() }.value
        let used = await Task.detached { AppUninstall.lastUsed(paths: listed.map(\.path)) }.value
        apps = listed.map { app in
            var copy = app
            copy.lastUsed = used[app.path]
            return copy
        }
        loading = false
        let control = AllocatedSize.ScanControl()
        await withTaskCancellationHandler {
            for app in listed {
                if Task.isCancelled { break }
                let bytes = await Task.detached { AppUninstall.allocatedSize(app.path, control: control) }.value
                if Task.isCancelled { break }
                if let index = apps.firstIndex(where: { $0.path == app.path }) {
                    apps[index].bytes = bytes
                }
            }
        } onCancel: {
            control.stop()
        }
    }

    private func uninstall(_ app: InstalledApp) async {
        pending = nil
        do {
            try await AppQuit.waitUntilQuit(bundleID: app.bundleID)
            try await Task.detached { try AppUninstall.trash(app) }.value
            message = L("「%@」已移到废纸篓。", app.name)
            await reload()
        } catch let error as ToolError {
            message = error.text
            await reload()
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct UninstallLoading: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("正在读取应用"))
                .font(.system(size: 12))
                .textSecondaryStyle()
                .padding(.bottom, 8)
            ForEach(0..<6, id: \.self) { index in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.ink.opacity(0.08))
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(palette.ink.opacity(0.1))
                            .frame(width: 132, height: 12)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(palette.ink.opacity(0.06))
                            .frame(width: 220, height: 10)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .modifier(SkeletonWave(index: index, active: true, reduceMotion: reduceMotion))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("正在读取应用"))
    }
}

private struct AppBundleIcon: View {
    var path: String

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)
    }
}

private enum AppQuit {
    @MainActor
    static func waitUntilQuit(bundleID: String) async throws {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty else { return }
        running.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty { return }
            try await Task.sleep(for: .milliseconds(120))
        }
        throw ToolError(L("应用没有退出，可能有没保存的内容。退出后再卸载。"))
    }
}
