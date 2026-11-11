import { spawn, spawnSync } from "node:child_process";
import { join } from "node:path";

const profileId = /^[A-Za-z0-9._-]+$/.test(process.argv[2] ?? "") ? process.argv[2] : "";
const env = { ...process.env };
if (profileId && env.LOCALAPPDATA) {
  env.CODEX_HOME = join(env.LOCALAPPDATA, "Nauagency", "Multi Agent Herdr", "agent-environments", profileId, ".codex");
}

const child = spawn("codex", ["app-server"], { env, stdio: ["pipe", "pipe", "ignore"], windowsHide: true });
let buffer = "";
let done = false;
let initialized = false;
let models = [];
let nextId = 2;
const pending = new Map([[1, "initialize"]]);

function stop(code = 0) {
  if (done) return;
  done = true;
  clearTimeout(timer);
  if (process.platform === "win32" && child.pid) spawnSync("taskkill", ["/pid", String(child.pid), "/t", "/f"], { stdio: "ignore", windowsHide: true });
  else child.kill("SIGKILL");
  if (code) process.exitCode = code;
}

function send(method, params, kind) {
  const id = nextId++;
  pending.set(id, kind);
  child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
}

function finish() {
  const seen = new Set();
  const rows = models.filter(row => row && row.hidden !== true && typeof row.id === "string" && !seen.has(row.id) && seen.add(row.id))
    .map(row => ({ id: row.id, label: typeof row.displayName === "string" && row.displayName.trim() ? row.displayName : row.id, isDefault: row.isDefault === true }));
  process.stdout.write(JSON.stringify(rows));
  stop(rows.length ? 0 : 1);
}

const timer = setTimeout(() => stop(1), 10000);
child.on("error", () => stop(1));
child.stdout.setEncoding("utf8");
child.stdout.on("data", chunk => {
  buffer += chunk;
  let newline;
  while ((newline = buffer.indexOf("\n")) !== -1) {
    const line = buffer.slice(0, newline);
    buffer = buffer.slice(newline + 1);
    if (!line.trim()) continue;
    let message;
    try { message = JSON.parse(line); } catch { continue; }
    const kind = pending.get(message.id);
    if (!kind) continue;
    pending.delete(message.id);
    if (message.error) { stop(1); return; }
    if (kind === "initialize") {
      initialized = true;
      child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method: "initialized", params: {} })}\n`);
      send("model/list", { cursor: null, limit: 100 }, "models");
      continue;
    }
    if (kind === "models") {
      if (Array.isArray(message.result?.data)) models.push(...message.result.data);
      const cursor = message.result?.nextCursor;
      if (typeof cursor === "string" && cursor) send("model/list", { cursor, limit: 100 }, "models");
      else finish();
    }
  }
});
pending.set(1, "initialize");
child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize", params: { clientInfo: { name: "multi-agent-herdr", version: "1" } } })}\n`);
