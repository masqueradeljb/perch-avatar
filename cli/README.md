# perch-avatar

CLI + MCP server for [Perch](https://github.com/masqueradeljb/perch-avatar), a desktop pet that perches on whatever window your agent is working in (macOS 14+, needs the Perch app).

```sh
npm i -g perch-avatar && perch setup
```

- `perch setup [--yes] [--only claude-code,claude-desktop,codex] [--dry-run]` configures Claude Code, Claude Desktop and Codex (diffs, confirmation, backups). `perch doctor` checks everything; `perch uninstall [--restore]` removes it.
- `perch-mcp`: MCP stdio server (name `perch`) with tools `avatar_state`, `avatar_show`, `avatar_targets`.
- `perch state working --activity typing`, `perch hook` (Claude Code hook payload on stdin), `perch show --pose point --rect x,y,w,h`, `perch act click 800 400` (play an agent action at a screen point), `perch targets`. These always exit 0.

Talks to the app over `~/.perch/perch.sock` (override with `PERCH_SOCK`); everything silently no-ops when the app is not running.

Development, from the repo's `cli/` directory: `npm install && npm test && npm run build`, then `npm i -g .` to try it. See the [main README](https://github.com/masqueradeljb/perch-avatar#readme) for the full docs.
