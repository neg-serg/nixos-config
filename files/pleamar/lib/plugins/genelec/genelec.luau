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
--   - the target is read back with `glm-vol read`, six looks a second, adopted only after
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

local target = fact.volume or -40
local muted = false
-- The volume the host had before the mute. A local would forget it on every restart — the plugin
-- is restarted whenever its scene reloads — and the next unmute would push -40 dB instead of what
-- was playing. QS keeps the same pair in its StateCache (`genelecPreMuteVolume`,
-- Services/Genelec.qml:55-73); here it is the plugin's own `state.json`. The mute flag itself
-- rides along: the monitors keep their state across the restart (the mute went to the adapter or
-- to the host), so a plugin that came back unmuted would mute again on the first press.
local STATE = "state.json"
local preMute = target
local busy = false
local cooling = false
local quiet = true
-- Whether `probe` has decided which transport is live. The level watcher below must not adopt
-- the legacy file before that: on load the file's first value can arrive ahead of `glm5ctl status`,
-- and with the daemon owning the adapter it is another session's number.
local daemonKnown = false
local commitTimer = nil
-- How many times the coalescing timer has come back for a send the busy slot ate; bounded so a
-- command that never answers cannot leave a timer spinning every 150 ms.
local commitRetries = 0
local quietTimer = nil
local anchors = {}

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

-- The daemon path is the same absolute target, handed to the process that already owns
-- the adapter: no state file, no MIDI anchor, and the write is paced by glm5d itself.
local function commitDaemon()
    if busy then return end
    busy = true
    markSent()
    run("glm5ctl", { "volume", tostring(target) }, function(_, code)
        busy = false
        if code ~= 0 then log("genelec: glm5ctl volume exited with " .. tostring(code)) end
    end)
end

local function commit()
    -- `busy` is the probe or a send already on the wire; each transport returns early then, and
    -- the last notch used to be dropped with it — measured 2026-11-02: the tile read -50 while
    -- `glm5ctl status` still said -49, so the monitors lagged a keypress behind. Come back for it.
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
    if fact.daemon then
        commitDaemon()
    elseif fact.midi then
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
    if fact.daemon then
        muted = not muted
        fact.muted = muted
        if not muted then setVolume(preMute) else preMute = target end
        persist()
        if busy then return end
        busy = true
        run("glm5ctl", { "mute", muted and "on" or "off" }, function(_, code)
            busy = false
            if code ~= 0 then log("genelec: glm5ctl mute exited with " .. tostring(code)) end
        end)
        return
    end
    if fact.midi then
        if not busy then
            busy = true
            run("glm-midi", { "mute" }, function(_, code)
                busy = false
                if code ~= 0 then log("genelec: glm-midi mute exited with " .. tostring(code)) end
            end)
        end
        -- The MIDI path mutes at the adapter, so the volume never leaves the monitor: what has to
        -- survive a restart is the same pair as on the host path (`preMute` above all), and this
        -- branch returned before either was written.
        if not muted then preMute = target end
        muted = not muted
        fact.muted = muted
        persist()
        return
    end
    if muted then
        muted = false
        fact.muted = false
        setVolume(preMute)
        persist()
        commitHost()
        return
    end
    preMute = target
    persist()
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
-- `glm5d` first: when the daemon owns the adapter it is the only path that can hold the
-- sessions (a lease lapses ~2.5 s after the monitor's last answer, which is why the daemon
-- exists at all), so it wins over both older transports. `glm5ctl status` exits 0 only when
-- the socket answers.
-- Fallback, unchanged: the adapter on the host answers `genlc discover`; silence means the
-- VM path.
-- Forward-declared: `probe`'s callback calls the legacy probe, and the success branch re-reads
-- the level from the daemon; both are written below. A `local function` written after `probe`
-- would leave `probe`'s body looking at a global, which is nil when the callback runs — that is
-- the "attempt to call a nil value" line 256 used to die on every 30 s while `glm5d` was down.
local probeLegacy
local adoptLevel

local function probe()
    if busy then return end
    busy = true
    run("glm5ctl", { "status" }, function(_, code)
        busy = false
        if code == 0 then
            fact.daemon = true
            fact.midi = false
            fact.available = true
            daemonKnown = true
            -- The daemon may have come up after this scene loaded, when `adoptLevel` ran and
            -- had to fall back to the legacy file; once it answers, its own last broadcast is
            -- the level the monitors actually stand at, so the first notch starts from it.
            adoptLevel()
            return
        end
        fact.daemon = false
        daemonKnown = true
        probeLegacy()
    end)
end

function probeLegacy()
    if busy then return end
    busy = true
    run("genlc", { "discover" }, function(_, code)
        busy = false
        local onHost = code == 0
        fact.midi = not onHost
        -- `available` is `adapterOnHost ? genlcOk : true` in the reference (Services/Genelec.qml:50):
        -- through the bridge the tile is never dimmed, because an adapter inside the dockur VM is this
        -- host's normal arrangement, not a failure. On the host path `onHost` *is* genlcOk, and a write
        -- that fails there still takes the tile's ink away (`commitHost`).
        fact.available = true
    end)
end

-- --------------------------------------------------------------- read back
-- The level lives in a state file anything may write (`glm-vol -43` in a terminal, this
-- plugin, another shell), and the reference *watched* it: its `FileView` reported a change the
-- moment it happened. Reading it with a fresh process every two seconds was both late — the
-- number stood still while somebody turned the knob — and a fork each time.
--
-- One `bash` for the life of the scene, six looks a second, printing only what changed: the
-- immediacy of a watch without a process per look.
local function watchLevel()
    local script = "f=\"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/genlc-volume\"\nlast=\"\"\nwhile :; do\n  v=$(cat \"$f\" 2>/dev/null)\n  if [ -n \"$v\" ] && [ \"$v\" != \"$last\" ]; then printf \"%s\n\" \"$v\"; last=\"$v\"; fi\n  sleep 0.15\ndone"
    spawn("bash", { "-c", script }, function(line)
        local value = tonumber((line or ""):match("-?%d+"))
        if not value then return end
        -- A level that arrives while the wheel is still moving is somebody else's and must not
        -- fight the gesture in flight. One that arrives while the plugin thinks it is muted is the
        -- knob being turned, and the reference unmutes on that; `genlc-media` steps the file but
        -- never unmutes, so the flag is cleared here. The plugin only adopts the number: the sender
        -- has already put it on the wire, and sending it again would double the CC20 burst.
        if not quiet then return end
        -- With `glm5d` owning the adapter this file is the VM path's history, not this session's:
        -- the daemon's own broadcast is the truth (`adoptLevel`). Adopting the file here overwrote
        -- it on load — measured 2026-11-02: file -60, daemon -30, the fact came up -60 and the
        -- first notch collapsed the monitors into the file's stale number.
        if not daemonKnown then return end
        if fact.daemon then return end
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
-- brings back the mute pair, `probe()` only decides which path is live, and `fact.volume` kept the
-- scene's own -40 while the monitors stood where the last shell left them — so the tile showed a
-- number nobody had set and the first wheel notch jumped the monitors to it. `glm-vol read` is the
-- same answer the reference widget used (its state file, then the old shell's cache); it asks the
-- monitors nothing, because `glm-midi` has no read and `genlc` only answers with the adapter on
-- this host.
--
-- The daemon answers first when it owns the adapter: `glm5ctl status` reports the level it last
-- broadcast, while the legacy file is written by the VM path alone and can hold another session's
-- target — on 2026-11-02 the file said -56 while the monitors stood at the level GLM had left
-- them, and the first notch collapsed them to the file's number.
function adoptLevel()
    -- Not while a gesture is in flight: the daemon's answer is the last thing sent, and it must
    -- not pull the target back from under the wheel.
    if not quiet then return end
    run("glm5ctl", { "status" }, function(out, code)
        if code == 0 then
            local db = tonumber(tostring(out or ""):match("volume%s+(-?%d+%.?%d*)%s*dB"))
            if db and not muted then
                local v = clampDb(db)
                if v ~= target then setVolume(v) end
                return
            end
        end
        run("glm-vol", { "read" }, function(out2, code2)
            if code2 ~= 0 then return end
            local value = tonumber((out2 or ""):match("-?%d+"))
            if not value then return end
            -- A muted adapter keeps the level it will come back to; adopting one would unmute it by
            -- proxy on the next wheel notch.
            if muted then return end
            local v = clampDb(value)
            if v ~= target then setVolume(v) end
        end)
    end)
end

restore()
adoptLevel()
probe()
watchLevel()
every(PROBE_MS, probe)
