import { test } from "node:test";
import assert from "node:assert/strict";
import { fromHook, toolActivity } from "../src/hook.js";

const pre = (tool_name: string) => fromHook({ hook_event_name: "PreToolUse", tool_name });

test("activity table", () => {
  for (const t of ["Edit", "Write", "MultiEdit", "NotebookEdit"]) assert.deepEqual(pre(t), { type: "state", state: "working", activity: "typing" });
  assert.deepEqual(pre("Read"), { type: "state", state: "working", activity: "reading" });
  for (const t of ["Grep", "Glob", "WebSearch", "ToolSearch"]) assert.deepEqual(pre(t), { type: "state", state: "working", activity: "searching" });
  for (const t of ["WebFetch", "mcp__claude-in-chrome__navigate", "mcp__foo__browser_click"]) {
    assert.deepEqual(pre(t), { type: "state", state: "working", activity: "browsing", window: "Google Chrome" });
  }
  assert.deepEqual(pre("Bash"), { type: "state", state: "working", activity: "running" });
});

test("unknown tool -> plain working", () => {
  assert.deepEqual(pre("Frobnicate"), { type: "state", state: "working" });
  assert.deepEqual(toolActivity(""), {});
});

test("lifecycle events", () => {
  assert.deepEqual(fromHook({ hook_event_name: "Stop" }), { type: "state", state: "done" });
  assert.deepEqual(fromHook({ hook_event_name: "UserPromptSubmit" }), { type: "state", state: "thinking" });
  assert.deepEqual(fromHook({ hook_event_name: "Notification" }), { type: "state", state: "waiting_user" });
  assert.deepEqual(fromHook({ hook_event_name: "SessionEnd" }), { type: "state", state: "idle", window: "home" });
});

test("unknown event -> null", () => {
  assert.equal(fromHook({ hook_event_name: "Whatever" }), null);
  assert.equal(fromHook({}), null);
});
