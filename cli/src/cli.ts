#!/usr/bin/env node
import { send } from "./client.js";
import { fromHook } from "./hook.js";
import { parseAct } from "./act.js";

const USAGE = `perch state <thinking|working|done|error|waiting_user|idle> [--note text] [--window app|home] [--activity typing|reading|searching|browsing|running]
perch hook   (reads a Claude Code hook JSON payload on stdin)
perch show [--pose p] [--face f] [--say text] [--fx f] [--hold s] [--window app] [--rect x,y,w,h]
perch act <click|scroll|type|drag> [x y] [--dir up|down]
perch targets
perch setup [--yes] [--only claude-code,claude-desktop,codex] [--dry-run]
perch doctor
perch uninstall [--restore] [--yes] [--dry-run]`;

function flags(argv: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith("--") && i + 1 < argv.length) out[argv[i].slice(2)] = argv[++i];
  }
  return out;
}

async function readStdin(): Promise<string> {
  if (process.stdin.isTTY) return "";
  let data = "";
  for await (const chunk of process.stdin) data += chunk;
  return data;
}

const [cmd, ...rest] = process.argv.slice(2);
if (cmd === "setup" || cmd === "doctor" || cmd === "uninstall") {
  const { main } = await import("./setup.js");
  process.exit(await main(cmd, rest));
}
const f = flags(rest);
let request: Record<string, unknown> | null = null;
if (cmd === "state" && rest[0]) {
  request = { type: "state", state: rest[0], note: f.note, window: f.window, activity: f.activity };
} else if (cmd === "hook") {
  try { request = fromHook(JSON.parse(await readStdin())); } catch { request = null; }
  if (!request) process.exit(0);
} else if (cmd === "show") {
  const at = f.rect ? { rect: f.rect.split(",").map(Number) } : f.window ? { window: f.window } : undefined;
  request = { type: "show", pose: f.pose, face: f.face, say: f.say, fx: f.fx, hold_s: f.hold ? Number(f.hold) : undefined, at };
} else if (cmd === "act") {
  request = parseAct(rest);
} else if (cmd === "targets") {
  request = { type: "targets" };
}
if (!request) {
  console.error(USAGE);
} else {
  const r = await send(request);
  if (cmd === "targets") console.log(JSON.stringify(r?.windows ?? [], null, 2));
}
process.exit(0); // hooks must never fail because of the mascot
