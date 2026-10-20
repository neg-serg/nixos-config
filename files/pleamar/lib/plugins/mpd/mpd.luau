-- mpd.luau — the logic of the MPD flags plugin (see mpd.plm).
--
-- Legacy: files/quickshell/Bar/Modules/MpdFlags.qml. `mpc status` is parsed for
-- the five options and the state; the watch is `mpc idle options player`, which
-- prints a line per subsystem change, and the 2500 ms fallback poll is the QS
-- `timers` tick (`mpd.flags`) for a missed or unsupported idle.
--
-- Deviation, on purpose: the QS command was `(mpc status || rmpc status)`; this
-- plugin speaks mpc only (one binary, one permission), and when mpc cannot reach
-- MPD it says `available = false` instead of asking a second client.
--
-- Permissions are the plugin's own: mpc.

local FALLBACK_MS = 2500

local idle = nil
local refreshing = false

local function isOn(value)
    if value == nil then return false end
    local text = tostring(value):lower()
    return text == "on" or text == "1" or text == "true" or text == "one"
end

local function xfadeOn(value)
    if value == nil then return false end
    local number = tonumber(value)
    if number then return number > 0 end
    return isOn(value)
end

local function apply(text)
    text = text or ""
    local state = text:match("%[(playing)%]")
        or text:match("%[(paused)%]")
        or text:match("%[(stopped)%]")
        or text:match("state:%s*(playing)")
        or text:match("state:%s*(paused)")
        or text:match("state:%s*(stopped)")
    fact.state = state or "unknown"
    fact.repeat = isOn(text:match("repeat:%s*(%w+)"))
    fact.random = isOn(text:match("random:%s*(%w+)"))
    fact.single = isOn(text:match("single:%s*(%w+)"))
    fact.consume = isOn(text:match("consume:%s*(%w+)"))
    fact.xfade = xfadeOn(text:match("xfade:%s*(%w+)"))
end

local function refresh()
    if refreshing then return end
    refreshing = true
    run("mpc", { "status" }, function(out, code)
        refreshing = false
        fact.available = code == 0
        if code == 0 then apply(out) end
    end)
end

-- `mpc idle` answers one line per change and keeps running; one line is enough
-- of a signal to ask for the whole status again (the parser is the only reader).
local function startIdle()
    if idle then return end
    local ok, handle = pcall(spawn, "mpc", { "-q", "idle", "options", "player" }, function()
        refresh()
    end, function()
        idle = nil
        -- mpc exits when MPD restarts or the socket drops: re-arm after the QS
        -- backoff; the fallback poll keeps the badges honest meanwhile.
        after(250, startIdle)
    end)
    if ok then idle = handle end
end

refresh()
startIdle()
every(FALLBACK_MS, refresh)
