import net from "node:net";
import os from "node:os";
import path from "node:path";

export const DEFAULT_SOCKET = process.env.PERCH_SOCK ?? path.join(os.homedir(), ".perch", "perch.sock");

export type Reply = { ok: boolean; error?: string; windows?: { app: string; rect: number[]; focused: boolean }[] };

/**
 * Sends one request line (with this process's pid, so the app can find the agent's window)
 * and resolves the reply — or null if the avatar app isn't running. Never throws: an agent
 * must not fail because its mascot is missing.
 */
export function send(request: Record<string, unknown>, opts: { socketPath?: string; timeoutMs?: number } = {}): Promise<Reply | null> {
  const { socketPath = DEFAULT_SOCKET, timeoutMs = 1000 } = opts;
  return new Promise((resolve) => {
    let buf = "";
    let done = false;
    const finish = (r: Reply | null) => {
      if (done) return;
      done = true;
      sock.destroy();
      resolve(r);
    };
    const sock = net.createConnection(socketPath, () => {
      sock.write(JSON.stringify({ ...request, pid: process.pid }) + "\n");
    });
    sock.setTimeout(timeoutMs, () => finish(null));
    sock.on("error", () => finish(null));
    sock.on("data", (d) => {
      buf += d.toString();
      const nl = buf.indexOf("\n");
      if (nl >= 0) {
        try { finish(JSON.parse(buf.slice(0, nl))); } catch { finish(null); }
      }
    });
    sock.on("close", () => finish(null));
  });
}
