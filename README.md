# DisplayDeck

A tiny macOS menu bar app for controlling your displays — including external monitors — without touching their buttons.

- **Brightness, contrast and volume** for external monitors over DDC/CI, with a software dimming fallback for monitors that don't support it
- **Brightness and volume keys** work on external monitors, with an on-screen HUD
- **Resolution and refresh rate** pickers per display
- **Mirror displays** toggle
- **Launch at login**

## Install

**Homebrew**

```sh
brew install --cask rahgurung/tap/displaydeck
```

**Manual:** download the latest `DisplayDeck-x.y.dmg` from [Releases](https://github.com/rahgurung/DisplayDeck/releases), open it and drag DisplayDeck to Applications.

Requires an Apple Silicon Mac running macOS 14 Sonoma or later.

### Permissions

To make the brightness/volume keys control your monitors, DisplayDeck asks for **Accessibility** access (System Settings → Privacy & Security → Accessibility). Everything else works without it, and you can turn the key handling off in the menu.

## Notes

- DDC support depends on the monitor and the connection. Most DisplayPort and USB‑C monitors work; some HDMI ports (notably the built-in HDMI on some Macs) and many TVs or docks don't pass DDC through. When DDC isn't available, DisplayDeck dims the screen in software instead.
- DisplayDeck uses private macOS APIs for DDC and built-in display brightness, which is why it isn't on the Mac App Store.

## Privacy

Release builds send a few anonymous usage signals to [TelemetryDeck](https://telemetrydeck.com) so I can see how many people use DisplayDeck and whether hardware (DDC) control works on their monitors: app and macOS version, region, how many displays are connected and how each is controlled, which options are on, and when the menu or settings window is opened. Each install is identified only by a hashed random ID, and nothing about you, your files or your screen content is collected. Turn it off in Settings → *Share anonymous usage stats*. Builds from source send nothing.

## Build from source

No Xcode project needed — just the Command Line Tools.

```sh
./build.sh            # builds build/DisplayDeck.app (ad-hoc signed)
./build.sh --install  # also copies it to /Applications and launches it
swift Resources/make-icon.swift  # regenerates Resources/AppIcon.icns
```

## License

[MIT](LICENSE)
