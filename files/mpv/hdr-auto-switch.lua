-- hdr-auto-switch.lua
-- Switch Hyprland monitor to HDR when playing HDR content (PQ/HLG),
-- back to auto when SDR or when mpv exits. Works around hyprland 0.55
-- not auto-switching for windowed/gpu-next HDR surfaces.
--
-- Requires: hyprctl in PATH (hyprland installed).
-- Monitor name and cm presets are configurable via env vars.

local MONITOR = os.getenv("HDR_MONITOR") or "DP-2"
local HDR_CM = os.getenv("HDR_CM") or "hdredid"
local SDR_CM = os.getenv("SDR_CM") or "auto"

local function setMonitorCmSync(cm)
  -- Synchronous: used on shutdown where async subprocess may not complete
  -- before mpv exits.
  mp.command_native({
    name = "subprocess",
    args = {
      "hyprctl", "eval",
      string.format('hl.monitor({ output = "%s", cm = "%s" })', MONITOR, cm),
    },
    capture_size = 0,
    playback_only = false,
  })
end

local function setMonitorCm(cm)
  mp.command_native_async({
    name = "subprocess",
    args = {
      "hyprctl", "eval",
      string.format('hl.monitor({ output = "%s", cm = "%s" })', MONITOR, cm),
    },
    capture_size = 0,
    playback_only = false,
  }, function() end)
end

local function updateHdr(isHdr)
  if exited or isHdr == currentHdr then
    return
  end
  currentHdr = isHdr
  -- Sync on the SDR restore path: it may be the last thing before mpv exits
  -- (gamma resets to nil on quit), and async would not complete in time.
  if isHdr then
    setMonitorCm(HDR_CM)
  else
    setMonitorCmSync(SDR_CM)
  end
  mp.msg.log("info", "HDR: " .. tostring(isHdr) .. " → cm=" .. (isHdr and HDR_CM or SDR_CM))
end

-- Restore SDR cm when mpv quits (covers kill/quit/EOF without a SDR frame)
mp.register_event("shutdown", function()
  exited = true
  if currentHdr then
    setMonitorCmSync(SDR_CM)
    mp.msg.log("info", "HDR: restore cm=" .. SDR_CM .. " on exit")
  end
end)

-- On script start, restore SDR cm: a previous mpv run may have been killed
-- (SIGKILL) while HDR was active, leaving the monitor stuck in HDR.
mp.register_event("start-file", function()
  if not currentHdr then
    setMonitorCm(SDR_CM)
  end
end)

mp.observe_property("video-params/gamma", "string", function(_, gamma)
  updateHdr(gamma == "pq" or gamma == "hlg")
end)
