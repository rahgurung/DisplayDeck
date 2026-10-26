# Changelog

Release notes for each version. The Release workflow publishes the section matching the version it releases;
patch releases (e.g. 1.1.1) fall back to the list of commits since the previous release.

## 1.5

### New
- **Your own keyboard shortcuts.** Set shortcuts for brightness, contrast, volume and mute, and for switching a monitor to any of its inputs, in the new *Settings → Shortcuts* tab. They work on any keyboard, including ones without Mac media keys, in every app, and don't need Accessibility access. Hold one to keep adjusting.
- **Darker than the monitor's minimum.** Turn on *Settings → Displays → Dim monitors below their minimum*, then drag a monitor's brightness below 0 (or keep pressing brightness down) to darken it further for late nights. A moon shows when you're past the monitor's own minimum. Off by default.
- **Turn a display off.** Turn on *Settings → Displays → Show a turn-off button on each display* for a button that puts a monitor to sleep, or blacks out a display that can't sleep, with one click. Click it again, or *Turn On*, to bring it back. DisplayDeck never turns off the last screen you can see, and wakes monitors when it quits. Off by default.

### Fixed
- **The MacBook slider keeps up.** Its brightness slider in the menu now follows the Mac's own brightness keys and auto-brightness, instead of showing the level from when DisplayDeck started.


### New
- **Monitors follow your MacBook's brightness.** Turn on *Settings → Displays → Monitors follow the built-in display* and your monitors change with the built-in screen, auto-brightness included. Move a monitor's slider once to keep it brighter or dimmer, and it keeps that balance across the whole range. Off by default.
- **Brightness and volume keys for every display at once.** Turn on *Settings → Keyboard → Keys adjust all displays at once*, or hold ⌃ Control for one press. The on-screen indicator says *All displays* when more than one changes.
- **Settings in tabs.** General, Displays, Keyboard and Updates, so Settings fits on smaller screens.

### Fixed
- **No more freeze when turning off Accessibility.** Revoking DisplayDeck's Accessibility access in System Settings could freeze the keyboard and mouse. DisplayDeck now lets go of the keys right away, and picks them up again if you grant access later.
- **No more cut-off text in Settings.** Long descriptions wrap instead of ending in "…".

## 1.3

### New
- **Input switching.** Each external monitor's card has an **Input** row for switching between DisplayPort, HDMI and USB-C, no monitor buttons needed. DisplayDeck lists the inputs your monitor reports and names them using each manufacturer's codes. If you pick an input with nothing connected, the row follows the monitor back to the input it lands on.
- **Name your inputs.** Choose *Rename Inputs…* in the input menu to call them "Work laptop", "PS5" or anything else. Names are kept per monitor; *Reset* brings back the defaults.

## 1.2.1

- **Simpler menu.** The Check for Updates button is gone from the menu footer; it's in *Settings → Updates*, and automatic checks are unchanged.

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
