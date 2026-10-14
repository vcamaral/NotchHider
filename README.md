# NotchHider

A tiny macOS menu bar app that hides the notch by painting a black band at the top of your wallpaper, so the menu bar turns solid black.

- Works on every display: notched screens get a band matching the notch height, other screens get one matching the menu bar height.
- Follows wallpaper, Space, and display changes automatically.
- Restores your original wallpaper when disabled or quit.

## Build

Requires the Xcode Command Line Tools.

```sh
./build.sh
open build/NotchHider.app
```

Generated wallpapers are stored in `~/Library/Application Support/NotchHider/`.

## Limitations

- Dynamic (time-of-day) wallpapers become static.
- Apple's animated aerial wallpapers are not supported and are left untouched.
