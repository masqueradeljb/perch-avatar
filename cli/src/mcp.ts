#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { send } from "./client.js";

const INSTRUCTIONS = `A desktop mascot (a black cat with a long tail) visualizes what you are doing.
- Call avatar_state with "thinking" or "working" when you start a task, "done" or "error" when you finish, "waiting_user" when you need the user.
- When you start working in another app's window (a browser, an editor), pass its app name as \`window\` so the mascot moves there; pass "home" when you come back.
- While working, report \`activity\` (typing, reading, searching, browsing, running) whenever it changes.
- Use avatar_show sparingly for moments worth seeing: point at a screen rect you are talking about (pose "point"); to point at something on screen use \`at: {text, window?}\` (visible text) rather than a rect, or say a very short line.
- These calls are cheap and never fail your task; if the mascot app is not running they are ignored.`;

const ok = (r: unknown) => ({ content: [{ type: "text" as const, text: r ? "ok" : "avatar app not running (ignored)" }] });

const server = new McpServer({ name: "perch", version: "0.1.0" }, { instructions: INSTRUCTIONS });

server.registerTool("avatar_state", {
  description: "Report what you are doing so the mascot reacts. Cheap; call at task start/end and when blocked on the user.",
  inputSchema: {
    state: z.enum(["thinking", "working", "done", "error", "waiting_user", "idle"]),
    note: z.string().max(80).optional(),
    activity: z.enum(["typing", "reading", "searching", "browsing", "running"]).optional().describe("What kind of work, when state is working"),
    window: z.string().optional().describe('App you are now working in (e.g. "Google Chrome"), or "home"'),
  },
}, async ({ state, note, window, activity }) => ok(await send({ type: "state", state, note, window, activity })));

server.registerTool("avatar_show", {
  description: "A visible moment: pose, face, speech bubble, effect, or point at a screen rect (CG points, top-left origin).",
  inputSchema: {
    pose: z.enum(["lie_edge", "sit_corner", "peek_side", "stand", "point", "think", "work", "celebrate", "shock", "sleep", "wave", "lie_low"]).optional(),
    face: z.enum(["happy", "shock", "sad", "blink"]).optional(),
    say: z.string().max(60).optional(),
    fx: z.enum(["exclaim", "question", "sparkle", "zzz", "sweat", "speedlines"]).optional(),
    at: z.union([
      z.object({ window: z.string(), edge: z.enum(["top", "left", "right", "corner_l", "corner_r"]).optional(), pos: z.number().min(0).max(1).optional() }),
      z.object({ text: z.string(), window: z.string().optional() }).describe("point at visible text in a window — preferred over rect"),
      z.object({ rect: z.tuple([z.number(), z.number(), z.number(), z.number()]) }),
    ]).optional(),
    hold_s: z.number().min(0.5).max(30).optional(),
  },
}, async (args) => ok(await send({ type: "show", ...args })));

server.registerTool("avatar_targets", {
  description: "List on-screen windows (app, rect, focused) so you can aim avatar_show.",
  inputSchema: {},
}, async () => {
  const r = await send({ type: "targets" });
  return { content: [{ type: "text" as const, text: r ? JSON.stringify(r.windows ?? []) : "avatar app not running" }] };
});

await server.connect(new StdioServerTransport());
