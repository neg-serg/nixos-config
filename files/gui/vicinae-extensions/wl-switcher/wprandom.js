"use strict";

var cp = require("child_process");
var api = require("@vicinae/api");
var path = require("path");
var fs = require("fs");

/**
 * Build the wl img command arguments from user preferences.
 */
function buildWlArgs(prefs) {
  var args = [];

  // Resize mode
  if (prefs.resize && prefs.resize !== "crop") {
    args.push("--resize", prefs.resize);
  }

  // Upscale
  if (prefs.upscale && prefs.upscale !== "never") {
    args.push("--upscale", prefs.upscale);
  }

  // Transition type
  if (prefs.transitionType && prefs.transitionType !== "random") {
    args.push("--transition-type", prefs.transitionType);
  }

  // Transition duration
  if (prefs.transitionDuration) {
    args.push("--transition-duration", prefs.transitionDuration);
  }

  // Transition step
  if (prefs.transitionStep && prefs.transitionStep !== "90") {
    args.push("--transition-step", prefs.transitionStep);
  }

  // Transition FPS
  if (prefs.transitionFPS && prefs.transitionFPS !== "60" && prefs.transitionFPS !== "30") {
    args.push("--transition-fps", prefs.transitionFPS);
  }

  return args;
}

/**
 * Run a color generation tool on the new wallpaper.
 */
function runColorGen(imagePath, tool) {
  if (!tool || tool === "none") return;
  try {
    switch (tool) {
      case "matugen":
        cp.execSync('matugen image "' + imagePath + '"', { stdio: "ignore", timeout: 15000 });
        break;
      case "pywal":
        cp.execSync('wal -i "' + imagePath + '"', { stdio: "ignore", timeout: 15000 });
        break;
      case "wallust":
        cp.execSync('wallust run "' + imagePath + '"', { stdio: "ignore", timeout: 15000 });
        break;
    }
  } catch (e) {
    console.error("Color gen failed:", e.message);
  }
}

/**
 * Run a post command after setting wallpaper.
 */
function runPostCommand(imagePath, cmd) {
  if (!cmd) return;
  try {
    cp.execSync(cmd, {
      stdio: "ignore",
      timeout: 30000,
      env: Object.assign({}, process.env, { WL_WALLPAPER: imagePath }),
    });
  } catch (e) {
    console.error("Post command failed:", e.message);
  }
}

/**
 * wprandom: Pick a random wallpaper and set it with wl.
 */
function command() {
  return Promise.resolve().then(function () {
    var prefs = api.getPreferenceValues();
    var home = process.env.HOME || "/home/neg";

    var wallpaperPath = prefs.wallpaperPath
      ? prefs.wallpaperPath.replace(/^~/, home)
      : path.join(home, "pic/wl");

    if (!fs.existsSync(wallpaperPath)) {
      return api.showToast({
        style: api.Toast.Style.Failure,
        title: "Wallpaper directory not found",
        message: wallpaperPath,
      });
    }

    // Find images
    var exts = [".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif"];
    var files = fs.readdirSync(wallpaperPath).filter(function (f) {
      var ext = path.extname(f).toLowerCase();
      return exts.indexOf(ext) !== -1;
    });

    if (files.length === 0) {
      return api.showToast({
        style: api.Toast.Style.Failure,
        title: "No images found",
        message: wallpaperPath,
      });
    }

    var randomFile = files[Math.floor(Math.random() * files.length)];
    var imagePath = path.join(wallpaperPath, randomFile);

    // Build wl command
    var args = buildWlArgs(prefs);
    var cmd = 'wl img "' + imagePath + '" ' + args.join(" ");

    try {
      cp.execSync(cmd, { stdio: "ignore", timeout: 30000 });

      // Run color gen
      if (prefs.colorGenTool) {
        runColorGen(imagePath, prefs.colorGenTool);
      }

      // Run post command
      if (prefs.postCommand) {
        runPostCommand(imagePath, prefs.postCommand);
      }

      // Toggle vicinae after setting
      if (prefs.toggleVicinaeSetting !== false) {
        setTimeout(function () {
          try {
            cp.execSync("vicinae toggle", { stdio: "ignore", timeout: 5000 });
          } catch (_) {}
        }, 300);
      }

      return api.showToast({
        style: api.Toast.Style.Success,
        title: "Wallpaper set",
        message: randomFile,
      });
    } catch (e) {
      return api.showToast({
        style: api.Toast.Style.Failure,
        title: "Failed to set wallpaper",
        message: e.message,
      });
    }
  });
}

module.exports = { default: command };
