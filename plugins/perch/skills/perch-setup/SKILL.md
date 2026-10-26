---
name: perch-setup
description: Set up or check the Perch desktop mascot, including for Claude Desktop and Codex. Use when the user asks to install, configure, fix, or remove Perch, or says the mascot is not reacting.
---

# Perch setup

The plugin already gives Claude Code the hooks and MCP server. For the other clients and for diagnosis, use the `perch` CLI; never edit client config files by hand.

1. If `command -v perch` finds nothing, run `npm i -g perch-avatar` first (Node 20+; never `npx`).
2. If Perch.app is missing (`perch doctor` says so), tell the user: `brew install --cask perch-avatar`, or download the DMG from https://github.com/masqueradeljb/perch-avatar/releases.
3. Set up Claude Desktop and Codex: `perch setup --only claude-desktop,codex --dry-run`, show the user the diffs, and after they agree run it again with `--yes` instead of `--dry-run`. Do not set up `claude-code` here: the plugin already covers it and a second set of hooks would fire every event twice.
4. Run `perch doctor` and report each ✗ with its printed fix. Ignore "Claude Code is not configured": `perch doctor` only checks `~/.claude/settings.json`, and the plugin provides those hooks instead.
5. Remind the user to restart Claude Desktop / Codex, and that pointing at text needs Screen Recording (System Settings > Privacy & Security > Screen & System Audio Recording > Perch).

To remove Perch from those clients: `perch uninstall --only claude-desktop,codex` (shows diffs, asks first).
