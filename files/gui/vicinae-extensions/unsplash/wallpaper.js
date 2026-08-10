"use strict";

const cp = require("child_process");
const api = require("@vicinae/api");
const path = require("path");
const os = require("os");

function wallpaper() {
  return Promise.resolve().then(function () {
    var prefs = api.getPreferenceValues();
    var query = prefs.query || "nature landscape";
    var orientation = prefs.orientation || "";
    var home = os.homedir();
    var dlDir = path.join(home, "pic", "wl");

    // Ensure download directory exists
    try { cp.execSync("mkdir -p " + dlDir, { stdio: "ignore" }); } catch (_) {}

    // Build sw command
    var args = ["unsplash", "-q", query, "-l", dlDir];
    if (orientation) {
      args.push("-o", orientation);
    }

    try {
      // Download via sw script
      var output = cp.execSync("sw " + args.join(" "), { timeout: 30000, encoding: "utf8" });
      var lines = output.trim().split("\n");
      var filepath = lines[lines.length - 1]?.trim();

      if (!filepath || !filepath.startsWith("/")) {
        return api.showToast({
          style: api.Toast.Style.Failure,
          title: "Failed to download image",
          message: query,
        });
      }

      // Set as wallpaper
      cp.execSync('wl img "' + filepath + '"', { stdio: "ignore", timeout: 10000 });

      return api.showToast({
        style: api.Toast.Style.Success,
        title: "Wallpaper set",
        message: filepath.split("/").pop(),
      });
    } catch (e) {
      return api.showToast({
        style: api.Toast.Style.Failure,
        title: "Failed",
        message: e.message,
      });
    }
  });
}

module.exports = { default: wallpaper };
