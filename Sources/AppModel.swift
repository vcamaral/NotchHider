import AppKit
import ServiceManagement

/// Shared state behind both the menu bar menu and the settings window.
final class AppModel: ObservableObject {
    private let manager = WallpaperManager()
    private let enabledKey = "enabled"

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: enabledKey)
            enabled ? manager.apply() : manager.restore()
        }
    }

    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    init() {
        enabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    func refresh() {
        if enabled { manager.apply() }
    }

    func restore() {
        manager.restore()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change \"Launch at Login\""
            alert.runModal()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func openMenuBarSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!)
    }
}
