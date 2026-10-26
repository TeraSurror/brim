# Brim

**Brim turns the MacBook notch into a live panel.** While music plays or a coding agent needs you, the notch widens to
show it. Hover the notch, click it, scroll on it or press a shortcut, and a panel grows out of it with media controls,
your agents' status, a clock and a prompt box for Claude.

Brim is a native macOS app (Swift, SwiftUI and AppKit), runs locally, needs no account, collects no analytics and has
no Dock or menu bar icon. On a display without a notch it lives in a slim handle at the top center of the screen.

📖 **Documentation site:** [`docs/index.html`](docs/index.html), published with GitHub Pages
(see [Publishing the docs](#publishing-the-docs)).

---

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Install and run](#install-and-run)
- [Using Brim](#using-brim)
- [Connecting coding agents](#connecting-coding-agents)
- [Quick Prompt](#quick-prompt)
- [Privacy and permissions](#privacy-and-permissions)
- [Project status](#project-status)
- [Development](#development)
- [Troubleshooting](#troubleshooting)
- [Documentation](#documentation)
- [License](#license)

## Features

### A notch that shows what is happening

- **Live notch.** While media plays, the notch grows two "ears": album artwork on the left and an animated waveform on
  the right. When an agent waits for input or fails, an orange or red glyph takes over. Nothing live, nothing shown:
  the notch looks like hardware again.
- **Out of the way in full screen.** Brim hides on any display where an app is full screen (a video, a game,
  a presentation) and comes back when you leave full screen.
- **Every display.** One panel per screen. Displays without a notch get a slim handle that becomes a small pill when
  something is live. Choose all displays, only the notched one or only the main one.

### A panel that opens the way you want

- **Hover or click.** Rest on the notch for 150 ms (adjustable) or switch to click-only.
- **Keyboard.** Record a global shortcut. The panel opens ready for typing without pulling focus from your app; Esc
  closes it.
- **Gestures.** Scroll down on the notch to open, up to close. Swipe the media ears left or right to skip tracks.
- **Drag and drop.** Drag files or text to the notch and the panel opens into drop zones for the modules that accept
  them.
- **Modules.** The panel widens for every module you enable; reorder them in Settings.

### Modules

| Module | What it does | Needs |
| --- | --- | --- |
| **Now Playing** | Artwork, title, artist, album, progress with seeking, play/pause/next/previous for anything macOS reports as playing (Spotify, Music, Safari, Brave, Chrome, Arc, Firefox, YouTube, …). Optionally follows Spotify or Music directly. | Nothing. Following Spotify/Music asks for Automation. |
| **Clock** | The time and date at a glance. | Nothing. |
| **Agent Status** | Live rows for Claude Code, Codex, Cursor, VS Code or any script: working, waiting, done, failed, with elapsed time and cost. Optional alerts when an agent needs you; clicking one switches to its terminal or editor. | Nothing. Local socket only. |
| **Quick Prompt** *(new)* | A prompt bar across the panel that asks Claude through your own `claude` CLI, with read-only access to a folder you pick. Answers stream into the panel. | Claude Code installed and logged in. |

## Requirements

- macOS 14 Sonoma or later. Apple Silicon MacBook with a notch is the main target; any Mac works through the handle.
- Xcode command-line tools with Swift 5.10 or later (`xcode-select --install`).
- [CMake](https://cmake.org) and network access **the first time you build**, to build the pinned media helper
  (`brew install cmake`). Not needed for `swift build` or `swift test`.
- Optional: [Claude Code](https://claude.com/claude-code) for Agent Status's one-click setup and for Quick Prompt.

## Install and run

Brim is built from source; there is no signed download yet.

```sh
git clone https://github.com/TeraSurror/brim.git
cd brim
./build.sh            # builds build/Brim.app (release, ad-hoc signed), including the media helper
open build/Brim.app
```

To keep it, copy `build/Brim.app` to `/Applications` and turn on **Settings → General → Launch at login**.

| Command | What it does |
| --- | --- |
| `./build.sh` | Release build of `build/Brim.app`, ad-hoc signed |
| `./build.sh debug` | Debug build of the same bundle |
| `BRIM_SKIP_MEDIA_ADAPTER=1 ./build.sh` | Build without the media helper (no CMake needed); everything except Now Playing works |
| `./scripts/build-media-adapter.sh --force` | Rebuild the media helper |
| `swift build` / `swift test` | Compile / run the unit tests (no helper needed) |

On first launch Brim opens Settings with a short welcome note, because a quiet notch shows nothing until something
plays. Open Brim again at any time (Finder, Spotlight or `open -a Brim`) to bring Settings back.

> **Ad-hoc signing.** Every rebuild looks like a new app to macOS, so granted permissions (Automation) and the login
> item can be dropped. Re-grant them after a rebuild. macOS notification banners also need a properly signed build; the
> development build uses Brim's own notch alert instead.

## Using Brim

| To… | Do this |
| --- | --- |
| Open the panel | Hover the notch (or the handle), click it, scroll down on it, or press your shortcut |
| Close it | Move away, scroll up on its top edge, press Esc, or click elsewhere |
| Skip a track | Swipe left (next) or right (previous) on the ears while media plays |
| Open Settings | The gear in the panel, right-click the panel, or open Brim again |
| Quit | Right-click the panel → Quit Brim |

**Settings** has five tabs:

- **General**: open on hover or click, hover and collapse delays, the global shortcut, the live notch, which displays
  show Brim, launch at login.
- **Media**: Now Playing on/off, which player to follow, Automation.
- **Agents**: Agent Status, the Claude Code connection, alerts, how long finished sessions stay, the socket path for
  other tools, and Quick Prompt's `claude` location.
- **Modules**: turn modules on or off and reorder them.
- **About**: version and **Copy Diagnostics** for bug reports.

Settings are saved as versioned JSON in `~/Library/Application Support/Brim/settings.json`.

## Connecting coding agents

Turn on **Agent Status** (Settings → Agents). It opens a Unix socket at
`~/Library/Application Support/Brim/agent.sock` (owner-only, removed on quit) and accepts `brim://agent` links.

**Claude Code** connects in one click: **Settings → Agents → Claude Code → Connect…** shows what it will change, then
writes `~/.brim/claude-hook.sh`, backs up `~/.claude/settings.json` and adds Brim's hooks next to yours. Start a new
Claude Code session afterwards. **Update…** appears when an older hook is installed; **Disconnect…** removes it.

**Any other tool** reports one JSON line:

```sh
printf '%s\n' '{"agent":"codex","session":"demo","status":"working","title":"Fix the parser","detail":"Running tests"}' \
  | nc -U "$HOME/Library/Application Support/Brim/agent.sock"
```

or opens a link:

```sh
open -g 'brim://agent?agent=codex&session=demo&status=waiting&title=Approve%20a%20tool%20call'
```

| Field | Required | Meaning |
| --- | --- | --- |
| `agent` | yes | Tool identifier, e.g. `claude-code`, `codex`, `cursor` |
| `session` | yes | Stable ID for one session |
| `status` | yes | `working`, `waiting`, `done` or `error` |
| `title`, `detail` | no | Shown on the row (trimmed and length-limited) |
| `costUSD` | no | Session cost so far |
| `cwd` | no | Project folder; rows and alerts can open it in Finder |
| `app` | no | Bundle ID of the terminal or editor (validated, never executed); alerts switch to it |
| `timestamp` | no | ISO 8601; older events never overwrite newer ones |

`brim://agent?action=dismiss&agent=…&session=…` removes one row and `action=clear` clears the list. Waiting sessions
sort first, then failures, working and done. Finished sessions disappear after 10 minutes (adjustable).

**Alerts** are a separate opt-in: when a session newly needs input or fails while the panel is closed, a card drops
from the top of the screen you are on (or a macOS banner on a signed build). Clicking it brings the session's app
forward.

## Quick Prompt

Turn on **Quick Prompt** in Settings → Modules. Brim explains what it does first; there is no macOS permission.

1. Open the panel (the shortcut focuses the prompt field) and type a question.
2. Pick the folder Claude may read with the chip on the left: by default the project of your most recent agent
   session, a recent folder, any folder, or none for plain chat.
3. Press Return. The answer streams in place of the cards, with lists and code blocks rendered and a Copy button.
   Ask a follow-up in the same bar; **New** starts over; **Done** or Esc returns to the cards.

If you close the panel while Claude is answering, the notch shows a quiet working glyph, then a check mark until you
look.

Quick Prompt runs your installed `claude` CLI under your own login with **only Read, Grep and Glob** and no MCP
servers: it can read files in the chosen folder but cannot edit files, run commands or fetch from the web. The prompt
is passed on standard input, never through a shell. Brim itself makes no network request; Claude Code does. If Brim
cannot find `claude`, choose it in Settings → Agents.

## Privacy and permissions

- **No network access from Brim.** Media, agents and settings are local. Quick Prompt's traffic is Claude Code's, under
  your login, and only when you send a prompt.
- **No analytics, ever.**
- **No permission prompts at launch.** A feature asks only when you turn it on, after an explanation, and keeps working
  in a limited form if you decline.

| Feature | Permission | When it is asked |
| --- | --- | --- |
| Following Spotify or Music directly | Automation (per player) | When you pick the player in Settings → Media |
| Agent alerts as macOS banners | Notifications | When you turn alerts on (signed builds only) |
| Global shortcut, gestures, drag and drop | none | — |
| Now Playing, Agent Status, Quick Prompt | none | — |

The Now Playing helper is the third-party [`ungive/mediaremote-adapter`](https://github.com/ungive/mediaremote-adapter)
v0.7.7 (BSD-3), built from a pinned commit and run as a separate process through `/usr/bin/perl`. It is never linked
into Brim and stops when Brim quits.

## Project status

Version 0.1.0. Built milestone by milestone from the [project spec](Brim%20%E2%80%94%20macOS%20Notch%20Panel%20Spec.md):

| Area | Features | State |
| --- | --- | --- |
| Notch panel shell | F1–F5 | Done and signed off |
| Media controls | F6 | Done and signed off |
| Agent status and alerts | F7–F8 | Done and signed off |
| Live notch revision | F9–F14 | Done and signed off |
| Panel input: displays, keyboard, gestures, drop | F15–F18 | Done; some manual checks pending |
| Quick Prompt | F19 | Implemented; typing into the prompt field still needs a hands-on check |
| Send to assistant (files, clipboard, screenshot, selection) | F20 | Designed, not built |

[`docs/PROGRESS.md`](docs/PROGRESS.md) is the detailed handoff log; [`docs/TESTING.md`](docs/TESTING.md) is the manual
checklist and known limitations.

## Development

```sh
swift build        # compile
swift test         # 344 unit tests (XCTest)
./build.sh debug && open build/Brim.app
log stream --predicate 'subsystem == "com.harshshelar.brim"'
```

```
Sources/
├── Brim/main.swift          # launcher only
└── BrimKit/
    ├── App/                 # composition root, app delegate, settings window, shared AppModel
    ├── Window/              # every NSPanel: notch windows, pointer/scroll/drag tracking, notch alert
    ├── State/               # pure logic: state machine, geometry, gestures, drag tracking, agent roster
    ├── Modules/             # BrimModule protocol, registry, Clock, Now Playing, Agent Status, Quick Prompt
    ├── Services/            # protocols + real implementations (screens, media helper, socket, hot keys, claude CLI, …)
    ├── Model/               # value types: ScreenInfo, Settings, NowPlaying, AgentEvent, HotKey, …
    ├── Support/             # logging and diagnostics
    └── UI/                  # SwiftUI panel, cards and settings (never touches NSPanel)
Tests/BrimTests/             # one file per unit, all fakes in Fakes.swift
scripts/                     # pinned media helper build
docs/                        # GitHub Pages site, progress log, testing checklist
```

Architecture rules, from [`AGENTS.md`](AGENTS.md): one `NSPanel` per screen; AppKit stays in `Window/` and `App/`;
`State/` is pure and driven by an injected clock; every system API sits behind a protocol with a fake; features are
`BrimModule`s that plug in without touching the window shell. Settings changes bump the schema (currently 7) and add a
migration step with a test. No third-party dependencies without asking first.

### Publishing the docs

The documentation site is plain HTML in [`docs/`](docs/) (`index.html`, no build step). To publish it, open the
repository on GitHub → **Settings → Pages → Build and deployment**, choose **Deploy from a branch**, branch `main`,
folder `/docs`, and save. It appears at `https://terasurror.github.io/brim/`.

## Troubleshooting

### The panel does not appear

- Is Brim running? `pgrep -fl '/Brim.app/Contents/MacOS/Brim'`
- Move the pointer to the very top edge, inside the notch (or onto the handle on other displays).
- **Settings → General → Open the panel** may be "On click"; hovering then does nothing.
- **Settings → General → Show Brim on** may exclude this display.
- Brim hides on purpose while an app is full screen on that display. Your shortcut still opens it there.

### Media does not appear

- **Settings → Media → Turn On Now Playing.** It asks for nothing.
- The ears hide 3 seconds after playback pauses; an agent that needs you takes priority.
- Check the helper: `pgrep -fl 'mediaremote-adapter|brim-media-supervisor'`. If it is missing, rebuild it with
  `./scripts/build-media-adapter.sh --force`. Without it, a running Spotify or Music still works through Automation.
- `swift run` has no app bundle; point `BRIM_MEDIA_ADAPTER_PATH` at `.build/media-adapter` or use `./build.sh`.

### Agents do not appear

- **Settings → Agents → Turn On Agent Status**, then **Show a Test Session**. If the test row appears, the problem is
  the integration.
- Check the socket: `ls -l "$HOME/Library/Application Support/Brim/agent.sock"`, then send the `nc -U` example above.
- After connecting Claude Code, start a **new** session; running sessions keep their old hooks.
- `brim://` links need the app launched once so macOS registers it. Percent-encode spaces.
- Very long home directory paths can exceed the ~104-byte Unix socket limit; the log says "path is too long".

### Alerts do not appear

- Turn on **Settings → Agents → Alert when an agent needs input or fails**.
- Alerts fire only when a session *newly* waits or fails, and only while no panel is open.
- On the ad-hoc build, look for Brim's card at the top of the screen, not Notification Center.

### Quick Prompt says it can't find `claude`

Install Claude Code and run `claude` once in Terminal to log in. If it lives somewhere unusual, choose it in
**Settings → Agents → Quick Prompt → Choose…**. Errors from Claude Code (for example, not logged in) show in the answer
view, with details in the log.

### The shortcut does nothing

Settings shows a warning when macOS refuses a combination. ⌃⌥Space is macOS's "next input source" shortcut; pick
another combination if you use several input sources.

### A rebuild dropped a permission or login item

Ad-hoc builds look new to macOS after every rebuild. Re-grant Automation in System Settings → Privacy & Security and
toggle Launch at login off and on.

### Settings are stuck or malformed

Quit Brim and move `~/Library/Application Support/Brim/settings.json` aside. Unreadable files are kept next to it as
`settings.corrupt-<timestamp>.json`.

When reporting a bug, include **Settings → About → Copy Diagnostics**.

## Documentation

- [Documentation site](docs/index.html)
- [Project spec](Brim%20%E2%80%94%20macOS%20Notch%20Panel%20Spec.md): features and acceptance criteria
- [Progress and handoff log](docs/PROGRESS.md)
- [Manual testing checklist and known limitations](docs/TESTING.md)
- [Guide for coding agents](AGENTS.md)

## License

[MIT](LICENSE) © 2026 Harsh Shelar. The bundled MediaRemote helper is BSD-3; its license ships in the app at
`Contents/Resources/MediaAdapter/LICENSE`.
