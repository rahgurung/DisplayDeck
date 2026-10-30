# DisplayDeck: notes for Claude

A free, open-source macOS menu bar app (Swift + SwiftUI, Apple Silicon, macOS 14+) for external monitor brightness,
contrast, volume and input switching over DDC/CI. The website lives in `docs/` (displaydeck.rahulgurung.com).
No Xcode project: everything is built by `build.sh` with plain `swiftc`.

## Layout

| Path | What |
|---|---|
| `Sources/DDC.swift` | DDC/CI over I²C (private `IOAVService` calls). **All DDC I/O runs on one shared serial queue.** |
| `Sources/DisplayManager.swift` | `Display` (one per screen) and `DisplayManager` (reload on reconfiguration, following the built-in display). |
| `Sources/InputSource.swift` | Input names per manufacturer and the capabilities-string parser. |
| `Sources/MenuView.swift` | The menu bar panel (one card per display). |
| `Sources/SettingsWindow.swift` | Settings, as tabs (segmented control). |
| `Sources/MediaKeys.swift` | Brightness/volume key event tap (needs Accessibility). |
| `Sources/Shortcuts.swift` | Custom global shortcuts via Carbon `RegisterEventHotKey` (no Accessibility needed), stored as JSON under `shortcuts`. |
| `Sources/Updater.swift` | Sparkle; only active when the build has a feed URL. |
| `docs/` | Website: `index.html`, `compare.html`, generated `releases.json` / `appcast.xml`. |
| `CHANGELOG.md` | Release notes; the Release workflow publishes the section for the version. |

## Build and run

- `./build.sh` builds **DisplayDeck Dev** (`build/DisplayDeck-Dev.app`, executable `DisplayDeck-Dev`, bundle ID
  `com.rahulgurung.DisplayDeck.dev`), signed with the Apple Development certificate. It's a separate app from the
  release, with its own settings, Accessibility entry and login item, so **testing never touches the user's installed
  release**: never delete, replace or reset `/Applications/DisplayDeck.app` or the `com.rahulgurung.DisplayDeck`
  defaults/permissions. `./build.sh --install` copies the dev app to /Applications next to the release.
  `./build.sh --release` builds `build/DisplayDeck.app` with the release ID, signs with Developer ID, notarizes and
  makes the DMG (CI does this).
- The local version comes from `git describe` (e.g. `1.3-2-gabc1234`); without tags it falls back to 1.0. `VERSION=`
  overrides it. `build.sh` runs with `set -euo pipefail`, so any command that can fail in a checkout with no tags (like
  CI's shallow clone) needs `|| true`.
- Development builds have **no Sparkle feed** (no updates UI, never replace themselves). `SPARKLE_FEED_URL=…` enables
  it for testing.
- To try a change: `pkill -x DisplayDeck-Dev; open build/DisplayDeck-Dev.app`. The dev build quits a running release
  on launch and reopens it when it quits (also on `pkill`, which it handles as Quit), because two copies talking DDC (or
  both following the built-in display) fight each other. Hardware tests write to the dev build's own defaults
  (`defaults write com.rahulgurung.DisplayDeck.dev …`).

## Releasing

1. Add a `## X.Y` section to `CHANGELOG.md` (user-facing, bold lead-ins). Patch releases may skip it; they fall back to
   the commit list.
2. On an up-to-date, clean `main`: `./release.sh X.Y`. It pushes `release/X.Y`, which runs `.github/workflows/release.yml`,
   and waits for it. Patch releases: commit fixes on the `release/X.Y` branch and run `./release.sh` there.
3. The workflow builds, signs, notarizes, publishes the GitHub release (DMG + `appcast.json`), updates the Homebrew cask
   (`rahgurung/homebrew-tap`), and triggers `pages.yml`, which regenerates `releases.json` / `appcast.xml` and deploys `docs/`.
4. Verify: the release page, `https://displaydeck.rahulgurung.com/appcast.xml` (new version), `releases.json`, and the
   cask version (`gh api repos/rahgurung/homebrew-tap/contents/Casks/displaydeck.rb`).

Minor version for new features (1.3, 1.4), patch for fixes. Sparkle compares build numbers (count of `v*` tags + 1):
never delete a release tag.

**The website only deploys on a release** (or *Actions → Deploy website → Run workflow*), never on a push to main. Site
changes merged now go live with the next release, so they can describe features that ship in it.

**Website previews:** every pull request that changes `docs/` (or `Packaging/site-data.py`) is deployed by
`.github/workflows/preview.yml` to Cloudflare Pages at `https://pr-<N>.<project>.pages.dev`, linked from a sticky PR
comment, a *Website preview* check and a `website-preview` deployment on the branch (its *View deployment* button is
the only one of the three GitHub opens in a new tab; it strips `target` from comment links). Use that link to check site changes instead of only rendering locally. It needs the
`CLOUDFLARE_API_TOKEN` secret and `CLOUDFLARE_ACCOUNT_ID` variable; without them (and for forks) the job skips.

## Pull requests

- Branch from the latest `main` (`feature/…`, `fix/…`, `docs/…`).
- **Always squash-merge**, never a merge commit or rebase: `gh pr merge N --squash --subject "<summary> (#N)" --body "…"`,
  so each PR is one commit on `main`. Write the subject and body to describe the whole PR, not the branch's last commit.
- PR descriptions follow `.github/pull_request_template.md` (GitHub fills it in on the web; `gh pr create --body-file`
  doesn't, so start from it): *What this adds* (with screenshots), *How it works* (a file/change table), *Testing*
  (✅ verified, ⏳ not tried; say honestly what wasn't tested) with the **manual checks** for the areas the PR touches
  plus *Always*, and *Notes*. `Closes #N` for the issue. Keep the checklist up to date when a feature is added.
- CI (`ci.yml`) only builds; check it with `gh pr checks N --watch`.

### Screenshots in PRs

`gh` can't attach images, so they go on the **`pr-assets` orphan branch** (never merged), one folder per PR:

```sh
A=$(mktemp -d) && git fetch -q origin pr-assets && git worktree add -q $A -B pr-assets origin/pr-assets
mkdir -p $A/<pr-topic> && cp <pngs> $A/<pr-topic>/
git -C $A add -A && git -C $A commit -qm "Screenshots for <topic>" && git -C $A push -q origin pr-assets
SHA=$(git -C $A rev-parse HEAD); git worktree remove --force $A; git branch -D -q pr-assets
```

Link them pinned to that commit: `https://raw.githubusercontent.com/rahgurung/DisplayDeck/$SHA/<pr-topic>/<file>.png`,
and check each URL returns 200 before using it.

### Rendering screenshots

The terminal has no Screen Recording or Accessibility permission, so `screencapture` and AppleScript UI scripting fail.
Instead, render the real SwiftUI views offscreen:

- Copy `Sources/*.swift` except `App.swift` (it has `@main`) to a folder under `build/`, add a `main.swift` that builds a
  `DisplayManager`, waits ~6 s for DDC probing, puts the view in an `NSHostingView` inside an offscreen borderless window,
  and saves `bitmapImageRepForCachingDisplay` / `cacheDisplay` as PNG. Set `NSAppearance` for light/dark.
- For private views (e.g. `SettingsView`), drop `private` in the copy. For release-only UI, force
  `Updater.isAvailable = true` **and** make its `init` return early (starting Sparkle outside an app bundle blocks on a
  hidden alert), and force `Telemetry.isAvailable = true`. Link Sparkle: `-F .sparkle/Sparkle-2.10.0 -framework Sparkle
  -Xlinker -rpath -Xlinker .sparkle/Sparkle-2.10.0`.
- Run with a time limit (macOS has no `timeout`): `perl -e 'alarm 60; exec @ARGV' ./t`.
- The copy has its own `UserDefaults` domain, so preview data never touches the user's settings.
- Web pages: `qlmanage -t -s 1400 -o <dir> page.html` renders the top of a page; wrap it in an `<iframe>` 390 px wide for
  phone width.
- Offscreen capture of `TabView`'s tab bar is unreliable; open the real app for anything doubtful.
- `docs/screenshot.png` (README) is a render of the website's hero mock (`.stage` in `docs/index.html`), not of the
  app: update the mock to match the menu, then render it with headless Chrome from a copy of `docs/` whose page gets
  extra CSS hiding everything but `.stage` (`visibility: hidden` on `body *`, the stage `position: fixed; left: 20px;
  top: 18px; width: 940px`, its `.hud` hidden): `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  --headless=new --hide-scrollbars --force-device-scale-factor=2 --window-size=980,<stage height + 36>
  --screenshot=docs/screenshot.png file://…/index.html`.

## Project board and issues

- Board: [DisplayDeck Roadmap](https://github.com/users/rahgurung/projects/4) (project number 4, id `PVT_kwHOAdIOVM4Bomky`).
  - **Status** field `PVTSSF_lAHOAdIOVM4BomkyzhnF6G8`: Todo `f75ad846`, Ready `0bdf600b`, In Progress `47fc9ee4`,
    Done `98236657`. "Ready" means it can be picked up right away.
  - **Priority** field `PVTSSF_lAHOAdIOVM4BomkyzhnF6Ik`: P1 `626e0d13`, P2 `385bd3eb`, P3 `3821580d`. Priority lives only
    in this field, not in issue titles.
  - Move an issue to In Progress when starting it, and add its PR to the board (In Progress). Closing/merging moves them
    to Done automatically.
  - `gh project item-edit --project-id PVT_kwHOAdIOVM4Bomky --id <item> --field-id <field> --single-select-option-id <option>`
- Issues have a summary line, a **Competitors** section (table of what MonitorControl, Lunar, BetterDisplay and
  DisplayBuddy offer, with sources, plus "Our angle"), then Why / Scope. Mark unverified claims as such.
- Website links to other sites open in a new tab (`target="_blank" rel="noopener"`), including links made in
  scripts. Download buttons and links within the site don't.
- Keep `docs/compare.html` honest: every ✓ / Pro / — needs a source; otherwise "Not checked". Planned items link to issues.
  Update it when a planned feature ships.

## DDC and hardware notes

- MCCS defines input codes only up to `0x12` and nothing for USB-C; manufacturers (sometimes per model) pick their own.
  Known ones are in `InputSource.vendorNames`, keyed by EISA vendor number (`CGDisplayVendorNumber`: BenQ `0x09D1`,
  Dell `0x10AC`, LG `0x1E6D`, HP `0x22F0`). Unknown codes show as *This Mac* / *Other input*, never hex.
- The capabilities string takes ~2 s and blocks other DDC traffic, so it's read once per monitor per session.
- Two DDC transactions at once garble replies, which is why there's one shared queue. `Display` objects are rebuilt on
  every reload (wake, hot-plug, resolution change), so per-monitor state that must survive goes in static caches or
  `UserDefaults`, keyed by `vendor-model-serial`.
- Monitors auto-switch inputs when the chosen one has no signal; the app reads the input back rather than assuming.
- Following the built-in display: a curve through one point per monitor (`FollowCurve`), polled twice a second on a
  common-modes timer (default-mode timers stop while a slider is dragged).
- Dimming below the minimum (`dimBelowMinimum`, off by default): DDC monitors' brightness runs from −0.4 to 1. Below 0
  the monitor stays at DDC 0 and `GammaDimmer` dims it (a quarter of normal at −0.4). `GammaDimmer` tracks each
  display's level so one can be restored without undoing others. macOS restores gamma when the app exits, even on a
  crash (verified with `kill -9`). Levels below 0 are kept per monitor across reloads; following stays within 0–1.
- Turning a display off (button behind `showTurnOffButton`, off by default): DDC power mode (`0xD6`): 4 to sleep, 1 to wake. The BenQ reports 2 in standby, keeps
  answering DDC, and stays in macOS's display list; waking takes a few seconds and the first request can go unanswered,
  so `wake` retries. Monitors that don't answer `0xD6` (and the built-in display) are blacked out with gamma instead.
  While off, every command to the display is skipped (it could wake it). The last visible display can't be turned off.
- The maintainer's test setup: MacBook Air + BenQ EX271Q on USB-C (input `0x13`). Restore both screens' brightness
  after any test that changes them.
- Accessibility permission is per app: the dev build shows up as *DisplayDeck Dev* and the release as *DisplayDeck*.
  To clear the dev build's permission: `tccutil reset Accessibility com.rahulgurung.DisplayDeck.dev`. Real users keep
  the permission across updates.

## UI constraints

- Settings must fit a 1440 × 900 screen (~863 pt usable). Measure release-like height (updates + usage-stats rows) when
  adding settings; tabs exist for this reason.
- `TabView` draws blurry tab labels in this transparent-titlebar window; use the segmented control.
- Telemetry signals are listed in the README Privacy section; add new ones there.

## Gotchas

- Shell: `git describe` with no tags exits 128; `set -e` scripts need `|| true`. Avoid `git stash` + branch switching in
  long-running test scripts; use `git worktree add` for another branch instead.
- The Trash (`~/.Trash`) can't be listed from the terminal; use exact paths.
- When editing files with scripts, match by position, not by content, if several elements are identical (a past
  table edit changed the wrong column), and check the result.
