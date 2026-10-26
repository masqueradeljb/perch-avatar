import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { planClaudeDesktop, planClaudeHooks, planClaudeJson, planCodex, unplanClaudeDesktop, unplanClaudeHooks, unplanClaudeJson, unplanCodex, type McpSpec, type Plan } from "./plan.js";

export type ClientId = "claude-code" | "claude-desktop" | "codex";
export type Client = { id: ClientId; name: string; configPath: string; detected: boolean };

/** What `perch` runs on behalf of the clients: absolute, stable paths. */
export type Commands = { hookCmd: string; mcp: McpSpec; notifyChain: string };

/** One file a client needs edited. */
export type Target = { client: ClientId; file: string; plan: (text: string) => Plan; unplan: (text: string) => Plan };

/** Test hook: PERCH_HOME_OVERRIDE replaces the user's home directory everywhere. */
export const homeDir = (): string => process.env.PERCH_HOME_OVERRIDE ?? os.homedir();

const exists = (p: string): boolean => fs.existsSync(p);

export function detectClients(home = homeDir()): Client[] {
  const desktop = path.join(home, "Library", "Application Support", "Claude");
  return [
    { id: "claude-code", name: "Claude Code", configPath: path.join(home, ".claude", "settings.json"), detected: exists(path.join(home, ".claude")) },
    { id: "claude-desktop", name: "Claude Desktop", configPath: path.join(desktop, "claude_desktop_config.json"), detected: exists(desktop) },
    { id: "codex", name: "Codex", configPath: path.join(home, ".codex", "config.toml"), detected: exists(path.join(home, ".codex")) },
  ];
}

export function targetsFor(client: Client, cmds: Commands, home = homeDir()): Target[] {
  switch (client.id) {
    case "claude-code":
      return [
        { client: client.id, file: client.configPath, plan: (t) => planClaudeHooks(t, cmds.hookCmd), unplan: (t) => unplanClaudeHooks(t, cmds.hookCmd) },
        // Written directly (instead of `claude mcp add -s user`) so the change can be previewed as a diff.
        { client: client.id, file: path.join(home, ".claude.json"), plan: (t) => planClaudeJson(t, cmds.mcp), unplan: unplanClaudeJson },
      ];
    case "claude-desktop":
      return [{ client: client.id, file: client.configPath, plan: (t) => planClaudeDesktop(t, cmds.mcp), unplan: unplanClaudeDesktop }];
    case "codex":
      return [{ client: client.id, file: client.configPath, plan: (t) => planCodex(t, cmds.mcp, cmds.notifyChain), unplan: (t) => unplanCodex(t, cmds.notifyChain) }];
  }
}
