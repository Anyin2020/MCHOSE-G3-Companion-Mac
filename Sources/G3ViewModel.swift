import Cocoa
import Combine
import Foundation

@MainActor
final class G3ViewModel: ObservableObject {
    @Published var snapshot: G3Snapshot = G3Snapshot()
    @Published var draftSettings: G3Settings = G3Settings()
    @Published var isApplying: Bool = false
    @Published var applyFeedback: String? = nil
    @Published var applySucceeded: Bool = true

    private let client = G3HIDClient()
    private var pollTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var notifiedLowBattery = false

    init() {
        client.onSnapshot = { [weak self] snap in
            Task { @MainActor [weak self] in
                self?.handleSnapshot(snap)
            }
        }
        client.start()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.refresh()
            }
        }
    }

    deinit {
        pollTimer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        client.stop()
    }

    func refresh() {
        client.refresh(queryBattery: true)
    }

    func syncDraftFromSnapshot() {
        if snapshot.configurationValid {
            draftSettings = snapshot.settings
        }
    }

    func applySettings() {
        guard !isApplying else { return }
        isApplying = true
        applyFeedback = "正在写入鼠标…"
        let baseline = snapshot.settings
        let draft = draftSettings

        client.applySettings(draft, baseline: baseline) { [weak self] ok, msg, newSnap in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.snapshot = newSnap
                if newSnap.configurationValid {
                    self.draftSettings = newSnap.settings
                }
                self.isApplying = false
                self.applySucceeded = ok
                self.applyFeedback = msg
            }
        }
    }

    private func handleSnapshot(_ snap: G3Snapshot) {
        let wasValid = snapshot.configurationValid
        let prevSettings = snapshot.settings
        snapshot = snap

        if snap.configurationValid && (!wasValid || draftSettings == prevSettings) {
            draftSettings = snap.settings
        }

        if snap.mode == .charging || snap.mode == .wired {
            notifiedLowBattery = false
        } else if snap.mode == .wireless, let pct = snap.relativePercent {
            if pct > 25 {
                notifiedLowBattery = false
            } else if pct <= 20 && !notifiedLowBattery {
                notifiedLowBattery = true
                sendLowBatteryNotification(percent: pct)
            }
        }
    }

    private func sendLowBatteryNotification(percent: Int) {
        let script = "display notification \"迈从 G3 鼠标电量仅剩 \(percent)%，请及时充电\" with title \"G3 Companion 低电量提醒\""
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        try? proc.run()
    }
}
