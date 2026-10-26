import { execFile } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import readline from "node:readline/promises";
import { fileURLToPath } from "node:url";
import { send } from "./client.js";
import { detectClients, homeDir, perchPluginActive, targetsFor, type Client, type ClientId, type Commands, type Target } from "./clients.js";
import { unifiedDiff } from "./diff.js";

export type Io = { out: (s: string) => void; ask: (q: string) => Promise<boolean> };
export type Opts = { yes?: boolean; dryRun?: boolean; only?: ClientId[]; restore?: boolean; home?: string; cmds?: Commands; skipApp?: boolean; now?: () => Date };

const shq = (s: string): string => (/^[A-Za-z0-9_@%+=:,./-]+$/.test(s) ? s : `'${s.replace(/'/g, `'\\''`)}'`);

/** process.execPath, but prefer the version-independent symlink (Homebrew's Cellar path breaks on upgrade). */
function stableNode(): string {
  const exec = process.execPath;
  let target = exec;
  try { target = fs.realpathSync(exec); } catch { /* keep */ }
  for (const c of ["/opt/homebrew/bin/node", "/usr/local/bin/node"]) {
    try { if (fs.realpathSync(c) === target) return c; } catch { /* next */ }
  }
  return exec;
}

/** Absolute node + real paths of this install's cli/mcp/notify-chain. Throws for npx-cache paths. */
export function resolveCommands(): Commands {
  const dir = path.dirname(fileURLToPath(import.meta.url));
  const real = (p: string): string => fs.realpathSync(p);
  const cli = real(path.join(dir, "cli.js"));
  const mcp = real(path.join(dir, "mcp.js"));
  const chains = [path.join(dir, "..", "assets", "notify-chain.sh"), path.join(dir, "..", "..", "adapters", "codex", "notify-chain.sh")];
  const chainSrc = chains.find((c) => fs.existsSync(c));
  if (!chainSrc) throw new Error("notify-chain.sh not found next to this install");
  const notifyChain = real(chainSrc);
  const node = stableNode();
  for (const p of [node, cli, mcp, notifyChain]) {
    if (p.includes("/_npx/")) throw new NpxError();
  }
  return { hookCmd: `${shq(node)} ${shq(cli)} hook`, mcp: { command: node, args: [mcp] }, notifyChain };
}

export class NpxError extends Error {
  constructor() { super("Perch is running from a temporary npx cache; configs must point at a stable install.\nRun:  npm i -g perch-avatar && perch setup"); }
}

type Record_ = { file: string; backup: string; ts: string; client: ClientId };
const installFile = (home: string): string => path.join(home, ".perch", "install.json");
function readInstall(home: string): { entries: Record_[] } {
  try { return JSON.parse(fs.readFileSync(installFile(home), "utf8")) as { entries: Record_[] }; } catch { return { entries: [] }; }
}
function writeInstall(home: string, data: { entries: Record_[] }): void {
  fs.mkdirSync(path.dirname(installFile(home)), { recursive: true });
  fs.writeFileSync(installFile(home), JSON.stringify(data, null, 2) + "\n");
}

const read = (f: string): string => (fs.existsSync(f) ? fs.readFileSync(f, "utf8") : "");
const stamp = (d: Date): string => d.toISOString().replace(/[-:]/g, "").replace(/\..*/, "");

function selectClients(home: string, only?: ClientId[]): Client[] {
  return detectClients(home).filter((c) => c.detected && (!only || only.includes(c.id)));
}

/** Backs up, writes, and records one file. */
function writeWithBackup(home: string, t: Target, after: string, now: Date): Record_ | null {
  let backup = "";
  if (fs.existsSync(t.file)) { backup = `${t.file}.perch-bak-${stamp(now)}`; fs.copyFileSync(t.file, backup); }
  else fs.mkdirSync(path.dirname(t.file), { recursive: true });
  fs.writeFileSync(t.file, after);
  const rec = { file: t.file, backup, ts: now.toISOString(), client: t.client };
  const inst = readInstall(home);
  inst.entries.push(rec);
  writeInstall(home, inst);
  return rec;
}

async function apply(mode: "plan" | "unplan", clients: Client[], cmds: Commands, o: Opts, io: Io): Promise<{ changed: number; errors: number }> {
  const home = o.home ?? homeDir();
  let changed = 0, errors = 0;
  for (const c of clients) {
    io.out(`\n== ${c.name} ==`);
    const viaPlugin = mode === "plan" && c.id === "claude-code" && perchPluginActive(home);
    if (viaPlugin) io.out("Claude Code: using the Perch plugin — skipping (remove it with /plugin uninstall perch to let setup manage Claude Code)");
    for (const t of targetsFor(c, cmds, home)) {
      const m = viaPlugin ? "unplan" : mode;
      let r;
      try { r = t[m](read(t.file)); } catch (e) { errors++; io.out(`! ${t.file}: cannot parse (${(e as Error).message}) — left untouched`); continue; }
      if (!r.changed) { if (!viaPlugin) io.out(`✓ ${t.file}: nothing to ${m === "plan" ? "change (already configured)" : "remove"}`); continue; }
      if (viaPlugin) io.out(`Removing duplicate setup entries from ${t.file} (the plugin provides them):`);
      io.out(unifiedDiff(r.before, r.after, t.file));
      changed++;
      if (o.dryRun) continue;
      if (!o.yes && !(await io.ask(`Apply to ${t.file}? [y/N] `))) { io.out("skipped"); continue; }
      writeWithBackup(home, t, r.after, (o.now ?? (() => new Date()))());
      io.out(`wrote ${t.file}`);
    }
  }
  return { changed, errors };
}

const appInstalled = (home: string): string | null =>
  ["/Applications/Perch.app", path.join(home, "Applications", "Perch.app")].find((p) => fs.existsSync(p)) ?? null;
const running = async (): Promise<boolean> => (await send({ type: "targets" })) !== null;
const sleep = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

export async function runSetup(o: Opts, io: Io): Promise<number> {
  const home = o.home ?? homeDir();
  const cmds = o.cmds ?? resolveCommands();
  const clients = selectClients(home, o.only);
  if (!clients.length) { io.out("No supported clients detected (Claude Code, Claude Desktop, Codex)."); return 0; }
  io.out(`Detected: ${clients.map((c) => c.name).join(", ")}${o.dryRun ? "  (dry run: nothing will be written)" : ""}`);
  const { errors } = await apply("plan", clients, cmds, o, io);
  if (o.dryRun || o.skipApp) return errors ? 1 : 0;
  io.out("");
  if (!appInstalled(home) && !(await running())) {
    io.out("Perch.app is not installed. Get it with:  brew install --cask perch-avatar  (or download the DMG from the GitHub release)");
  } else {
    if (!(await running())) { await new Promise<void>((r) => execFile("open", ["-a", "Perch"], () => r())); await sleep(2000); }
    const r = await send({ type: "state", state: "done" });
    io.out(r ? "✓ Perch reacted" : "! Perch did not answer — start Perch.app and run `perch doctor`");
  }
  io.out("Restart Claude Desktop / Codex so they pick up the new MCP server.");
  return errors ? 1 : 0;
}

export async function runUninstall(o: Opts, io: Io): Promise<number> {
  const home = o.home ?? homeDir();
  if (o.restore) {
    const latest = new Map<string, Record_>();
    for (const e of readInstall(home).entries) if (e.backup && fs.existsSync(e.backup) && !latest.has(e.file)) latest.set(e.file, e); // oldest backup = pre-Perch state
    if (!latest.size) { io.out("No backups recorded in ~/.perch/install.json."); return 0; }
    for (const e of latest.values()) {
      io.out(`restore ${e.file}  <-  ${e.backup}`);
      if (o.dryRun) continue;
      if (!o.yes && !(await io.ask("Overwrite with the backup? Edits made since will be lost. [y/N] "))) continue;
      fs.copyFileSync(e.backup, e.file);
      io.out("restored");
    }
    return 0;
  }
  const clients = selectClients(home, o.only);
  const cmds = o.cmds ?? safeCommands();
  const { errors } = await apply("unplan", clients, cmds, o, io);
  return errors ? 1 : 0;
}

/** Uninstall must work even from an npx cache or a moved install: unplanners ignore the exact paths. */
function safeCommands(): Commands {
  try { return resolveCommands(); } catch { return { hookCmd: "", mcp: { command: "", args: [] }, notifyChain: "notify-chain.sh" }; }
}

export async function runDoctor(o: Opts, io: Io): Promise<number> {
  const home = o.home ?? homeDir();
  const ok = (m: string): void => io.out(`✓ ${m}`);
  const bad = (m: string, fix: string): void => io.out(`✗ ${m}\n    fix: ${fix}`);
  let cmds: Commands | null = null;
  try { cmds = o.cmds ?? resolveCommands(); } catch (e) { bad((e as Error).message.split("\n")[0], "npm i -g perch-avatar && perch setup"); }
  const app = appInstalled(home);
  app ? ok(`Perch.app installed (${app})`) : bad("Perch.app not found", "brew install --cask perch-avatar");
  (await running()) ? ok("Perch is running and the socket answers") : bad("Perch is not running (socket does not answer)", "open -a Perch");
  if (cmds) {
    const node = cmds.mcp.command, entry = cmds.mcp.args[0];
    fs.existsSync(node) && fs.existsSync(entry) ? ok(`Node path valid (${node})`) : bad("Node or perch path no longer exists", "perch setup");
    for (const c of detectClients(home)) {
      if (!c.detected) { io.out(`- ${c.name}: not detected`); continue; }
      let good = true, present = false;
      for (const t of targetsFor(c, cmds, home)) {
        try { if (t.plan(read(t.file)).changed) good = false; } catch { good = false; }
        if (c.id === "claude-code") { try { if (t.unplan(read(t.file)).changed) present = true; } catch { /* unparseable */ } }
      }
      if (c.id === "claude-code" && perchPluginActive(home)) {
        present ? bad("Claude Code has the Perch plugin and setup entries — events fire twice.", "perch setup (removes the setup entries)") : ok("Claude Code configured (Perch plugin)");
        continue;
      }
      good ? ok(`${c.name} configured`) : bad(`${c.name} is not configured (or still uses an old entry)`, "perch setup");
    }
  }
  io.out("i Pointing at text needs Screen Recording: System Settings > Privacy & Security > Screen & System Audio Recording > Perch.");
  return 0;
}

export async function main(cmd: string, argv: string[]): Promise<number> {
  const has = (f: string): boolean => argv.includes(f);
  const oi = argv.indexOf("--only");
  const only = oi >= 0 && argv[oi + 1] ? (argv[oi + 1].split(",") as ClientId[]) : undefined;
  const o: Opts = { yes: has("--yes") || has("-y"), dryRun: has("--dry-run"), restore: has("--restore"), only };
  const io: Io = {
    out: (s) => console.log(s),
    ask: async (q) => {
      if (!process.stdin.isTTY) { console.log(`${q}(no terminal; pass --yes to apply)`); return false; }
      const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
      const a = (await rl.question(q)).trim().toLowerCase();
      rl.close();
      return a === "y" || a === "yes";
    },
  };
  try {
    if (cmd === "setup") return await runSetup(o, io);
    if (cmd === "uninstall") return await runUninstall(o, io);
    return await runDoctor(o, io);
  } catch (e) {
    console.error((e as Error).message);
    return cmd === "doctor" ? 0 : 1;
  }
}
