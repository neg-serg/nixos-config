/**
 * dsh-layout-slash, host half.
 *
 * Serves a tiny loopback-only HTTP endpoint that switches the Hyprland
 * keyboard layout to the us group (index 0). The browser half
 * (lib/client.js) calls it when the first character typed in the composer is
 * "." — the character the "/" key produces under the ru layout — right after
 * replacing that dot with "/", so the rest of the message is typed in
 * English.
 *
 * hyprctl is addressed by absolute path (NixOS system environment) and the
 * instance signature is resolved from `hyprctl instances -j`, so the command
 * works even when HYPRLAND_INSTANCE_SIGNATURE is not in the service
 * environment.
 *
 * @module dsh-layout-slash
 */

import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

/** Cordis plugin name — must match the patch row / package name. */
export const name = "dsh-layout-slash";

/** Required services: the HTTP route registry. */
export const inject = ["webServer"];

/** hyprctl is deployed in the system environment on NixOS. */
const HYPRCTL = "/run/current-system/sw/bin/hyprctl";

/** Exact route path the browser half fetches. */
const SWITCH_PATH = "/hypr-layout/switch";

/**
 * Loopback-only: the LAN phone proxy (192.168.2.87:3080) forwards requests
 * with their original Host header, so a request arriving through it carries a
 * non-loopback host and is rejected — the phone's own keyboard must never
 * flip the desktop layout.
 */
const LOOPBACK_HOSTS = new Set(["127.0.0.1", "localhost", "::1"]);

/** Resolve the running Hyprland instance signature without the env var. */
async function hyprlandSignature() {
  const { stdout } = await execFileAsync(HYPRCTL, ["instances", "-j"], {
    encoding: "utf8",
  });
  const instances = JSON.parse(stdout);
  const first = Array.isArray(instances) ? instances[0] : undefined;
  if (!first || typeof first.instance !== "string") {
    throw new Error("no Hyprland instance found");
  }
  return first.instance;
}

/** Switch every keyboard to the us layout group (index 0). */
async function switchLayoutToUs() {
  const signature = await hyprlandSignature();
  await execFileAsync(HYPRCTL, ["-i", signature, "switchxkblayout", "all", "0"]);
}

/**
 * Register the layout-switch endpoint.
 * @param ctx - registrant context.
 */
export function apply(ctx) {
  ctx.effect(() => ctx.webServer.register({
    kind: "exact",
    path: SWITCH_PATH,
    handler: async (req, res) => {
      const host = String(req.headers.host ?? "").split(":")[0];
      if (!LOOPBACK_HOSTS.has(host)) {
        res.writeHead(403, { "content-type": "text/plain; charset=utf-8" });
        res.end("forbidden");
        return;
      }
      try {
        await switchLayoutToUs();
        res.writeHead(204);
        res.end();
      } catch (error) {
        res.writeHead(500, { "content-type": "text/plain; charset=utf-8" });
        res.end(String(error));
      }
    },
  }), "dsh-layout-slash.route");
}
