-- genelec.luau — the logic of the Genelec plugin (see genelec.plm).
--
-- Port of the parts of files/quickshell/Services/Genelec.qml that decide what
-- goes to the monitors, with the QS numbers:
--
--   - whole dB only (GLM CC20 is an integer), clamped to [-95, maxVolume];
--   - commits coalesce: 150 ms after the last wheel notch, never closer than
--     400 ms to the previous send (GLM drops messages that arrive in a burst);
--   - one transport: `genlc volume <dB>` owns the write. It stores the target in
--     $XDG_RUNTIME_DIR/genlc-volume and routes it itself — to the daemon's
--     socket when the daemon holds the adapter, straight to the HID adapter
--     otherwise — so the plugin names the absolute target and does not care
--     which path is live;
--   - the target is read back from that same state file with
--     `genlc volume --show`, watched with `genlc volume --watch`, adopted only
--     after the wheel has been quiet for 2.5 s and never while muted (the port
--     of the QS FileView watch and its user-input guard);
--   - mute is `genlc mute on|off`, routed by genlc the same way.
--
-- Timing is kept in one-shot timers and flags: the sandbox closes `os`, so the
-- logic has no clock of its own.
--
-- Permissions are the plugin's own: genlc, files, files.write.

local MIN_DB = -95
local USER_IDLE_MS = 2500
local COMMIT_MS = 150
local MIN_SEND_GAP_MS = 400

local target = fact.volume or -40
local muted = false
-- The volume the host had before the mute. A local would forget it on every restart — the plugin
-- is restarted whenever its scene reloads — and the next unmute would push -40 dB instead of what
-- was playing. QS keeps the same pair in its StateCache (`genelecPreMuteVolume`,
-- Services/Genelec.qml:55-73); here it is the plugin's own `state.json`. The mute flag itself
-- rides along: the monitors keep their state across the restart (the mute went to the adapter),
-- so a plugin that came back unmuted would mute again on the first press.
local STATE = "state.json"
local preMute = target
local busy = false
local cooling = false
local quiet = true
local commitTimer = nil
-- How many times the coalescing timer has come back for a send the busy slot ate; bounded so a
-- command that never answers cannot leave a timer spinning every 150 ms.
local commitRetries = 0
local quietTimer = nil

local function persist()
    local ok, err = pcall(sys.call, "files.write", STATE, { preMute = preMute, target = target, muted = muted })
    if not ok then log("genelec: state not saved: " .. tostring(err)) end
end

local function restore()
    local ok, state = pcall(sys.ask, "files.read", STATE, "json")
    if not ok or type(state) ~= "table" then return end
    local pre = tonumber(state.preMute)
    if pre and pre ~= preMute then preMute = pre end
    -- Adopted only with a `preMute` beside it: an unmute with no level to come back to would push
    -- the -40 default over whatever was playing.
    if state.muted == true and pre then
        muted = true
        fact.muted = true
    end
end

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

-- The one write: genlc sends the absolute target and writes the state file the widget reads, so
-- a failed command is the only thing that can take the tile's ink away.
local function commit()
    -- `busy` is a send already on the wire. The last notch used to be dropped with it — measured
    -- 2026-11-02: the tile read -50 while the daemon still said -49, so the monitors lagged a
    -- keypress behind. Come back for it.
    if busy then
        if commitRetries >= 8 then
            commitRetries = 0
            return
        end
        commitRetries = commitRetries + 1
        if commitTimer then cancel(commitTimer) end
        commitTimer = after(COMMIT_MS, function()
            commitTimer = nil
            commit()
        end)
        return
    end
    commitRetries = 0
    busy = true
    markSent()
    run("genlc", { "volume", tostring(target) }, function(_, code)
        busy = false
        fact.available = code == 0
    end)
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

-- ------***------------------------ gestures
-- A high-resolution wheel reports fractions of a notch (libinput sends e.g. 0.4 per detent),
-- while the monitors take whole dB. The remainder is carried to the next event instead of being
-- rounded away: three 0.4 detents used to be three no-ops, so the tile's number stood still while
-- the wheel was turning.
local wheelAcc = 0
on("turn", function(notches)
    if type(notches) ~= "number" then return end
    markInput()
    -- A wheel turn unmutes (QS): the flag and the file follow, or a restart would come back
    -- muted over monitors that are not. Written only on the flip — a notch is no reason to write.
    local wasMuted = muted
    muted = false
    fact.muted = false
    wheelAcc = wheelAcc + notches
    local steps = 0
    if wheelAcc >= 1 then
        steps = math.floor(wheelAcc)
    elseif wheelAcc <= -1 then
        steps = math.ceil(wheelAcc)
    end
    if steps == 0 then
        if wasMuted then persist() end
        return
    end
    wheelAcc = wheelAcc - steps
    local before = target
    setVolume(target + steps)
    -- The clamp ate the step (the wheel is already at the top or the floor): drop the carried
    -- remainder too, or the wheel would have to unwind a backlog before the number moves again.
    if target == before then wheelAcc = 0 end
    if wasMuted then persist() end
    scheduleCommit()
end)

on("toggle", function()
    markInput()
    muted = not muted
    fact.muted = muted
    if not muted then setVolume(preMute) else preMute = target end
    persist()
    -- A mute must not wait for the `busy` slot: a coalesced commit can hold it, and the flag has
    -- already flipped on the tile — a dropped command would leave monitors that never muted. The
    -- daemon serializes its own queue, and the direct path is one command, so the mute goes out
    -- without the guard.
    run("genlc", { "mute", muted and "on" or "off" }, function(_, code)
        if code ~= 0 then log("genelec: genlc mute exited with " .. tostring(code)) end
    end)
end)

-- ------***------------------------ read back
-- The level lives in $XDG_RUNTIME_DIR/genlc-volume, which `genlc volume` owns and anything may
-- write (a terminal, this plugin, the media keys). The reference *watched* that file: its
-- `FileView` reported a change the moment it happened. Reading it with a fresh process every two
-- seconds was both late — the number stood still while somebody turned the knob — and a fork each
-- time.
--
-- One process for the life of the scene, printing only what changed: the immediacy of a watch
-- without a process per look. `genlc volume --watch` is that process, so no interpreter is
-- involved.
local function watchLevel()
    spawn("genlc", { "volume", "--watch" }, function(line)
        local value = tonumber((line or ""):match("-?%d+%.?%d*"))
        if not value then return end
        -- A level that arrives while the wheel is still moving is somebody else's and must not
        -- fight the gesture in flight. One that arrives while the plugin thinks it is muted is the
        -- knob being turned, and the reference unmutes on that; the writer has already put the
        -- level on the wire, so the plugin only adopts the number — sending it again would double
        -- the CC20 burst.
        if not quiet then return end
        local v = clampDb(value)
        if v == target then return end
        if muted then
            muted = false
            fact.muted = false
            persist()
        end
        setVolume(v)
    end)
end

-- The level a fresh scene starts from. Nothing in the plugin could tell it before: `restore()`
-- brings back the mute pair, `fact.volume` kept the scene's own -40 while the monitors stood where
-- the last shell left them — so the tile showed a number nobody had set and the first wheel notch
-- jumped the monitors to it. `genlc volume --show` answers from the state file every writer
-- maintains, and asks the monitors nothing.
function adoptLevel()
    -- Not while a gesture is in flight: the file holds the last thing sent, and it must not pull
    -- the target back from under the wheel.
    if not quiet then return end
    run("genlc", { "volume", "--show" }, function(out, code)
        if code ~= 0 then return end
        local value = tonumber((out or ""):match("-?%d+%.?%d*"))
        if not value then return end
        -- A muted adapter keeps the level it will come back to; adopting one would unmute it by
        -- proxy on the next wheel notch.
        if muted then return end
        local v = clampDb(value)
        if v ~= target then setVolume(v) end
    end)
end

restore()
adoptLevel()
watchLevel()
