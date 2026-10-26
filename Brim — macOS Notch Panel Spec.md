# Brim — macOS Notch Panel Spec

Oct 25, 2026 · @Harsh Shelar

## Overview

**Brim** is a native macOS app that turns the MacBook notch into a small panel that drops down when you hover over it, in the spirit of NotchNook (getnotchnook.com). The notch is the top edge of the screen, like the brim of a glass, and the name nods to its sibling app, Speakeasy.

This spec is written for a coding agent. Build milestone by milestone; each feature has acceptance criteria that define "done."

**Goals**

- Put glanceable, controllable things (starting with media) right where the pointer already goes: the notch.
- Feel native: SwiftUI content, fluid system-style animations, light and dark mode, near-zero idle CPU.
- Stay modular: the panel hosts pluggable modules, so new features (AI tools, later) slot in without touching the shell.
- Work on screens without a notch too, through a slim handle at the top center.

**Non-goals**

- Mac App Store distribution (MediaRemote and the notch window tricks need APIs outside the sandbox). Run locally, ad hoc signed.
- Supporting macOS versions older than macOS 14 Sonoma.
- Managing menu bar icons. That's Speakeasy's job.

**Why Brim is separate from Speakeasy**

- Speakeasy promises no network access and minimal permissions. Brim needs Now Playing, Automation, and later probably Calendar, Camera, Bluetooth and network access for AI tools.
- Crash isolation: a Brim crash must never leave Speakeasy's hidden menu bar icons stuck off-screen.
- Separate bundle IDs mean rebuilding one ad hoc signed app doesn't drop the other's Accessibility grant.
- The only overlap is screen and notch geometry, which is small enough to copy.

**Platform and stack**

| Item | Choice |
| --- | --- |
| Language | Swift 5.10+ (Swift 6 strict concurrency where practical) |
| UI | SwiftUI for panel content and settings; AppKit (`NSPanel`) for the notch window |
| Min OS | macOS 14 Sonoma; primary target is the current macOS release |
| Hardware | Apple Silicon MacBook with a notch is the primary test machine |
| App type | Agent app: `LSUIElement = YES`, no Dock icon |
| Bundle ID | `com.harshshelar.brim` |
| Dependencies | Prefer none. Ask before adding any |

## Core concept and architecture

Brim owns one borderless, non-activating `NSPanel` per screen. The window sits above the menu bar, centered on the notch, and is sized to the notch when collapsed. Hovering grows it into a rounded black panel that looks like the notch growing downward. SwiftUI draws everything inside; AppKit only positions the window and tracks the pointer.

**Layers**

| Layer | Folder | Responsibility |
| --- | --- | --- |
| Window | `Sources/BrimKit/Window/` | `NotchWindow` (`NSPanel`), per-screen window manager, pointer tracking |
| State | `Sources/BrimKit/State/` | Hover/expand state machine, timers; pure logic, no AppKit |
| Modules | `Sources/BrimKit/Modules/` | `BrimModule` protocol and its implementations (Media first) |
| Services | `Sources/BrimKit/Services/` | Protocols plus real implementations (screens, now playing, login item, settings) |
| UI | `Sources/BrimKit/UI/` | SwiftUI panel views and settings; never touches `NSPanel` |

Each service is a Swift protocol with one real implementation and one fake for tests; the UI never calls a macOS API directly.

**Data model**

| Type | Fields |
| --- | --- |
| `ScreenInfo` | id, frame, notchRect (optional), topInset |
| `PanelState` | `.collapsed`, `.expanded` (the peek was removed in F9) |
| `BrimModule` | id, title, live activity and ear views, expanded view, required permissions, isEnabled |
| `NowPlaying` | title, artist, album, artwork, duration, elapsed, isPlaying, sourceApp |
| `Settings` | hoverDelay, collapseDelay, opensOnHover, showLiveActivity, launchAtLogin, enabledModules, displayMode, media and agent options, schemaVersion |

**Reuse from Speakeasy** (copy and adapt, don't depend on it)

- `Package.swift` layout: executable `Brim` + library `BrimKit` + test target `BrimTests`, macOS 14.
- `build.sh`: builds `build/Brim.app`, copies resource bundles, signs ad hoc.
- `Resources/Info.plist`: `LSUIElement = YES`. Add usage strings only when a feature needs them.
- `Support/Log.swift`: the `os.Logger` category pattern.
- `ScreenInfo` + `notchRect` (Speakeasy `Model/Section.swift`) and the `NSScreen` adapter (Speakeasy `MenuBar/SystemAdapters.swift`), which find the notch with `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`.
- `LoginItemService`, `SettingsStore`, and the fakes-based testing approach.

## Milestone 1: Notch panel shell

M1 delivers an empty but polished panel: it lives over the notch, opens on hover, closes when the pointer leaves, and hosts a placeholder module. No permissions needed.

**F1. Notch window**

A borderless, non-activating `NSPanel` with level above `.mainMenu`, `collectionBehavior` `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` and a transparent background, centered on `notchRect`.

- [x] When collapsed, the window lines up exactly with the hardware notch and can't be seen.
- [x] Never takes keyboard focus or activates Brim when it opens.
- [x] Appears on every Space. *Amended by F14: it hides while another app is full screen on that display.*
- [x] Clicks outside the visible panel shape pass through to the menu bar and apps below.

**F2. Hover and expand**

A pure state machine: collapsed → peek on hover → expanded on click or longer hover → collapsed when the pointer leaves, after a delay. *Amended by F9: hover opens the full panel directly.*

- [x] Hovering the notch shows a short peek within the hover delay (default 150 ms).
- [x] Clicking, or hovering longer, opens the full panel with a spring animation.
- [x] Leaving the panel collapses it after the collapse delay (default 400 ms); coming back cancels the collapse.
- [x] State machine logic is unit tested with a fake clock.

**F3. Multiple displays and screens without a notch**

- [x] One window per screen; windows rebuild on `NSApplication.didChangeScreenParametersNotification`.
- [x] On a screen without a notch, a slim handle at the top center opens the same panel (setting, default on).
- [x] Plugging in or removing an external display never leaves a stray or misplaced window.

**F4. Module host**

The expanded panel shows enabled modules side by side. `BrimModule` is the extension point for every future feature.

- [x] A placeholder module (clock or date) renders in compact and expanded layouts.
- [x] Modules can be enabled, disabled and reordered from settings.
- [x] A module that needs a permission asks for it only when it's turned on, after an in-app explanation.

**F5. Settings and launch at login**

- [x] Menu bar-free access: right-clicking the panel opens a menu with Settings and Quit.
- [x] Settings window: launch at login, hover delay, collapse delay, screens without a notch, modules.
- [x] Settings persist as versioned JSON in Application Support.

## Milestone 2: Media controls

**F6. Now Playing**

Show what's playing and control it. Behind a `NowPlayingService` protocol with a fake for tests.

Known risk, check first: since macOS 15.4, MediaRemote's now-playing calls refuse apps that don't hold Apple's special permission. Options:
1. The community `mediaremote-adapter` workaround, which runs the calls through the system Perl (it has that permission). Covers every app macOS shows as Now Playing.
2. Apple Events to Spotify and Music.app. Needs the Automation permission and covers only those two apps.

Prototype option 1; fall back to option 2 if it breaks.

- [x] Compact view: small artwork on the left of the notch and a playing indicator on the right while media plays. *Delivered by F10 (live notch).*
- [x] Expanded view: artwork, title, artist, progress bar, and previous / play-pause / next buttons.
- [x] Works with Spotify, Music.app and Safari (YouTube); updates within 1 s of a track change.
- [x] When nothing is playing, the module hides or shows a quiet empty state.
- [x] If two apps are playing, the user can pick which one Brim follows.

## Milestone 3: AI tools and IDE integration

M3 starts with local agent status. Quick prompt and send-to-assistant (F19, F20) are specified in "Milestone 3,
continued", after the panel input features (F15–F18) they depend on.

**F7. Agent status**

Coding tools report what they are doing to Brim over a local Unix socket or a `brim://agent` URL. Every integration is
still a `BrimModule`; this first one needs no permission and no network.

- [x] A tool can report `working`, `waiting`, `done` or `error` for a session, with an optional title, detail, cost and working directory.
- [x] The peek shows the most urgent state (waiting, then failed, then working, then done) and hides when there is no activity.
- [x] The expanded panel lists sessions with agent, title, detail, elapsed time and cost; waiting sessions come first and can be dismissed.
- [x] Finished and failed sessions expire after the configured retention (default 10 minutes); working and waiting sessions stay until they report again or are cleared.
- [x] The transport is local only: the socket lives in Application Support with `0600` permissions, accepts only the current user, and is removed when the module is disabled or Brim quits. Malformed, oversized and stale events are ignored.
- [x] `brim://agent` works while Brim is running and launches it when it is not. The URL parser accepts only the documented fields.
- [x] Enabling Agent Status starts the listener; disabling it stops the listener and clears the roster. No permission prompt appears at launch or when the module is enabled.
- [x] Settings schema 3 stores the retention period and migrates schema 2 files without losing values.
- [x] Claude Code is documented as the reference integration; the same contract works for Codex, Cursor, VS Code and any tool that can write one JSON line or open a URL.

**F8. Agent alerts and project actions**

Agent alerts are opt-in, local, and never requested at launch.

- [x] A session that newly enters `waiting` or `error` while no panel is open produces one alert; repeated events in the same state do not repeat it, and a transition back through working can alert again.
- [x] Alerts use a macOS notification when the build has permission, and Brim's own notch card otherwise. The notch card is non-activating, auto-dismisses, and carries the same title/body.
- [x] Clicking an alert or the folder button on an agent row opens the session's `cwd` in Finder. Rows without a path have no folder action.
- [x] Enabling alerts shows an in-app explanation before any system permission request; denial leaves the notch alert working.
- [x] Settings schema 4 stores the opt-in flag and migrates older files without losing values.
- [x] Diagnostics include the alert setting and authorization state.

## UX revision: live notch

A review against NotchNook (Oct 25, 2026) found that Brim's notch shows nothing until it is hovered, so the two things
Brim is for, what's playing and an agent waiting on you, aren't glanceable. Hovering also passed through a peek that
duplicated the panel, agent alerts led to Finder instead of the agent, and the headline features were hard to set up.
This revision makes the collapsed notch carry live content and fixes the setup and alert problems from the same review.

It amends F2 (the peek is gone), F6 (the compact view is now the live notch) and F8 (alert placement and action).
Where it conflicts with them, this section wins. Build it before the remaining M3 features.

**F9. Hover opens the panel**

The live notch (F10) is now the glanceable state, so hovering goes straight to the full panel.

- [x] Resting on the notch, the live notch or the handle for the hover delay (default 150 ms) opens the full panel.
  There is no intermediate peek; `PanelState` is `.collapsed` or `.expanded`.
- [x] Settings → Open the panel: "On hover" (default) or "On click". In click mode hovering does nothing and a click
  opens the panel.
- [x] Leaving still collapses after the collapse delay, and coming back cancels it.
- [x] Opening the panel plays a light haptic tap on trackpads that support it.
- [x] With Reduce Motion on, the panel appears and disappears with a cross-fade instead of growing.
- [x] Settings schema 5 stores the open mode; older files migrate without losing values.
- [x] State machine tests cover hover mode, click mode and the live notch hit area.

**F10. Live notch**

When a module has something live, the collapsed notch widens sideways at menu-bar height and shows it in the two
"ears" beside the hardware notch, the way NotchNook shows Now Playing.

- [x] While media plays, the left ear shows the artwork and the right ear an animated playing indicator, within 1 s of
  playback starting. It hides 3 s after playback pauses or stops, so a track change doesn't make it flicker.
- [x] An agent session in `waiting` or `error` shows its status glyph (orange or red), with a count when several
  sessions share it. This takes priority over media. A `working` session shows a quiet glyph only when nothing else
  is live. Opening the panel acknowledges failures: they stay listed but stop lighting the notch.
- [x] Modules publish a `LiveActivity` (a priority) and draw their own ear views; the shell shows the highest-priority
  activity, with ties going to module order. The window shell knows nothing about media or agents.
- [x] Hovering or clicking the live notch opens the panel. Clicks on the ears never fall through to the menu bar.
- [x] With nothing live, the collapsed notch is invisible exactly as in F1.
- [x] On screens without a notch, live content replaces the handle with a small black pill at the top center, as tall
  as the menu bar (under the same "screens without a notch" setting).
- [x] Settings → "Show activity beside the notch" (default on). Off restores the hover-only behaviour. Stored in
  schema 5.
- [x] While that setting is on and Now Playing is enabled, the media helper runs continuously rather than only while
  the panel is open. It stops when the module is disabled, when the setting is turned off and no panel is open, and
  when Brim quits or crashes. If it exits, Brim restarts it with a backoff (5 s, 30 s, then every 5 minutes).
- [x] Brim plus its helper stay under 0.5% CPU and 80 MB while idle. Polling a followed player over Apple Events slows
  to every 3 s while the panel is closed.

**F11. Agent alerts that lead somewhere**

- [x] The notch alert hangs from the top edge of the screen under the pointer (falling back to the notched screen)
  and uses the panel's shape, so it reads as the notch dropping down.
- [x] Opening a panel dismisses a visible notch alert.
- [x] Clicking anywhere on the alert performs its open action. Hovering it pauses the auto-dismiss.
- [x] Events accept an optional `app` field: a bundle identifier, validated and never executed. The open action on
  alerts, notifications and rows brings that app to the front when it is installed, and otherwise opens `cwd` in
  Finder. Rows without either have no open action.
- [x] The Claude Code hook reports `app` from the terminal or editor that runs it and uses the project folder name as
  the session title.

**F12. First run and setup**

- [x] New installs enable Now Playing and Clock. Existing settings keep their module list.
- [x] Enabling Now Playing asks for nothing. Automation is explained and requested only when the user chooses to follow
  Spotify or Music. Choosing a player in the panel without Automation opens Settings → Media instead of failing
  silently.
- [x] Opening Brim again (Finder, Spotlight, `open -a Brim`) opens Settings. The first launch opens Settings with a
  short note on how to use the notch.
- [x] Settings → Agents can install the Claude Code hook, after an explanation of exactly what changes. It writes
  `~/.brim/claude-hook.sh`, backs up `~/.claude/settings.json` and merges Brim's hooks into it without touching other
  hooks. It refuses to edit a file it cannot parse, shows whether the hook is installed or out of date, can remove the
  hook again, and can show a test session in the panel.
- [x] Settings has General, Media, Agents, Modules and About tabs, with each module's options in its own tab.

**F13. The panel fits its modules**

- [x] The expanded panel is about 290 pt wide per enabled module (at least 460 pt), clamped to the screen. Enabling,
  disabling or reordering modules resizes it.
- [x] The clock's time stays on one line at any width.
- [x] With two modules enabled, the media card uses its full layout (album and source name visible).

**F14. Out of the way in full screen**

Watching a full-screen video should not leave Brim's ears or handle on top of it.

- [x] While another app is full screen on a display, Brim hides its notch, live notch, handle and pill there and
  ignores the pointer; an open panel collapses. Other displays are unaffected.
- [x] Leaving full screen, or switching back to a desktop Space, brings them back within about a second.
- [x] A zoomed window is not full screen, including on a notched display where both stop below the menu bar strip.
- [x] Detection reads the public window list on Space, app and display changes: no permission prompt, no polling.
- [x] Agent alerts are unaffected; they are opt-in and time-sensitive.

## Panel input

Designed with the user on Oct 26, 2026. These are the foundations the rest of M3 needs: a way to reach the panel
from the keyboard, a panel that can take focus, and a drop target on the notch. Build F15–F18 before F19 and F20.

**F15. Choose displays**

- [x] Settings → General → "Show Brim on": All displays (default), Only the notched display, or Only the main display
  (the one with the menu bar in System Settings → Displays). It replaces the "screens without a notch" toggle.
- [x] Changes apply immediately, and plugging displays in or out follows the choice without a relaunch.
- [x] "Only the notched display" with no notched display connected (lid closed) falls back to the main display, so
  Brim never disappears entirely.
- [x] The notch alert (F11) appears on the pointer's display when Brim is shown there, otherwise on the first display
  that shows Brim.
- [x] Settings schema 6 stores the choice. Migration maps the old toggle: on → All displays, off → Only the notched
  display. Diagnostics include it.

**F16. Keyboard**

- [ ] Settings → General has a shortcut recorder for "Open Brim", empty by default, with a Clear button. It is
  registered as a system hot key, so no permission prompt appears. Shortcuts without ⌘, ⌥ or ⌃ are rejected, and a
  combination macOS refuses (already taken) is reported in Settings, not silently ignored.
- [ ] The shortcut opens the panel on the display under the pointer (or the first display that shows Brim). Pressing
  it again, pressing Esc, or clicking outside the panel closes it.
- [ ] A panel opened by the shortcut takes keyboard focus without activating Brim: the front app keeps its menu bar,
  and when the panel closes, typing goes back to that app. It does not collapse when the pointer moves away.
- [ ] Panels opened by hover or click stay non-activating exactly as in F9. The one exception is the quick prompt field
  (F19): clicking it is a request to type, so it takes focus.
- [ ] With focus, Tab moves between the panel's controls and Space/Return activate them; VoiceOver reads them.
- [ ] The shortcut works over a full-screen app (F14): an explicit request shows the panel there, and it hides again
  when closed.
- [ ] The shortcut is stored in settings schema 6.

**F17. Gestures**

- [ ] A two-finger scroll down (or a mouse-wheel step down) over the notch, live notch, pill or handle opens the panel
  at once, in both hover and click modes. A scroll up over the panel's top strip (the notch-height band) closes it;
  scrolling inside a card still scrolls the card.
- [ ] A horizontal two-finger swipe over the ears while media is live skips tracks: swipe left for next, right for
  previous, without opening the panel. One swipe is one skip; trailing momentum never skips twice.
- [ ] Swipes over agent ears, and gestures on a display hidden by F14, do nothing.
- [ ] No permission is needed. Scroll events come from the existing pointer monitor and the panel window; nothing
  polls.

**F18. Drop onto the notch**

- [ ] While files or text are being dragged anywhere, bringing the pointer to the notch, live notch, pill or handle
  opens the panel into a drop view with one zone per module that accepts drops. Drags are noticed from the drag
  pasteboard and mouse-drag events; no permission is needed.
- [ ] Dropping on a zone hands the files or text to that module. Dropping elsewhere, or dragging out of the panel
  (with the usual exit slop and collapse delay), does nothing and collapses it.
- [ ] Modules declare the drop types they accept; the shell knows nothing about prompts or files. With no module
  accepting drops, a drag never opens the panel. The first zone arrives with F20.
- [ ] Displays hidden by F14 never open for a drag.

## Milestone 3, continued: quick prompt and send to assistant

Designed with the user on Oct 26, 2026. Quick prompt runs the user's own Claude Code CLI rather than calling a model
API: it reuses the Claude login the user already has, needs no API key, and Brim itself still makes no network
requests. The network traffic is Claude Code's, which the module's explanation says plainly.

**F19. Quick prompt**

- [ ] A Quick Prompt module, off by default. Turning it on explains what happens: Brim runs the installed `claude`
  command with read-only tools, under the user's Claude login. No macOS permission is involved.
- [ ] Brim finds `claude` on the login shell's `PATH` and in the usual install folders, and Settings shows which one
  it found. When none is found, Settings explains how to install it and accepts a path. Brim never runs a command it
  could not find or the user did not point it to.
- [ ] With the module on, the open panel has a prompt bar across the top. A panel opened by the shortcut focuses it.
  Return sends; the module cards make way for a scrolling answer view; Esc or Done brings the cards back.
- [ ] The prompt runs in a folder shown in the prompt bar: the most recent agent session's project (F7) by default, or
  one picked from recent folders or a folder panel. With no folder it runs in an empty scratch folder in Application
  Support, which makes it plain chat.
- [ ] Only read-only tools are available (Read, Grep, Glob). Nothing can edit files, run commands or fetch from the
  web. The prompt and folder are passed as process arguments, never through a shell.
- [ ] The answer streams in as it arrives, with paragraphs, lists and code blocks rendered, and a Copy button.
  Stop ends the run. A follow-up in the same bar continues the same Claude Code session; New starts over.
- [ ] If the panel closes while an answer is streaming, the run continues. The live notch shows a quiet working glyph,
  then a done glyph until the panel is opened again.
- [ ] A missing CLI, a Claude login problem or a non-zero exit shows a short, readable error in the answer view, with
  the detail in the log. One prompt runs at a time; the process ends when Brim quits.
- [ ] Nothing runs while no prompt is in flight, so the idle budget is unchanged.
- [ ] Settings schema 7 stores the module's options (CLI path override, recent folders).

**F20. Send to assistant**

- [ ] With Quick Prompt on, F18's drop view shows an "Ask Claude" zone. Dropped files and text attach to the prompt as
  removable chips, and the prompt field takes focus, since the drop was an explicit request.
- [ ] The prompt bar has buttons to attach the clipboard (text, files or an image) and a screenshot. A second
  recordable shortcut, "Ask about selection", attaches the text selected in the front app and opens the prompt.
- [ ] Clipboard and dropped files need no permission. A screenshot asks for Screen Recording, and selected text asks
  for Accessibility, each only on first use and after an in-app explanation. When one is denied, its button explains
  why it is unavailable and the other sources keep working.
- [ ] Attached files are made readable to Claude Code for that run only (their folders are added as extra read-only
  directories). Screenshots and pasted images are written to a temporary folder that is deleted when the
  conversation ends or Brim quits.
- [ ] Limits are explicit: at most 10 attachments, and files over 20 MB are refused with a message.
- [ ] The second shortcut is stored in settings schema 7.

Each integration ships as a `BrimModule`.

## Stretch goals

Build these only after M2 is stable; each is independent. On Oct 26, 2026 the user chose not to design any of them
yet.

- **S1. File tray.** Drop files on the notch to park them; drag them back out or AirDrop them. Decided already: the
  tray keeps references (not copies) across restarts until the user removes them, and greys out files that moved.
  It would be a second F18 drop zone.
- **S2. Calendar.** Upcoming events via EventKit with meeting join buttons.
- **S3. Speakeasy integration.** Show Speakeasy's hidden menu bar icons in the panel, talking to Speakeasy through its planned `speakeasy://` URL scheme or system-wide notifications. No shared code.
- **S4. Volume and brightness display.** Replace the system on-screen display with one drawn from the notch.

## Non-functional requirements

| Area | Requirement |
| --- | --- |
| Performance | Under 0.5% CPU when idle; under 80 MB memory, counting Brim's helper processes. No polling faster than 1 s while collapsed; prefer notifications. |
| Responsiveness | Hover-to-peek under 100 ms after the delay; animations at display refresh rate. |
| Permissions | Never at launch. Each module requests its own permission when enabled, after an in-app screen explaining why. Degrade gracefully when denied. |
| Privacy | No network access in M1 and M2. Any network use (M3) is per module, opt-in, and documented. No analytics. |
| Persistence | Settings stored as JSON in Application Support, versioned with a schema number and migrations. |
| Multi-display | Correct behavior when displays are added, removed or rearranged while running. |
| Accessibility | Panel controls have VoiceOver labels; settings usable with keyboard only. |
| Logging | `os.Logger` with categories (window, state, media); a "Copy diagnostics" button in settings. |

## Technical notes, risks, and agent instructions

**Known risks**

| Risk | Why | Mitigation |
| --- | --- | --- |
| MediaRemote locked down | macOS 15.4+ refuses now-playing calls from apps without Apple's permission | `mediaremote-adapter` first, Apple Events fallback; keep it behind `NowPlayingService` |
| Window sits above the menu bar | Window levels and full-screen behavior change between macOS releases | Keep window setup in one `NotchWindow` type; test on each new macOS beta |
| Notch geometry | `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` are the only public hints | Derive `notchRect` in one place; unit test with recorded screen values |
| Hover feels twitchy | Pointer crosses the notch on the way to the menu bar | Peek delay, larger exit area than entry area, cancelable collapse timer |
| Ad hoc signing | Every rebuild looks like a new app and drops granted permissions | Document re-granting in the README troubleshooting section |

**Testing**

- Unit tests for the state machine (fake clock), screen and notch geometry, the module registry, settings migrations, and the media module against a fake `NowPlayingService`.
- Manual checklist per milestone on a notched MacBook, with and without an external display, in light and dark mode, and over a full-screen app.
- Check idle CPU in Activity Monitor after each milestone.

**Instructions for the coding agent**

1. Build one milestone at a time, in order. Do not start M2 until every M1 acceptance box is met.
2. Before writing code for a milestone, propose the file list and protocols and wait for approval.
3. Keep AppKit window code in `Window/`; SwiftUI views must not touch `NSPanel` directly.
4. Put every system API behind a protocol (screens, pointer events, now playing, login item) so it can be faked in tests.
5. Never request a permission at launch. Request it from the module that needs it.
6. After each feature, list how to manually verify it, mapped to its acceptance criteria.
7. Ask before adding any third-party dependency.
8. Use `Brim` as the product name and `com.harshshelar.brim` as the bundle ID.
