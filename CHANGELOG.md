# Changelog

Release notes for each version. The Release workflow publishes the section matching the version it releases;
patch releases (e.g. 1.1.1) fall back to the list of commits since the previous release.

## 1.2

### New
- **Automatic updates.** DisplayDeck checks for new versions once a day and offers to install them, with release notes. Use **Check for Updates…** in Settings or the menu to check right away, and turn automatic checks off in *Settings → Updates*.

If you're on 1.1.1 or earlier, install 1.2 by hand once (from the website or with `brew upgrade`); from then on DisplayDeck updates itself.

## 1.1.1

- **Current macOS look.** DisplayDeck is now built with the latest macOS SDK, so its menu, switches and sliders use the same modern style as the rest of macOS. It still runs on macOS 14 and later.

## 1.1

### New
- **Redesigned menu.** Each display gets its own card, with the resolution in a compact menu in the card header, mirroring on its own row, and icon buttons for Refresh, Settings and Quit.
- **Refresh rate at a glance.** External monitors show the current refresh rate next to the resolution, e.g. `2560 × 1440 · 144 Hz`.
- **Every refresh rate your monitor supports.** The refresh rate list now includes rates that are only available with HiDPI on or off, and tells you when picking one changes HiDPI.
- **New setting:** *Settings → Menu → Show refresh rate as a separate menu* puts resolution and refresh rate in two menus instead of one.

## 1.0

First release.

- Brightness, contrast and volume for external monitors over DDC/CI, with software dimming as a fallback.
- Brightness and volume keys control the monitor under the pointer, with an on-screen indicator.
- Resolution and refresh rate per display, display mirroring, and launch at login.
