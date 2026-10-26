// Ships the Codex notify chain inside the npm package (single source: ../adapters/codex/notify-chain.sh).
import fs from "node:fs";
fs.mkdirSync("assets", { recursive: true });
fs.copyFileSync("../adapters/codex/notify-chain.sh", "assets/notify-chain.sh");
fs.chmodSync("assets/notify-chain.sh", 0o755);
