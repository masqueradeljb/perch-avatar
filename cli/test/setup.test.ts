import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { runSetup, runUninstall, runDoctor, type Io } from "../src/setup.js";
import type { Commands } from "../src/clients.js";

const cmds: Commands = { hookCmd: "/n /p/cli.js hook", mcp: { command: "/n", args: ["/p/mcp.js"] }, notifyChain: "/p/notify-chain.sh" };

function fixture() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "perch-test-"));
  fs.mkdirSync(path.join(home, ".claude"));
  fs.mkdirSync(path.join(home, ".codex"));
  const settings = path.join(home, ".claude", "settings.json");
  const codex = path.join(home, ".codex", "config.toml");
  fs.writeFileSync(settings, JSON.stringify({ theme: "dark", hooks: { Stop: [{ hooks: [{ type: "command", command: "echo mine" }] }] } }, null, 2) + "\n");
  fs.writeFileSync(codex, '# keep me\nmodel = "x"\n\n[features]\na = 1\n');
  const lines: string[] = [];
  const io: Io = { out: (s) => lines.push(s), ask: async () => true };
  return { home, settings, codex, io, lines };
}

test("dry run writes nothing but prints diffs", async () => {
  const f = fixture();
  const before = fs.readFileSync(f.settings, "utf8");
  await runSetup({ home: f.home, cmds, dryRun: true }, f.io);
  assert.equal(fs.readFileSync(f.settings, "utf8"), before);
  assert.ok(!fs.existsSync(path.join(f.home, ".perch")));
  assert.ok(f.lines.join("\n").includes("+++ " + f.settings));
});

test("setup writes with backup + record, second run is a no-op, uninstall reverses, restore is verbatim", async () => {
  const f = fixture();
  const orig = { s: fs.readFileSync(f.settings, "utf8"), c: fs.readFileSync(f.codex, "utf8") };
  let t = 0;
  const now = () => new Date(Date.UTC(2026, 0, 1, 0, 0, t++));
  await runSetup({ home: f.home, cmds, yes: true, skipApp: true, now }, f.io);
  assert.match(fs.readFileSync(f.settings, "utf8"), /cli\.js hook/);
  assert.match(fs.readFileSync(f.codex, "utf8"), /\[mcp_servers\.perch\]/);
  const inst = JSON.parse(fs.readFileSync(path.join(f.home, ".perch", "install.json"), "utf8"));
  const rec = inst.entries.find((e: { file: string }) => e.file === f.settings);
  assert.equal(fs.readFileSync(rec.backup, "utf8"), orig.s);

  f.lines.length = 0;
  await runSetup({ home: f.home, cmds, yes: true, skipApp: true, now }, f.io);
  assert.ok(!f.lines.join("\n").includes("@@"), "second run must not produce diffs");

  await runUninstall({ home: f.home, cmds, yes: true, now }, f.io);
  assert.deepEqual(JSON.parse(fs.readFileSync(f.settings, "utf8")), JSON.parse(orig.s));
  assert.equal(fs.readFileSync(f.codex, "utf8"), orig.c);

  await runSetup({ home: f.home, cmds, yes: true, skipApp: true, now }, f.io);
  await runUninstall({ home: f.home, cmds, yes: true, restore: true }, f.io);
  assert.equal(fs.readFileSync(f.settings, "utf8"), orig.s);
});

test("--only limits clients; doctor reports and exits 0", async () => {
  const f = fixture();
  await runSetup({ home: f.home, cmds, yes: true, skipApp: true, only: ["codex"] }, f.io);
  assert.ok(!/cli\.js hook/.test(fs.readFileSync(f.settings, "utf8")));
  f.lines.length = 0;
  assert.equal(await runDoctor({ home: f.home, cmds }, f.io), 0);
  const out = f.lines.join("\n");
  assert.match(out, /✓ Codex configured/);
  assert.match(out, /✗ Claude Code is not configured/);
});
