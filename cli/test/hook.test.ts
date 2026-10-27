import { test } from "node:test";
import assert from "node:assert/strict";
import { chromeAct, fromHook, toolActivity } from "../src/hook.js";

const pre = (tool_name: string) => fromHook({ hook_event_name: "PreToolUse", tool_name });
const CC = "mcp__claude-in-chrome__computer";
const act = (extra: Record<string, unknown>) => ({ type: "act", source: "hook", window: "Google Chrome", ...extra });

test("activity table", () => {
  for (const t of ["Edit", "Write", "MultiEdit", "NotebookEdit"]) assert.deepEqual(pre(t), [{ type: "state", state: "working", activity: "typing" }]);
  assert.deepEqual(pre("Read"), [{ type: "state", state: "working", activity: "reading" }]);
  for (const t of ["Grep", "Glob", "WebSearch", "ToolSearch"]) assert.deepEqual(pre(t), [{ type: "state", state: "working", activity: "searching" }]);
  for (const t of ["WebFetch", "mcp__claude-in-chrome__navigate", "mcp__foo__browser_click"]) {
    assert.deepEqual(pre(t), [{ type: "state", state: "working", activity: "browsing", window: "Google Chrome" }]);
  }
  assert.deepEqual(pre("Bash"), [{ type: "state", state: "working", activity: "running" }]);
});

test("unknown tool -> plain working", () => {
  assert.deepEqual(pre("Frobnicate"), [{ type: "state", state: "working" }]);
  assert.deepEqual(toolActivity(""), {});
});

test("lifecycle events", () => {
  assert.deepEqual(fromHook({ hook_event_name: "Stop" }), [{ type: "state", state: "done" }]);
  assert.deepEqual(fromHook({ hook_event_name: "UserPromptSubmit" }), [{ type: "state", state: "thinking" }]);
  assert.deepEqual(fromHook({ hook_event_name: "Notification" }), [{ type: "state", state: "waiting_user" }]);
  assert.deepEqual(fromHook({ hook_event_name: "SessionEnd" }), [{ type: "state", state: "idle", window: "home" }]);
});

test("unknown event -> empty", () => {
  assert.deepEqual(fromHook({ hook_event_name: "Whatever" }), []);
  assert.deepEqual(fromHook({}), []);
});

test("chromeAct: clicks with viewport coordinates", () => {
  for (const action of ["left_click", "right_click", "double_click", "triple_click"]) {
    assert.deepEqual(chromeAct(CC, { action, tabId: 1, coordinate: [274, 402] }),
      act({ action: "click", x: 274, y: 402, space: "viewport" }));
  }
  assert.equal(chromeAct(CC, { action: "left_click" }), null);
  assert.equal(chromeAct(CC, { action: "left_click", coordinate: ["a", 2] }), null);
});

test("chromeAct: drag uses the end coordinate", () => {
  assert.deepEqual(chromeAct(CC, { action: "left_click_drag", start_coordinate: [1, 2], coordinate: [30, 40] }),
    act({ action: "drag", x: 30, y: 40, space: "viewport" }));
});

test("chromeAct: scroll up/down; left/right ignored", () => {
  assert.deepEqual(chromeAct(CC, { action: "scroll", coordinate: [10, 20], scroll_direction: "down" }),
    act({ action: "scroll", x: 10, y: 20, space: "viewport", dir: "down" }));
  assert.deepEqual(chromeAct(CC, { action: "scroll", coordinate: [10, 20], scroll_direction: "up" }),
    act({ action: "scroll", x: 10, y: 20, space: "viewport", dir: "up" }));
  assert.equal(chromeAct(CC, { action: "scroll", coordinate: [10, 20], scroll_direction: "left" }), null);
  assert.equal(chromeAct(CC, { action: "scroll", coordinate: [10, 20], scroll_direction: "right" }), null);
});

test("chromeAct: type/key have no coordinates", () => {
  assert.deepEqual(chromeAct(CC, { action: "type", text: "hi" }), act({ action: "type" }));
  assert.deepEqual(chromeAct(CC, { action: "key", text: "Enter" }), act({ action: "type" }));
});

test("chromeAct: non-input actions and other tools -> null", () => {
  for (const action of ["screenshot", "hover", "wait", "zoom", "scroll_to"]) assert.equal(chromeAct(CC, { action, tabId: 1 }), null);
  assert.equal(chromeAct(CC, undefined), null);
  assert.equal(chromeAct("Read", { action: "left_click", coordinate: [1, 2] }), null);
  assert.equal(chromeAct("mcp__claude-in-chrome__navigate", { url: "https://x" }), null);
});

test("chromeAct: javascript scrolling -> scroll act", () => {
  const js = "mcp__claude-in-chrome__javascript_tool";
  assert.deepEqual(chromeAct(js, { action: "javascript_exec", tabId: 1, text: "window.scrollTo(0, 820);" }), act({ action: "scroll" }));
  assert.deepEqual(chromeAct(js, { text: "window.scrollBy(0, 100)" }), act({ action: "scroll" }));
  assert.deepEqual(chromeAct(js, { text: "el.scrollIntoView()" }), act({ action: "scroll" }));
  assert.equal(chromeAct(js, { action: "javascript_exec", text: "document.title" }), null);
});

test("PreToolUse with a Claude in Chrome click -> [state, act]", () => {
  assert.deepEqual(fromHook({ hook_event_name: "PreToolUse", tool_name: CC,
    tool_input: { action: "left_click", tabId: 197392681, coordinate: [274, 402] } }), [
    { type: "state", state: "working", activity: "browsing", window: "Google Chrome" },
    act({ action: "click", x: 274, y: 402, space: "viewport" }),
  ]);
  assert.deepEqual(fromHook({ hook_event_name: "PreToolUse", tool_name: CC, tool_input: { action: "screenshot", scale: 0.6 } }),
    [{ type: "state", state: "working", activity: "browsing", window: "Google Chrome" }]);
});
