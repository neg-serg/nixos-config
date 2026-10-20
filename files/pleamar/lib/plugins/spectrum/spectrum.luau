-- spectrum.luau — the logic of the Spectrum plugin (see spectrum.plm).
--
-- What it owns: the cava process, the peak decay, and the `values` model the
-- library draws. It paints nothing and knows no coordinates (reference §4).
--
-- The QS reference this follows, number by number:
--   files/quickshell/Components/Cava.qml            cava config, 43 bars,
--                                                   framerate 30, autosens,
--                                                   gravity 20000, noise 5
--   files/quickshell/Components/LinearSpectrum.qml  peak = peak - 0.04 every
--                                                   spectrum.decay (50 ms)
--   files/quickshell/Components/IPhoneSpectrum.qml  the coloured band, mapped
--                                                   linearly across the range
--
-- Permissions come from spectrum.plm, not from the scene using it:
--   run: "cava"        — the analyser itself
--   services: "media"  — when something plays (a watch only: nothing is called)
-- Unapproved, cava is not spawned and every bar stays at zero; the console says
-- why. Approve with `pleamar --approve <scene>.plm`.

local BARS = 43          -- == model values max in spectrum.plm
local DECAY_MS = 50      -- palette spectrum.decay
local FALL = 0.04        -- LinearSpectrum: the peak falls this much per decay
local LEVEL_RANGE = 255  -- cava's ascii data_format writes 0..255 per bar

-- cava's own grammar: a raw ascii stream, one line of `;`-separated values per
-- frame. The smoothing half is the QS config untouched; `data_format = ascii`
-- is what turns the 8-bit stream into lines (the QS version read bytes).
local CAVA_CONFIG = table.concat({
    "[general]",
    "bars=" .. BARS,
    "framerate=30",
    "autosens=1",
    "[smoothing]",
    "monstercat=0",
    "gravity=20000",
    "noise_reduction=5",
    "[output]",
    "method=raw",
    "data_format=ascii",
    "channels=mono",
    "mono_option=average",
    "",
}, "\n")

local levels = {}
local peaks = {}
local lit = {}
local handle = nil      -- the cava process, or nil
local decay = nil       -- the decay timer, or nil
local playing = false

-- The band, read from the boundary facts every frame (the scene owns them).
local function band()
    local lo = fact.lowHz or 15
    local hi = fact.highHz or 24000
    local clo = fact.colorLowHz or lo
    local chi = fact.colorHighHz or hi
    if hi <= lo then hi = lo + 1 end
    for i = 1, BARS do
        -- the centre of the bin, mapped linearly like IPhoneSpectrum does
        local f = lo + (hi - lo) * (i - 0.5) / BARS
        lit[i] = f >= clo and f <= chi
    end
end

local function publish()
    local out = {}
    for i = 1, BARS do
        out[i] = {
            level = levels[i] or 0,
            peak = peaks[i] or 0,
            lit = lit[i] ~= false,
        }
    end
    model.values = out
end

-- One cava frame: `;`-separated levels, a short frame means silence.
local function on_line(line)
    local n = 0
    for token in line:gmatch("[^;]+") do
        n = n + 1
        if n > BARS then break end
        local raw = tonumber(token)
        if raw then
            local level = raw / LEVEL_RANGE
            if level < 0 then level = 0 elseif level > 1 then level = 1 end
            levels[n] = level
            if level > (peaks[n] or 0) then peaks[n] = level end
        else
            levels[n] = 0
        end
    end
    for i = n + 1, BARS do
        levels[i] = 0
    end
    band()
    publish()
end

local function on_exit(_, code)
    handle = nil
    if code ~= 0 then
        log("spectrum: cava exited with " .. tostring(code))
    end
    for i = 1, BARS do
        levels[i] = 0
        peaks[i] = 0
    end
    band()
    publish()
end

-- The peak marks fall on a timer of their own, whatever cava is doing.
local function step()
    local changed = false
    for i = 1, BARS do
        local peak = (peaks[i] or 0) - FALL
        if peak < (levels[i] or 0) then peak = levels[i] or 0 end
        if peak < 0 then peak = 0 end
        if peak ~= peaks[i] then
            peaks[i] = peak
            changed = true
        end
    end
    if changed then publish() end
end

local function start()
    if handle then return end
    local ok, id = pcall(spawn, "cava", { "-p", "/dev/stdin" }, on_line, on_exit, { input = CAVA_CONFIG })
    if not ok or not id then
        log("spectrum: cava could not be started (approve the plugin's permissions?)")
        return
    end
    handle = id
    if not decay then
        decay = every(DECAY_MS, step)
    end
end

local function stop()
    if decay then
        cancel(decay)
        decay = nil
    end
    if not handle then return end
    pcall(kill, handle)
    handle = nil
end

-- `media` reports what plays; a pause is not a stop (the QS Cava stops with
-- `MusicManager.isPlaying`, so this does the same). The watch hands the current
-- state over right away, so nothing here starts on a maybe.
if not sys.watch("media", function(m)
        playing = m ~= nil and m.playing == true
        if playing then start() else stop() end
    end) then
    -- No media service on this system: the analyser runs and reads silence.
    start()
end
