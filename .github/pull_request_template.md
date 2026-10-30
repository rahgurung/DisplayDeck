Closes #

## What this adds

<!-- What changes for people using DisplayDeck, with screenshots (see CLAUDE.md → Screenshots in PRs). -->

## How it works

| File | Change |
|---|---|
| | |

## Testing

<!-- ✅ verified, ⏳ not tried. Say honestly what wasn't tested. -->

### Manual checks

Test with `./build.sh` and `open build/DisplayDeck-Dev.app`, on a Mac with an external monitor (DDC). Tick the areas this
PR touches, plus **Always**. Delete the sections that don't apply, or leave them unticked and say why under Notes.

<details open>
<summary><b>Always</b></summary>

- [ ] It builds with no warnings, and DisplayDeck Dev launches with its menu bar icon.
- [ ] The menu opens with one card per display, and its sliders move the real displays.
- [ ] Settings opens; every tab fits the window (no cut-off text, all tabs visible), in light and dark mode.
- [ ] Quitting DisplayDeck Dev leaves every display at normal colours and awake.
</details>

<details>
<summary><b>Menu and display controls</b></summary>

- [ ] Brightness, contrast and volume sliders change the monitor; the numbers match.
- [ ] The MacBook slider follows the Mac's own brightness keys and auto-brightness while the menu is open.
- [ ] Resolution and refresh rate menus switch modes; *Show refresh rate as a separate menu* splits them.
- [ ] *Mirror displays* turns mirroring on and off.
- [ ] Refresh, Settings… and Quit in the footer work.
</details>

<details>
<summary><b>Inputs</b></summary>

- [ ] The input menu lists the monitor's inputs with real names (USB-C, HDMI 1…), never hex codes.
- [ ] Switching to an input with nothing connected: the row follows the monitor back to the input it falls back to.
- [ ] *Rename Inputs…* renames them; *Reset* brings the defaults back; names survive a relaunch.
</details>

<details>
<summary><b>Brightness and volume keys</b> (Settings → Keyboard)</summary>

- [ ] Brightness keys change the display under the pointer, with the on-screen indicator.
- [ ] Volume keys change a monitor's speakers (if it has them).
- [ ] *Keys adjust all displays at once* changes every display; holding ⌃ does the other for one press.
- [ ] Accessibility: granting it starts the keys; **revoking it doesn't freeze the Mac**; granting again works without a relaunch.
</details>

<details>
<summary><b>Following the built-in display</b> (Settings → Displays)</summary>

- [ ] With it on, monitors change with the MacBook's brightness, auto-brightness included, also while dragging its slider.
- [ ] Moving a monitor's slider sets its balance, which it keeps across the range.
- [ ] With it on, brightness keys don't move a monitor twice.
</details>

<details>
<summary><b>Dimming below the minimum</b> (Settings → Displays)</summary>

- [ ] With it on, a monitor's slider goes to −40; below 0 it gets darker and the icon becomes a moon.
- [ ] Brightness down at the minimum carries on below 0; the indicator says *Below minimum*.
- [ ] Turning the setting off, or quitting, brings the picture back to normal.
</details>

<details>
<summary><b>Turning a display off</b> (Settings → Displays)</summary>

- [ ] With the setting on, each card has the crossed-out sun; with it off, cards look as before.
- [ ] A monitor goes to standby and *Turn On* wakes it (a few seconds); the MacBook screen goes black and comes back.
- [ ] The last display you can see can't be turned off.
- [ ] Quitting with a monitor off wakes it.
</details>

<details>
<summary><b>Shortcuts</b> (Settings → Shortcuts)</summary>

- [ ] Recording a shortcut works; it runs in another app; holding a brightness/contrast/volume one repeats.
- [ ] One modifier (⌘K) is refused with *Add two of ⌃ ⌥ ⌘*; a macOS shortcut is refused or flagged with the reason under the row.
- [ ] An input shortcut switches the monitor; a contrast/volume shortcut over the MacBook says the display has none.
- [ ] Esc cancels, Delete clears, ⓧ removes; shortcuts survive a relaunch.
</details>

<details>
<summary><b>Presets</b> (Settings → Presets)</summary>

- [ ] Saving, renaming, updating (⟳) and deleting a preset work, and survive a relaunch.
- [ ] The menu's Presets row appears once a preset exists; picking one sets every display to its own saved levels.
- [ ] The pill names the preset while the levels match, and says *Choose* after a slider moves.
- [ ] A preset's shortcut applies it.
</details>

<details>
<summary><b>Sleep, wake and plugging in</b></summary>

- [ ] After the Mac sleeps and wakes, and after unplugging and replugging the monitor, its card comes back with the right levels and input.
- [ ] Settings that live per monitor survive it: input names, following balance, dimming below 0, turned off.
</details>

<details>
<summary><b>Release builds</b> (only when changing updates, signing or the release)</summary>

- [ ] The DMG opens without a security warning; dragging to Applications and launching works.
- [ ] *Check for Updates…* (Settings → General) finds the newest release; automatic checks can be turned off.
- [ ] Usage stats can be turned off in Settings → General.
</details>

<details>
<summary><b>Website</b> (when <code>docs/</code> changes)</summary>

- [ ] The *Website preview* deployment (View deployment) shows the change, on the home page and `/compare`.
- [ ] Links to other sites open in a new tab; download buttons work.
- [ ] It reads well at phone width.
- [ ] The comparison page only claims what's sourced; anything new is marked ✓ with a source.
</details>

## Notes

