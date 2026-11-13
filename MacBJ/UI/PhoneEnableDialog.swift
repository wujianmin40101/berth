import AppKit
import SwiftUI

/// 开启手机任务前的说明。遮罩 240ms 淡入，面板从略低、略小的位置在 400ms 内升起；关闭用 160ms。
struct PhoneEnableDialog: View {
    var offersEnable: Bool
    var onConfirm: () -> Void
    var onClose: () -> Void
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var dim = false
    @State private var risen = false
    @State private var closing = false

    private static let repository = URL(string: "https://github.com/zhongerxin/iPhone-use")!

    var body: some View {
        ZStack {
            Color.black.opacity(dim && !closing ? 0.28 : 0)
                .background(dim && !closing ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear))
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
            card
                .scaleEffect(reduceMotion ? 1 : (risen && !closing ? 1 : (closing ? 0.98 : 0.96)))
                .offset(y: reduceMotion ? 0 : (risen && !closing ? 0 : (closing ? 4 : 8)))
                .opacity(risen && !closing ? 1 : 0)
        }
        .onAppear {
            if reduceMotion {
                dim = true
                risen = true
            } else {
                withAnimation(Motion.enter) { dim = true }
                withAnimation(.spring(response: 0.4, dampingFraction: 1)) { risen = true }
            }
            focused = true
        }
        .onExitCommand { dismiss() }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "iphone")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(palette.accentInk)
                    .frame(width: 40, height: 40)
                    .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(offersEnable ? L("开启手机任务") : L("先安装 iPhone Use"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Text(L("查看打卡任务、执行结果，并自己加定时。"))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(palette.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("关闭"))
            }
            VStack(alignment: .leading, spacing: 10) {
                point("clock", L("到点可以打卡，也可以立刻执行一次。"))
                point("list.bullet.rectangle", L("执行记录里能看到成功、未确认、跳过和停止。"))
                point("hand.tap", L("画面页看手机预览，手势标在对应截图上。"))
            }
            if offersEnable {
                Text(L("确认后，手机任务才会出现在左侧导航。"))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.ink)
            } else {
                Text(L("目录里要有 scripts/punch.py。设置好脚本位置后才能打卡。"))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.ink)
            }
            Button {
                NSWorkspace.shared.open(Self.repository)
            } label: {
                Label(L("在 GitHub 打开 iPhone Use"), systemImage: "arrow.up.right")
            }
            .buttonStyle(FieldMenuStyle())
            HStack(spacing: 8) {
                Spacer()
                if offersEnable {
                    Button(L("取消"), action: dismiss)
                        .buttonStyle(FieldMenuStyle())
                }
                Button(offersEnable ? L("确认开启") : L("知道了")) {
                    if offersEnable { onConfirm() }
                    dismiss()
                }
                .buttonStyle(TintCapsuleStyle())
                .focused($focused)
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.line))
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.accentInk)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dismiss() {
        guard !closing else { return }
        closing = true
        if reduceMotion {
            onClose()
            return
        }
        withAnimation(Motion.exit) {
            dim = false
            risen = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            onClose()
        }
    }
}
