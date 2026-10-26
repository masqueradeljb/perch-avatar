# Installing Perch (for AI agents)

Perch is a macOS desktop mascot that coding agents drive through hooks and an MCP server. Follow these steps exactly. Do not edit any client config file yourself: `perch setup` is the only thing that writes configs.

1. Check the platform. Run `sw_vers -productVersion`; stop and tell the user if it is not macOS 14 or later. Run `node --version`; Node.js 20 or later is required (install it first if missing).
2. Install the app. Run `brew install --cask perch-avatar`. If Homebrew is not available, tell the user to download `Perch-<version>.dmg` from https://github.com/masqueradeljb/perch-avatar/releases and drag Perch to Applications, then wait for them.
3. Install the CLI: `npm i -g perch-avatar`. Do not use `npx`; configs must point at a stable install.
4. Configure every detected client: `perch setup --yes`. It prints a diff per file, backs up each file, starts Perch, and checks that it reacts. Show the user the diffs it printed.
5. Verify: `perch doctor`. Every line should be ✓ (the Screen Recording line is informational). If something shows ✗, run the fix it prints, then `perch doctor` again.
6. Tell the user:
   - Restart Claude Desktop and Codex (if installed) so they load the new MCP server. Claude Code picks it up in the next session.
   - To let Perch point at text on screen, grant Screen Recording: System Settings > Privacy & Security > Screen & System Audio Recording > Perch. Optional; everything else works without it.

To remove: `perch uninstall --yes`, then `npm rm -g perch-avatar` and `brew uninstall --cask perch-avatar`.
