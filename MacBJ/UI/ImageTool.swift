import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

extension ImageToolMode: Identifiable {
    var id: String { rawValue }
}

extension ImageStitchAxis: Identifiable {
    var id: String { rawValue }
}

extension ImageFileKind {
    var display: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .heic: "HEIC"
        case .webp: "WebP"
        case .tiff: "TIFF"
        }
    }
}

private struct ImagePick: Identifiable {
    var id = UUID()
    var url: URL
    var thumbnail: CGImage?
}

struct ImageTool: View {
    @Environment(\.palette) private var palette
    @State private var mode: ImageToolMode = .compress
    @State private var picks: [ImagePick] = []
    @State private var selected: UUID?
    @State private var targeted = false
    @State private var picking = false
    @State private var quality = ImageJob.mediumQuality
    @State private var output: ImageFileKind = .jpeg
    @State private var axis: ImageStitchAxis = .horizontal
    @State private var watermark = ""
    @State private var overwrite = false
    @State private var confirmOverwrite = false
    @State private var working = false
    @State private var progress = 0.0
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(
                    title: L("图片处理"),
                    subtitle: L("默认保存在原图旁边，原图不动。"),
                    help: FeatureHelp.images
                )
                ImageChoiceBar(
                    items: ImageToolMode.allCases,
                    title: { $0.title },
                    selection: $mode
                )
                sourceArea
                if !picks.isEmpty {
                    preview
                    parameters
                }
                if !note.isEmpty {
                    Text(note)
                        .font(.system(size: 13))
                        .textSecondaryStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
                if working {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress, total: 1)
                            .progressViewStyle(.linear)
                            .tint(palette.accentInk)
                            .transaction { $0.animation = nil }
                        Text(L("正在处理"))
                            .font(.system(size: 12))
                            .textSecondaryStyle()
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(L("正在处理"))
                }
                Button(L("保存"), action: prepareSave)
                    .buttonStyle(TintCapsuleStyle())
                    .disabled(!canSave)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fileImporter(
            isPresented: $picking,
            allowedContentTypes: [.image, .jpeg, .png, .heic, .webP, .tiff, .gif, .bmp],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                add(urls)
            }
        }
        .confirmationDialog(
            L("覆盖原来的图片"),
            isPresented: $confirmOverwrite,
            titleVisibility: .visible
        ) {
            Button(L("覆盖"), role: .destructive) {
                run(currentJob(save: .overwrite))
            }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("原来的文件会被替换。取消则保持不动。"))
        }
        .onChange(of: mode) { _, _ in message = "" }
        .onChange(of: watermark) { _, _ in message = "" }
        .onChange(of: picks.count) { _, _ in message = "" }
    }

    private var canSave: Bool {
        if working || picks.isEmpty { return false }
        if mode == .stitch, picks.count < 2 { return false }
        if mode == .watermark, watermark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return true
    }

    private var note: String {
        if !message.isEmpty { return message }
        guard !picks.isEmpty else { return "" }
        if mode == .stitch, picks.count < 2 { return ImageRefusal.stitchNeedsTwo.text }
        if mode == .watermark, watermark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ImageRefusal.emptyWatermark.text
        }
        return ""
    }

    private var sourceArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                picking = true
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    if picks.isEmpty {
                        Text(L("把图片拖到这里，或点这里选择。可以多选，不会上传。"))
                            .font(.system(size: 13))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(L("选择图片"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.accentInk)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: picks.isEmpty ? 120 : 44, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(targeted ? palette.accentInk : palette.line, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainPressStyle())
            if !picks.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(picks) { pick in
                            thumbnailButton(pick)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            ingest(providers)
            return true
        }
    }

    private func thumbnailButton(_ pick: ImagePick) -> some View {
        let on = selectedPick?.id == pick.id
        return Button {
            selected = pick.id
        } label: {
            thumbnail(pick.thumbnail)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(on ? palette.accentInk : palette.line, lineWidth: on ? 2 : 1)
                )
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .accessibilityLabel(pick.url.lastPathComponent)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("预览"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                Button(L("移除")) { removeSelected() }
                    .buttonStyle(FieldMenuStyle())
            }
            Group {
                if mode == .stitch {
                    stitchPreview
                } else if let image = selectedPick?.thumbnail {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 220, alignment: .leading)
                        .overlay(alignment: .bottomLeading) {
                            watermarkCaption
                        }
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.field)
                        .frame(height: 120)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.line)
            )
        }
    }

    @ViewBuilder
    private var watermarkCaption: some View {
        let text = watermark.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .watermark, !text.isEmpty {
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                .padding(12)
        }
    }

    private var stitchPreview: some View {
        let row = HStack(spacing: 4) { stitchThumbs }
        let column = VStack(spacing: 4) { stitchThumbs }
        return Group {
            if axis == .horizontal {
                row
            } else {
                column
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 220, alignment: .topLeading)
    }

    private var stitchThumbs: some View {
        ForEach(picks) { pick in
            thumbnail(pick.thumbnail)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private var parameters: some View {
        switch mode {
        case .compress:
            qualityRow
            overwriteToggle
        case .convert:
            ImageChoiceBar(
                items: ImageFileKind.convertOutputs,
                title: { $0.display },
                selection: $output
            )
            overwriteToggle
        case .stitch:
            ImageChoiceBar(
                items: Array(ImageStitchAxis.allCases),
                title: { $0.title },
                selection: $axis
            )
        case .watermark:
            VStack(alignment: .leading, spacing: 6) {
                Text(L("水印文字"))
                    .font(.system(size: 12, weight: .medium))
                    .textSecondaryStyle()
                TextField(L("水印文字"), text: $watermark)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(palette.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            overwriteToggle
        }
    }

    private var qualityRow: some View {
        HStack(spacing: 12) {
            Text(L("质量"))
                .font(.system(size: 13))
            Slider(value: $quality, in: 0.1...1)
            Text("\(Int((quality * 100).rounded()))")
                .font(.system(size: 13, design: .monospaced))
                .frame(width: 36, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("质量"))
        .accessibilityValue("\(Int((quality * 100).rounded()))")
    }

    private var overwriteToggle: some View {
        Toggle(L("覆盖原来的图片"), isOn: $overwrite)
            .toggleStyle(.switch)
            .font(.system(size: 13))
            .frame(minHeight: 44)
    }

    @ViewBuilder
    private func thumbnail(_ image: CGImage?) -> some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.field)
        }
    }

    private var selectedPick: ImagePick? {
        if let selected, let pick = picks.first(where: { $0.id == selected }) {
            return pick
        }
        return picks.first
    }

    private func currentJob(save: ImageSaveMode) -> ImageJob {
        ImageJob(
            sources: picks.map(\.url),
            mode: mode,
            quality: quality,
            output: output,
            axis: axis,
            watermark: watermark,
            save: mode == .stitch ? .saveAs : save
        )
    }

    private func prepareSave() {
        let save: ImageSaveMode = overwrite && mode != .stitch ? .overwrite : .saveAs
        let job = currentJob(save: save)
        if let refusal = ImageWorkbench.validate(job) {
            message = refusal.text
            return
        }
        if save == .overwrite {
            confirmOverwrite = true
            return
        }
        run(job)
    }

    private func run(_ job: ImageJob) {
        guard !working else { return }
        working = true
        progress = 0
        message = ""
        let (stream, continuation) = AsyncStream<Double>.makeStream()
        Task {
            for await fraction in stream {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { progress = fraction }
            }
        }
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                let value = ImageWorkbench.perform(job) { fraction in
                    continuation.yield(fraction)
                }
                continuation.finish()
                return value
            }.value
            working = false
            progress = 1
            switch result {
            case .success(let write):
                if job.save == .overwrite {
                    message = L("已覆盖原来的图片。")
                } else if write.written.count > 1 {
                    message = L("已另存 %lld 张。", write.written.count)
                } else {
                    message = L("已保存在原图旁边。")
                }
            case .failure(let refusal):
                message = refusal.text
            }
        }
    }

    private func ingest(_ providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = await fileURL(from: provider) {
                    urls.append(url)
                }
            }
            add(urls)
        }
    }

    private func fileURL(from provider: NSItemProvider) async -> URL? {
        if provider.canLoadObject(ofClass: URL.self) {
            let loaded: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { object, _ in
                    continuation.resume(returning: object)
                }
            }
            if let loaded { return loaded }
        }
        let identifier = UTType.fileURL.identifier
        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                continuation.resume(returning: data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) })
            }
        }
    }

    private func add(_ urls: [URL]) {
        var rejected: [String] = []
        var added: [ImagePick] = []
        for url in urls {
            let normalized = url.standardizedFileURL
            guard ImageFileKind.match(url: normalized) != nil else {
                rejected.append(normalized.lastPathComponent)
                continue
            }
            let known = picks.contains { $0.url.path == normalized.path } || added.contains { $0.url.path == normalized.path }
            if known { continue }
            added.append(ImagePick(url: normalized))
        }
        picks.append(contentsOf: added)
        if selected == nil { selected = picks.first?.id }
        if !rejected.isEmpty {
            message = ImageRefusal.unsupported(rejected.joined(separator: L("、"))).text
        }
        for pick in added {
            let id = pick.id
            let url = pick.url
            Task {
                let image = await Task.detached(priority: .utility) {
                    ImageWorkbench.thumbnail(at: url, maxPixel: 480)
                }.value
                guard let index = picks.firstIndex(where: { $0.id == id }) else { return }
                picks[index].thumbnail = image
            }
        }
    }

    private func removeSelected() {
        guard let pick = selectedPick else { return }
        picks.removeAll { $0.id == pick.id }
        selected = picks.first?.id
    }
}

private struct ImageChoiceBar<Item: Hashable>: View {
    var items: [Item]
    var title: (Item) -> String
    @Binding var selection: Item
    @Environment(\.palette) private var palette
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                let selected = selection == item
                Button {
                    selection = item
                } label: {
                    Text(title(item))
                        .font(.system(size: 13, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? palette.accentInk : palette.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            selected ? palette.accentSoft : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainPressStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(focused ? palette.accentInk : Color.clear, lineWidth: 2)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard let index = items.firstIndex(of: selection) else { return .ignored }
        let next = (index + step + items.count) % items.count
        selection = items[next]
        focused = true
        return .handled
    }
}
