/**
 * dsh-desktop backends: layered Linux desktop control on Hyprland.
 *
 * Three layers, chosen per action by `backend: auto|native|cul`:
 *
 *   1. native  — zero-daemon path: hyprctl (windows/focus/move/resize),
 *                grim (screenshot), wtype (type/press_key). Processes are
 *                short-lived and tiny; nothing stays resident.
 *   2. cul     — computer-use-linux MCP bridge (click/drag/scroll by pixels
 *                or semantic selectors, app state, set_value, perform_action).
 *                Spawned per call and killed after (no resident process).
 *   3. atspi   — accessibility tree via CUL list_apps/get_app_state. Needs
 *                org.a11y.Bus; doctor reports readiness, actions fail with
 *                a precise message instead of hanging.
 *
 * "auto" (default) uses native where the capability exists and falls back
 * to cul only for actions native cannot do (click/drag/scroll/state).
 */

import { execFile } from "node:child_process";

const run = (bin, args, opts = {}) =>
  new Promise((resolve, reject) => {
    execFile(bin, args, { timeout: 10000, maxBuffer: 16 * 1024 * 1024, ...opts }, (err, stdout) =>
      err ? reject(new Error(String(err.message || err).slice(0, 300))) : resolve(String(stdout || "").trim()),
    );
  });

const which = (bin) => ["/run/current-system/sw/bin/" + bin, "/usr/bin/" + bin, bin];

/* ── 1. native layer ─────────────────────────────────────────────────── */

export const nativeDoctor = async () => {
  const probe = async (bin, args) => {
    for (const p of which(bin)) {
      try { await run(p, args ?? [], { timeout: 3000 }); return "ok"; } catch { /* next */ }
    }
    return "missing";
  };
  const [hyprctl, grim, wtype] = await Promise.all([
    probe("hyprctl", ["version"]),
    probe("grim", ["-h"]),
    probe("wtype", ["-h"]),
  ]);
  return { hyprctl, grim, wtype };
};

export const nativeWindows = async () => {
  const out = await run("/run/current-system/sw/bin/hyprctl", ["clients", "-j"], { timeout: 5000 });
  const list = JSON.parse(out);
  return (Array.isArray(list) ? list : []).map((w) => ({
    address: w.address ?? null,
    app_id: w.class ?? w.app_id ?? null,
    title: w.title ?? null,
    workspace: w.workspace?.id ?? null,
    x: w.at?.[0] ?? null,
    y: w.at?.[1] ?? null,
    w: w.size?.[0] ?? null,
    h: w.size?.[1] ?? null,
    focus: w.focus ?? false,
    floating: w.floating ?? false,
  }));
};

export const nativeFocused = async () => {
  const out = await run("/run/current-system/sw/bin/hyprctl", ["activewindow", "-j"], { timeout: 5000 });
  const w = JSON.parse(out);
  return {
    address: w.address ?? null,
    app_id: w.class ?? w.app_id ?? null,
    title: w.title ?? null,
    x: w.at?.[0] ?? null,
    y: w.at?.[1] ?? null,
    w: w.size?.[0] ?? null,
    h: w.size?.[1] ?? null,
  };
};

export const nativeScreenshot = async (args = {}, tmpDir = "/tmp") => {
  const path = args.path ?? tmpDir + "/dsh-shot-" + Date.now() + ".png";
  const target = args.window; // {address, w, h} from windows()
  if (target && target.w && target.h) {
    // region capture via grim -g "x,y wxh"
    const g = target.x + "," + target.y + " " + target.w + "x" + target.h;
    await run("/run/current-system/sw/bin/grim", ["-g", g, path], { timeout: 10000 });
  } else {
    await run("/run/current-system/sw/bin/grim", [path], { timeout: 10000 });
  }
  return { path, full: !target };
};

export const nativeFocus = async (address) => {
  if (!address) throw new Error("desktop: focus needs window address");
  await run("/run/current-system/sw/bin/hyprctl", ["dispatch", "focuswindow", "address:" + address], { timeout: 5000 });
  return { focused: address };
};

export const nativeMoveWindow = async (address, x, y) => {
  await run("/run/current-system/sw/bin/hyprctl", ["dispatch", "movewindowpixel", "exact " + x + " " + y + ",address:" + address], { timeout: 5000 });
  return { moved: address, x, y };
};

export const nativeResizeWindow = async (address, w, h) => {
  await run("/run/current-system/sw/bin/hyprctl", ["dispatch", "resizewindowpixel", "exact " + w + " " + h + ",address:" + address], { timeout: 5000 });
  return { resized: address, w, h };
};

export const nativeType = async (text) => {
  if (!text) throw new Error("desktop: type needs text");
  await run("/run/current-system/sw/bin/wtype", ["-s", "0", text], { timeout: 8000 });
  return { typed: text.slice(0, 80) + (text.length > 80 ? "…" : "") };
};

export const nativePressKey = async (combo) => {
  // combo grammar: "ctrl+a", "super+Return", "Escape", "ctrl+shift+t"
  if (!combo) throw new Error("desktop: press_key needs a combo");
  const parts = String(combo).toLowerCase().split("+");
  const key = parts.pop();
  const args = [];
  for (const m of parts) args.push("-M", m);
  args.push("-k", key);
  await run("/run/current-system/sw/bin/wtype", args, { timeout: 8000 });
  return { pressed: combo };
};

/* ── 2. CUL MCP bridge ──────────────────────────────────────────────── */

export class CulMCP {
  constructor(culBin) { this.culBin = culBin; this.pending = new Map(); this.id = 0; }
  async start() {
    const { spawn } = await import("node:child_process");
    this.proc = spawn(this.culBin, ["mcp"], { stdio: ["pipe", "pipe", "inherit"] });
    this.proc.stdout.on("data", (d) => this._onData(d));
    await this._call("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "dsh-desktop", version: "1.0" } });
    this._notify("notifications/initialized", {});
    return this;
  }
  _onData(d) {
    const text = d.toString();
    const lines = text.split("\n");
    for (const line of lines) {
      if (!line.trim()) continue;
      let msg;
      try { msg = JSON.parse(line); } catch { continue; }
      if (msg.id && this.pending.has(msg.id)) {
        const p = this.pending.get(msg.id); this.pending.delete(msg.id);
        msg.error ? p.reject(new Error(msg.error.message || "MCP error")) : p.resolve(msg.result);
      }
    }
  }
  _call(method, params) {
    const id = ++this.id;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(new Error("MCP timeout: " + method)); }, 15000);
      this.pending.set(id, { resolve: (v) => { clearTimeout(timer); resolve(v); }, reject: (e) => { clearTimeout(timer); reject(e); } });
      this.proc.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    });
  }
  _notify(method, params) {
    this.proc.stdin.write(JSON.stringify({ jsonrpc: "2.0", method, params }) + "\n");
  }
  async tools() {
    const res = await this._call("tools/list", {});
    return (res?.tools ?? []).map((t) => t.name);
  }
  async callTool(name, params = {}) {
    const res = await this._call("tools/call", { name, arguments: params });
    if (res?.isError) throw new Error("CUL " + name + ": " + JSON.stringify(res.content ?? {}).slice(0, 300));
    return res?.content ?? res ?? {};
  }
  stop() {
    try { this.proc?.kill(); } catch { /* ignore */ }
  }
}

export const culDoctor = async (culBin) => {
  const mcp = new CulMCP(culBin);
  try {
    await mcp.start();
    const list = await mcp.tools();
    return { ok: true, tools: list.length, sample: list.slice(0, 8) };
  } catch (e) {
    return { ok: false, error: String(e.message || e).slice(0, 200) };
  } finally { mcp.stop(); }
};

/* ── 3. AT-SPI readiness (via CUL list_apps) ────────────────────────── */

export const atspiApps = async (culBin) => {
  const mcp = new CulMCP(culBin);
  try {
    await mcp.start();
    const res = await mcp.callTool("list_apps", {});
    const apps = res?.apps ?? res?.content ?? res;
    return { backend: "atspi", apps: typeof apps === "string" ? apps : JSON.stringify(apps ?? []).slice(0, 4000) };
  } catch (e) {
    const m = String(e.message || e);
    return { backend: "atspi", error: m.slice(0, 300), hint: "AT-SPI bus (org.a11y.Bus) is not running; enable it (e.g. at-spi2-core + a11y service) for semantic selectors" };
  } finally { mcp.stop(); }
};
