import AppKit
import CryptoKit
import ImageIO
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - Wallpaper processing

/// Generates wallpapers with a black band at the top so the menu bar (and the notch) turns black.
final class WallpaperManager {
    private let defaults = UserDefaults.standard
    private let originalsKey = "originalWallpapers" // [screenKey: original path]
    let outputDir: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        outputDir = support.appendingPathComponent("NotchHider", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    private var originals: [String: String] {
        get { defaults.dictionary(forKey: originalsKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: originalsKey) }
    }

    static func screenKey(_ screen: NSScreen) -> String {
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
        return uuid.map { CFUUIDCreateString(nil, $0) as String } ?? screen.localizedName
    }

    /// Height in points of the band to paint black: the notch area, or the menu bar on other screens.
    static func bandHeight(for screen: NSScreen) -> CGFloat? {
        let notch = screen.safeAreaInsets.top
        if notch > 0 { return notch }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return menuBar > 0 ? menuBar : NSStatusBar.system.thickness
    }

    private func isOurs(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(outputDir.standardizedFileURL.path)
    }

    /// Makes sure every notched screen shows a processed wallpaper. Cheap when nothing changed.
    func apply() {
        for screen in NSScreen.screens {
            guard let band = Self.bandHeight(for: screen),
                  let current = NSWorkspace.shared.desktopImageURL(for: screen) else { continue }
            let key = Self.screenKey(screen)

            let source: URL
            if isOurs(current) {
                // Already processed; regenerate only if the screen geometry changed (file name encodes it).
                guard let originalPath = originals[key] else { continue }
                source = URL(fileURLWithPath: originalPath)
                if current.lastPathComponent == outputName(source: source, screen: screen, band: band) { continue }
            } else {
                source = current
                originals[key] = current.path
            }

            do {
                let output = try render(source: source, screen: screen, band: band)
                try NSWorkspace.shared.setDesktopImageURL(output, for: screen, options: [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                    .allowClipping: true,
                ])
                NSLog("NotchHider: applied %@ on %@", output.lastPathComponent, screen.localizedName)
            } catch {
                NSLog("NotchHider: failed for %@: %@", source.path, String(describing: error))
            }
        }
        cleanup()
    }

    /// Puts the original wallpapers back.
    func restore() {
        for screen in NSScreen.screens {
            let key = Self.screenKey(screen)
            guard let current = NSWorkspace.shared.desktopImageURL(for: screen), isOurs(current),
                  let originalPath = originals[key] else { continue }
            let original = URL(fileURLWithPath: originalPath)
            guard FileManager.default.fileExists(atPath: original.path) else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(original, for: screen, options: [:])
        }
    }

    private func outputName(source: URL, screen: NSScreen, band: CGFloat) -> String {
        let mtime = (try? source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
            .timeIntervalSince1970 ?? 0
        let size = pixelSize(screen)
        let id = "\(source.path)|\(mtime)|\(Int(size.width))x\(Int(size.height))|\(band)"
        let hash = SHA256.hash(data: Data(id.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "wallpaper-\(hash).png"
    }

    private func pixelSize(_ screen: NSScreen) -> CGSize {
        let s = screen.backingScaleFactor
        return CGSize(width: (screen.frame.width * s).rounded(), height: (screen.frame.height * s).rounded())
    }

    private func render(source: URL, screen: NSScreen, band: CGFloat) throws -> URL {
        let output = outputDir.appendingPathComponent(outputName(source: source, screen: screen, band: band))
        if FileManager.default.fileExists(atPath: output.path) { return output }

        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw NSError(domain: "NotchHider", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unsupported wallpaper format"])
        }

        let size = pixelSize(screen)
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "NotchHider", code: 2)
        }
        ctx.interpolationQuality = .high

        // Aspect-fill, centered — same as macOS "Fill Screen".
        let imgW = CGFloat(image.width), imgH = CGFloat(image.height)
        let scale = max(size.width / imgW, size.height / imgH)
        let drawW = imgW * scale, drawH = imgH * scale
        ctx.draw(image, in: CGRect(x: (size.width - drawW) / 2, y: (size.height - drawH) / 2,
                                   width: drawW, height: drawH))

        // Black band at the top (CG origin is bottom-left).
        let bandPx = (band * screen.backingScaleFactor).rounded(.up)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: size.height - bandPx, width: size.width, height: bandPx))

        guard let result = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "NotchHider", code: 3)
        }
        CGImageDestinationAddImage(dest, result, nil)
        guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "NotchHider", code: 4) }
        return output
    }

    /// Deletes generated files that no screen is using anymore.
    private func cleanup() {
        let inUse = Set(NSScreen.screens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0)?.lastPathComponent })
        let files = (try? FileManager.default.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600) // other Spaces may still reference recent files
        for file in files where !inUse.contains(file.lastPathComponent) {
            let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if mtime < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let manager = WallpaperManager()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private let enabledKey = "enabled"

    private var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                           accessibilityDescription: "NotchHider")
        rebuildMenu()

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(refresh), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        ws.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // No public notification exists for wallpaper changes, so poll lightly.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.restore()
    }

    @objc private func refresh() {
        if enabled { manager.apply() }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let toggle = NSMenuItem(title: "Hide Notch", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.state = enabled ? .on : .off
        menu.addItem(toggle)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit (Restore Wallpaper)", action: #selector(quit), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        enabled ? manager.apply() : manager.restore()
        rebuildMenu()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change \"Launch at Login\""
            alert.runModal()
        }
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
