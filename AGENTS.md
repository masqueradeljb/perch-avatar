# AGENTS.md

## If you were asked to install Perch for the user

Follow `llms-install.md`. In short: check macOS 14+ and Node 20+ → `brew install --cask perch-avatar` (or the DMG from GitHub Releases) → `npm i -g perch-avatar` → `perch setup --yes` → `perch doctor` → ask the user to grant Screen Recording if they want text pointing, and to restart Claude Desktop / Codex. Make no other config edits.

## If Perch is installed and you have its MCP tools

- `avatar_state`: call with `thinking` / `working` when you start, `done` / `error` when you finish, `waiting_user` when you need the user. Pass `activity` (typing, reading, searching, browsing, running) when it changes, and `window` with the app name when you start working in another app (`"home"` when you come back).
- `avatar_show`: use sparingly. Point at visible text with `at: {text, window?}`, or say a short line (≤ 60 chars).
- Calls are cheap and never fail; if the app is not running they are ignored.

## If you are working on this repository

- `app/`: Swift package (macOS 14+). `cd app && swift test`. Executable product `Perch` (target `AvatarApp`), logic in `AvatarCore` (tested).
- `cli/`: npm package `perch-avatar` (bins `perch`, `perch-mcp`). `cd cli && npm install && npm test && npm run build`. Config edits live in pure planners in `src/plan.ts` (each returns `{before, after, changed}` and must be idempotent); add tests in `test/plan.test.ts` for any change.
- `scripts/build-app.sh`: builds `build/Perch.app`, zip and dmg. `--sign` / `--notarize` need the maintainer's Developer ID.
- `adapters/codex/notify-chain.sh` is the single source; `npm run build` copies it to `cli/assets/`.
- `plugins/perch/`: Claude Code plugin; `.claude-plugin/marketplace.json` lists it.
- Never commit copyrighted characters' art; packs in this repo must be redistributable (Kuro is CC-BY-4.0).
