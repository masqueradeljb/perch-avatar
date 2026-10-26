# Adapters

`perch setup` writes these into client configs for you; this folder is the source for the parts that are not plain config.

## Codex: `codex/notify-chain.sh`

Codex allows one `notify` command. `perch setup` sets it to this script, keeping any previous notify command after it:

    notify = ["/abs/perch-avatar/assets/notify-chain.sh", "<previous notify argv...>"]

The script tells Perch the turn is done (`perch state done`, in the background) and then runs the previous command with Codex's arguments unchanged. It finds the CLI via `PERCH_CLI` if set, otherwise runs `node` (`PERCH_NODE` overrides it) on `dist/cli.js`, either in the npm package (`<pkg>/assets/` → `<pkg>/dist/`) or in a source checkout (`adapters/codex/` → `cli/dist/`).

`npm run build` in `cli/` copies this file into `cli/assets/` so it ships with the npm package; edit it here.

## Claude Code

The Claude Code integration is the plugin in [`../plugins/perch`](../plugins/perch) (hooks + MCP server), or `perch setup`, which writes the same hooks into `~/.claude/settings.json`. See the main README for manual config of every client.
