import Foundation
import IOKit.hid

enum G3ConnectionMode: String, Equatable {
    case unknown
    case wireless
    case offline
    case wired
    case missing
    case charging
    case error
    case awaitingBattery

    var displayLabel: String {
        switch self {
        case .unknown: return "检测中…"
        case .wireless: return "2.4G 在线"
        case .offline: return "已休眠/离线"
        case .wired: return "有线连接"
        case .missing: return "未检测到接收器"
        case .charging: return "充电中"
        case .error: return "通信异常"
        case .awaitingBattery: return "读取电量中…"
        }
    }
}

struct G3DPIStage: Equatable, Identifiable {
    let id: Int
    var dpiX: Int
    var dpiY: Int
    var r: UInt8
    var g: UInt8
    var b: UInt8
}

struct G3Settings: Equatable {
    var sleepMinutes: Int = 10
    var debounceMs: Int = 4
    var reportRate: Int = 1000
    var stageCount: Int = 6
    var currentStage: Int = 1
    var angleSnap: Bool = false
    var ripple: Bool = false
    var stages: [G3DPIStage] = (0..<6).map { i in
        let dpis = [800, 1600, 2400, 3200, 5000, 12000]
        return G3DPIStage(id: i, dpiX: dpis[i], dpiY: dpis[i], r: 0, g: 0, b: 255)
    }

    var activeStage: G3DPIStage? {
        let idx = currentStage - 1
        guard idx >= 0 && idx < stages.count else { return nil }
        return stages[idx]
    }
}

struct G3Snapshot: Equatable {
    var mode: G3ConnectionMode = .unknown
    var rawPercent: Int = -1
    var settings: G3Settings = G3Settings()
    var configurationValid: Bool = false
    var isWired: Bool = false
    var lastUpdated: Date? = nil
    var statusMessage: String? = nil

    var relativePercent: Int? {
        guard rawPercent >= 0 && rawPercent <= 100 else { return nil }
        let rel = (rawPercent * 100 + 47) / 94
        return min(100, rel)
    }
}

final class G3HIDClient: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.github.anyin2020.g3companion.hid", qos: .utility)
    private var manager: IOHIDManager?
    private var activeDevice: IOHIDDevice?
    private var activeIsWired: Bool = false
    private var inputBuffer = [UInt8](repeating: 0, count: 16)
    private var isStarted = false

    private let logPath = NSHomeDirectory() + "/.local/tmp/g3-companion.log"

    var onSnapshot: (@Sendable (G3Snapshot) -> Void)?

    private var currentSnapshot = G3Snapshot()

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isStarted else { return }
            self.isStarted = true
            self.log("Started G3HIDClient")
            self.setupManager()
            self.refreshSync(queryBattery: true)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.closeActiveDevice()
            if let mgr = self.manager {
                IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
                IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
                self.manager = nil
            }
            self.isStarted = false
        }
    }

    func refresh(queryBattery: Bool = true) {
        queue.async { [weak self] in
            self?.refreshSync(queryBattery: queryBattery)
        }
    }

    func applySettings(_ draft: G3Settings, baseline: G3Settings, completion: @escaping @Sendable (Bool, String, G3Snapshot) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let (ok, msg) = self.applySettingsSync(draft: draft, baseline: baseline)
            let snap = self.currentSnapshot
            completion(ok, msg, snap)
        }
    }

    private func log(_ msg: String) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "[\(df.string(from: Date()))] \(msg)\n"
        if let dir = URL(fileURLWithPath: logPath).deletingLastPathComponent() as URL? {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath),
               let fh = FileHandle(forWritingAtPath: logPath) {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }

    private func setupManager() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [kIOHIDVendorIDKey: 0x258a]
        IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { context, _, _, _ in
            guard let context else { return }
            let client = Unmanaged<G3HIDClient>.fromOpaque(context).takeUnretainedValue()
            client.queue.async {
                client.refreshSync(queryBattery: true)
            }
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { context, _, _, _ in
            guard let context else { return }
            let client = Unmanaged<G3HIDClient>.fromOpaque(context).takeUnretainedValue()
            client.queue.async {
                client.closeActiveDevice()
                client.refreshSync(queryBattery: true)
            }
        }, ctx)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = mgr
    }

    private func findTargetDevice() -> (IOHIDDevice, Bool)? {
        guard let mgr = manager, let set = IOHIDManagerCopyDevices(mgr) else { return nil }
        let count = CFSetGetCount(set)
        guard count > 0 else { return nil }
        var rawPtrs = [UnsafeRawPointer?](repeating: nil, count: count)
        CFSetGetValues(set, &rawPtrs)

        var wiredDev: IOHIDDevice?
        var wirelessDev: IOHIDDevice?

        for ptr in rawPtrs {
            guard let ptr else { continue }
            let dev = unsafeBitCast(ptr, to: IOHIDDevice.self)
            guard hasVendorUsagePair(dev) else { continue }
            let pid = (IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
            if pid == 0x0136 {
                wiredDev = dev
            } else if pid == 0x0138 {
                wirelessDev = dev
            }
        }
        if let wiredDev { return (wiredDev, true) }
        if let wirelessDev { return (wirelessDev, false) }
        return nil
    }

    private func hasVendorUsagePair(_ dev: IOHIDDevice) -> Bool {
        guard let pairs = IOHIDDeviceGetProperty(dev, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Any]] else {
            return false
        }
        return pairs.contains { dict in
            let up = (dict[kIOHIDDeviceUsagePageKey] as? NSNumber)?.intValue ?? 0
            let u = (dict[kIOHIDDeviceUsageKey] as? NSNumber)?.intValue ?? 0
            return up == 0xff02 && u == 2
        }
    }

    private func openDevice(_ dev: IOHIDDevice, isWired: Bool) -> (Bool, Bool) {
        if activeDevice === dev { return (true, false) }
        closeActiveDevice()
        let kr = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        guard kr == kIOReturnSuccess else {
            let notPermitted = (kr == kIOReturnNotPermitted)
            log("ERROR: IOHIDDeviceOpen failed: 0x\(String(UInt32(bitPattern: kr), radix: 16))\(notPermitted ? " (kIOReturnNotPermitted)" : "")")
            if notPermitted {
                IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            }
            return (false, notPermitted)
        }
        activeDevice = dev
        activeIsWired = isWired
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        inputBuffer.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            IOHIDDeviceRegisterInputReportCallback(dev, base, buf.count, { context, _, _, _, _, report, reportLength in
                guard let context else { return }
                let client = Unmanaged<G3HIDClient>.fromOpaque(context).takeUnretainedValue()
                let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
                client.queue.async {
                    client.handleInputReport(bytes)
                }
            }, ctx)
        }
        return (true, false)
    }

    private func closeActiveDevice() {
        if let dev = activeDevice {
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
            activeDevice = nil
        }
    }

    private func handleInputReport(_ bytes: [UInt8]) {
        guard bytes.count == 8, bytes[0] == 9, bytes[1] == 10, bytes[5] == 0, bytes[6] == 0, bytes[7] == 0 else {
            return
        }
        if bytes[2] == 2 && bytes[4] == 0 {
            if bytes[3] == 1 {
                currentSnapshot.mode = .awaitingBattery
                currentSnapshot.lastUpdated = Date()
                publish()
                refreshSync(queryBattery: true)
            } else if bytes[3] == 0 {
                currentSnapshot.mode = .offline
                currentSnapshot.lastUpdated = Date()
                publish()
            }
        } else if bytes[2] == 5 {
            let v = bytes[3]
            if v == 255 {
                currentSnapshot.mode = .charging
                currentSnapshot.lastUpdated = Date()
                log("Input report: charging")
                publish()
            } else if v <= 100 {
                currentSnapshot.mode = .wireless
                currentSnapshot.rawPercent = Int(v)
                currentSnapshot.lastUpdated = Date()
                log("Input report: battery raw=\(v) rel=\(currentSnapshot.relativePercent ?? -1)%")
                publish()
            }
        }
    }

    private func sendFeature(_ dev: IOHIDDevice, payload: [UInt8]) -> IOReturn {
        var buf = [UInt8](repeating: 0, count: 520)
        let n = min(payload.count, 520)
        for i in 0..<n { buf[i] = payload[i] }
        return IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, 9, &buf, buf.count)
    }

    private func readMatchingFeature(_ dev: IOHIDDevice, initialDelayMs: Int, timeoutMs: Int = 2000, matches: ([UInt8], Int) -> Bool) -> [UInt8]? {
        usleep(useconds_t(initialDelayMs * 1000))
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        var buf = [UInt8](repeating: 0, count: 520)
        while Date() < deadline {
            buf.withUnsafeMutableBufferPointer { $0.initialize(repeating: 0) }
            buf[0] = 9
            var len: CFIndex = 520
            let kr = IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, 9, &buf, &len)
            if kr == kIOReturnSuccess && matches(buf, Int(len)) {
                return buf
            }
            usleep(20_000)
        }
        return nil
    }

    private func queryByte(_ dev: IOHIDDevice, header: [UInt8]) -> UInt8? {
        let kr = sendFeature(dev, payload: header)
        guard kr == kIOReturnSuccess else { return nil }
        guard let reply = readMatchingFeature(dev, initialDelayMs: 15, timeoutMs: 2000, matches: { buf, len in
            len == 9 && (0..<8).allSatisfy { buf[$0] == header[$0] }
        }) else {
            return nil
        }
        return reply[8]
    }

    private func checksum(_ bytes: [UInt8], count: Int) -> UInt8 {
        var total = 0
        for i in 2..<count { total += Int(bytes[i]) }
        return UInt8(total & 0xFF)
    }

    private func validateParameterReply(_ buf: [UInt8], len: Int) -> Bool {
        guard len == 408 else { return false }
        guard buf[0] == 9, buf[2] == 0x44, buf[3] == 0, buf[4] == 1, buf[5] == 0, buf[6] == 0x90, buf[7] == 1 else {
            return false
        }
        return buf[1] == checksum(buf, count: 520)
    }

    private func decodeDpi(_ buf: [UInt8], offset: Int) -> Int {
        return (Int(buf[offset]) + (Int(buf[offset + 1]) << 8) + 1) * 100
    }

    private func encodeDpi(_ buf: inout [UInt8], offset: Int, dpi: Int) {
        let v = max(0, dpi / 100 - 1)
        buf[offset] = UInt8(v & 0xFF)
        buf[offset + 1] = UInt8((v >> 8) & 0xFF)
    }

    private func parseParameters(_ buf: [UInt8]) -> G3Settings? {
        var s = G3Settings()
        switch buf[10] {
        case 1: s.reportRate = 125
        case 2: s.reportRate = 250
        case 3: s.reportRate = 500
        case 4: s.reportRate = 1000
        default: return nil
        }
        s.stageCount = Int(buf[11] & 0x0F)
        s.currentStage = Int(buf[11] >> 4)
        s.debounceMs = Int(buf[13] & 0x0F)
        s.angleSnap = (buf[14] & 0x0F) != 0
        s.ripple = (buf[14] >> 4) != 0
        s.sleepMinutes = Int(buf[82])

        guard (1...30).contains(s.sleepMinutes),
              (1...14).contains(s.debounceMs),
              (1...6).contains(s.stageCount),
              (1...s.stageCount).contains(s.currentStage) else {
            return nil
        }

        var stages: [G3DPIStage] = []
        for i in 0..<6 {
            let dx = decodeDpi(buf, offset: 15 + 2 * i)
            let dy = decodeDpi(buf, offset: 35 + 2 * i)
            let off = 55 + 3 * i
            stages.append(G3DPIStage(id: i, dpiX: dx, dpiY: dy, r: buf[off], g: buf[off + 1], b: buf[off + 2]))
        }
        s.stages = stages
        return s
    }

    private func readParameters(_ dev: IOHIDDevice) -> ([UInt8], G3Settings)? {
        let hdr: [UInt8] = [9, 0, 0x44, 0, 1, 0, 0x90, 1]
        guard sendFeature(dev, payload: hdr) == kIOReturnSuccess else { return nil }
        guard let reply = readMatchingFeature(dev, initialDelayMs: 100, timeoutMs: 2000, matches: validateParameterReply),
              let parsed = parseParameters(reply) else {
            return nil
        }
        return (reply, parsed)
    }

    private func refreshSync(queryBattery: Bool) {
        guard let (dev, wired) = findTargetDevice() else {
            closeActiveDevice()
            currentSnapshot.mode = .missing
            currentSnapshot.isWired = false
            currentSnapshot.configurationValid = false
            currentSnapshot.lastUpdated = Date()
            log("Device missing")
            publish()
            return
        }

        let (opened, notPermitted) = openDevice(dev, isWired: wired)
        guard opened else {
            currentSnapshot.mode = .error
            currentSnapshot.statusMessage = notPermitted ? "需授权输入监控" : "无法打开 HID 设备"
            currentSnapshot.lastUpdated = Date()
            publish()
            return
        }

        currentSnapshot.isWired = wired

        if !wired {
            guard let conn = queryByte(dev, header: [9, 9, 7, 0, 1, 0, 1, 0]) else {
                currentSnapshot.mode = .error
                currentSnapshot.statusMessage = "连接状态查询失败"
                currentSnapshot.lastUpdated = Date()
                publish()
                return
            }
            if conn == 0 {
                currentSnapshot.mode = .offline
                currentSnapshot.configurationValid = false
                currentSnapshot.lastUpdated = Date()
                log("Mouse offline (sleeping)")
                publish()
                return
            }
            if queryBattery {
                if let bat = queryByte(dev, header: [9, 12, 9, 1, 1, 0, 1, 0]) {
                    if bat == 255 {
                        currentSnapshot.mode = .charging
                    } else if bat <= 100 {
                        currentSnapshot.mode = .wireless
                        currentSnapshot.rawPercent = Int(bat)
                    }
                }
            } else if currentSnapshot.mode != .charging {
                currentSnapshot.mode = .wireless
            }
        } else {
            currentSnapshot.mode = .wired
        }

        if let (_, params) = readParameters(dev) {
            currentSnapshot.settings = params
            currentSnapshot.configurationValid = true
            currentSnapshot.statusMessage = nil
            let activeDpi = params.activeStage?.dpiX ?? 0
            log("Refreshed: mode=\(currentSnapshot.mode.rawValue) rel=\(currentSnapshot.relativePercent ?? -1)% rate=\(params.reportRate)Hz stage=\(params.currentStage)/\(params.stageCount)(\(activeDpi)DPI) sleep=\(params.sleepMinutes)m")
        } else {
            currentSnapshot.statusMessage = "参数读取失败"
        }

        currentSnapshot.lastUpdated = Date()
        publish()
    }

    private func applySettingsSync(draft: G3Settings, baseline: G3Settings) -> (Bool, String) {
        guard let dev = activeDevice else {
            return (false, "鼠标未连接")
        }
        guard let (fresh, freshSettings) = readParameters(dev) else {
            return (false, "读取鼠标当前配置失败，请移动鼠标唤醒后重试")
        }

        var write = fresh
        for i in 408..<520 { write[i] = 0 }

        if draft.sleepMinutes != baseline.sleepMinutes {
            write[82] = UInt8(clamping: draft.sleepMinutes)
        }
        if draft.debounceMs != baseline.debounceMs {
            write[13] = (write[13] & 0xF0) | UInt8(clamping: draft.debounceMs)
        }
        if draft.reportRate != baseline.reportRate {
            let code: UInt8 = draft.reportRate == 125 ? 1 : draft.reportRate == 250 ? 2 : draft.reportRate == 500 ? 3 : 4
            write[10] = code
        }
        if draft.angleSnap != baseline.angleSnap {
            write[14] = (write[14] & 0xF0) | (draft.angleSnap ? 1 : 0)
        }
        if draft.ripple != baseline.ripple {
            write[14] = (write[14] & 0x0F) | (draft.ripple ? 0x10 : 0)
        }

        let count = draft.stageCount != baseline.stageCount ? draft.stageCount : freshSettings.stageCount
        let current = min(max(1, freshSettings.currentStage), count)
        write[11] = UInt8((current << 4) | count)

        for i in 0..<draft.stageCount {
            if draft.stages[i].dpiX != baseline.stages[i].dpiX {
                encodeDpi(&write, offset: 15 + 2 * i, dpi: draft.stages[i].dpiX)
            }
            if draft.stages[i].dpiY != baseline.stages[i].dpiY {
                encodeDpi(&write, offset: 35 + 2 * i, dpi: draft.stages[i].dpiY)
            }
            if draft.stages[i].r != baseline.stages[i].r ||
                draft.stages[i].g != baseline.stages[i].g ||
                draft.stages[i].b != baseline.stages[i].b {
                let off = 55 + 3 * i
                write[off] = draft.stages[i].r
                write[off + 1] = draft.stages[i].g
                write[off + 2] = draft.stages[i].b
            }
        }

        write[2] = 4
        write[1] = checksum(write, count: 520)

        let kr = sendFeature(dev, payload: write)
        guard kr == kIOReturnSuccess else {
            return (false, "写入鼠标失败 (0x\(String(kr, radix: 16)))")
        }

        guard let (reply, verified) = readParameters(dev) else {
            return (false, "写入后回读校验超时")
        }

        let matched = (8..<408).allSatisfy { write[$0] == reply[$0] }
        currentSnapshot.settings = verified
        currentSnapshot.configurationValid = true
        currentSnapshot.lastUpdated = Date()
        publish()

        if matched {
            log("Applied settings OK: rate=\(verified.reportRate)Hz sleep=\(verified.sleepMinutes)m debounce=\(verified.debounceMs)ms")
            return (true, "已写入并校验成功")
        } else {
            return (true, "已应用（部分字段以设备当前值为准）")
        }
    }

    private func publish() {
        let snap = currentSnapshot
        onSnapshot?(snap)
    }
}
