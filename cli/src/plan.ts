/**
 * Pure config planners. Each takes the current file text and returns the text it should have.
 * Idempotent (second run => changed:false) and conservative: only Perch's own entries and the
 * prototype's old `agent-avatar` entries are touched.
 */
import path from "node:path";

export type Plan = { before: string; after: string; changed: boolean };
export type McpSpec = { command: string; args: string[] };

export const HOOK_EVENTS = ["UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SessionEnd"] as const;

/** Commands that belong to Perch or to its prototype ("agent-avatar"). */
const OURS = /agent-avatar|bin\/avatar\b|perch hook|cli\.js hook/;
export const isOurHookCommand = (c: unknown): boolean => typeof c === "string" && OURS.test(c);

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => typeof v === "object" && v !== null && !Array.isArray(v);

function parseJson(text: string): Obj {
  if (text.trim() === "") return {};
  const v: unknown = JSON.parse(text);
  if (!isObj(v)) throw new Error("expected a JSON object at the top level");
  return v;
}

function serialize(obj: Obj, before: string): string {
  const m = before.match(/\n([ \t]+)"/);
  const indent = m ? (m[1].startsWith("\t") ? "\t" : m[1].length) : 2;
  const nl = before === "" || before.endsWith("\n") ? "\n" : "";
  return JSON.stringify(obj, null, indent) + nl;
}

function finishJson(before: string, original: Obj, next: Obj): Plan {
  if (before.trim() !== "" && JSON.stringify(original) === JSON.stringify(next)) return { before, after: before, changed: false };
  return { before, after: serialize(next, before), changed: true };
}

const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v)) as T;

// ---------------------------------------------------------------- Claude Code hooks

export function planClaudeHooks(json: string, hookCmd: string): Plan {
  const original = parseJson(json);
  const o = clone(original);
  const hooks: Obj = isObj(o.hooks) ? o.hooks : {};
  for (const ev of HOOK_EVENTS) {
    const arr = Array.isArray(hooks[ev]) ? (hooks[ev] as Obj[]) : [];
    const out: Obj[] = [];
    let placed = false;
    for (const entry of arr) {
      const hs = isObj(entry) && Array.isArray(entry.hooks) ? (entry.hooks as Obj[]) : null;
      if (!hs || !hs.some((h) => isOurHookCommand(h.command))) { out.push(entry); continue; }
      const nh: Obj[] = [];
      for (const h of hs) {
        if (!isOurHookCommand(h.command)) nh.push(h);
        else if (!placed) { placed = true; nh.push(h.command === hookCmd ? h : { type: "command", command: hookCmd }); }
      }
      if (nh.length) out.push({ ...entry, hooks: nh });
    }
    if (!placed) out.push({ hooks: [{ type: "command", command: hookCmd }] });
    hooks[ev] = out;
  }
  o.hooks = hooks;
  return finishJson(json, original, o);
}

export function unplanClaudeHooks(json: string, _hookCmd?: string): Plan {
  const original = parseJson(json);
  const o = clone(original);
  if (!isObj(o.hooks)) return { before: json, after: json, changed: false };
  const hooks = o.hooks;
  for (const ev of Object.keys(hooks)) {
    if (!Array.isArray(hooks[ev])) continue;
    const out: Obj[] = [];
    for (const entry of hooks[ev] as Obj[]) {
      if (!isObj(entry) || !Array.isArray(entry.hooks)) { out.push(entry); continue; }
      const nh = (entry.hooks as Obj[]).filter((h) => !isOurHookCommand(h.command));
      if (nh.length === (entry.hooks as Obj[]).length) out.push(entry);
      else if (nh.length) out.push({ ...entry, hooks: nh });
    }
    if (out.length) hooks[ev] = out; else delete hooks[ev];
  }
  if (Object.keys(hooks).length === 0) delete o.hooks;
  return finishJson(json, original, o);
}

// ---------------------------------------------------------------- MCP servers in JSON files

function setServer(o: Obj, name: string, value: Obj, legacy: string): void {
  const servers: Obj = isObj(o.mcpServers) ? o.mcpServers : {};
  const next: Obj = {};
  let placed = false;
  for (const [k, v] of Object.entries(servers)) {
    if (k === name) { next[name] = value; placed = true; }
    else if (k === legacy) { if (!placed) { next[name] = value; placed = true; } }
    else next[k] = v;
  }
  if (!placed) next[name] = value;
  o.mcpServers = next;
}

function removeServers(o: Obj, names: string[]): void {
  if (!isObj(o.mcpServers)) return;
  for (const n of names) delete o.mcpServers[n];
  if (Object.keys(o.mcpServers).length === 0) delete o.mcpServers;
}

function planServer(json: string, value: Obj): Plan {
  const original = parseJson(json);
  const o = clone(original);
  const existing = isObj(o.mcpServers) ? o.mcpServers.perch : undefined;
  setServer(o, "perch", JSON.stringify(existing) === JSON.stringify(value) ? (existing as Obj) : value, "agent-avatar");
  return finishJson(json, original, o);
}

function unplanServer(json: string): Plan {
  const original = parseJson(json);
  const o = clone(original);
  removeServers(o, ["perch", "agent-avatar"]);
  return finishJson(json, original, o);
}

export const planClaudeDesktop = (json: string, mcp: McpSpec): Plan => planServer(json, { command: mcp.command, args: mcp.args });
export const unplanClaudeDesktop = (json: string): Plan => unplanServer(json);
/** ~/.claude.json (Claude Code user-scope MCP servers). */
export const planClaudeJson = (json: string, mcp: McpSpec): Plan => planServer(json, { type: "stdio", command: mcp.command, args: mcp.args, env: {} });
export const unplanClaudeJson = (json: string): Plan => unplanServer(json);

// ---------------------------------------------------------------- Codex TOML (text level)

const tomlStr = (s: string): string => `"${s.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
const HEADER = /^\s*\[\[?\s*([^\]]+?)\s*\]\]?\s*(#.*)?$/;

type Section = { name: string; start: number; end: number }; // end exclusive (includes trailing blanks)

function sections(lines: string[]): Section[] {
  const out: Section[] = [];
  lines.forEach((l, i) => {
    const m = HEADER.exec(l);
    if (!m) return;
    if (out.length) out[out.length - 1].end = i;
    out.push({ name: m[1].replace(/"/g, "").replace(/\s+/g, ""), start: i, end: lines.length });
  });
  return out;
}

const contentEnd = (lines: string[], s: Section): number => {
  let e = s.end;
  while (e > s.start + 1 && lines[e - 1].trim() === "") e--;
  return e;
};

function splitText(text: string): { lines: string[]; nl: boolean } {
  const lines = text.split("\n");
  if (lines[lines.length - 1] === "") lines.pop();
  return { lines, nl: text === "" || text.endsWith("\n") };
}
const joinText = (lines: string[], nl: boolean): string => (lines.length === 0 ? "" : lines.join("\n") + (nl ? "\n" : ""));

function removeSections(lines: string[], pred: (name: string) => boolean): string[] {
  let cur = lines;
  for (;;) {
    const s = sections(cur).find((x) => pred(x.name));
    if (!s) return cur;
    const next = [...cur.slice(0, s.start), ...cur.slice(s.end)];
    if (s.end >= cur.length) while (next.length && next[next.length - 1].trim() === "") next.pop();
    cur = next;
  }
}

const isServer = (n: string, key: string): boolean => n === `mcp_servers.${key}` || n.startsWith(`mcp_servers.${key}.`);

type NotifyArr = { start: number; end: number; tokens: string[]; values: string[]; rest: string };

/** Parses a top-level (pre-first-table) `notify = [ ... ]` of TOML strings. null = none or not understood. */
function findNotify(lines: string[]): NotifyArr | null {
  const first = sections(lines)[0]?.start ?? lines.length;
  for (let i = 0; i < first; i++) {
    const m = /^(\s*notify\s*=\s*)\[/.exec(lines[i]);
    if (!m) continue;
    const text = lines.slice(i, first).join("\n");
    let p = m[0].length;
    const tokens: string[] = [], values: string[] = [];
    for (;;) {
      while (p < text.length && /[\s,]/.test(text[p])) p++;
      if (text[p] === "#") { while (p < text.length && text[p] !== "\n") p++; continue; }
      if (p >= text.length) return null;
      if (text[p] === "]") { p++; break; }
      const q = text[p];
      if (q !== '"' && q !== "'") return null;
      const s = p++;
      let v = "";
      while (p < text.length && text[p] !== q) {
        if (q === '"' && text[p] === "\\") {
          const c = text[p + 1];
          if (c === "u") { v += String.fromCharCode(parseInt(text.slice(p + 2, p + 6), 16)); p += 6; continue; }
          v += c === "n" ? "\n" : c === "t" ? "\t" : c;
          p += 2; continue;
        }
        v += text[p++];
      }
      if (p >= text.length) return null;
      p++;
      tokens.push(text.slice(s, p)); values.push(v);
    }
    const consumed = text.slice(0, p);
    return { start: i, end: i + consumed.split("\n").length - 1, tokens, values, rest: text.slice(p).split("\n")[0] };
  }
  return null;
}

const notifyLine = (lines: string[], n: NotifyArr, tokens: string[]): string[] => {
  const prefix = /^(\s*notify\s*=\s*)/.exec(lines[n.start])![1];
  return [...lines.slice(0, n.start), `${prefix}[${tokens.join(", ")}]${n.rest}`, ...lines.slice(n.end + 1)];
};

const isChain = (v: string, chain: string): boolean => v === chain || path.basename(v) === "notify-chain.sh";

/** Codex Computer Use rewrites notify to `[client, args..., "--previous-notify", "<JSON array>"]`. */
type Wrapper = { idx: number; outer: string[]; inner: string[] };
function findWrapper(n: NotifyArr): Wrapper | null {
  const k = n.values.indexOf("--previous-notify");
  if (k < 1 || k + 1 >= n.values.length) return null;
  try {
    const v: unknown = JSON.parse(n.values[k + 1]);
    if (!Array.isArray(v) || !v.every((x) => typeof x === "string")) return null;
    return { idx: k, outer: n.values.slice(0, k), inner: v as string[] };
  } catch { return null; }
}
/** JSON with escaped slashes (as Codex writes it), then as a TOML basic string. */
const encodeInner = (a: string[]): string => tomlStr(JSON.stringify(a).replace(/\//g, "\\/"));
const sameArr = (a: string[], b: string[]): boolean => a.length === b.length && a.every((x, i) => x === b[i]);

function planWrapped(lines: string[], n: NotifyArr, w: Wrapper, chain: string): string[] {
  let inner = w.inner.filter((x) => !isChain(x, chain));
  // drop the trailing re-invocation of the wrapping program that our old chain forwarded to
  if (inner.length >= w.outer.length && sameArr(inner.slice(inner.length - w.outer.length), w.outer)) inner = inner.slice(0, inner.length - w.outer.length);
  const desired = [chain, ...inner];
  const tokens = [...n.tokens];
  if (!sameArr(desired, w.inner)) tokens[w.idx + 1] = encodeInner(desired);
  const out = n.values[0] !== undefined && isChain(n.values[0], chain) ? tokens.slice(1) : tokens;
  return out.length === tokens.length && out.every((t, i) => t === n.tokens[i]) ? lines : notifyLine(lines, n, out);
}

export function planCodex(toml: string, mcp: McpSpec, notifyChain: string): Plan {
  let { lines, nl } = splitText(toml);
  // 1. [mcp_servers.perch]
  const desired = ["[mcp_servers.perch]", `command = ${tomlStr(mcp.command)}`, `args = [${mcp.args.map(tomlStr).join(", ")}]`];
  const all = sections(lines);
  const perch = all.find((s) => s.name === "mcp_servers.perch");
  const legacy = all.find((s) => s.name === "mcp_servers.agent-avatar");
  const target = perch ?? legacy;
  if (target) {
    const ce = contentEnd(lines, target);
    if (lines.slice(target.start, ce).join("\n") !== desired.join("\n")) lines = [...lines.slice(0, target.start), ...desired, ...lines.slice(ce)];
  } else {
    if (lines.length && lines[lines.length - 1].trim() !== "") lines.push("");
    lines.push(...desired);
  }
  lines = removeSections(lines, (n) => isServer(n, "agent-avatar"));
  // 2. notify chain
  const n = findNotify(lines);
  const wrap = n ? findWrapper(n) : null;
  if (n && wrap) {
    lines = planWrapped(lines, n, wrap, notifyChain);
  } else if (n) {
    if (!(n.values.length && n.values[0] === notifyChain)) {
      const rest = n.values.length && isChain(n.values[0], notifyChain) ? n.tokens.slice(1) : n.tokens;
      lines = notifyLine(lines, n, [tomlStr(notifyChain), ...rest]);
    }
  } else if (!hasNotifyKey(lines)) {
    const p = sections(lines)[0]?.start ?? lines.length;
    let q = p;
    while (q > 0 && lines[q - 1].trim() === "") q--;
    const ins = [`notify = [${tomlStr(notifyChain)}]`];
    if (q < lines.length && lines[q].trim() !== "") ins.push("");
    lines = [...lines.slice(0, q), ...ins, ...lines.slice(q)];
  }
  const after = joinText(lines, nl || toml === "");
  return after === toml ? { before: toml, after: toml, changed: false } : { before: toml, after, changed: true };
}

/** True if a top-level notify key exists that we could not parse (then we leave it alone). */
const hasNotifyKey = (lines: string[]): boolean => {
  const first = sections(lines)[0]?.start ?? lines.length;
  return lines.slice(0, first).some((l) => /^\s*notify\s*=/.test(l));
};

export function unplanCodex(toml: string, notifyChain: string): Plan {
  let { lines, nl } = splitText(toml);
  lines = removeSections(lines, (n) => isServer(n, "perch") || isServer(n, "agent-avatar"));
  const n = findNotify(lines);
  const wrap = n ? findWrapper(n) : null;
  if (n && wrap) {
    const tokens = [...n.tokens];
    const inner = wrap.inner.filter((x) => !isChain(x, notifyChain));
    if (inner.length !== wrap.inner.length) {
      if (inner.length) tokens[wrap.idx + 1] = encodeInner(inner);
      else tokens.splice(wrap.idx, 2);
    }
    const out = n.values[0] !== undefined && isChain(n.values[0], notifyChain) ? tokens.slice(1) : tokens;
    if (out.length !== n.tokens.length || out.some((t, i) => t !== n.tokens[i])) lines = notifyLine(lines, n, out);
  } else if (n && n.values.length && isChain(n.values[0], notifyChain)) {
    if (n.tokens.length > 1) lines = notifyLine(lines, n, n.tokens.slice(1));
    else {
      lines = [...lines.slice(0, n.start), ...lines.slice(n.end + 1)];
      if (n.start > 0 && n.start < lines.length && lines[n.start - 1].trim() === "" && lines[n.start].trim() === "") lines.splice(n.start, 1);
      while (lines.length && lines[0].trim() === "") lines.shift();
    }
  }
  const after = joinText(lines, nl);
  return after === toml ? { before: toml, after: toml, changed: false } : { before: toml, after, changed: true };
}
