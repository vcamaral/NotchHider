import AppKit
import ServiceManagement

/// Shared state behind both the menu bar menu and the settings window.
final class AppModel: ObservableObject {
    private let manager = WallpaperManager()
    private let enabledKey = "enabled"

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: enabledKey)
            enabled ? refresh() : restore()
        }
    }

    /// Screens whose wallpaper file couldn't be read (e.g. it was deleted), shown as a warning in the UI.
    @Published private(set) var unreadableScreens: [String] = []

    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    init() {
        enabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    func refresh() {
        guard enabled else { return }
        manager.apply()
        if unreadableScreens != manager.unreadableScreens { unreadableScreens = manager.unreadableScreens }
    }

    func restore() {
        manager.restore()
        unreadableScreens = []
    }

    var unreadableMessage: String? {
        guard !unreadableScreens.isEmpty else { return nil }
        return "Can't read the wallpaper on \(unreadableScreens.joined(separator: " and ")). "
            + "Its file may have been moved or deleted — choose it again in System Settings › Wallpaper."
    }

    func openWallpaperSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!)
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
