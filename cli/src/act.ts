const ACTIONS = ["click", "scroll", "type", "drag"];

/** `perch act <click|scroll|type|drag> [x y] [--dir up|down]` → an act request, or null on bad usage. */
export function parseAct(args: string[]): Record<string, unknown> | null {
  const [action, ...rest] = args;
  if (!action || !ACTIONS.includes(action)) return null;
  const at = rest.indexOf("--dir");
  const dir = at >= 0 ? rest[at + 1] : undefined;
  if (at >= 0 && dir !== "up" && dir !== "down") return null;
  const nums = rest.filter((_, i) => at < 0 || (i !== at && i !== at + 1)).map(Number);
  if ((nums.length !== 0 && nums.length !== 2) || nums.some((n) => !Number.isFinite(n))) return null;
  const req: Record<string, unknown> = { type: "act", action, source: "cli" };
  if (nums.length === 2) [req.x, req.y] = nums;
  if (dir) req.dir = dir;
  return req;
}
