import AppKit
import SwiftUI

private enum MachineSection: String, CaseIterable, Identifiable {
    case memory
    case uninstall
    case caches
    case disk
    case speed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .memory: L("内存分布")
        case .uninstall: L("卸载应用")
        case .caches: L("清理缓存")
        case .disk: L("启动磁盘")
        case .speed: L("优化速度")
        }
    }

    var icon: String {
        switch self {
        case .memory: "chart.pie"
        case .uninstall: "trash"
        case .caches: "internaldrive"
        case .disk: "internaldrive.fill"
        case .speed: "hare"
        }
    }
}

struct MachineCareTool: View {
    @Environment(\.palette) private var palette
    @State private var section = MachineSection.memory

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(MachineSection.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: item.icon)
                                .frame(width: 16)
                            Text(item.title)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 13, weight: section == item ? .semibold : .regular))
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainPressStyle())
                    .background(section == item ? palette.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .frame(width: 168, alignment: .topLeading)
            Rectangle()
                .fill(palette.line)
                .frame(width: 1)
            Group {
                switch section {
                case .memory:
                    MemoryMapTool()
                case .uninstall:
                    AppUninstallTool()
                case .caches:
                    CacheCleanTool()
                case .disk:
                    DiskMapTool()
                case .speed:
                    SpeedTuneTool()
                }
            }
            .padding(.leading, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.leading, -28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
