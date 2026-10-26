const MASK = "\u2022\u2022\u2022";
const SECRET_KEY = "token|secret|password|passwd|api[_-]?key|access[_-]?key|authorization|auth|cookie|session|bearer|credential|private[_-]?key";
// key (JSON "k": or TOML k =) whose name looks secret, followed by a scalar value
const KEY_VALUE = new RegExp(`(["']?)([\\w.-]*(?:${SECRET_KEY})[\\w.-]*)\\1(\\s*[:=]\\s*)(?!(?:Bearer|Basic)\\b)("(?:[^"\\\\]|\\\\.)*"|'[^']*'|[^\\s,{}\\[\\]]+)`, "gi");
const SECRET_STRING = /(["'])(?:Bearer |sk-|ghp_|xox)(?:(?!\1)[^\\]|\\.)*\1/g;
const EMBEDDED = /\b(Bearer|Basic)(\s+)[^\s"'\\,}\]]+/gi;

/** Display-only redaction of secret values in a single config line. Never use on text written to disk. */
export function redactLine(line: string): string {
  return line
    .replace(KEY_VALUE, (_m, q: string, k: string, sep: string) => `${q}${k}${q}${sep}${q === "'" ? "'" + MASK + "'" : '"' + MASK + '"'}`)
    .replace(SECRET_STRING, (_m, q: string) => `${q}${MASK}${q}`)
    .replace(EMBEDDED, (_m, scheme: string, sp: string) => `${scheme}${sp}${MASK}`);
}

/** Minimal unified diff (LCS on lines, 3 lines of context). Returns "" when equal. */
export function unifiedDiff(before: string, after: string, label: string, context = 3): string {
  if (before === after) return "";
  const a = before === "" ? [] : before.replace(/\n$/, "").split("\n");
  const b = after === "" ? [] : after.replace(/\n$/, "").split("\n");
  let pre = 0;
  while (pre < a.length && pre < b.length && a[pre] === b[pre]) pre++;
  let suf = 0;
  while (suf < a.length - pre && suf < b.length - pre && a[a.length - 1 - suf] === b[b.length - 1 - suf]) suf++;
  const am = a.slice(pre, a.length - suf);
  const bm = b.slice(pre, b.length - suf);
  // LCS table on the differing middle
  const n = am.length, m = bm.length;
  const t: number[][] = Array.from({ length: n + 1 }, () => new Array<number>(m + 1).fill(0));
  for (let i = n - 1; i >= 0; i--) for (let j = m - 1; j >= 0; j--) t[i][j] = am[i] === bm[j] ? t[i + 1][j + 1] + 1 : Math.max(t[i + 1][j], t[i][j + 1]);
  type Op = { k: " " | "-" | "+"; s: string };
  const ops: Op[] = [];
  for (let i = 0; i < pre; i++) ops.push({ k: " ", s: a[i] });
  let i = 0, j = 0;
  while (i < n || j < m) {
    if (i < n && j < m && am[i] === bm[j]) { ops.push({ k: " ", s: am[i] }); i++; j++; }
    else if (i < n && (j >= m || t[i + 1][j] >= t[i][j + 1])) ops.push({ k: "-", s: am[i++] });
    else ops.push({ k: "+", s: bm[j++] });
  }
  for (let k = a.length - suf; k < a.length; k++) ops.push({ k: " ", s: a[k] });

  // hunks
  const changed: number[] = [];
  ops.forEach((o, idx) => { if (o.k !== " ") changed.push(idx); });
  const out: string[] = [`--- ${label}`, `+++ ${label}`];
  let h = 0;
  while (h < changed.length) {
    let start = Math.max(0, changed[h] - context);
    let end = Math.min(ops.length, changed[h] + context + 1);
    let next = h + 1;
    while (next < changed.length && changed[next] - context <= end) { end = Math.min(ops.length, changed[next] + context + 1); next++; }
    const slice = ops.slice(start, end);
    const oldStart = ops.slice(0, start).filter((o) => o.k !== "+").length + 1;
    const newStart = ops.slice(0, start).filter((o) => o.k !== "-").length + 1;
    const oldLen = slice.filter((o) => o.k !== "+").length;
    const newLen = slice.filter((o) => o.k !== "-").length;
    out.push(`@@ -${oldLen ? oldStart : oldStart - 1},${oldLen} +${newLen ? newStart : newStart - 1},${newLen} @@`);
    for (const o of slice) out.push(o.k + redactLine(o.s));
    h = next;
  }
  return out.join("\n") + "\n";
}
