---
name: perch-setup
description: Set up or check the Perch desktop mascot, including for Claude Desktop and Codex. Use when the user asks to install, configure, fix, or remove Perch, or says the mascot is not reacting.
---

# Perch setup

The plugin already gives Claude Code the hooks and MCP server. For the other clients and for diagnosis, use the `perch` CLI; never edit client config files by hand.

1. If `command -v perch` finds nothing, run `npm i -g perch-avatar` first (Node 20+; never `npx`).
2. If Perch.app is missing (`perch doctor` says so), tell the user: `brew install --cask perch-avatar`, or download the DMG from https://github.com/masqueradeljb/perch-avatar/releases.
3. Set up Claude Desktop and Codex: `perch setup --dry-run`, show the user the diffs, and after they agree run it again with `--yes` instead of `--dry-run`. Setup detects this plugin automatically and skips Claude Code (removing any duplicate setup-written entries), so no `--only` is needed.
4. Run `perch doctor` and report each ✗ with its printed fix. Doctor counts the plugin as Claude Code being configured; if it warns that the plugin and setup entries both exist, run `perch setup` to remove the setup entries.
5. Remind the user to restart Claude Desktop / Codex, and that pointing at text needs Screen Recording (System Settings > Privacy & Security > Screen & System Audio Recording > Perch).

To remove Perch from those clients: `perch uninstall --only claude-desktop,codex` (shows diffs, asks first).
