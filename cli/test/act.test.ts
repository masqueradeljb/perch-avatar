import { test } from "node:test";
import assert from "node:assert/strict";
import { parseAct } from "../src/act.js";

test("perch act parsing", () => {
  assert.deepEqual(parseAct(["click", "800", "400"]), { type: "act", action: "click", source: "cli", x: 800, y: 400 });
  assert.deepEqual(parseAct(["scroll", "1", "2", "--dir", "up"]), { type: "act", action: "scroll", source: "cli", x: 1, y: 2, dir: "up" });
  assert.deepEqual(parseAct(["type"]), { type: "act", action: "type", source: "cli" });
  for (const bad of [[], ["wiggle"], ["click", "1"], ["click", "a", "b"], ["scroll", "1", "2", "--dir", "left"]]) {
    assert.equal(parseAct(bad), null);
  }
});
