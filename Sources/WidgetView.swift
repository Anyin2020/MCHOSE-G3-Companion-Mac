import Cocoa
import SwiftUI

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct WidgetView: View {
    @ObservedObject var vm: G3ViewModel
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    @State private var isHovering = false

    private var ringColor: Color {
        switch vm.snapshot.mode {
        case .charging:
            return .blue
        case .wired:
            return .teal
        case .offline, .missing, .error:
            return .gray
        default:
            let pct = vm.snapshot.relativePercent ?? 0
            if pct <= 20 { return .red }
            if pct <= 35 { return .orange }
            return .green
        }
    }

    private var ringProgress: Double {
        switch vm.snapshot.mode {
        case .charging, .wired:
            return 1.0
        case .missing:
            return 0.0
        default:
            if let pct = vm.snapshot.relativePercent {
                return max(0.03, min(1.0, Double(pct) / 100.0))
            }
            return 0.0
        }
    }

    private var centerText: String {
        switch vm.snapshot.mode {
        case .charging:
            return "充电中"
        case .wired:
            return "有线"
        case .missing:
            return "无接收器"
        case .awaitingBattery, .unknown:
            return "--"
        default:
            if let pct = vm.snapshot.relativePercent {
                return "\(pct)%"
            }
            return "--"
        }
    }

    private var bottomLabel: String {
        if vm.snapshot.configurationValid {
            let dpi = vm.snapshot.settings.activeStage?.dpiX ?? 0
            return "\(vm.snapshot.settings.reportRate)Hz · \(dpi) DPI"
        }
        return vm.snapshot.statusMessage ?? vm.snapshot.mode.displayLabel
    }

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "computermouse.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ringColor)
                    Text("迈从 G3")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if isHovering {
                        Button(action: { vm.refresh() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .help("立即刷新")

                        Button(action: onOpenSettings) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .help("鼠标设置")
                    } else {
                        Circle()
                            .fill(vm.snapshot.mode == .wireless || vm.snapshot.mode == .charging || vm.snapshot.mode == .wired ? Color.green : Color.secondary.opacity(0.5))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.10), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: ringProgress)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.35), value: ringProgress)

                    VStack(spacing: 1) {
                        if vm.snapshot.mode == .charging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.blue)
                        }
                        Text(centerText)
                            .font(.system(size: vm.snapshot.mode == .charging || vm.snapshot.mode == .missing ? 13 : 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                }
                .frame(width: 78, height: 78)

                Text(bottomLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 172, height: 172)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("立即刷新") { vm.refresh() }
            Button("鼠标设置…") { onOpenSettings() }
            Divider()
            Button("退出 G3 Companion") { onQuit() }
        }
    }
}
