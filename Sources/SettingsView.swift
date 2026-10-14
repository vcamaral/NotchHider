import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NotchHider").font(.headline)
                    Text("Turns the menu bar black to hide the notch.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let warning = model.unreadableMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(warning).font(.callout).fixedSize(horizontal: false, vertical: true)
                        Button("Open Wallpaper Settings…") { model.openWallpaperSettings() }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Hide Notch", isOn: $model.enabled)
                Toggle("Launch at Login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("To show or hide the menu bar icon, use System Settings › Menu Bar. Open NotchHider again anytime to get back to this window.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Menu Bar Settings…") { model.openMenuBarSettings() }
            }

            HStack {
                Spacer()
                Button("Quit NotchHider") { NSApp.terminate(nil) }
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
