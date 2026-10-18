<div align="center">

<img src="docs/icon.png" width="128" height="128" alt="DisplayDeck icon">

# DisplayDeck

**Your monitors, from the menu bar.**

Brightness, contrast and volume for external displays, plus brightness keys that actually work on them.
<br>A tiny, free and open-source macOS app.

[![Latest release](https://img.shields.io/github/v/release/rahgurung/DisplayDeck?style=flat-square&color=3E4BF0&label=release)](https://github.com/rahgurung/DisplayDeck/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/rahgurung/DisplayDeck/total?style=flat-square&color=3E4BF0)](https://github.com/rahgurung/DisplayDeck/releases)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?style=flat-square&logo=apple&logoColor=white)](#requirements)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-111?style=flat-square)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5-F05138?style=flat-square&logo=swift&logoColor=white)](Sources)
[![MIT License](https://img.shields.io/badge/license-MIT-2EA44F?style=flat-square)](LICENSE)

[**Download**](https://github.com/rahgurung/DisplayDeck/releases/latest) · [**Website**](https://displaydeck.rahulgurung.com) · [Install](#-install) · [Features](#-features) · [Build from source](#%EF%B8%8F-build-from-source)

<br>

<img src="docs/screenshot.png" width="820" alt="The DisplayDeck menu open from the menu bar, with brightness, contrast and volume sliders for a built-in and an external display">

</div>

<br>

## ✨ Features

| | |
|---|---|
| ☀️ **Real brightness** | Changes the monitor's own backlight over DDC/CI rather than drawing a dark overlay, so blacks stay black. |
| ⌨️ **Brightness keys that work** | Your Mac's brightness keys control the display under your pointer, with a clean on-screen indicator. |
| 🔊 **Monitor speakers** | Volume for speakers built into your monitor, from a slider or your volume keys. |
| ◐ **Contrast** | Adjust contrast on monitors that support it. |
| 🖥️ **Resolution & refresh rate** | Switch per display in two clicks, no System Settings detour. |
| 🪞 **Mirroring** | Toggle display mirroring straight from the menu. |
| 🌗 **Software dimming fallback** | Displays that can't be controlled over DDC still dim, in software. |
| 🚀 **Launch at login** | Starts quietly in the menu bar when you log in. |

## 📦 Install

### Homebrew

```sh
brew install --cask rahgurung/tap/displaydeck
```

### Download

1. Grab the latest **`DisplayDeck-x.y.dmg`** from [Releases](https://github.com/rahgurung/DisplayDeck/releases/latest).
2. Open it and drag **DisplayDeck** into **Applications**.
3. Launch it. The <img src="docs/glyph.svg" width="16" height="16" alt="DisplayDeck menu bar icon"> icon appears in your menu bar.

Releases are signed with a Developer ID and notarized by Apple, so they open without Gatekeeper warnings.

### Requirements

- 🍎 Apple Silicon Mac (M1 or later)
- 💻 macOS 14 Sonoma or later

## 🕹️ Usage

- **Click** the menu bar icon to see every connected display with its own sliders and pickers.
- **Open DisplayDeck again** (Finder, Spotlight, Launchpad) or press <kbd>⌘</kbd> <kbd>,</kbd> in the menu to bring up **Settings**.
- **Brightness / volume keys** need **Accessibility** access: macOS asks the first time, or use *Open Settings…* in DisplayDeck's settings window. You can switch either key off.

<div align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/settings-dark.png">
  <img src="docs/settings-light.png" width="420" alt="DisplayDeck settings window with keyboard and general options">
</picture>
</div>

## 🔌 Compatibility

DisplayDeck talks to monitors over **DDC/CI**, the control channel most displays expose over the video cable.

| Connection | Hardware control |
|---|---|
| USB‑C / Thunderbolt | ✅ Almost always |
| DisplayPort | ✅ Almost always |
| HDMI | ⚠️ Depends on the port and monitor; the built-in HDMI on some Macs doesn't pass DDC |
| Docks, adapters, TVs | ⚠️ Often blocked |
| Apple displays & built-in screen | ✅ Native Apple brightness |

When a display can't be controlled directly, its menu label reads **Software dimming** and DisplayDeck dims it in software instead.

## 🔒 Privacy

Release builds send a few **anonymous** usage signals to [TelemetryDeck](https://telemetrydeck.com) so I can see how many people use DisplayDeck and whether hardware control works on their monitors:

- App and macOS version, region
- How many displays are connected and how each is controlled (DDC / software / Apple)
- Which options are on, and when the menu or settings window is opened

Each install is identified only by a hashed random ID. Nothing about you, your files or your screen is collected. Turn it off in **Settings → Share anonymous usage stats**. Builds from source send nothing.

## 🛠️ Build from source

No Xcode project. You only need the Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/rahgurung/DisplayDeck.git
cd DisplayDeck
./build.sh            # builds build/DisplayDeck.app
./build.sh --install  # also copies it to /Applications and launches it
```

Local builds are signed with your Apple Development certificate if you have one, so macOS keeps the Accessibility permission across rebuilds. Otherwise they're ad-hoc signed.

<details>
<summary><b>Project layout</b></summary>

```
Sources/
  App.swift             Menu bar extra, menu UI and app lifecycle
  DisplayManager.swift  Display discovery, modes and mirroring
  DisplayControl.swift  Apple brightness and software (gamma) dimming
  DDC.swift             DDC/CI over IOAVService (Apple Silicon)
  MediaKeys.swift       Brightness / volume key interception
  HUD.swift             On-screen level indicator
  SettingsWindow.swift  Settings window
  MenuBarIcon.swift     Menu bar template glyph
  Telemetry.swift       Anonymous usage signals (TelemetryDeck)
Resources/
  make-icon.swift       Draws the app icon: swift Resources/make-icon.swift
docs/                   Website (displaydeck.rahulgurung.com)
build.sh                Build, install and release build (sign, notarize, DMG)
release.sh              Tag and publish a GitHub release (updates the website)
```

</details>

<details>
<summary><b>Releasing</b></summary>

```sh
./release.sh 1.1
```

Builds with `./build.sh --release` (signs with your Developer ID, packages `build/DisplayDeck-1.1.dmg`, notarizes it with the `DisplayDeck` notarytool keychain profile and staples the ticket), then tags `v1.1` and publishes a GitHub release with the DMG. Publishing the release redeploys the website, so its download buttons point at the new version and the previous one moves to *Older versions*. Put `TELEMETRYDECK_APP_ID=…` in an untracked `release.env` to enable analytics in the build.

</details>

## ❓ Why isn't it on the Mac App Store?

DDC control needs private macOS APIs, and the brightness keys need a system-wide event tap. Neither is allowed in the App Store sandbox, which is why DisplayDeck, like MonitorControl and BetterDisplay, is distributed directly.

## 🤝 Contributing

Issues and pull requests are welcome. If your monitor doesn't respond to DDC, please [open an issue](https://github.com/rahgurung/DisplayDeck/issues/new) with the monitor model, the connection type and your Mac model.

## 📄 License

[MIT](LICENSE) © 2026 Rahul Gurung
