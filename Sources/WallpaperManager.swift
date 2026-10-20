import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Wallpaper processing

/// Generates wallpapers with a black band at the top so the menu bar (and the notch) turns black.
final class WallpaperManager {
    private let defaults = UserDefaults.standard
    private let originalsKey = "originalWallpapers" // [screenKey: original path]
    private let cachedOriginalsKey = "cachedOriginalWallpapers" // [screenKey: path of our copy of it]
    private let generatedKey = "generatedWallpapers" // [screenKey: file name of the last wallpaper we set]
    let outputDir: URL
    /// Copies of the user's wallpapers, so we keep working (and can restore) if the originals get deleted.
    private let originalsDir: URL

    /// Names of screens whose current wallpaper couldn't be read during the last `apply()`.
    private(set) var unreadableScreens: [String] = []

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        outputDir = support.appendingPathComponent("NotchHider", isDirectory: true)
        originalsDir = outputDir.appendingPathComponent("Originals", isDirectory: true)
        try? FileManager.default.createDirectory(at: originalsDir, withIntermediateDirectories: true)
    }

    private var originals: [String: String] {
        get { defaults.dictionary(forKey: originalsKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: originalsKey) }
    }

    private var cachedOriginals: [String: String] {
        get { defaults.dictionary(forKey: cachedOriginalsKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: cachedOriginalsKey) }
    }

    private var generated: [String: String] {
        get { defaults.dictionary(forKey: generatedKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: generatedKey) }
    }

    /// Stable per-display key, or nil while a display is still being (dis)connected and has no UUID yet.
    static func screenKey(_ screen: NSScreen) -> String? {
        guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// The wallpaper macOS falls back to when it can't show the configured one (e.g. mid display reconnect).
    private static func isSystemFallback(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path == "/System/Library/CoreServices/DefaultDesktop.heic"
            || path.hasPrefix("/System/Library/Wallpapers/.default/")
    }

    /// Height in points of the band to paint black: the notch area, or the menu bar on other screens.
    static func bandHeight(for screen: NSScreen) -> CGFloat? {
        let notch = screen.safeAreaInsets.top
        if notch > 0 { return notch }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return menuBar > 0 ? menuBar : NSStatusBar.system.thickness
    }

    /// Whether `url` is a wallpaper we generated (not one of the cached originals).
    private func isOurs(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL.path == outputDir.standardizedFileURL.path
            && url.lastPathComponent.hasPrefix("wallpaper-")
    }

    /// Makes sure every screen shows a processed wallpaper. Cheap when nothing changed.
    func apply() {
        var unreadable: [String] = []
        for screen in NSScreen.screens {
            guard let band = Self.bandHeight(for: screen),
                  let current = NSWorkspace.shared.desktopImageURL(for: screen),
                  let key = Self.screenKey(screen) else { continue }

            let source: URL
            if Self.isSystemFallback(current), let cachedPath = cachedOriginals[key],
               FileManager.default.fileExists(atPath: cachedPath) {
                // macOS showed its default instead of our wallpaper; put the user's back rather than adopting it.
                source = URL(fileURLWithPath: cachedPath)
            } else if isOurs(current) {
                // Already processed; regenerate only if the screen geometry changed (file name encodes it).
                guard let sourcePath = cachedOriginals[key] ?? originals[key] else { continue }
                source = URL(fileURLWithPath: sourcePath)
                // Without the source we can't regenerate; keep showing what we already made.
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                if current.lastPathComponent == outputName(source: source, screen: screen, band: band) { continue }
            } else {
                // macOS keeps showing a wallpaper whose file was deleted, but we can't read it.
                guard let cached = cacheOriginal(current) else {
                    unreadable.append(screen.localizedName)
                    continue
                }
                originals[key] = current.path
                cachedOriginals[key] = cached.path
                source = cached
            }

            do {
                let output = try render(source: source, screen: screen, band: band)
                try NSWorkspace.shared.setDesktopImageURL(output, for: screen, options: [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                    .allowClipping: true,
                ])
                generated[key] = output.lastPathComponent
                NSLog("NotchHider: applied %@ on %@", output.lastPathComponent, screen.localizedName)
            } catch {
                NSLog("NotchHider: failed for %@: %@", source.path, String(describing: error))
                unreadable.append(screen.localizedName)
            }
        }
        unreadableScreens = unreadable
        cleanup()
    }

    /// Puts the original wallpapers back.
    func restore() {
        for screen in NSScreen.screens {
            guard let key = Self.screenKey(screen),
                  let current = NSWorkspace.shared.desktopImageURL(for: screen), isOurs(current) else { continue }
            // Prefer the user's own file; fall back to our copy if it was deleted.
            let candidates = [originals[key], cachedOriginals[key]].compactMap { $0 }
            guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
        }
    }

    /// Copies a wallpaper into `originalsDir`, or returns nil if it can't be read.
    private func cacheOriginal(_ url: URL) -> URL? {
        let fm = FileManager.default
        guard fm.isReadableFile(atPath: url.path) else { return nil }
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
            .timeIntervalSince1970 ?? 0
        let hash = SHA256.hash(data: Data("\(url.path)|\(mtime)".utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let ext = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
        let copy = originalsDir.appendingPathComponent("original-\(hash)\(ext)")
        if fm.fileExists(atPath: copy.path) { return copy }
        do {
            try fm.copyItem(at: url, to: copy)
            return copy
        } catch {
            NSLog("NotchHider: couldn't copy %@: %@", url.path, String(describing: error))
            return nil
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

    /// Deletes generated wallpapers and cached originals that nothing uses anymore.
    private func cleanup() {
        let inUse = Set(NSScreen.screens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0)?.lastPathComponent })
            .union(cachedOriginals.values.map { URL(fileURLWithPath: $0).lastPathComponent })
            .union(generated.values) // disconnected displays still point at these and will want them back
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600) // other Spaces may still reference recent files
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let files = ((try? fm.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: keys)) ?? [])
            + ((try? fm.contentsOfDirectory(at: originalsDir, includingPropertiesForKeys: keys)) ?? [])
        for file in files where !inUse.contains(file.lastPathComponent) {
            let values = try? file.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            if (values?.contentModificationDate ?? .distantPast) < cutoff { try? fm.removeItem(at: file) }
        }
    }
}
