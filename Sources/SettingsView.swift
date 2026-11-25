import Cocoa
import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: G3ViewModel

    private let rates = [125, 250, 500, 1000]

    private func stageColorBinding(_ index: Int) -> Binding<Color> {
        Binding<Color>(
            get: {
                let s = vm.draftSettings.stages[index]
                return Color(red: Double(s.r) / 255.0, green: Double(s.g) / 255.0, blue: Double(s.b) / 255.0)
            },
            set: { newColor in
                let ns = NSColor(newColor).usingColorSpace(.sRGB) ?? NSColor.white
                vm.draftSettings.stages[index].r = UInt8(clamping: Int(round(ns.redComponent * 255)))
                vm.draftSettings.stages[index].g = UInt8(clamping: Int(round(ns.greenComponent * 255)))
                vm.draftSettings.stages[index].b = UInt8(clamping: Int(round(ns.blueComponent * 255)))
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("迈从 G3 鼠标设置")
                        .font(.headline)
                    HStack(spacing: 8) {
                        Text(vm.snapshot.mode.displayLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let pct = vm.snapshot.relativePercent {
                            Text("电量 \(pct)%")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(pct <= 20 ? .red : .green)
                        }
                    }
                }
                Spacer()
                Button("重新读取") {
                    vm.refresh()
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !vm.snapshot.configurationValid {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("鼠标当前未唤醒或暂未读到配置，请晃动鼠标后点击右上角“重新读取”。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Report rate
                    VStack(alignment: .leading, spacing: 6) {
                        Text("回报率 (Polling Rate)")
                            .font(.subheadline.weight(.semibold))
                        Picker("", selection: $vm.draftSettings.reportRate) {
                            ForEach(rates, id: \.self) { r in
                                Text("\(r) Hz").tag(r)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    // Sleep & Debounce
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("休眠时间：\(vm.draftSettings.sleepMinutes) 分钟")
                                .font(.subheadline.weight(.semibold))
                            Stepper("", value: $vm.draftSettings.sleepMinutes, in: 1...30)
                                .labelsHidden()
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("按键消抖：\(vm.draftSettings.debounceMs) ms")
                                .font(.subheadline.weight(.semibold))
                            Stepper("", value: $vm.draftSettings.debounceMs, in: 1...14)
                                .labelsHidden()
                        }
                    }

                    // Motion toggles
                    HStack(spacing: 24) {
                        Toggle("直线修正", isOn: $vm.draftSettings.angleSnap)
                        Toggle("波纹控制", isOn: $vm.draftSettings.ripple)
                    }

                    Divider()

                    // DPI Stages
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("DPI 档位 (\(vm.draftSettings.stageCount) 档)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Stepper("", value: $vm.draftSettings.stageCount, in: 1...6)
                                .labelsHidden()
                        }

                        ForEach(0..<vm.draftSettings.stageCount, id: \.self) { idx in
                            HStack(spacing: 10) {
                                Text("档位 \(idx + 1)")
                                    .font(.callout.monospacedDigit())
                                    .frame(width: 50, alignment: .leading)

                                if vm.draftSettings.currentStage == idx + 1 {
                                    Text("当前")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.18))
                                        .foregroundStyle(Color.accentColor)
                                        .clipShape(Capsule())
                                }

                                Spacer()

                                Text("\(vm.draftSettings.stages[idx].dpiX) DPI")
                                    .font(.callout.monospacedDigit())
                                    .frame(width: 80, alignment: .trailing)

                                Stepper("", value: Binding(
                                    get: { vm.draftSettings.stages[idx].dpiX },
                                    set: { val in
                                        let clamped = min(12000, max(100, val))
                                        vm.draftSettings.stages[idx].dpiX = clamped
                                        vm.draftSettings.stages[idx].dpiY = clamped
                                    }
                                ), in: 100...12000, step: 100)
                                .labelsHidden()

                                ColorPicker("", selection: stageColorBinding(idx), supportsOpacity: false)
                                    .labelsHidden()
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                if let feedback = vm.applyFeedback {
                    Text(feedback)
                        .font(.caption)
                        .foregroundStyle(vm.applySucceeded ? Color.secondary : Color.red)
                }
                Spacer()
                Button(vm.isApplying ? "写入中…" : "应用到鼠标") {
                    vm.applySettings()
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isApplying || !vm.snapshot.configurationValid)
            }
            .padding()
        }
        .frame(width: 450, height: 520)
    }
}
