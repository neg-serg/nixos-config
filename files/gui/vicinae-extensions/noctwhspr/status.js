"use strict";

// Vicinae patches Module.prototype.require to provide these.
// MUST use CommonJS (not ESM) for the patch to work.
var React = require("react");
var cp = require("child_process");
var api = require("@vicinae/api");

function stateIcon(state) {
  switch (state) {
    case "Recording": return { source: api.Icon.Microphone, tintColor: "#ef4444" };
    case "Ready": return { source: api.Icon.Microphone, tintColor: "#22c55e" };
    case "Stopped": return { source: api.Icon.StopFilled, tintColor: "#6b7280" };
    case "Model Unloaded": return { source: api.Icon.Power, tintColor: "#f59e0b" };
    case "Error": return { source: api.Icon.Warning, tintColor: "#ef4444" };
    default: return { source: api.Icon.QuestionMarkCircle, tintColor: "#6b7280" };
  }
}

function getState(root) {
  return new Promise(function (resolve) {
    try {
      var trayScript = root + "/config/hyprland/hyprwhspr-tray.sh";
      cp.exec('bash "' + trayScript + '" status 2>/dev/null', { timeout: 5000 }, function (err, stdout) {
        if (err) return resolve({ state: "Error", detail: err.message || "tray script failed", raw: "" });
        var out = stdout.trim();
        var lines = out.split("\n");
        var state = (lines[0] || "Unknown").replace(/[^a-zA-Z0-9 ]/g, "").trim();
        var detail = lines.slice(1).join(" \u2022 ").trim();
        resolve({ state: state || "Unknown", detail: detail, raw: out });
      });
    } catch (e) {
      resolve({ state: "Error", detail: e.message, raw: "" });
    }
  });
}

function NoctWhspr() {
  var _a = React.useState("Loading"), state = _a[0], setState = _a[1];
  var _b = React.useState(""), detail = _b[0], setDetail = _b[1];
  var _c = React.useState(0), tick = _c[0], setTick = _c[1];
  var prefs = api.getPreferenceValues();
  var root = prefs.root || "/usr/lib/hyprwhspr";

  React.useEffect(function () {
    var cancelled = false;
    getState(root).then(function (info) {
      if (cancelled) return;
      setState(info.state);
      setDetail(info.detail);
    });
    return function () { cancelled = true; };
  }, [root, tick]);

  var icon = stateIcon(state);

  var refresh = function () {
    setTick(function (t) { return t + 1; });
  };

  return React.createElement(api.List, { isLoading: false },
    React.createElement(api.List.Section, { title: "hyprwhspr Status" },
      React.createElement(api.List.Item, {
        key: "state",
        id: "state",
        title: "State",
        subtitle: state,
        icon: icon,
        accessories: [{ text: state }],
      }),
      detail ? React.createElement(api.List.Item, {
        key: "detail",
        id: "detail",
        title: "Detail",
        subtitle: detail,
        icon: api.Icon.Info,
      }) : null
    ),
    React.createElement(api.List.Section, { title: "Controls" },
      React.createElement(api.List.Item, {
        key: "toggle",
        id: "toggle",
        title: state === "Recording" ? "Stop Recording" : "Start Recording",
        subtitle: state === "Recording" ? "Stop the current dictation session" : "Begin dictation",
        icon: state === "Recording"
          ? { source: api.Icon.StopFilled, tintColor: "#ef4444" }
          : { source: api.Icon.Microphone, tintColor: "#22c55e" },
        actions: React.createElement(api.ActionPanel, null,
          React.createElement(api.Action, {
            title: state === "Recording" ? "Stop Recording" : "Start Recording",
            icon: api.Icon.Microphone,
            onAction: function () {
              return Promise.resolve().then(function () {
                var trayScript = root + "/config/hyprland/hyprwhspr-tray.sh";
                cp.execSync('bash "' + trayScript + '" toggle 2>/dev/null', {
                  timeout: 5000,
                  stdio: "ignore",
                });
                refresh();
                return api.showToast({
                  style: api.Toast.Style.Success,
                  title: state === "Recording" ? "Stopped" : "Started",
                });
              }).catch(function (e) {
                return api.showToast({
                  style: api.Toast.Style.Failure,
                  title: "Toggle failed",
                  message: e.message,
                });
              });
            }
          }),
          React.createElement(api.Action, {
            title: "Refresh",
            icon: api.Icon.ArrowClockwise,
            onAction: refresh,
          })
        ),
      }),
      React.createElement(api.List.Item, {
        key: "restart",
        id: "restart",
        title: "Restart Service",
        subtitle: "Restart the hyprwhspr systemd service",
        icon: api.Icon.ArrowClockwise,
        actions: React.createElement(api.ActionPanel, null,
          React.createElement(api.Action, {
            title: "Restart hyprwhspr",
            icon: api.Icon.ArrowClockwise,
            onAction: function () {
              return Promise.resolve().then(function () {
                cp.execSync("systemctl --user restart hyprwhspr.service", {
                  timeout: 10000,
                  stdio: "ignore",
                });
                refresh();
                return api.showToast({
                  style: api.Toast.Style.Success,
                  title: "Service restarted",
                });
              }).catch(function (e) {
                return api.showToast({
                  style: api.Toast.Style.Failure,
                  title: "Restart failed",
                  message: e.message,
                });
              });
            }
          })
        ),
      }),
      React.createElement(api.List.Item, {
        key: "refresh",
        id: "refresh",
        title: "Refresh Status",
        subtitle: "Re-query hyprwhspr state",
        icon: api.Icon.ArrowClockwise,
        actions: React.createElement(api.ActionPanel, null,
          React.createElement(api.Action, {
            title: "Refresh",
            icon: api.Icon.ArrowClockwise,
            onAction: refresh,
          })
        ),
      })
    )
  );
}

module.exports = { default: NoctWhspr };
