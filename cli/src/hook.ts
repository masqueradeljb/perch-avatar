export type HookInput = { hook_event_name?: string; tool_name?: string };
export type StateRequest = { type: "state"; state: string; activity?: string; window?: string };

const BROWSER = /^(WebFetch$|mcp__claude-in-chrome__|mcp__.*browser)/i;

/** Maps a Claude Code hook payload to a mascot state message (null = ignore). */
export function fromHook(h: HookInput): StateRequest | null {
  switch (h.hook_event_name) {
    case "UserPromptSubmit": return { type: "state", state: "thinking" };
    case "Notification": return { type: "state", state: "waiting_user" };
    case "Stop": return { type: "state", state: "done" };
    case "SessionEnd": return { type: "state", state: "idle", window: "home" };
    case "PreToolUse": return { type: "state", state: "working", ...toolActivity(h.tool_name ?? "") };
    default: return null;
  }
}

export function toolActivity(tool: string): { activity?: string; window?: string } {
  if (BROWSER.test(tool)) return { activity: "browsing", window: "Google Chrome" };
  if (/^(Edit|Write|MultiEdit|NotebookEdit)$/.test(tool)) return { activity: "typing" };
  if (tool === "Read") return { activity: "reading" };
  if (/^(Grep|Glob|WebSearch|ToolSearch)$/.test(tool)) return { activity: "searching" };
  if (tool === "Bash") return { activity: "running" };
  return {};
}
