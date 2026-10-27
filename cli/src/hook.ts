export type HookInput = { hook_event_name?: string; tool_name?: string; tool_input?: Record<string, unknown> };
export type StateRequest = { type: "state"; state: string; activity?: string; window?: string };
export type Request = Record<string, unknown>;

const BROWSER = /^(WebFetch$|mcp__claude-in-chrome__|mcp__.*browser)/i;

/** Maps a Claude Code hook payload to mascot messages, sent in order (empty = ignore). */
export function fromHook(h: HookInput): Request[] {
  switch (h.hook_event_name) {
    case "UserPromptSubmit": return [{ type: "state", state: "thinking" }];
    case "Notification": return [{ type: "state", state: "waiting_user" }];
    case "Stop": return [{ type: "state", state: "done" }];
    case "SessionEnd": return [{ type: "state", state: "idle", window: "home" }];
    case "PreToolUse": {
      const tool = h.tool_name ?? "";
      const state: StateRequest = { type: "state", state: "working", ...toolActivity(tool) };
      const act = chromeAct(tool, h.tool_input);
      return act ? [state, act] : [state];
    }
    default: return [];
  }
}

const CHROME_CLICKS = new Set(["left_click", "right_click", "double_click", "triple_click"]);

function point(v: unknown): { x: number; y: number } | null {
  if (!Array.isArray(v) || v.length < 2) return null;
  const [x, y] = v;
  return typeof x === "number" && typeof y === "number" && Number.isFinite(x) && Number.isFinite(y) ? { x, y } : null;
}

/**
 * Claude in Chrome drives the page over CDP, so no system input exists for the watcher to see; map its
 * tool_input to an act instead. Coordinates are page-viewport points (the app converts them to screen).
 */
export function chromeAct(tool: string, input: Record<string, unknown> | undefined): Request | null {
  if (!input) return null;
  const base = { type: "act", source: "hook", window: "Google Chrome" };
  if (tool === "mcp__claude-in-chrome__computer") {
    const action = input.action;
    const p = point(input.coordinate);
    if (typeof action !== "string") return null;
    if (CHROME_CLICKS.has(action)) return p ? { ...base, action: "click", ...p, space: "viewport" } : null;
    if (action === "left_click_drag") return p ? { ...base, action: "drag", ...p, space: "viewport" } : null;
    if (action === "scroll") {
      const dir = input.scroll_direction;
      if (!p || (dir !== "up" && dir !== "down")) return null;
      return { ...base, action: "scroll", ...p, space: "viewport", dir };
    }
    if (action === "type" || action === "key") return { ...base, action: "type" };
    return null;
  }
  if (tool === "mcp__claude-in-chrome__javascript_tool") {
    return typeof input.text === "string" && /scrollTo|scrollBy|scrollIntoView/.test(input.text)
      ? { ...base, action: "scroll" } : null;
  }
  return null;
}

export function toolActivity(tool: string): { activity?: string; window?: string } {
  if (BROWSER.test(tool)) return { activity: "browsing", window: "Google Chrome" };
  if (/^(Edit|Write|MultiEdit|NotebookEdit)$/.test(tool)) return { activity: "typing" };
  if (tool === "Read") return { activity: "reading" };
  if (/^(Grep|Glob|WebSearch|ToolSearch)$/.test(tool)) return { activity: "searching" };
  if (tool === "Bash") return { activity: "running" };
  return {};
}
