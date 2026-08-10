"use strict";

// Vicinae patches Module.prototype.require to provide these.
// MUST use CommonJS (not ESM) for the patch to work.
var React = require("react");
var cp = require("child_process");
var api = require("@vicinae/api");

function exec(cmd) {
  try {
    return cp.execSync(cmd, { timeout: 15000, encoding: "utf8" }).trim();
  } catch (_) {
    return null;
  }
}

function NixMonitor() {
  var _a = React.useState(false), refreshing = _a[0], setRefreshing = _a[1];
  var _b = React.useState(0), tick = _b[0], setTick = _b[1];
  var prefs = api.getPreferenceValues();
  var branch = prefs.branch || "nixos-unstable";

  var currentSystem = React.useMemo(function () {
    return exec("readlink /run/current-system") || "unknown";
  }, [tick]);

  var genName = React.useMemo(function () {
    return currentSystem.split("/").pop() || "unknown";
  }, [currentSystem]);

  var nixosVersion = React.useMemo(function () {
    return exec("nixos-version") || "unknown";
  }, [tick]);

  var localRev = React.useMemo(function () {
    try {
      var m = nixosVersion.match(/\(([^)]+)\)/);
      return m ? m[1] : nixosVersion;
    } catch (_) { return "unknown"; }
  }, [nixosVersion]);

  var storeSize = React.useMemo(function () {
    return exec("du -sh /nix/store 2>/dev/null | cut -f1") || "unknown";
  }, [tick]);

  var closureCount = React.useMemo(function () {
    var count = exec("nix-store --query --requisites /run/current-system 2>/dev/null | wc -l");
    return count ? count.trim() : "?";
  }, [tick]);

  var _c = React.useState("unknown"), updateStatus = _c[0], setUpdateStatus = _c[1];
  var _d = React.useState(null), remoteRev = _d[0], setRemoteRev = _d[1];

  React.useEffect(function () {
    var remote = exec("git ls-remote https://github.com/NixOS/nixpkgs.git " + branch + " 2>/dev/null | cut -f1");
    setRemoteRev(remote || null);
    if (remote && localRev !== "unknown") {
      setUpdateStatus(remote.trim().substring(0, 7) === localRev.substring(0, 7) ? "up-to-date" : "update-available");
    }
  }, [branch, localRev, tick]);

  var updateIcon = updateStatus === "up-to-date"
    ? { source: api.Icon.CheckCircle, tintColor: "#22c55e" }
    : updateStatus === "update-available"
      ? { source: api.Icon.Warning, tintColor: "#ef4444" }
      : { source: api.Icon.QuestionMarkCircle, tintColor: "#6b7280" };

  var updateLabel = updateStatus === "up-to-date"
    ? "Up to date"
    : updateStatus === "update-available"
      ? "Update available"
      : "Unknown";

  var refresh = function () {
    setTick(function (t) { return t + 1; });
  };

  return React.createElement(api.List, { isLoading: refreshing },
    React.createElement(api.List.Section, { title: "System" },
      React.createElement(api.List.Item, {
        key: "generation",
        id: "gen",
        title: "Current Generation",
        subtitle: genName,
        icon: api.Icon.Tag,
        accessories: [{ text: nixosVersion }],
      }),
      React.createElement(api.List.Item, {
        key: "local-rev",
        id: "lrev",
        title: "Nixpkgs Revision (local)",
        subtitle: localRev,
        icon: api.Icon.Code,
      }),
      React.createElement(api.List.Item, {
        key: "remote-rev",
        id: "rrev",
        title: "Remote (" + branch + ")",
        subtitle: remoteRev ? remoteRev.substring(0, 40) : "unavailable",
        icon: updateIcon,
        accessories: [{ text: updateLabel }],
      })
    ),
    React.createElement(api.List.Section, { title: "Store" },
      React.createElement(api.List.Item, {
        key: "store-size",
        id: "ssize",
        title: "Store Size",
        subtitle: storeSize,
        icon: api.Icon.HardDrive,
      }),
      React.createElement(api.List.Item, {
        key: "closures",
        id: "closures",
        title: "Closure Count",
        subtitle: closureCount + " paths",
        icon: api.Icon.CheckList,
      })
    ),
    React.createElement(api.List.Section, { title: "Actions" },
      React.createElement(api.List.Item, {
        key: "refresh",
        id: "refresh",
        title: "Refresh Status",
        subtitle: "Reload system information",
        icon: api.Icon.ArrowClockwise,
        actions: React.createElement(api.ActionPanel, null,
          React.createElement(api.Action, {
            title: "Refresh",
            icon: api.Icon.ArrowClockwise,
            onAction: refresh,
          })
        ),
      }),
      React.createElement(api.List.Item, {
        key: "optimize",
        id: "optimize",
        title: "Optimize Store",
        subtitle: prefs.optimize_command || "nix-store --optimise -vv",
        icon: api.Icon.WrenchScrewdriver,
        actions: React.createElement(api.ActionPanel, null,
          React.createElement(api.Action, {
            title: "Run Optimize",
            icon: api.Icon.WrenchScrewdriver,
            onAction: function () {
              return Promise.resolve().then(function () {
                var cmd = prefs.optimize_command || "nix-store --optimise -vv";
                return api.showToast({ style: api.Toast.Style.Animated, title: "Optimizing..." }).then(function () {
                  cp.execSync(cmd, { stdio: "inherit", timeout: 300000 });
                  return api.showToast({ style: api.Toast.Style.Success, title: "Store optimized" });
                });
              }).catch(function (e) {
                return api.showToast({ style: api.Toast.Style.Failure, title: "Optimize failed", message: e.message });
              });
            }
          })
        ),
      }),
      React.createElement(api.List.Item, {
        key: "gc",
        id: "gc",
        title: "Collect Garbage",
        subtitle: prefs.clean_command || "nix-collect-garbage -d",
        icon: api.Icon.Trash,
        actions: React.createElement(api.ActionPanel, null,
          React.createElement(api.Action, {
            title: "Run GC",
            icon: api.Icon.Trash,
            style: api.Action.Style.Destructive,
            onAction: function () {
              return Promise.resolve().then(function () {
                var cmd = prefs.clean_command || "nix-collect-garbage -d";
                return api.showToast({ style: api.Toast.Style.Animated, title: "Collecting..." }).then(function () {
                  cp.execSync(cmd, { stdio: "inherit", timeout: 300000 });
                  return api.showToast({ style: api.Toast.Style.Success, title: "GC complete" });
                });
              }).catch(function (e) {
                return api.showToast({ style: api.Toast.Style.Failure, title: "GC failed", message: e.message });
              });
            }
          })
        ),
      })
    )
  );
}

module.exports = { default: NixMonitor };
