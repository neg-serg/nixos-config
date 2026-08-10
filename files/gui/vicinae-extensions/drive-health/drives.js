"use strict";

// Vicinae patches Module.prototype.require to provide these.
// MUST use CommonJS (not ESM) for the patch to work.
var React = require("react");
var cp = require("child_process");
var api = require("@vicinae/api");

function exec(cmd) {
  try {
    return cp.execSync(cmd, { timeout: 10000, encoding: "utf8" });
  } catch (_) {
    return "";
  }
}

function formatBytes(bytes) {
  if (!bytes || bytes === 0) return "0 B";
  var units = ["B", "KB", "MB", "GB", "TB"];
  var i = Math.floor(Math.log(bytes) / Math.log(1024));
  return (bytes / Math.pow(1024, i)).toFixed(1) + " " + units[i];
}

function getDisks() {
  // lsblk JSON: all block devices with type, model, size, rotation, transport
  var out = exec("lsblk -bJ -o NAME,MODEL,SIZE,TYPE,ROTA,TRAN,SERIAL 2>/dev/null");
  var disks = [];
  try {
    var parsed = JSON.parse(out);
    if (!parsed.blockdevices) return disks;
    var walk = function (dev) {
      if (dev.type === "disk" && dev.name.indexOf("ram") !== 0 && dev.name.indexOf("loop") !== 0) {
        disks.push({
          name: dev.name,
          device: "/dev/" + dev.name,
          model: dev.model || "",
          size: dev.size || 0,
          type: dev.rota === "1" ? "HD" : "SSD",
          transport: dev.tran || "",
          serial: dev.serial || "",
        });
      }
      if (dev.children) dev.children.forEach(walk);
    };
    parsed.blockdevices.forEach(walk);
  } catch (_) {}
  return disks;
}

function getFsUsage() {
  // df in bytes, tab-separated: mount size used avail use%
  var out = exec("df -B1 -P 2>/dev/null");
  var usage = [];
  var lines = out.split("\n");
  for (var i = 1; i < lines.length; i++) {
    var parts = lines[i].trim().split(/\s+/);
    if (parts.length >= 6) {
      usage.push({
        fs: parts[0],
        size: parseInt(parts[1], 10) || 0,
        used: parseInt(parts[2], 10) || 0,
        avail: parseInt(parts[3], 10) || 0,
        use: parseInt(parts[4], 10) || 0,
        mount: parts[5],
      });
    }
  }
  return usage;
}

// Parse SMART attributes + temperature from `smartctl -A <dev>`
function getSmartData(device) {
  var out = exec("smartctl -A " + device + " 2>/dev/null");
  var attrs = [];
  var temp = 0;
  var lines = out.split("\n");
  var inTable = false;
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (line.indexOf("ATTRIBUTE_NAME") !== -1) { inTable = true; continue; }
    if (!inTable || line.trim() === "") continue;
    var parts = line.trim().split(/\s+/);
    if (parts.length >= 10) {
      var name = parts[1];
      var raw = parts.slice(10).join(" ");
      // Temperature_Celsius raw value is the first number
      if (name.indexOf("Temperature_Celsius") !== -1) {
        var m = raw.match(/\d+/);
        if (m) temp = parseInt(m[0], 10);
      }
      attrs.push({
        id: parts[0],
        name: name,
        value: parseInt(parts[9], 10) || 0,
        worst: parseInt(parts[8], 10) || 0,
        threshold: parseInt(parts[7], 10) || 0,
        raw: raw,
      });
    }
  }
  return { attrs: attrs, temp: temp };
}

function healthIcon(status, temp, warningTemp, criticalTemp) {
  if (status === "Predicted Failure") return { source: api.Icon.XMarkCircle, tintColor: "#ef4444" };
  if (temp >= criticalTemp) return { source: api.Icon.Warning, tintColor: "#ef4444" };
  if (temp >= warningTemp || status !== "Ok") return { source: api.Icon.Warning, tintColor: "#eab308" };
  return { source: api.Icon.CheckCircle, tintColor: "#22c55e" };
}

function healthLabel(status, temp, warningTemp, criticalTemp) {
  if (status === "Predicted Failure") return "FAIL";
  if (temp >= criticalTemp) return "CRIT";
  if (temp >= warningTemp || status !== "Ok") return "WARN";
  return "OK";
}

function DriveHealth() {
  var _a = React.useState([]), drives = _a[0], setDrives = _a[1];
  var _b = React.useState(true), loading = _b[0], setLoading = _b[1];
  var prefs = api.getPreferenceValues();
  var warningTemp = parseInt(prefs.warning_temp, 10) || 55;
  var criticalTemp = parseInt(prefs.critical_temp, 10) || 70;
  var showHdd = prefs.show_hdd !== false;

  var loadDrives = React.useCallback(function () {
    setLoading(true);
    var disks = getDisks();
    var usage = getFsUsage();

    var enriched = disks.map(function (disk) {
      var smart = getSmartData(disk.device);
      disk._smart = smart.attrs;
      disk._temp = smart.temp;
      // Match mounts: df fs column starts with device or its partition prefix
      var mounts = usage.filter(function (u) {
        return u.fs.indexOf(disk.device) === 0 && u.fs.length > disk.device.length;
      });
      disk._mounts = mounts;
      return disk;
    });

    if (!showHdd) {
      enriched = enriched.filter(function (d) { return d.type !== "HD"; });
    }
    setDrives(enriched);
    setLoading(false);
  }, [showHdd]);

  React.useEffect(function () {
    loadDrives();
  }, []);

  if (!loading && drives.length === 0) {
    return React.createElement(api.List, { isLoading: false },
      React.createElement(api.List.EmptyView, {
        icon: api.Icon.HardDrive,
        title: "No drives found",
        description: "No physical drives detected"
      })
    );
  }

  var items = drives.map(function (disk) {
    var temp = disk._temp || 0;
    var status = "Ok";
    var icon = healthIcon(status, temp, warningTemp, criticalTemp);
    var label = healthLabel(status, temp, warningTemp, criticalTemp);

    var subtitle = [
      disk.model || disk.name,
      formatBytes(disk.size),
      temp > 0 ? temp + "\u00b0C" : null,
      disk.transport ? disk.transport.toUpperCase() : null,
    ].filter(Boolean).join(" \u2022 ");

    var accessories = [];
    if (temp > 0) {
      accessories.push({ text: temp + "\u00b0C", icon: api.Icon.Temperature });
    }
    accessories.push({ text: label, icon: icon });



    return React.createElement(api.List.Item, {
      key: disk.device,
      id: "disk-" + disk.device.replace(/\//g, "-"),
      title: disk.device,
      subtitle: subtitle,
      icon: disk.type === "SSD" ? api.Icon.MemoryStick : api.Icon.HardDrive,
      accessories: accessories,
      actions: React.createElement(api.ActionPanel, null,
        React.createElement(api.Action, {
          title: "Refresh",
          icon: api.Icon.ArrowClockwise,
          onAction: loadDrives,
        }),
        React.createElement(api.Action.CopyToClipboard, {
          title: "Copy Device Path",
          content: disk.device,
          icon: api.Icon.CopyClipboard,
        })
      )
    });
  });

  return React.createElement(api.List, {
    isLoading: loading,
    searchBarPlaceholder: "Search drives...",
  },
    React.createElement(api.List.Section, { title: items.length + " drive" + (items.length !== 1 ? "s" : "") },
      items
    )
  );
}

module.exports = { default: DriveHealth };
