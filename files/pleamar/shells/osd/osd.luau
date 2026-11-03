-- osd.luau — what raises and lowers the pill (see osd.plm).
--
-- The scene decides for itself, from the services: the `audio` service's volume and
-- mute, and the `brightness` service's level. Every other source of a volume change
-- (the bar's capsule, its wheel, an application's mixer, wpctl) lands here the same
-- way, which is the point of doing it in a scene rather than in a bind.
--
-- The first report of a service is a baseline, never a change: a scene that flashed
-- on startup would flash on every session start and on every reload. A value that has
-- not moved is not a change either — the audio service speaks on many things (devices,
-- streams) and only the sink's own volume and mute are the pill's business.

local HIDE_MS = 1400
local hide_timer = nil
local last_volume, last_muted = nil, nil
local last_brightness = nil
local first_audio, first_brightness = true, true

local function hide()
    hide_timer = nil
    fact.shown = false
end

local function show(mode)
    fact.mode = mode
    fact.shown = true
    if hide_timer then cancel(hide_timer) end
    hide_timer = after(HIDE_MS, hide)
end

local function percent_text(value)
    value = math.max(0, math.min(1, value or 0))
    return string.format("%.0f %%", value * 100)
end

local function audio_apply(a)
    if type(a) ~= "table" then return end
    local volume = tonumber(a.volume)
    if type(volume) ~= "number" then return end
    local muted = a.muted == true
    if first_audio then
        first_audio = false
        last_volume, last_muted = volume, muted
        return
    end
    if volume == last_volume and muted == last_muted then return end
    last_volume, last_muted = volume, muted
    fact.muted = muted
    fact.level = muted and 0 or volume
    text.percent = muted and "muted" or percent_text(volume)
    text.glyph = muted and "volume_off" or "volume_up"
    show("volume")
end

local function brightness_apply(b)
    if type(b) ~= "table" then return end
    if b.present ~= true then return end
    local level = tonumber(b.level)
    if type(level) ~= "number" then return end
    if first_brightness then
        first_brightness = false
        last_brightness = level
        return
    end
    if level == last_brightness then return end
    last_brightness = level
    fact.muted = false
    fact.level = level
    text.percent = percent_text(level)
    text.glyph = "brightness_6"
    show("brightness")
end

sys.watch("audio", audio_apply)
sys.watch("brightness", brightness_apply)
