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
| F4 | Add a second module (M2 media) and use the up/down arrows. | The panel order follows the list and survives relaunch. The up/down chevrons form a vertically aligned pair with a full click target. (With only the clock in M1, both arrows are disabled; ordering is covered by unit tests.) |
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
| F6 | With the panel expanded, look at the media card. | Artwork, title, artist, album, progress bar, elapsed/remaining time, previous / play-pause / next, and a source menu. The transport is centered on the card and the progress bar spans the card; there is no large dead area. |
| F6 | Look at the bottom of the metadata in the expanded card, and at the peek subtitle. | The expanded card says “Playing in Spotify/Safari/…” and the peek subtitle appends the app name, so it is clear which app macOS is reporting. The top-right source menu still lets you change the followed player. |
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
| Settings | Change Follow, quit and relaunch. | The choice is restored from `settings.json`; schema is 4 (M3), and M2's player choice still survives. |
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

## M3 manual verification — agent status (F7)

Turn on **Settings → Modules → Agent Status** first. No permission prompt should appear, at launch or on enable. The
module is local-only: it does not use the network and does not ask for Automation/Accessibility.

| Feature | Check | Expected |
| --- | --- | --- |
| F7 | Enable Agent Status in Settings → Modules. | The module appears in the panel; `ls -l "$HOME/Library/Application Support/Brim/agent.sock"` shows a `srw-------` socket. No macOS prompt. |
| F7 | Send a working event (below) and hover the notch. | The peek shows a status glyph, “Claude Code” and “Working” with the session title. |
| F7 | Send a waiting event for a second session, then expand. | The waiting row is amber and first; working and done rows follow. Each row shows agent, title, detail, elapsed time and cost when provided. |
| F7 | Press a row's dismiss button; then press “Clear” in the AGENTS header. | The dismissed row disappears; “Clear” removes every done/failed row but keeps waiting/working ones. |
| F7 | With nothing reported, open the panel. | The card says “No agent activity”; the peek has no agent content. |
| F7 | Set **Settings → General → Agents → Keep finished sessions** to 1 minute, send a done event, wait a minute and reopen the panel. | The done session is gone. Working/waiting sessions do not expire on their own. |
| F7 | Disable Agent Status, then enable it again. | The socket disappears/reappears; the roster is cleared on disable. |
| F7 | Quit Brim and check the socket path. | The socket file is gone. Relaunch with the module enabled: it returns. |
| F7 | While Brim runs, run the `brim://agent?...` URL example below. | The event appears in the panel. |
| F7 | Quit Brim, then run the same `open` command. | Brim launches, the event is accepted, and the next hover shows it. |
| F7 | Send malformed JSON and a line over 8 KB. | Nothing appears; the log records the rejection; Brim keeps running and accepts the next valid event. |
| F7 | Send an event with an older timestamp than the current session. | The session keeps its newer state; a late event cannot make a finished session look busy. |
| F7 | Connect from another user account (if available). | The socket directory/socket permissions reject the connection; no event appears. |
| F7 | Use the agent card with clock + media enabled on the notched display, in light and dark mode. | The three cards share the width; the agent card scrolls when there are more rows than fit; text stays readable. |
| F7 | Use VoiceOver on the peek and card. | The peek announces the agent status/count; each row reads agent, title, status, elapsed and cost; dismiss/clear have labels. |
| Perf | Leave Brim collapsed after using agent status, then check Activity Monitor. | Under 0.5% CPU and under 80 MB; the listener is one file descriptor, no timer. |

### Agent event examples

Socket, with `nc` (macOS supports `-U`):

```sh
printf '%s\n' '{"agent":"claude-code","session":"demo","status":"working","title":"Fix the parser","detail":"Running tests","costUSD":0.12}' \
  | nc -U "$HOME/Library/Application Support/Brim/agent.sock"
```

URL:

```sh
open -g 'brim://agent?agent=claude-code&session=demo&status=waiting&title=Approve%20a%20tool%20call'
```

Actions:

```sh
open -g 'brim://agent?action=dismiss&agent=claude-code&session=demo'
open -g 'brim://agent?action=clear'
```

### Claude Code reference hook

Save this as `~/.brim/claude-hook.sh` and make it executable (`chmod +x`). It reads Claude Code's JSON payload from
stdin, so each session gets its own row. It needs `/usr/bin/python3` (Xcode Command Line Tools); if the socket is
missing it exits quietly, so it never blocks Claude.

```sh
#!/bin/sh
# ~/.brim/claude-hook.sh — report Claude Code activity to Brim.
# usage: claude-hook.sh working "Running tests"
/usr/bin/python3 -c '
import json, os, socket, sys, time
status = sys.argv[1] if len(sys.argv) > 1 else "working"
detail = sys.argv[2] if len(sys.argv) > 2 else ""
try:
    hook = json.load(sys.stdin)
except Exception:
    hook = {}
event = {
    "agent": "claude-code",
    "session": str(hook.get("session_id") or "unknown"),
    "status": status,
    "title": "Claude Code",
    "detail": detail,
    "cwd": str(hook.get("cwd") or ""),
    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}
path = os.path.expanduser("~/Library/Application Support/Brim/agent.sock")
try:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(0.5)
    client.connect(path)
    client.sendall((json.dumps(event) + "\n").encode())
    client.close()
except OSError:
    pass
' "${1:-working}" "${2:-}"
```

Before wiring it into Claude Code, test the script and Brim directly:

```sh
mkdir -p "$HOME/.brim"
# Save the script above as $HOME/.brim/claude-hook.sh.
chmod +x "$HOME/.brim/claude-hook.sh"
printf '%s' '{"session_id":"hook-test","cwd":"/tmp/demo","hook_event_name":"Notification"}' \
  | "$HOME/.brim/claude-hook.sh" waiting "Waiting for input"
```

Hover the notch: a Claude Code row should say “Needs input” within a moment. If it does not, fix that before touching
Claude Code's settings. Check that Agent Status is enabled, Brim is running, the socket exists, and this log shows the
event:

```sh
log stream --level debug --predicate 'subsystem == "com.harshshelar.brim" AND category == "agent"'
```

Then add the hooks to `~/.claude/settings.json` (merge with your existing hooks; event names and matchers depend on your
Claude Code version):

```json
{
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command", "command": "\"$HOME/.brim/claude-hook.sh\" working 'Session started'"}]}],
    "PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "\"$HOME/.brim/claude-hook.sh\" working 'Running a tool'"}]}],
    "Notification": [{"matcher": "permission_prompt|idle_prompt|agent_needs_input", "hooks": [{"type": "command", "command": "\"$HOME/.brim/claude-hook.sh\" waiting 'Waiting for your input'"}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "\"$HOME/.brim/claude-hook.sh\" done 'Finished'"}]}],
    "SessionEnd": [{"hooks": [{"type": "command", "command": "\"$HOME/.brim/claude-hook.sh\" done 'Session ended'"}]}]
  }
}
```

Use `"$HOME/..."` rather than a bare `~` so the command does not depend on shell tilde expansion. The `Notification`
matcher keeps auth/quota notices from becoming a false “Needs input”; use `"matcher": ""` temporarily if you want to see
every notification type.

After saving, run `/hooks` in Claude Code to confirm the entries, then start a new session (hooks are read at session
start). Use `claude --debug` (or `/debug` mid-session) to watch hook execution.

To trigger the states in a real session:

- **working** — start a session, then ask Claude to run a command or edit a file.
- **waiting** — let Claude ask for permission. Switching away from the terminal while a permission prompt is open also
  covers the `idle_prompt` case.
- **done** — let the turn finish (the `Stop` hook) or exit the session (the `SessionEnd` hook).

If Brim is not running when a hook fires, the socket event is lost; the URL variant below can launch Brim. Enable Agent
Status before starting the Claude Code session you want to watch.

The same contract works for Codex, Cursor, VS Code extensions or any script: one JSON object per line on the socket,
or a `brim://agent` URL. The schema is `agent`, `session`, `status` (`working`/`waiting`/`done`/`error`), and optional
`title`, `detail`, `costUSD`, `cwd`, `timestamp`.

## M3 F8 manual verification — agent alerts and open project

Turn on **Settings → General → Agents → Notify when an agent needs input**. Enabling shows Brim's explanation first;
macOS may then show a notification prompt on a signed build.

| Feature | Check | Expected |
| --- | --- | --- |
| F8 | Enable the alert toggle. | Brim explains what it will show; no launch-time prompt. The toggle persists across relaunch. |
| F8 | Close the panel, then send a `waiting` event with a `cwd` (use the socket example above). | A card appears under the notch with “Claude Code needs your input” and the session detail. Brim does not activate. |
| F8 | Wait 7 seconds. | The notch alert disappears without input. |
| F8 | Send another `waiting` event for the same session while it is still waiting. | No duplicate alert. Send `working`, then `waiting` again: a new alert appears. |
| F8 | Open the panel, then send a `waiting` event. | No notch alert or banner while the panel is open. |
| F8 | Click the folder button on the notch alert. | Finder opens the session's `cwd`; the alert dismisses. |
| F8 | Click the folder button on an agent row in the panel. | Finder opens that project. Rows without `cwd` have no folder button. |
| F8 | Send an `error` event with the panel closed. | An alert titled “Claude Code failed” appears. |
| F8 | On a signed build with notification permission allowed, repeat the closed-panel `waiting` check. | A macOS banner appears instead of the notch card; clicking it opens the project. |
| F8 | Deny macOS notification permission (or use the ad-hoc dev build). | The toggle stays on, the settings note explains that banners are off and the notch alert is used, and alerts still appear. |
| F8 | Quit and relaunch. | Schema is 4; the alert setting and retention survive. |
| Perf | Leave Brim collapsed after alerts. | Under 0.5% CPU and under 80 MB; the alert window is destroyed after dismissal. |

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
- The expanded panel splits the width evenly between enabled modules. The media card adapts when it gets less than
  320 pt (hides the album, collapses the source menu to an icon), but a very long title still truncates. Both modules
  remain usable.
- The panel stays near-black in light and dark mode on purpose; only the settings window follows the system appearance.
- The adapter build needs CMake and network access on the first run. `BRIM_SKIP_MEDIA_ADAPTER=1 ./build.sh` produces an
  app without it; the rest of Brim works.

## Known limitations and notes for M3

- **Agent Status is local-only.** F7 has no network code and no quick prompt. Any future prompt/assistant feature needs
  its own opt-in, provider choice, key storage and privacy documentation.
- **The URL scheme is not authenticated.** Any app or script running as you can open `brim://agent?...`; the router
  validates fields but treats the sender as trusted. The module must be enabled to accept events. Leave it off if you
  do not want URLs to change the panel.
- **The socket path is short on purpose.** Unix sockets have a ~104-byte path limit. The default
  `~/Library/Application Support/Brim/agent.sock` fits a normal home directory; a very long username could exceed it,
  in which case the log says the path is too long and the module shows no listener.
- **Working and waiting sessions do not expire.** A crashed or abandoned agent can leave a row until you dismiss or
  clear it. This avoids treating a long-running tool call as a failure, but it means the panel can retain a stale
  working state.
- **The roster is in memory.** Quitting Brim forgets sessions; the next event starts a new row. There is no event
  history or transcript storage.
- **One roster for all displays.** Panels on every screen show the same sessions; dismissing on one screen dismisses
  everywhere.
- **Disabled means dropped.** Events that arrive while Agent Status is off are ignored rather than buffered. Enable the
  module before starting a hooked agent if you want its first events.
- **The session cap is eight.** When more sessions arrive, the least urgent/oldest rows are dropped first. Increase
  `AgentRoster.defaultMaxSessions` if that becomes limiting.
- **Claude Code hooks are version-dependent.** The example uses `SessionStart`, `PreToolUse`, `Notification`, `Stop` and
  `SessionEnd` and reads `session_id`/`cwd` from stdin. Check Claude Code's hook documentation if a payload or event name
  changes; the Brim side only cares about the JSON line.
- **No jump-to-terminal yet.** Rows carry `cwd` but there is no “open the project” action in F7.
- The agent card scrolls when there are more rows than fit. Native scrollbars are hidden, so use the trackpad/wheel;
  VoiceOver still reaches every row.
- **macOS notification banners need a signed build.** The ad-hoc development bundle cannot register with
  `UNUserNotificationCenter`; macOS returns “Notifications are not allowed for this application” without a prompt.
  Brim falls back to a notch alert, which is the verified path in development. Do not treat a missing banner as a
  module failure.
- Alerts fire on a transition into waiting/failed, not on every event. A session that stays waiting does not remind
  you again; the panel row remains until it changes or is dismissed.
- The notch alert is transient (about 7 seconds) and shows on the notched display (or the primary display). It is not
  added to Notification Center and does not have action categories.
- “Open project” uses Finder. There is no terminal/editor choice yet, and a missing `cwd` disables the folder button.
