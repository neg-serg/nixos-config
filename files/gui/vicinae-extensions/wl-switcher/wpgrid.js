"use strict";

var React = require("react");
var cp = require("child_process");
var api = require("@vicinae/api");
var path = require("path");
var fs = require("fs");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

var IMG_EXTS = [".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif", ".tiff", ".tif", ".avif"];

function isImageFile(name) {
  var ext = path.extname(name).toLowerCase();
  return IMG_EXTS.indexOf(ext) !== -1;
}

function expandPath(p) {
  if (!p) return p;
  return p.replace(/^~/, process.env.HOME || "/home/neg");
}

function formatSize(bytes) {
  if (bytes < 1024) return bytes + " B";
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
  return (bytes / (1024 * 1024)).toFixed(1) + " MB";
}

function buildWlArgs(prefs) {
  var args = [];
  if (prefs.resize && prefs.resize !== "crop") args.push("--resize", prefs.resize);
  if (prefs.upscale && prefs.upscale !== "never") args.push("--upscale", prefs.upscale);
  if (prefs.transitionType && prefs.transitionType !== "random")
    args.push("--transition-type", prefs.transitionType);
  if (prefs.transitionDuration) args.push("--transition-duration", prefs.transitionDuration);
  if (prefs.transitionStep && prefs.transitionStep !== "90")
    args.push("--transition-step", prefs.transitionStep);
  if (prefs.transitionFPS && prefs.transitionFPS !== "60" && prefs.transitionFPS !== "30")
    args.push("--transition-fps", prefs.transitionFPS);
  return args;
}

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

function setWallpaper(filePath, prefs) {
  var args = buildWlArgs(prefs);
  var cmd = 'wl img "' + filePath + '" ' + args.join(" ");
  cp.execSync(cmd, { stdio: "ignore", timeout: 30000 });

  if (prefs.colorGenTool) runColorGen(filePath, prefs.colorGenTool);
  if (prefs.postCommand) runPostCommand(filePath, prefs.postCommand);
}

// ---------------------------------------------------------------------------
// Component (no JSX — React.createElement)
// ---------------------------------------------------------------------------

function WallpaperGrid() {
  var _a = React.useState([]), images = _a[0], setImages = _a[1];
  var _b = React.useState(""), searchText = _b[0], setSearchText = _b[1];
  var prefs = api.getPreferenceValues();

  var wallpaperPath = React.useMemo(function () {
    return expandPath(prefs.wallpaperPath || "~/pic/wl");
  }, [prefs.wallpaperPath]);

  // Load image list on mount
  React.useEffect(function () {
    try {
      if (!fs.existsSync(wallpaperPath)) { setImages([]); return; }
      var entries = fs.readdirSync(wallpaperPath).filter(isImageFile);
      var mapped = entries.map(function (name) {
        var fullPath = path.join(wallpaperPath, name);
        var stat = null;
        try { stat = fs.statSync(fullPath); } catch (_) {}
        return { name: name, fullPath: fullPath, size: stat ? stat.size : 0, mtime: stat ? stat.mtime : null };
      });
      mapped.sort(function (a, b) { return (b.mtime || 0) - (a.mtime || 0); });
      setImages(mapped);
    } catch (e) {
      console.error(e);
      setImages([]);
    }
  }, [wallpaperPath]);

  var filtered = React.useMemo(function () {
    if (!searchText) return images;
    var q = searchText.toLowerCase();
    return images.filter(function (img) { return img.name.toLowerCase().indexOf(q) !== -1; });
  }, [images, searchText]);

  var items = filtered.map(function (img) {
    var showDetails = prefs.showImageDetails !== false;
    return React.createElement(api.List.Item, {
      key: img.name,
      icon: { source: img.fullPath },
      title: img.name,
      subtitle: showDetails ? formatSize(img.size) : undefined,
      accessories: showDetails ? [{ text: formatSize(img.size) }] : undefined,
      actions: React.createElement(api.ActionPanel, null,
        React.createElement(api.Action, {
          title: "Set as Wallpaper",
          icon: api.Icon.Image,
          onAction: function () {
            return Promise.resolve().then(function () {
              setWallpaper(img.fullPath, prefs);
              if (prefs.toggleVicinaeSetting !== false) {
                setTimeout(function () {
                  try { cp.execSync("vicinae toggle", { stdio: "ignore", timeout: 5000 }); } catch (_) {}
                }, 300);
              }
              return api.showToast({ style: api.Toast.Style.Success, title: "Wallpaper set", message: img.name });
            }).catch(function (e) {
              return api.showToast({ style: api.Toast.Style.Failure, title: "Failed", message: e.message });
            });
          }
        }),
        React.createElement(api.Action, {
          title: "Set & Stay",
          icon: api.Icon.Window,
          onAction: function () {
            return Promise.resolve().then(function () {
              setWallpaper(img.fullPath, prefs);
              return api.showToast({ style: api.Toast.Style.Success, title: "Wallpaper set", message: img.name });
            }).catch(function (e) {
              return api.showToast({ style: api.Toast.Style.Failure, title: "Failed", message: e.message });
            });
          }
        }),
        React.createElement(api.Action.OpenInBrowser, { title: "Open File", url: img.fullPath }),
        React.createElement(api.Action.CopyToClipboard, { title: "Copy Path", content: img.fullPath })
      )
    });
  });

  if (images.length === 0 && !searchText) {
    items = React.createElement(api.List.EmptyView, {
      icon: api.Icon.Image,
      title: "No wallpapers found",
      description: "Place images in " + wallpaperPath
    });
  }

  return React.createElement(api.List, {
    isLoading: images.length === 0,
    searchBarPlaceholder: "Search wallpapers...",
    onSearchTextChange: setSearchText,
    throttle: true
  }, items);
}

module.exports = { default: WallpaperGrid };
