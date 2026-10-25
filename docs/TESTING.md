# Manual testing and known limitations

Run on a notched MacBook, with and without an external display, in light and dark mode, and over a full-screen app.
M1 and the M2 media card were also exercised programmatically (window bounds, accessibility tree, synthetic clicks, an
offscreen stub adapter); the visual checks below still need a person at the screen. See [`PROGRESS.md`](PROGRESS.md)
for what was already verified.

## M1 manual verification — notch panel shell

| Feature | Check | Expected |
| --- | --- | --- |
| F1 | Launch Brim with the lid open and no other app full screen. Look at the notch. | No visible window, glow or shadow at the notch. Nothing steals focus from the front app. |
| F1 | Open a full-screen app (for example Safari or a video). Move the pointer to the notch. | The panel appears over the full-screen app; no Space switch, no Dock icon. |
| F1 | Switch between Spaces (⌃←/⌃→) while the panel is collapsed. | A panel exists on every Space, still aligned to the notch. |
| F1 | Expand the panel, then click an app visible just below and beside the panel. | The click reaches the app; only the panel's visible rectangle takes clicks. |
| F2 | Hover the notch and stop moving. | A short black peek appears within ~150 ms (Settings → General → Peek delay). |
| F2 | Keep hovering after the peek. | The full panel grows downward with a spring; no flicker. |
| F2 | Click the notch once. | The full panel opens immediately. |
| F2 | Expand, then move away. Come back within the collapse delay. | The panel stays open. Leave again and wait ~400 ms: it collapses. |
| F2 | Move the pointer just below the panel edge. | The panel does not flicker; the exit area is a little larger than the panel. |
| F3 | Connect a second display. | One panel per eligible screen; nothing duplicated or left behind. |
| F3 | Disconnect the second display while a panel is open. | Its window disappears; the remaining panel is still aligned. |
| F3 | On a display without a notch, hover the slim handle at the top center. | Peek then expand exactly as on the notched display. |
| F3 | Settings → General → uncheck "Show a handle on displays without a notch". | The handle disappears immediately; the notched display is unaffected. Re-check it: the handle returns. |
| F4 | Expand the panel. | The clock card is visible in the expanded layout; the peek shows the compact clock. |
| F4 | Settings → Modules: turn the clock off, then on. | The panel updates immediately. With nothing enabled, the expanded panel says "No modules enabled" and links to settings. |
| F4 | Add a second module (M2 media) and use the up/down arrows. | The panel order follows the list and survives relaunch. (With only the clock in M1, both arrows are disabled; ordering is covered by unit tests.) |
| F4 | Turn on a module that needs a permission (M2). | No prompt at launch. Turning it on shows Brim's explanation sheet first, then macOS asks. Declining still enables it in a limited form. |
| F5 | Right-click the expanded panel. | A menu with Settings… and Quit Brim appears. Both work. |
| F5 | Settings → General: change both sliders and the handle toggle; quit and relaunch. | Values are restored from `~/Library/Application Support/Brim/settings.json`. |
| F5 | Settings → General → Launch at login. | It appears in System Settings → General → Login Items. The toggle reflects changes made there. Toggle it back off after testing a dev build. |
| F5 | Settings → About → Copy Diagnostics. | The clipboard contains version, macOS, displays/notches, the settings JSON and recent Brim log lines. |
| F5 | Use only the keyboard in Settings. | Tab reaches every control; Space toggles checkboxes; the window is readable and closable with ⌘W. |
| WCAG | Use VoiceOver on the panel and settings. | The gear is "Open Brim settings"; the handle is "Brim panel"; sliders and module toggles have labels; the panel exposes its module content. |
| Perf | Leave Brim collapsed for a minute, then check Activity Monitor. | Under 0.5% CPU and under 80 MB memory. No periodic polling visible in `log stream`. |
| Logs | `log stream --predicate 'subsystem == "com.harshshelar.brim"'` while hovering and opening settings. | Window/state/general messages appear; no `print` output. |

## M2 manual verification — media controls

Turn the media module on in Settings → Modules first. The first enable shows Brim's explanation, then macOS may ask for
Automation (only for Spotify or Music that is running). Declining must still leave macOS-reported media working.

| Feature | Check | Expected |
| --- | --- | --- |
| F6 | Play a track in Spotify or Music, then hover the notch. | The peek shows small artwork on the left, title/artist beside it and the playing indicator on the right. |
| F6 | Play a YouTube video in Safari, then hover the notch. | The same compact view appears with Safari as the source (artwork when macOS provides it). |
| F6 | With the panel expanded, look at the media card. | Artwork, title, artist, album, progress bar, elapsed/remaining time, previous / play-pause / next, and a source menu. |
| F6 | Press play/pause, next and previous in the expanded panel. | The player reacts immediately and the card updates. Pause shows a play glyph; the compact indicator stops animating. |
| F6 | Drag the progress bar, then release. | The player seeks to that position. While dragging, the time labels follow the pointer. |
| F6 | Let a track play for a few seconds without touching anything. | The progress bar and elapsed time advance every second while the panel is open; they stop when it closes. |
| F6 | Change track in the player while the panel is open. | Artwork and metadata update within one second. |
| F6 | Stop playback (or quit the player). | The media module hides from the peek; the expanded card shows the quiet "Nothing playing" state. |
| F6 | Play Spotify and Music at the same time. Open the source menu (or Settings → General → Follow). | Picking a player makes Brim follow it. Picking Automatic returns to whatever macOS reports. (The development machine only has Music installed; test Spotify on a machine that has it.) |
| F6 | Open Settings → General while a player runs. | The Follow picker lists Automatic plus installed Spotify/Music. Automation status is readable; "Grant Automation…" exists when it is not granted. |
| Permissions | Enable the media module with the player closed. | No Brim or macOS prompt appears (macOS cannot ask for a target that is not running). Start the player, then use Grant Automation…: the system prompt appears. |
| Permissions | Deny Automation, then play Safari/YouTube. | Media still appears through MediaRemote; Spotify/Music direct following falls back to Automatic. |
| Lifecycle | Open the panel, then close it and wait ~2 s. | `pgrep -fl mediaremote-adapter` is empty; the helper stops after the one-second grace. |
| Lifecycle | With the panel open, quit Brim, then repeat with `kill -9`. | No `perl … mediaremote-adapter` or `brim-media-supervisor` process survives. |
| Multi-display | Open a panel on each display, then close one. | The other panel keeps its media; the helper stops only when both are closed. |
| Perf | Leave Brim collapsed for a minute after using media. | Under 0.5% CPU and under 80 MB memory; no Perl helper while collapsed. |
| Settings | Change Follow, quit and relaunch. | The choice is restored from `settings.json`; schema is 2. |
| F5 | Settings → About → Copy Diagnostics. | The report includes a Media section: helper bundled/available, followed player, current track (no artwork). |
| F6 | Move the panel to a display without a notch while media plays. | Same compact/expanded media layout; no crash or stale artwork. |

### Media regression checks

- Build without the helper: `BRIM_SKIP_MEDIA_ADAPTER=1 ./build.sh`, then enable the module. The panel must not crash;
  the expanded card shows the empty state and the log says the helper is unavailable. Automation for a running,
  permitted player can still provide a track.
- Pin/update the adapter: run `./scripts/build-media-adapter.sh --force`, then
  `/usr/bin/perl build/Brim.app/Contents/Resources/MediaAdapter/mediaremote-adapter.pl "$PWD/build/Brim.app/Contents/Resources/MediaAdapter/MediaRemoteAdapter.framework" test`.
  Exit code 0 means the current macOS still allows the helper.
- ad-hoc signing: after a rebuild, Automation may need to be granted again. Check the Automation status in Settings.

## Notched vs non-notched geometry

- Notched screen: the collapsed window must equal the hardware notch (recorded 179×32 on the development machine).
  Hovering anywhere in that rectangle should peek; clicks in it should expand without activating Brim.
- Non-notched screen: the collapsed window is a 148×10 handle at the top center. It is intentionally interactive, so it
  can receive the click that opens the panel; everything outside its 148×10 rectangle passes through.
- Expanded panel: 600×320, clamped to the screen's width and centered on the screen (not on the notch width).

## Known limitations and notes for M1

- No screenshot-based visual test was possible in the agent environment (Screen Recording permission is not granted to
  the agent process). Use the manual table above for the final look-and-feel sign-off.
- The right-click menu is attached to the visible panel. Right-clicking the collapsed notch itself is left to the menu
  bar/underlying app; the panel is opened by hover/click, and its menu is available once it is visible.
- The collapsed notched window ignores mouse events on purpose. A click there is observed by the global pointer monitor
  and opens the panel, but it also reaches whatever is underneath the notch (normally nothing).
- M1 has no module that needs a permission. M2 wires the Automation check (per player) through the same
  explanation/enable flow; Accessibility, Calendar and the placeholder media-access kind still return `.notDetermined`.
- Launch at login is implemented through `SMAppService.mainApp`. Ad-hoc-signed dev builds can fail registration or
  become stale after a rebuild; test it once, then turn it off. Grant/registration behavior can differ from a
  properly signed release build.
- Settings are written on every change. Dragging a slider writes several times; this is intentional until a debounce is
  needed.
- The clock updates once a minute while the panel is visible; the collapsed panel has no timeline at all.
- Full-screen behaviour and window levels can change between macOS releases. If the panel stops appearing over a
  full-screen app, check `NotchWindow`'s level and collection behaviour first.
- The app is an agent (`LSUIElement`); it has no Dock icon and no menu bar icon. Settings is reachable from the panel
  context menu, the panel gear, or ⌘, while a Brim window is focused.

## Known limitations and notes for M2

- **MediaRemote is private.** The helper is `ungive/mediaremote-adapter` v0.7.7 (BSD-3), built from source by
  `scripts/build-media-adapter.sh` and loaded by `/usr/bin/perl`. If a macOS update closes that hole, the helper's
  `test` command fails and Brim falls back to Apple Events for Spotify/Music. Safari/Chrome would then lose media.
- The helper runs only while a panel is open, so the first peek can show the empty state for a fraction of a second
  while Perl starts. This is deliberate: keeping the stream alive while collapsed costs ~25 MB.
- The `stream` helper is wrapped in a one-second supervisor (a tiny `/bin/sh`) that watches Brim's PID. A crash or
  `kill -9` therefore cannot leave an orphaned Perl process; a normal quit stops it immediately.
- **Player choice covers Spotify and Music only.** Safari, Chrome, QuickTime and other players are whatever macOS
  reports; they cannot be chosen independently. Spotify's scripting dictionary has no artwork data, so when it is
  followed directly while another app owns the system Now Playing, the artwork placeholder is shown. Music artwork is
  read through Apple Events.
- Automation is granted per player and macOS refuses to prompt for a player that is not running. Start Spotify or
  Music before using Grant Automation…; the module still works through MediaRemote without it.
- With only Music installed (the development machine), the two-player acceptance check cannot be exercised against
  Spotify. The coordinator and menu logic are covered by unit tests with fakes.
- The expanded panel gives the media module layout priority so it gets more than half the width when the clock is also
  enabled. A card narrower than about 300 pt truncates the title; both modules still remain usable.
- The panel stays near-black in light and dark mode on purpose; only the settings window follows the system appearance.
- The adapter build needs CMake and network access on the first run. `BRIM_SKIP_MEDIA_ADAPTER=1 ./build.sh` produces an
  app without it; the rest of Brim works.
