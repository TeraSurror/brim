# Manual testing and known limitations

Run on a notched MacBook, with and without an external display, in light and dark mode, and over a full-screen app.
M1 and the M2 media card were also exercised programmatically (window bounds, accessibility tree, synthetic clicks, an
offscreen stub adapter). The user signed off every manual row below on 2026-10-26, which led to F14 (hide over
full-screen apps) and a menu-bar-height pill. See [`PROGRESS.md`](PROGRESS.md) for what was already verified.

## M1 manual verification — notch panel shell

| Feature | Check | Expected |
| --- | --- | --- |
| F1 | Launch Brim with the lid open and no other app full screen. Look at the notch. | No visible window, glow or shadow at the notch. Nothing steals focus from the front app. |
| F1 | Open a full-screen app (for example Safari or a video). Move the pointer to the notch. | Superseded by F14: nothing of Brim shows on that display and hovering does nothing. |
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

## UX revision manual verification — live notch (F9–F13)

The UX revision replaces the hover peek with a live notch. Rows above that mention the peek (F2, F3, F4, F6) are
superseded by the F9/F10 rows here. Run these on the notched MacBook with and without an external display, in light and
dark mode, and once over a full-screen app.

| Feature | Check | Expected |
| --- | --- | --- |
| F9 | Rest the pointer on the bare notch. | After the hover delay (150 ms) the full panel grows straight out of the notch; there is no intermediate strip. A Force Touch trackpad gives a light tap. |
| F9 | Settings → General → Open the panel → On click. Hover the notch, then click it. | Hovering does nothing; the click opens the panel. The hover-delay slider is disabled. Switch back to On hover. |
| F9 | Move the pointer along the menu bar across the notch without stopping. | The panel does not open. |
| F9 | System Settings → Accessibility → Display → Reduce motion on. Open and close the panel. | The panel fades in and out at full size instead of growing; no sliding content. Turn it off again. |
| F10 | Play a YouTube video in a browser (or Spotify/Music) with the panel closed. | Within a second the notch widens by an ear on each side: artwork on the left, an animated waveform on the right. Nothing else changes in the menu bar. |
| F10 | Pause playback. | The ears stay for about 3 seconds, then retract into the notch and the notch is invisible again. Resuming within 3 seconds keeps them without a flicker; skipping tracks never flickers. |
| F10 | Hover the left ear (outside the hardware notch), then click it. | Hovering opens the panel; a click opens it immediately. The click never reaches the menu bar item underneath. |
| F10 | Move the pointer next to the notch, then start playback so the ears appear under the pointer. | The panel does not open by itself; it opens only when the pointer moves or clicks. |
| F10 | With media playing, send a `waiting` agent event (socket example above). | The ears switch to an orange glyph (and a count when several sessions wait). Send `working`: media takes the ears back. With nothing playing, a `working` agent shows a quiet pulsing glyph. |
| F10 | Send an `error` event, open the panel, close it. | The red glyph lights the notch until the panel is opened; afterwards the row is still listed but the notch is bare (or shows media). |
| F10 | On a display without a notch, play media. | The slim handle becomes a small black pill at the top center, exactly as tall as the menu bar, with the same artwork and waveform. |
| F10 | Settings → General → turn off "Show activity beside the notch". | The ears disappear immediately. About a second later `pgrep -f brim-media-supervisor` finds nothing while the panel is closed. Turn it back on: the helper restarts and the ears return while media plays. |
| F10 | Leave media playing and the panel closed for 10 minutes. Check Activity Monitor. | Brim plus its `perl` helper stay under 0.5% CPU and 80 MB combined. |
| F10 | `pkill -f mediaremote-adapter` while Now Playing is enabled. | The ears disappear; the helper is back within about 5 seconds and the ears return. |
| F11 | Enable alerts, close the panel, move the pointer to the external display and send a `waiting` event with `app` set to your terminal's bundle ID. | A black card drops from the top edge of the external display (not under the MacBook notch), titled “… needs your input”. |
| F11 | Hover the card for 10 seconds, then move off it. | It stays while hovered and closes about 3 seconds after the pointer leaves. |
| F11 | Click anywhere on the card (not the ✕). | The terminal comes to the front and the card closes. Without `app`, Finder opens `cwd`. |
| F11 | Send `waiting`, then open the panel while the card is visible. | The card disappears as the panel opens; nothing overlaps the panel. |
| F11 | Look at an agent row with `app` set, and one with only `cwd`. | The first shows an "open app" arrow, the second a folder; rows with neither have no open button. |
| F11 | Run a real Claude Code session in Terminal, iTerm or VS Code after connecting the hook (F12). | Rows are titled with the project folder, the detail names the running tool ("Running Bash"), and the open action switches to that terminal/editor. |
| F12 | Quit Brim, move `~/Library/Application Support/Brim/settings.json` aside, launch Brim. | Settings opens on General with a "Brim lives in your notch" note; Now Playing and Clock are enabled. Restore your file afterwards. |
| F12 | With Brim running, double-click `build/Brim.app` (or Spotlight → Brim). | Settings comes to the front. |
| F12 | Settings → Modules: turn Now Playing off and on. | No explanation sheet and no macOS prompt. |
| F12 | Without Automation granted, pick Spotify or Music in the panel's source menu. | Settings opens on the Media tab, which explains Automation and offers Grant Automation…. |
| F12 | Settings → Agents → Claude Code. With the old manual hook installed, the status reads "Connected with an older hook". Press Update…, read the explanation, confirm. | `~/.claude/settings.json.brim-backup-<time>` exists, other hooks are untouched, `~/.brim/claude-hook.sh` contains `brim-hook-version: 2`, and the status reads Connected. |
| F12 | Break `~/.claude/settings.json` (invalid JSON) and reopen the Agents tab. | Status says the file isn't valid JSON; Connect is not offered and the file is not modified. Restore it. |
| F12 | Settings → Agents → Show a Test Session (Agent Status on). | A "Brim · Test session" row waits in the panel and the notch shows the orange glyph; with alerts on and the panel closed, the card appears. |
| F12 | Walk all five tabs with the keyboard only. | Every control is reachable; the Media and Agents tabs offer "Turn On …" when their module is off. |
| F13 | Enable one, two and three modules and open the panel each time. | 460, 630 and 934 pt wide; the cards keep the same width and the panel stays centered on the notch. |
| F13 | Use a 12-hour clock (System Settings → General → Date & Time). | "10:45 PM" stays on one line in the clock card at every module count. |
| F13 | With Now Playing and Clock enabled, look at the media card. | The full layout: 96 pt artwork, title, artist, album and "Playing in …". The source menu is an icon with a chevron. |
| F14 | Play a video in a browser and make it full screen on the MacBook. | The ears disappear with the menu bar; hovering the notch does nothing. The external display keeps its pill. |
| F14 | Leave full screen (Esc), or swipe back to a desktop Space. | The ears return within about a second. |
| F14 | Repeat on the external display. | Its pill or handle disappears while the video is full screen; the MacBook notch keeps working. |
| F14 | Open the panel, then put the app under it into full screen (⌃⌘F). | The panel collapses and hides; it comes back collapsed afterwards. |
| F14 | Zoom a window (double-click its title bar) on each display. | Brim stays visible: a zoomed window is not full screen. |

### Verified by the agent (2026-10-25)

Against the debug build on macOS 26.6.2 with a YouTube video playing in Brave and this Claude Code session reporting
`working` through the old hook:

- Collapsed with media playing: windows were `259×32` at the 179×32 notch (two 40 pt ears) and a `150×24` pill on the
  external display, both alpha 1. The accessibility tree read the track title, artist and "playing", with the source
  as "from Browser". That led to named entries for Brave, Arc, Firefox, Opera and Vivaldi (unit tested, not re-run).
- Hover warp onto the notch opened `934×320` (three modules); moving away collapsed back to `259×32`.
- A `waiting` socket event with `app` switched the ears to "Agent: Needs input" and dropped a `360×64` card at
  `(780, 0)` on the screen under the pointer; `working` handed the ears back to media; the card closed on its own.
- Opening Brim again showed the Settings window with General/Media/Agents/Modules/About tabs and the open-mode radio
  group. Copy Diagnostics reported `live notch: on, showing media` and `Claude Code hook: outdated`.
- The installed hook script, run against a scratch socket, sent `title` = project folder, `detail` = "Running Bash" and
  `app` = `com.apple.Terminal`, and exited 0 with no listener.
- Quitting removed the helper and the socket. The user's settings file was restored afterwards.

Not verified here: real clicks on the ears and the alert card, haptics, Reduce Motion, full-screen apps and the Claude
Code Update… button (it edits `~/.claude/settings.json`, so it was left for the user). The user covered these in the
2026-10-26 sign-off.

### F14 verified by the agent (2026-10-26)

A scratch app put its own window into native full screen on each display while Brim (debug and release) ran:

- Built-in display: the window list showed the full-screen window at `1920,33 1470×923` (below the notch strip, the
  same rect as the zoomed windows beside it). Finder's and WindowManager's desktop-level windows for that display were
  gone while it was in front and back afterwards. Brim logged `Full-screen screens: display-1`, its `259×32` window
  left the window list, and it returned (empty set logged) after leaving full screen.
- External display: the full-screen window covered `0,0 1920×1080`; Brim logged `display-3` and hid only that pill.
- With media live, the external pill measured `150×30` against a 30 pt menu bar (it was `150×24` before).


## Panel input manual verification (F15–F18)

| Feature | Check | Expected |
| --- | --- | --- |
| F15 | Settings → General → Show Brim on → Only the notched display. | The external display's handle or pill disappears at once; the notch keeps working. |
| F15 | Choose Only the main display. | Only the display with the menu bar (System Settings → Displays) has Brim. |
| F15 | With Only the notched display, close the lid (clamshell on the external display). | Brim appears on the external display instead of disappearing. Open the lid: it moves back to the notch. |
| F15 | With Only the notched display, enable alerts and send a `waiting` event with the pointer on the external display. | The alert drops from the MacBook notch, not the external display. |
| F15 | Quit and relaunch. | The choice is kept; `settings.json` has `"schemaVersion" : 6` and `displayMode`, and no `showOnNonNotchedDisplays`. |
| F16 | Settings → General → Keyboard → Open Brim → Record Shortcut, press ⌃⌥⌘B. | The button shows ⌃⌥⌘B. Pressing B or ⇧B alone beeps and keeps recording; Esc cancels. |
| F16 | In another app, press the shortcut. | The panel opens on the display under the pointer. The app keeps its menu bar (Brim does not activate). |
| F16 | Type a letter, then press Esc. | The letter does not reach your app; Esc closes the panel and the next keystroke goes to your app again. |
| F16 | Open with the shortcut, move the pointer far away, wait. | The panel stays open. Press the shortcut again (or click another window): it closes and your app has focus. |
| F16 | Open with the shortcut while a video is full screen on that display. | The panel shows over the video; closing it hides Brim there again. |
| F16 | With focus and Keyboard navigation on, press Tab and Space. | Focus moves through the panel's buttons; Space presses them. VoiceOver reads them. |
| F16 | Record a combination another app already registered. | Settings says macOS refused it; nothing is registered. Clear removes the shortcut. |
| F17 | With Open the panel → On click, scroll down with two fingers on the notch (or roll a mouse wheel toward you). | The panel opens at once; hovering alone still does nothing. Works with natural scrolling on and off. |
| F17 | Scroll up with the pointer on the panel's top band (beside the notch). | The panel closes. Scrolling inside the agent list scrolls the list and keeps the panel open. |
| F17 | While media plays and the panel is closed, swipe left over the ears, then right. | Next track, then previous; the panel stays closed. A hard fling skips only once. |
| F17 | Swipe over the ears while an agent glyph is shown, and over a display hidden by full screen. | Nothing happens. |

### F15 verified by the agent (2026-10-26)

With the user's settings file backed up, set to each mode and Brim relaunched: `notchedOnly` built only the `179×32`
notch window, `mainOnly` only the external display's `148×10` handle, and `all` both. The original schema 5 file
(`showOnNonNotchedDisplays: true`) migrated to All displays and was restored unchanged afterwards.

### F17 verified by the agent (2026-10-26)

In click mode, with the pointer warped onto the notch and synthetic scroll events: hovering alone did nothing; a wheel
step toward the user opened the `630×320` panel; a wheel step away over a card kept it open; the same over the top
band closed it. Phased trackpad-style events (began/changed/ended) opened and closed it the same way. Natural
scrolling was on. Horizontal swipes were not sent, because they would have skipped the user's playing track.

### F16 verified by the agent (2026-10-26)

With ⌃⌥⌘B written into a backed-up copy of the user's settings and synthetic key events:

- The shortcut opened a `630×320` panel on the display under the pointer while the front app stayed active and
  frontmost. A probe app's window lost key status and did not receive the next letter.
- Esc closed it and the probe's window was key again and received the next letter. Pressing the shortcut again also
  closed it. With the user's real front app (Brave), it stayed frontmost after six open/close cycles (three via Esc,
  three via the shortcut).
- A probe app that activated itself programmatically sometimes lost activation to another app after the close. That
  did not happen with a user-activated app and looks like an artifact of programmatic activation.
- Over a full-screen window on the external display, Brim was hidden, the shortcut showed the panel, Esc hid it again,
  and the pill returned after leaving full screen.
- Not verified: Tab/Space navigation, VoiceOver and a refused registration on a real conflict (unit tested with a fake).

## Notched vs non-notched geometry

- Notched screen: the collapsed window must equal the hardware notch (recorded 179×32 on the development machine).
  Hovering anywhere in that rectangle opens the panel; clicks in it open it without activating Brim.
- Live notch: the notch plus a 40 pt ear on each side (259×32 on the development machine), visible and clickable so a
  click on an ear never reaches the menu bar below.
- Non-notched screen: the collapsed window is a 148×10 handle at the top center, or a 150 pt pill as tall as the menu
  bar (150×30 on the 1080p external display) while something is live. It is intentionally interactive; everything outside it passes through.
- Expanded panel: 290 pt per module card plus spacing and padding (at least 460 pt), 320 tall, clamped to the screen's
  width and centered on the screen.

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
- Window levels can change between macOS releases; keep all window setup in `NotchWindow`.
- F16: ⌃⌥Space is macOS's default "Select next source in Input menu" shortcut. Brim can register it, but with several
  input sources the two fight; pick another combination.
- F14 detects full screen as "another app's window fills the display and the display shows no desktop" (Finder's and
  WindowManager's desktop-level windows are absent in a full-screen Space). On a Mac with neither (Finder's desktop
  disabled with `CreateDesktop` and no WindowManager shield), a window zoomed to fill the screen also hides Brim. A borderless,
  non-native full screen that resizes without a Space or app change is picked up at the next app switch.
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
