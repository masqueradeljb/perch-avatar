import { test } from "node:test";
import assert from "node:assert/strict";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import fs from "node:fs";
import { send } from "../src/client.js";

function fakeServer(reply: string): Promise<{ path: string; got: Promise<string>; close: () => void }> {
  const sock = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "av-")), "s.sock");
  let resolveGot!: (s: string) => void;
  const got = new Promise<string>((r) => (resolveGot = r));
  const server = net.createServer((c) => {
    c.on("data", (d) => { resolveGot(d.toString()); c.write(reply + "\n"); });
  });
  return new Promise((r) => server.listen(sock, () => r({ path: sock, got, close: () => server.close() })));
}

test("sends one JSON line with the caller pid and parses the reply", async () => {
  const s = await fakeServer('{"ok":true}');
  const res = await send({ type: "state", state: "working" }, { socketPath: s.path });
  const line = JSON.parse((await s.got).trim());
  assert.equal(line.type, "state");
  assert.equal(line.pid, process.pid);
  assert.deepEqual(res, { ok: true });
  s.close();
});

test("resolves null when the app is not running", async () => {
  const res = await send({ type: "targets" }, { socketPath: "/tmp/definitely-not-here.sock", timeoutMs: 200 });
  assert.equal(res, null);
});

import { perchPluginActiveFrom } from "../src/clients.js";
test("perchPluginActiveFrom", () => {
  const inst = (id: string) => ({ version: 2, plugins: { [id]: [{ scope: "user" }] } });
  assert.equal(perchPluginActiveFrom(inst("perch@perch-avatar"), {}), true);
  assert.equal(perchPluginActiveFrom(inst("perch@other-alias"), { enabledPlugins: { "perch@other-alias": true } }), true);
  assert.equal(perchPluginActiveFrom(inst("perch@perch-avatar"), { enabledPlugins: { "perch@perch-avatar": false } }), false);
  assert.equal(perchPluginActiveFrom(inst("perchy@x"), {}), false);
  assert.equal(perchPluginActiveFrom(null, null), false);
  assert.equal(perchPluginActiveFrom({ plugins: [] }, {}), false);
});
