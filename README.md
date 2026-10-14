# NotchHider

A tiny macOS menu bar app that hides the notch by painting a black band at the top of your wallpaper, so the menu bar turns solid black.

- Works on every display: notched screens get a band matching the notch height, other screens get one matching the menu bar height.
- Follows wallpaper, Space, and display changes automatically.
- Restores your original wallpaper when disabled or quit.

## Download

**[⬇ Download NotchHider.dmg](https://github.com/vcamaral/NotchHider/releases/latest/download/NotchHider.dmg)** — macOS 13 or later, Apple silicon and Intel.

Open the DMG and drag **NotchHider** into **Applications**.

The app isn't notarized by Apple yet, so the first launch is blocked by Gatekeeper. To allow it:

1. Open NotchHider once and dismiss the warning.
2. Go to **System Settings › Privacy & Security**, scroll down and click **Open Anyway**.

Or run `xattr -dr com.apple.quarantine /Applications/NotchHider.app` in Terminal.

## Settings

Open **Settings…** from the menu bar icon, or open NotchHider again from Finder or Spotlight, to toggle the effect and Launch at Login.

To hide the menu bar icon, use **System Settings › Menu Bar** — the settings window has a shortcut to it. Opening the app again always brings the settings window back.

## Build

To build from source instead, you need the Xcode Command Line Tools. The app icon is drawn by `scripts/make-icon.swift` during the build.

```sh
./build.sh
open build/NotchHider.app
```

To package a DMG for distribution, run `./scripts/make-dmg.sh` — it writes `build/NotchHider.dmg`.

Generated wallpapers are stored in `~/Library/Application Support/NotchHider/`.

## Limitations

- Dynamic (time-of-day) wallpapers become static.
- Apple's animated aerial wallpapers are not supported and are left untouched.

## License

MIT — see [LICENSE](LICENSE).
