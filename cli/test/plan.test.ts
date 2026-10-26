import { test } from "node:test";
import assert from "node:assert/strict";
import { planClaudeHooks, planClaudeDesktop, planClaudeJson, planCodex, unplanClaudeHooks, unplanClaudeDesktop, unplanClaudeJson, unplanCodex } from "../src/plan.js";

const HOOK = "/usr/local/bin/node /opt/perch/dist/cli.js hook";
const MCP = { command: "/usr/local/bin/node", args: ["/opt/perch/dist/mcp.js"] };
const CHAIN = "/opt/perch/assets/notify-chain.sh";
const OLD_HOOK = "/home/u/proj/agent-avatar/bin/avatar hook";
const OTHER = "python3 /home/u/scripts/nudge.py 2>/dev/null || true";
const EVENTS = ["UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SessionEnd"];

const entry = (command: string) => ({ hooks: [{ type: "command", command }] });
const settings = (extra: object = {}, hooks: Record<string, unknown[]> = {}) => JSON.stringify({ theme: "dark", hooks, ...extra }, null, 2) + "\n";
const cmds = (s: string, ev: string): string[] => (JSON.parse(s).hooks[ev] ?? []).flatMap((e: { hooks: { command: string }[] }) => e.hooks.map((h) => h.command));

test("claude hooks: fresh config gets all five events", () => {
  const r = planClaudeHooks("", HOOK);
  assert.ok(r.changed);
  for (const ev of EVENTS) assert.deepEqual(cmds(r.after, ev), [HOOK]);
});

test("claude hooks: unrelated settings and hooks preserved, ours appended", () => {
  const before = settings({ voice: true }, { UserPromptSubmit: [{ hooks: [{ type: "command", command: OTHER, timeout: 5 }] }], PostToolUse: [entry("echo hi")] });
  const r = planClaudeHooks(before, HOOK);
  const o = JSON.parse(r.after);
  assert.equal(o.theme, "dark"); assert.equal(o.voice, true);
  assert.deepEqual(o.hooks.PostToolUse, [entry("echo hi")]);
  assert.deepEqual(cmds(r.after, "UserPromptSubmit"), [OTHER, HOOK]);
  assert.equal(o.hooks.UserPromptSubmit[0].hooks[0].timeout, 5);
});

test("claude hooks: idempotent", () => {
  const once = planClaudeHooks(settings(), HOOK).after;
  const twice = planClaudeHooks(once, HOOK);
  assert.equal(twice.changed, false);
  assert.equal(twice.after, once);
});

test("claude hooks: migrates old prototype entries in place", () => {
  const hooks: Record<string, unknown[]> = {};
  for (const ev of EVENTS) hooks[ev] = [entry(OLD_HOOK)];
  hooks.UserPromptSubmit = [entry(OLD_HOOK), entry(OTHER)];
  const r = planClaudeHooks(settings({}, hooks), HOOK);
  for (const ev of EVENTS) assert.ok(!cmds(r.after, ev).includes(OLD_HOOK));
  assert.deepEqual(cmds(r.after, "UserPromptSubmit"), [HOOK, OTHER]);
  assert.deepEqual(cmds(r.after, "Stop"), [HOOK]);
  assert.equal(planClaudeHooks(r.after, HOOK).changed, false);
});

test("claude hooks: stale perch path is replaced", () => {
  const stale = "/old/node /old/dist/cli.js hook";
  const r = planClaudeHooks(planClaudeHooks(settings(), "/old/node /old/perch hook").after, HOOK);
  assert.deepEqual(cmds(r.after, "Stop"), [HOOK]);
  void stale;
});

test("claude hooks: invalid JSON throws", () => {
  assert.throws(() => planClaudeHooks("{nope", HOOK));
});

test("unplan claude hooks: removes only ours, drops empty events", () => {
  const installed = planClaudeHooks(settings({}, { UserPromptSubmit: [entry(OTHER)] }), HOOK).after;
  const r = unplanClaudeHooks(installed, HOOK);
  assert.ok(r.changed);
  assert.deepEqual(cmds(r.after, "UserPromptSubmit"), [OTHER]);
  assert.equal(JSON.parse(r.after).hooks.Stop, undefined);
  assert.equal(unplanClaudeHooks(r.after, HOOK).changed, false);
});

const desktop = (servers: object) => JSON.stringify({ preferences: { a: 1 }, mcpServers: servers }, null, 2) + "\n";

test("claude desktop: fresh, preserved, idempotent, migrated", () => {
  const fresh = planClaudeDesktop("", MCP);
  assert.deepEqual(JSON.parse(fresh.after).mcpServers.perch, MCP);
  const before = desktop({ other: { command: "x" }, "agent-avatar": { command: "/home/u/agent-avatar/bin/agent-avatar-mcp" } });
  const r = planClaudeDesktop(before, MCP);
  const o = JSON.parse(r.after);
  assert.deepEqual(o.mcpServers.other, { command: "x" });
  assert.equal(o.mcpServers["agent-avatar"], undefined);
  assert.deepEqual(o.preferences, { a: 1 });
  assert.equal(planClaudeDesktop(r.after, MCP).changed, false);
  const u = unplanClaudeDesktop(r.after);
  assert.equal(JSON.parse(u.after).mcpServers.perch, undefined);
  assert.deepEqual(JSON.parse(u.after).mcpServers.other, { command: "x" });
});

test("claude json (code): stdio server shape, migrate", () => {
  const before = JSON.stringify({ numStartups: 3, mcpServers: { "agent-avatar": { type: "stdio", command: "/x/agent-avatar-mcp", args: [], env: {} }, s: { type: "http", url: "u" } } }, null, 2);
  const r = planClaudeJson(before, MCP);
  const o = JSON.parse(r.after);
  assert.deepEqual(o.mcpServers.perch, { type: "stdio", command: MCP.command, args: MCP.args, env: {} });
  assert.equal(o.mcpServers["agent-avatar"], undefined);
  assert.equal(o.numStartups, 3);
  assert.equal(planClaudeJson(r.after, MCP).changed, false);
  assert.equal(JSON.parse(unplanClaudeJson(r.after).after).mcpServers.perch, undefined);
});

const CODEX = `model = "gpt"
# a comment that must survive
notify = ["/Users/u/.codex/cu/Client", "turn-ended", "--previous-notify", "[\\"/old/agent-avatar/adapters/codex/notify-chain.sh\\"]"]

[features]
x = true # trailing

[mcp_servers.node_repl]
command = "/bin/node_repl"

[mcp_servers.node_repl.env]
A = "1"

[mcp_servers.agent-avatar]
command = "/home/u/agent-avatar/bin/agent-avatar-mcp"
`;

test("codex: migrates agent-avatar block in place, prepends notify chain, preserves the rest", () => {
  const r = planCodex(CODEX, MCP, CHAIN);
  assert.ok(r.changed);
  assert.ok(!r.after.includes("[mcp_servers.agent-avatar]"));
  assert.ok(r.after.includes('[mcp_servers.perch]\ncommand = "/usr/local/bin/node"\nargs = ["/opt/perch/dist/mcp.js"]\n'));
  assert.ok(r.after.includes('notify = ["/Users/u/.codex/cu/Client", "turn-ended", "--previous-notify", "[\\"' + CHAIN.replace(/\//g, "\\\\/") + '\\"]"]'));
  assert.ok(r.after.includes("# a comment that must survive"));
  assert.ok(r.after.includes("x = true # trailing"));
  assert.ok(r.after.includes('[mcp_servers.node_repl.env]\nA = "1"\n'));
  assert.equal(planCodex(r.after, MCP, CHAIN).changed, false);
});

test("codex: fresh/empty file", () => {
  const r = planCodex("", MCP, CHAIN);
  assert.equal(r.after, `notify = ["${CHAIN}"]\n\n[mcp_servers.perch]\ncommand = "/usr/local/bin/node"\nargs = ["/opt/perch/dist/mcp.js"]\n`);
  assert.equal(planCodex(r.after, MCP, CHAIN).changed, false);
});

test("codex: no notify -> inserted at top level (before first table)", () => {
  const r = planCodex('model = "x"\n\n[features]\na = 1\n', MCP, CHAIN);
  const lines = r.after.split("\n");
  assert.ok(lines.indexOf(`notify = ["${CHAIN}"]`) < lines.indexOf("[features]"));
  assert.equal(planCodex(r.after, MCP, CHAIN).changed, false);
});

test("codex: stale chain path replaced, stale perch block replaced", () => {
  const src = `notify = ["/old/notify-chain.sh", "prev"]\n\n[mcp_servers.perch]\ncommand = "/old/node"\nargs = ["/old/mcp.js"]\n\n[other]\nk = 1\n`;
  const r = planCodex(src, MCP, CHAIN);
  assert.ok(r.after.includes(`notify = ["${CHAIN}", "prev"]`));
  assert.ok(r.after.includes('command = "/usr/local/bin/node"'));
  assert.ok(r.after.includes("[other]\nk = 1\n"));
  assert.ok(!r.after.includes("/old/"));
});

test("unplan codex: removes block and chain, keeps previous notify", () => {
  const installed = planCodex(CODEX, MCP, CHAIN).after;
  const r = unplanCodex(installed, CHAIN);
  assert.ok(r.changed);
  assert.ok(!r.after.includes("mcp_servers.perch"));
  assert.ok(r.after.includes('notify = ["/Users/u/.codex/cu/Client", "turn-ended"]'));
  assert.ok(r.after.includes("[mcp_servers.node_repl.env]"));
  assert.equal(unplanCodex(r.after, CHAIN).changed, false);
  assert.equal(unplanCodex(planCodex("", MCP, CHAIN).after, CHAIN).after.trim(), "");
});

// ---- Codex Computer Use wrapper
const SKY = "/H/.codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient";
const esc = (s: string): string => s.replace(/\//g, "\\/");
const innerTok = (a: string[]): string => JSON.stringify(esc(JSON.stringify(a))).slice(1, -1).replace(/\\\\\//g, "\\\\/");
const wrapLine = (inner: string[]): string => `notify = ["${SKY}", "turn-ended", "--previous-notify", "${innerTok(inner)}"]`;
const innerOf = (toml: string): string[] => {
  const m = /--previous-notify", "(.*)"\]/.exec(toml)!;
  return JSON.parse(JSON.parse(`"${m[1]}"`)) as string[];
};

test("codex wrapper: real Sky-wrapped line is rewritten inside, outer untouched, Sky not repeated", () => {
  const src = `model = "x"\n${wrapLine(["/Users/u/old/agent-avatar/adapters/codex/notify-chain.sh", SKY, "turn-ended"])}\n\n[features]\na = 1\n`;
  assert.ok(src.includes("\\\\/Users\\\\/u"));
  const r = planCodex(src, MCP, CHAIN);
  assert.ok(r.changed);
  assert.deepEqual(innerOf(r.after), [CHAIN]);
  assert.ok(r.after.startsWith(`model = "x"\nnotify = ["${SKY}", "turn-ended", "--previous-notify", "[`));
  assert.ok(r.after.includes("[\\\"\\\\/opt\\\\/perch") || r.after.includes("\\\\/"));
  assert.equal(r.after.split("SkyComputerUseClient\"").length, 2);
  assert.equal(planCodex(r.after, MCP, CHAIN).changed, false);
  const u = unplanCodex(r.after, CHAIN);
  assert.ok(u.after.includes(`notify = ["${SKY}", "turn-ended"]`));
  assert.ok(!u.after.includes("previous-notify"));
  assert.equal(unplanCodex(u.after, CHAIN).changed, false);
});

test("codex wrapper: user's own command in inner array is kept, chain first", () => {
  const r = planCodex(wrapLine(["/bin/mine", "arg"]) + "\n", MCP, CHAIN);
  assert.deepEqual(innerOf(r.after), [CHAIN, "/bin/mine", "arg"]);
  assert.equal(planCodex(r.after, MCP, CHAIN).changed, false);
  const u = unplanCodex(r.after, CHAIN);
  assert.deepEqual(innerOf(u.after), ["/bin/mine", "arg"]);
});

test("codex wrapper: user command plus old chain and Sky re-invocation", () => {
  const r = planCodex(wrapLine(["/old/notify-chain.sh", "/bin/mine", SKY, "turn-ended"]) + "\n", MCP, CHAIN);
  assert.deepEqual(innerOf(r.after), [CHAIN, "/bin/mine"]);
});

test("codex: unwrapped line keeps existing behavior; no notify line inserts", () => {
  const r = planCodex('notify = ["/bin/mine"]\n', MCP, CHAIN);
  assert.ok(r.after.startsWith(`notify = ["${CHAIN}", "/bin/mine"]`));
  assert.ok(planCodex("", MCP, CHAIN).after.startsWith(`notify = ["${CHAIN}"]`));
});
