-- genelec.luau — the logic of the Genelec plugin (see genelec.plm).
--
-- Port of the parts of files/quickshell/Services/Genelec.qml that decide what
-- goes to the monitors, with the QS numbers:
--
--   - whole dB only (GLM CC20 is an integer), clamped to [-95, maxVolume];
--   - commits coalesce: 150 ms after the last wheel notch, never closer than
--     400 ms to the previous send (GLM drops messages that arrive in a burst);
--   - the VM path sends the absolute CC20 once 400 ms after the commit, and is
--     re-anchored at 2 s and 8 s (the QS self-heal / confirmation / late
--     confirmation one-shots), never periodically;
--   - the adapter's placement is probed every 30 s with `genlc discover`
--     (host path) — no answer means the adapter is in the VM and the MIDI
--     bridge is the only way in;
--   - the target is read back every 2 s with `glm-vol read`, adopted only after
--     the wheel has been quiet for 2.5 s and never while muted (the port of the
--     QS FileView watch and its user-input guard).
--
-- Timing is kept in one-shot timers and flags: the sandbox closes `os`, so the
-- logic has no clock of its own.
--
-- Permissions are the plugin's own: genlc, glm-vol, glm-midi.

local MIN_DB = -95
local USER_IDLE_MS = 2500
local COMMIT_MS = 150
local MIN_SEND_GAP_MS = 400
local ANCHORS_MS = { 400, 2000, 8000 }
local PROBE_MS = 30000
local POLL_MS = 2000

local target = fact.volume or -40
local muted = false
local preMute = target
local busy = false
local cooling = false
local quiet = true
local commitTimer = nil
local quietTimer = nil
local anchors = {}

local function maxDb()
    local max = fact.maxVolume or -20
    local min = fact.minVolume or MIN_DB
    if max < min then max = min end
    return max, min
end

local function clampDb(value)
    local max, min = maxDb()
    local v = math.floor(value + 0.5)
    if v < min then v = min end
    if v > max then v = max end
    return v
end

local function setVolume(value)
    target = clampDb(value)
    fact.volume = target
end

local function markInput()
    quiet = false
    if quietTimer then cancel(quietTimer) end
    quietTimer = after(USER_IDLE_MS, function()
        quietTimer = nil
        quiet = true
    end)
end

local function markSent()
    cooling = true
    after(MIN_SEND_GAP_MS, function() cooling = false end)
end

local function sendAnchor()
    if busy then return end
    busy = true
    run("glm-midi", { "volume", tostring(target) .. "dB" }, function(_, code)
        busy = false
        if code ~= 0 then log("genelec: glm-midi volume exited with " .. tostring(code)) end
    end)
end

local function cancelAnchors()
    for _, id in ipairs(anchors) do cancel(id) end
    anchors = {}
end

-- The VM path: the state file first (glm-vol owns it), then the CC20 anchors.
local function commitMidi()
    run("glm-vol", { tostring(target) }, function(_, code)
        if code ~= 0 then log("genelec: glm-vol exited with " .. tostring(code)) end
    end)
    cancelAnchors()
    for _, ms in ipairs(ANCHORS_MS) do
        anchors[#anchors + 1] = after(ms, sendAnchor)
    end
end

local function commitHost()
    if busy then return end
    busy = true
    markSent()
    run("genlc", { "set-volume", "--volume", tostring(target) .. "dB" }, function(_, code)
        busy = false
        fact.available = code == 0
    end)
end

local function commit()
    if fact.midi then
        commitMidi()
    else
        commitHost()
    end
end

-- The coalescing timer: one absolute target per burst of notches (QS 150 ms),
-- pushed out when the last send is still inside the 400 ms gap.
local function scheduleCommit()
    if commitTimer then cancel(commitTimer) end
    commitTimer = after(COMMIT_MS, function()
        commitTimer = nil
        if cooling then
            commitTimer = after(MIN_SEND_GAP_MS, commit)
            return
        end
        commit()
    end)
end

-- --------------------------------------------------------------- gestures
on("turn", function(notches)
    if type(notches) ~= "number" then return end
    markInput()
    muted = false
    fact.muted = false
    setVolume(target + notches)
    scheduleCommit()
end)

on("toggle", function()
    markInput()
    if fact.midi then
        if not busy then
            busy = true
            run("glm-midi", { "mute" }, function(_, code)
                busy = false
                if code ~= 0 then log("genelec: glm-midi mute exited with " .. tostring(code)) end
            end)
        end
        muted = not muted
        fact.muted = muted
        return
    end
    if muted then
        muted = false
        fact.muted = false
        setVolume(preMute)
        commitHost()
        return
    end
    preMute = target
    muted = true
    fact.muted = true
    if busy then return end
    busy = true
    run("genlc", { "mute" }, function(_, code)
        busy = false
        if code ~= 0 then log("genelec: genlc mute exited with " .. tostring(code)) end
    end)
end)

-- ------------------------------------------------------------------ probe
-- The adapter on the host answers `genlc discover`; silence means the VM path.
local function probe()
    if busy then return end
    busy = true
    run("genlc", { "discover" }, function(_, code)
        busy = false
        local onHost = code == 0
        fact.midi = not onHost
        fact.available = onHost
    end)
end

-- --------------------------------------------------------------- read back
local function poll()
    if not quiet or muted then return end
    run("glm-vol", { "read" }, function(out)
        local value = tonumber((out or ""):match("-?%d+"))
        if value and clampDb(value) ~= target then
            setVolume(value)
        end
    end)
end

probe()
poll()
every(PROBE_MS, probe)
every(POLL_MS, poll)
