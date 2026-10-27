# Perch

**A desktop pet that perches on whatever window your agent is working in.**

Perch is a small macOS app plus a CLI/MCP server. Your coding agent (Claude Code, Codex, Claude Desktop, or anything that can speak MCP or write to a Unix socket) drives a mascot that sits on the edge of the window the agent is working in and acts out what it is doing: reading, typing, searching, running commands, finishing, or waiting for you. The default character is **Kuro**, a round black cat with a very long tail that she uses as a hand.

![Perch demo](docs/demo.gif)

*(Demo GIF coming soon.)*

## Quickstart

Requires macOS 14 or later and Node.js 20 or later.

```sh
brew install --cask perch-avatar          # or download Perch-<version>.dmg from GitHub Releases
npm i -g perch-avatar && perch setup
```

`perch setup` finds the clients you have (Claude Code, Claude Desktop, Codex), shows a diff of every config change, asks before writing, backs each file up, starts Perch, and checks that it reacts. Restart Claude Desktop / Codex afterwards so they load the MCP server.

Using Claude Code only? You can install the plugin instead (see [Claude Code plugin](#claude-code-plugin)). You still need the app and `npm i -g perch-avatar`.

## What it does

- **Perches on the agent's window.** Kuro lies on the top edge, sits in a corner, or peeks from the side of the window, and follows it when you move or resize it.
- **Two follow modes.** *Follow focused window* (default): she sits on whatever window you are using. *Follow agent window*: she stays on the agent's window (the terminal or app the agent runs in, or the app it says it is working in). **Double-click** Kuro to toggle between the two; **right-click** her for a menu with both modes and Quit. The 🐾 menu-bar item has the same modes plus Simulate, forced edges, and Launch at login.
- **Acts out each tool call** (Claude Code hooks):

  | Agent does | Activity | Kuro |
  |---|---|---|
  | You send a prompt | thinking | `think` (tilts her head) |
  | `Read` | reading | `read` |
  | `Edit`, `Write`, `MultiEdit`, `NotebookEdit` | typing | `type` |
  | `Grep`, `Glob`, `WebSearch`, `ToolSearch` | searching | `search` |
  | `Bash` | running | `tail_swipe` |
  | `WebFetch`, browser MCP tools (`mcp__claude-in-chrome__*`, `mcp__*browser*`) | browsing | runs over to the Google Chrome window and searches there |
  | any other tool | working | `work` |
  | Needs your input (`Notification`) | waiting_user | `wave` with a question mark, then sits in the corner |
  | Turn finished (`Stop`) | done | `celebrate` with sparkles, then lies down happy |
  | Error (via MCP / CLI) | error | `shock`, then lies down sad |
  | Session ends / long quiet | idle | back home, then `sleep` |

- **Points at text.** An agent can ask Kuro to point her tail at visible text in a window (`avatar_show` with `at: {text}`), for example "the failing test name". Perch finds the text on screen with on-device OCR (needs Screen Recording permission).
- **Desktop actions.** When the agent clicks, scrolls or types through computer use, Kuro taps, scrolls or types at that spot (needs Input Monitoring; see [Privacy](#privacy)). Claude in Chrome drives the page without system input, so its clicks, scrolls and typing are mapped from the Claude Code hook instead: page coordinates are converted to screen points assuming Chrome's toolbar is 87 pt tall (set `"browserTopInset"` in `~/.perch/config.json`, e.g. `115` with the bookmarks bar shown). This is best effort: it uses the front Chrome window and assumes 100% zoom.
- **Speech bubbles and effects.** Short lines (`say`, up to 60 characters) and effects (`exclaim`, `question`, `sparkle`, `zzz`, `sweat`, `speedlines`).

Everything is best effort: if Perch is not running, every CLI and MCP call silently does nothing and never fails the agent's task.

## Supported clients

| Client | Live reactions | MCP tools | Set up by |
|---|---|---|---|
| Claude Code | Hooks on `UserPromptSubmit`, `PreToolUse`, `Notification`, `Stop`, `SessionEnd` (per-tool actions above) | yes | `perch setup` or the plugin |
| Codex | `notify` at the end of each turn (done); the agent reports the rest through MCP | yes | `perch setup` |
| Claude Desktop | No hooks; the MCP server's instructions ask the model to call `avatar_state` at start / end / when blocked | yes | `perch setup` |
| Anything else | Write to the socket or call `perch state ...` | any MCP client: run `perch-mcp` over stdio | manual |

## Claude Code plugin

```
/plugin marketplace add masqueradeljb/perch-avatar
/plugin install perch@perch-avatar
```

The plugin adds the five hooks (`perch hook`) and the MCP server (`perch-mcp`). It relies on the global install (`npm i -g perch-avatar`) for the `perch` and `perch-mcp` commands. It also ships a `perch-setup` skill that sets up Claude Desktop and Codex for you.

`perch setup` detects the plugin automatically: it skips Claude Code (and removes any earlier setup-written Claude Code entries, so events don't fire twice) and sets up the other clients as usual. To let setup manage Claude Code instead, run `/plugin uninstall perch`.

## Manual configuration (fallback)

`perch setup` writes exactly the entries below, with absolute paths so GUI apps that do not inherit your shell `PATH` can still find Node. Replace `/abs/node` with `which node` (prefer a version-independent path like `/opt/homebrew/bin/node`) and `/abs/perch-avatar` with `$(npm root -g)/perch-avatar`.

**Claude Code hooks**, `~/.claude/settings.json` (merge into any existing `hooks`):

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "/abs/node /abs/perch-avatar/dist/cli.js hook" }] }],
    "PreToolUse":       [{ "hooks": [{ "type": "command", "command": "/abs/node /abs/perch-avatar/dist/cli.js hook" }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "/abs/node /abs/perch-avatar/dist/cli.js hook" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "/abs/node /abs/perch-avatar/dist/cli.js hook" }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "/abs/node /abs/perch-avatar/dist/cli.js hook" }] }]
  }
}
```

**Claude Code MCP server**, `~/.claude.json` under `mcpServers` (or `claude mcp add -s user perch -- /abs/node /abs/perch-avatar/dist/mcp.js`):

```json
{
  "mcpServers": {
    "perch": { "type": "stdio", "command": "/abs/node", "args": ["/abs/perch-avatar/dist/mcp.js"], "env": {} }
  }
}
```

**Claude Desktop**, `~/Library/Application Support/Claude/claude_desktop_config.json`, then restart Claude Desktop:

```json
{
  "mcpServers": {
    "perch": { "command": "/abs/node", "args": ["/abs/perch-avatar/dist/mcp.js"] }
  }
}
```

**Codex**, `~/.codex/config.toml`, then restart Codex:

```toml
notify = ["/abs/perch-avatar/assets/notify-chain.sh"]

[mcp_servers.perch]
command = "/abs/node"
args = ["/abs/perch-avatar/dist/mcp.js"]
```

Codex allows only one `notify` command. If you already have one, keep it by putting it after the chain script, which runs Perch and then hands off to your command with the same arguments: `notify = ["/abs/perch-avatar/assets/notify-chain.sh", "/your/notify", "arg"]`. `notify` must stay above the first `[table]`.

## MCP tools

The `perch-mcp` stdio server (server name `perch`) has three tools:

| Tool | Parameters | Use |
|---|---|---|
| `avatar_state` | `state`: `thinking` \| `working` \| `done` \| `error` \| `waiting_user` \| `idle`; `note?` (≤ 80 chars); `activity?`: `typing` \| `reading` \| `searching` \| `browsing` \| `running`; `window?`: app name you are now working in (e.g. `"Google Chrome"`), or `"home"` to come back | Cheap status report at task start / end, when blocked on the user, and when the kind of work changes |
| `avatar_show` | `pose?`: `lie_edge` `sit_corner` `peek_side` `stand` `point` `think` `work` `celebrate` `shock` `sleep` `wave` `lie_low`; `face?`: `happy` `shock` `sad` `blink`; `say?` (≤ 60 chars); `fx?`: `exclaim` `question` `sparkle` `zzz` `sweat` `speedlines`; `at?`: `{text, window?}` (point at visible text, preferred) or `{window, edge?: top\|left\|right\|corner_l\|corner_r, pos?: 0–1}` or `{rect: [x, y, w, h]}` (screen points, top-left origin); `hold_s?` (0.5–30) | A visible moment: point at something, say a short line |
| `avatar_targets` | none | Lists on-screen windows (`app`, `rect`, `focused`) to aim `avatar_show` |

## CLI

```
perch state <thinking|working|done|error|waiting_user|idle> [--note text] [--window app|home] [--activity typing|reading|searching|browsing|running]
perch hook          # reads a Claude Code hook JSON payload on stdin
perch show [--pose p] [--face f] [--say text] [--fx f] [--hold s] [--window app] [--rect x,y,w,h]
perch act <click|scroll|type|drag> [x y] [--dir up|down]
perch targets
perch setup [--yes] [--only claude-code,claude-desktop,codex] [--dry-run]
perch doctor
perch uninstall [--restore] [--yes] [--dry-run]
```

`perch state`, `hook`, `show`, `act` and `targets` always exit 0.

## Socket protocol (other integrations)

Newline-delimited JSON on the Unix socket `~/.perch/perch.sock` (override with `PERCH_SOCK`), one request per line, one reply line each (`{"ok":true,...}` or `{"ok":false,"error":"..."}`):

```sh
echo '{"type":"state","state":"working","activity":"typing"}' | nc -U ~/.perch/perch.sock
```

Request types: `state` (`state`, `note?`, `activity?`, `window?`), `show` (same fields as `avatar_show`), `act` (`action`: `click|scroll|type|drag`, `x?`, `y?` in screen points, `dir?`: `up|down`), `targets`. Add `"pid": <your process id>` so Perch can find your window.

## Packs

A pack is a folder with `pack.json` and transparent PNG poses (12 core poses with anchors such as `edge_top`, `corner`, `floor`, plus optional faces and action poses). Perch loads, in order: `--pack <dir>` → `~/.perch/packs/<id>` selected by `~/.perch/config.json` (`{"pack": "<id>"}`) → the bundled Kuro.

Optional desktop-action poses: `tap` (2 frames, hotspot at what presses) and `scroll` (2 frames). Missing ones fall back: `tap` → `point`, `scroll` → `tail_swipe` → `work`. A pose may declare `"family": "point"` (or `"tap"`) to be a directional variant; Perch picks the variant whose placement is closest to where the character already is.

- Code: MIT ([LICENSE](LICENSE)).
- Kuro artwork (`packs/kuro/`): CC-BY-4.0 ([packs/kuro/LICENSE](packs/kuro/LICENSE)), "Kuro © 2026 Jingbang Liu". Other packs carry their own license in their `pack.json`.

## Privacy

Everything runs on your Mac. Perch makes no network requests and has no telemetry. Agents talk to it over a local Unix socket. Screen Recording permission is needed for pointing at text (Perch reads the agent's window with on-device OCR to find the words). Without it, everything else still works. Grant it in System Settings > Privacy & Security > Screen & System Audio Recording > Perch.

**Input Monitoring** is used only to notice clicks, scrolls and key presses that *another program posted* (an agent's computer use) while your agent is working, and keys are counted, never read. Input straight from your keyboard and mouse is ignored, but utilities that re-post your input (scroll smoothers such as Mos, remappers such as Karabiner or BetterTouchTool, text expanders) can look like the agent — list them in `~/.perch/config.json` `"ignoreApps"` (app name, bundle id or executable name; relaunch Perch after editing). Without Input Monitoring, desktop actions are off.

## Troubleshooting

```sh
perch doctor
```

Checks that the app is installed and running, that the socket answers, that the Node path written into your configs still exists, and that each detected client is configured. It prints a fix for each ✗. With the Claude Code plugin installed, doctor counts it as configured, and warns if setup entries also exist (events would fire twice; `perch setup` removes them). Common fixes: `open -a Perch`; re-run `perch setup` after upgrading Node or moving the install; restart Claude Desktop / Codex after setup.

## Uninstall

```sh
perch uninstall          # removes only Perch's entries from each client config (shows diffs, asks first)
perch uninstall --restore  # or: put back the pre-Perch backups verbatim (edits made since are lost)
npm rm -g perch-avatar
brew uninstall --cask perch-avatar   # or drag Perch.app to the Trash
rm -rf ~/.perch
```

Backups live next to each config as `<file>.perch-bak-<timestamp>`; `~/.perch/install.json` records them.

## Building from source

```sh
cd app && swift build && swift test        # the app (Swift package, executable "Perch")
swift run Perch --pack ../packs/kuro       # run without bundling
scripts/build-app.sh                       # build/Perch.app + .zip + .dmg (unsigned; --sign / --notarize need a Developer ID)
cd cli && npm install && npm test && npm run build && npm i -g .
```

Layout: `app/` (Swift app: overlay, window probing, OCR, socket server), `cli/` (npm package `perch-avatar`: `perch`, `perch-mcp`, setup), `packs/kuro/`, `adapters/codex/` (notify chain), `plugins/perch/` (Claude Code plugin), `.claude-plugin/marketplace.json`.

## License

MIT for code; CC-BY-4.0 for the Kuro pack.
