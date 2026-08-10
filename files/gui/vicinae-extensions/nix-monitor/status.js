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

function execAsync(cmd) {
  return new Promise(function (resolve) {
    cp.exec(cmd, { timeout: 15000, encoding: "utf8" }, function (err, stdout) {
      if (err) resolve(null);
      else resolve(stdout.trim());
    });
  });
}

function NixMonitor() {
  var _a = React.useState(true), loading = _a[0], setLoading = _a[1];
  var _b = React.useState({}), data = _b[0], setData = _b[1];
  var prefs = api.getPreferenceValues();
  var branch = prefs.branch || "nixos-unstable";

  var refresh = React.useCallback(function () {
    setLoading(true);
    var jobs = [
      execAsync("readlink /run/current-system"),
      execAsync("nixos-version"),
      // df on the /nix/store mount is instant; du -sh would take minutes
      execAsync("df -B1 --output=used /nix/store 2>/dev/null | tail -1"),
      execAsync("nix-store --query --requisites /run/current-system 2>/dev/null | wc -l"),
      execAsync("git ls-remote https://github.com/NixOS/nixpkgs.git " + branch + " 2>/dev/null | cut -f1"),
    ];

    Promise.all(jobs).then(function (r) {
      var currentSystem = r[0] || "unknown";
      var nixosVersion = r[1] || "unknown";
      var storeBytes = parseInt(r[2], 10);
      var closureCount = r[3] || "?";
      var remoteRev = r[4] || null;

      var localRev = "unknown";
      var m = nixosVersion.match(/\(([^)]+)\)/);
      if (m) localRev = m[1];

      var updateStatus = "unknown";
      if (remoteRev && localRev !== "unknown") {
        updateStatus = remoteRev.substring(0, 7) === localRev.substring(0, 7)
          ? "up-to-date"
          : "update-available";
      }

      setData({
        genName: currentSystem.split("/").pop() || "unknown",
        nixosVersion: nixosVersion,
        localRev: localRev,
        remoteRev: remoteRev,
        updateStatus: updateStatus,
        storeSize: storeBytes ? formatBytes(storeBytes) : "unknown",
        closureCount: closureCount,
      });
      setLoading(false);
    });
  }, [branch]);

  React.useEffect(function () {
    refresh();
  }, []);

  var updateIcon = data.updateStatus === "up-to-date"
    ? { source: api.Icon.CheckCircle, tintColor: "#22c55e" }
    : data.updateStatus === "update-available"
      ? { source: api.Icon.Warning, tintColor: "#ef4444" }
      : { source: api.Icon.QuestionMarkCircle, tintColor: "#6b7280" };

  var updateLabel = data.updateStatus === "up-to-date"
    ? "Up to date"
    : data.updateStatus === "update-available"
      ? "Update available"
      : "Unknown";

  return React.createElement(api.List, { isLoading: loading },
    React.createElement(api.List.Section, { title: "System" },
      React.createElement(api.List.Item, {
        key: "generation",
        id: "gen",
        title: "Current Generation",
        subtitle: data.genName || "...",
        icon: api.Icon.Tag,
        accessories: data.nixosVersion ? [{ text: data.nixosVersion }] : undefined,
      }),
      React.createElement(api.List.Item, {
        key: "local-rev",
        id: "lrev",
        title: "Nixpkgs Revision (local)",
        subtitle: data.localRev || "...",
        icon: api.Icon.Code,
      }),
      React.createElement(api.List.Item, {
        key: "remote-rev",
        id: "rrev",
        title: "Remote (" + branch + ")",
        subtitle: data.remoteRev ? data.remoteRev.substring(0, 40) : "unavailable",
        icon: updateIcon,
        accessories: data.updateStatus ? [{ text: updateLabel }] : undefined,
      })
    ),
    React.createElement(api.List.Section, { title: "Store" },
      React.createElement(api.List.Item, {
        key: "store-size",
        id: "ssize",
        title: "Store Size",
        subtitle: data.storeSize || "...",
        icon: api.Icon.HardDrive,
      }),
      React.createElement(api.List.Item, {
        key: "closures",
        id: "closures",
        title: "Closure Count",
        subtitle: data.closureCount ? data.closureCount + " paths" : "...",
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

function formatBytes(bytes) {
  if (!bytes || bytes === 0) return "0 B";
  var units = ["B", "KB", "MB", "GB", "TB"];
  var i = Math.floor(Math.log(bytes) / Math.log(1024));
  return (bytes / Math.pow(1024, i)).toFixed(1) + " " + units[i];
}

module.exports = { default: NixMonitor };
