import { test } from "node:test";
import assert from "node:assert/strict";
import { unifiedDiff } from "../src/diff.js";

test("no change -> empty", () => assert.equal(unifiedDiff("a\nb\n", "a\nb\n", "f"), ""));
test("simple replacement with context", () => {
  const d = unifiedDiff("1\n2\n3\n4\n5\n6\n7\n8\n9\n", "1\n2\n3\n4\nX\n6\n7\n8\n9\n", "f");
  assert.match(d, /^--- f\n\+\+\+ f\n@@ /);
  assert.ok(d.includes("-5\n+X\n"));
  assert.ok(d.includes(" 2\n") && !d.includes(" 1\n"));
});
test("addition from empty", () => assert.ok(unifiedDiff("", "a\n", "f").includes("+a\n")));

import { redactLine } from "../src/diff.js";
test("redact: JSON secret key keeps key, masks value", () => assert.equal(redactLine('      "apiKey": "abc123",'), '      "apiKey": "•••",'));
test("redact: TOML secret key", () => assert.equal(redactLine('bearer_token_env = "x"\nauth_token = "s3cr3t"'.split("\n")[1]), 'auth_token = "•••"'));
test("redact: Authorization Bearer inside a JSON string", () => {
  const r = redactLine('"args": ["--header", "Authorization: Bearer abc.DEF-123"]');
  assert.ok(!r.includes("abc.DEF") && r.includes("Bearer •••"));
});
test("redact: value prefixes", () => {
  assert.equal(redactLine('"x": "sk-live-1"'), '"x": "•••"');
  assert.equal(redactLine('v = "ghp_abc"'), 'v = "•••"');
});
test("redact: non-secret line unchanged", () => {
  for (const l of ['  "command": "/usr/bin/node",', 'model = "gpt"', '"args": ["a", "b"]', '  "mcpServers": {']) assert.equal(redactLine(l), l);
});
test("diff output redacts context, added and removed lines", () => {
  const b = '{\n"a": 1,\n"token": "T0P",\n"b": 2,\n"c": 3\n}\n';
  const d = unifiedDiff(b, b.replace('"b": 2', '"password": "PW1"'), "f");
  assert.ok(!/T0P|PW1/.test(d) && d.includes(' "token": "•••"'));
  const d2 = unifiedDiff(b.replace("T0P", "OLD"), b, "f");
  assert.ok(!/OLD|T0P/.test(d2) && d2.includes('-"token": "•••"') && d2.includes('+"token": "•••"'));
});
