import Cocoa
import SwiftUI

final class DesktopWidgetWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let vm = G3ViewModel()
    private var widgetWindow: DesktopWidgetWindow?
    private var settingsWindow: NSWindow?

    private let posXKey = "WidgetPosX"
    private let posYKey = "WidgetPosY"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupWidgetWindow()
    }

    private func setupWidgetWindow() {
        let size = NSSize(width: 172, height: 172)
        let origin: NSPoint
        if UserDefaults.standard.object(forKey: posXKey) != nil {
            origin = NSPoint(
                x: UserDefaults.standard.double(forKey: posXKey),
                y: UserDefaults.standard.double(forKey: posYKey)
            )
        } else if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            origin = NSPoint(x: vf.maxX - size.width - 24, y: vf.maxY - size.height - 24)
        } else {
            origin = NSPoint(x: 100, y: 100)
        }

        let win = DesktopWidgetWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        win.isMovableByWindowBackground = true
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let rootView = WidgetView(
            vm: vm,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: size)
        win.contentView = hosting
        win.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: win,
            queue: .main
        ) { [weak self, weak win] _ in
            guard let self, let win else { return }
            UserDefaults.standard.set(win.frame.origin.x, forKey: self.posXKey)
            UserDefaults.standard.set(win.frame.origin.y, forKey: self.posYKey)
        }

        self.widgetWindow = win
    }

    private func openSettings() {
        vm.syncDraftFromSnapshot()
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "G3 Companion 设置"
        win.center()
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: SettingsView(vm: vm))
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = win
    }
}

@main
struct G3CompanionApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
