-- panels.luau — the logic behind panels.plm (PH2-B slice 1).
--
-- What the declarative scene cannot do itself:
--   · read settings.json and push defaults/clamps into the drawing facts;
--   · start a worker while one of the three worker-backed drawers is open and
--     kill it the moment the drawer closes;
--   · turn worker samples into the live texts and models the drawers draw;
--   · carry mixer presses/drags to the `audio` service commands.
--
-- Workers (INTERFACES.md §7; installed into PATH as pleamar-<name> and spawned
-- by that bare name):
--   system   -> pleamar-sysmon    topic sysmon      one sample per second
--   weather  -> pleamar-weather   topic weather     refreshed every five minutes
--   calendar -> pleamar-calendar  topic calendar    one month, month navigation
-- Each worker writes a `{"ok":true,"worker":…,"version":1,…}` handshake first;
-- a version this scene does not know kills the worker and is reported. On
-- start the scene subscribes with the cadence it wants (`{"cmd":"subscribe",
-- "topic":…,"interval_ms":…,"month":…}`), on a month change it asks
-- `{"cmd":"sample","month":…}`, on close it writes `{"cmd":"stop"}` and sends
-- SIGTERM. Samples are `{"ok":true,"worker":…,"topic":…,"t":…,"data":{…}}` and
-- failures keep the worker alive: `{"ok":false,"worker":…,"err":…}`.
-- The deprecated draft shape (`{"ok":{…}}`, no handshake) is still accepted so
-- a scene does not break against the older helpers, but §7 is the contract.
-- A helper that is not installed (spawn fails) or that keeps dying leaves the
-- drawer in its documented "not available"/offline state: `cal.err`,
-- `weather.err` or `sysmon.err` says so and no data is invented.
--
-- The audio service needs no worker: the scene binds `service audio` for the
-- drawing; this logic watches it only to remember the stream/device `id`s the
-- service commands take (event payloads are numbers, ids are texts).

-- ======================= settings =======================

local FILE = "settings.json"

-- ======================= the live palette =======================
-- `pleamar-themes push` leaves the theme's channels in this scene's own folder
-- (a scene reads only its own), and the scene draws lib/palette-live.plm's
-- `live.*` colours from the facts named here. A theme change is then a change of
-- facts: no file is rewritten and nothing reloads. The poll is one small read
-- every two seconds; a value that has not moved is not written again.
local PALETTE_ROLES = { "coal", "surface", "ink", "ink_dim", "accent", "on_accent" }
-- The warmth slider writes through the tool; until its run answers, a poll of
-- `palette.json` must not drag the knob back to the old temperature.
local warm_hold = false
local warm_timer = nil

local function palette_load()
    local ok, palette = pcall(function()
        return sys.ask("files.read", "palette.json", "json")
    end)
    if not ok or type(palette) ~= "table" then return end
    for _, role in ipairs(PALETTE_ROLES) do
        for _, channel in ipairs({ "r", "g", "b" }) do
            local value = palette[role .. "_" .. channel]
            local name = "pal_" .. role .. "_" .. channel
            if type(value) == "number" and fact[name] ~= value then
                fact[name] = value
            end
        end
    end
    if type(palette.light) == "number" and fact.pal_light ~= palette.light then
        fact.pal_light = palette.light
    end
    -- A light theme's paper is worked out from its warmth; the tool leaves the
    -- number it used in the palette, and the slider shows it.
    if type(palette.temperature) == "number" and not warm_hold then
        local value = math.min(math.max((palette.temperature - 2700) / 3800, 0), 1)
        if fact.warm ~= value then fact.warm = value end
        text["theme.warm"] = string.format("%.0f K", palette.temperature)
    end
end

palette_load()
every(2000, palette_load)


-- Defaults live here; the file holds only what the user changed.
local D = {
    closeOnEscape = true,
    closeOnOutside = true,
    scale = 1.0,                       -- user multiplier on top of ui and the fit
    fontScale = 1.0,                   -- multiplies type.* sizes
    weatherCity = "Saint Petersburg",  -- the legacy Quickshell default
    useFahrenheit = false,
    calendarCountry = "ru",            -- ISO country for the holiday list and the work calendar; empty: neither
}

local conf = { weatherCity = D.weatherCity, calendarCountry = D.calendarCountry }
-- The file as it was read, unknown keys and all: a save writes this table back
-- with the seven known keys replaced, so a key another version put there survives.
local raw_conf = {}

local function num(v, lo, hi, def)
    if type(v) ~= "number" or v ~= v then return def end
    return math.max(lo, math.min(hi, v))
end

local function str(v, def)
    if type(v) ~= "string" then return def end
    return v
end

local function flag(v, def)
    if type(v) ~= "boolean" then return def end
    return v
end

local function read_settings()
    local raw = {}
    local ok, got = pcall(function() return sys.ask("files.read", FILE, "json") end)
    if ok and type(got) == "table" then
        raw = got
    elseif not ok then
        log("panels: settings.json is broken; defaults kept")
    end
    return raw
end

local function apply_settings()
    local raw = read_settings()
    raw_conf = raw
    fact.close_on_escape = flag(raw.closeOnEscape, D.closeOnEscape)
    fact.close_on_outside = flag(raw.closeOnOutside, D.closeOnOutside)
    fact.zoom = num(raw.scale, 0.5, 2.0, D.scale)
    fact.text_scale = num(raw.fontScale, 0.5, 2.0, D.fontScale)
    fact.use_fahrenheit = flag(raw.useFahrenheit, D.useFahrenheit)
    fact.night_light = flag(raw.nightLight, false)
    conf.weatherCity = str(raw.weatherCity, D.weatherCity)
    conf.calendarCountry = str(raw.calendarCountry, D.calendarCountry)
    -- The two fields on the shell page show what the file says (a write of ours
    -- arrives here too; the same string is not a caret reset).
    text.city = conf.weatherCity
    text.country = conf.calendarCountry
end

apply_settings()
-- Another copy, or an editor, changed the file: re-read and re-apply.
sys.watch("files:" .. FILE, function() apply_settings() end)

-- ==================== the night light ====================
-- `wlsunset` shifts the screen's temperature; it runs until killed, so it is one spawned process
-- for as long as the switch is on. The scene owns it: this logic started it, this logic kills it.
local night_pid = nil

local function night_apply(on)
    if on and not night_pid then
        local ok, id = pcall(spawn, "wlsunset", { "-t", "3500", "-T", "6500" }, function() end, function()
            night_pid = nil
        end)
        if ok then
            night_pid = id
        else
            log("panels: wlsunset did not start: " .. tostring(id))
        end
    elseif not on and night_pid then
        pcall(kill, night_pid)
        night_pid = nil
    end
end

apply_settings()

night_apply(fact.night_light)

-- ======================= small helpers =======================

local MONTHS = { "January", "February", "March", "April", "May", "June",
                 "July", "August", "September", "October", "November", "December" }
local WDAY = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local DIM = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local function leap(y)
    return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0
end

local function days_in_month(y, m)
    if m == 2 and leap(y) then return 29 end
    return DIM[m]
end

-- Zeller: 0 = Sunday. Deterministic and timezone-free.
local function weekday(y, m, d)
    local yy, mm = y, m
    if mm < 3 then mm = mm + 12; yy = yy - 1 end
    local k = yy % 100
    local j = math.floor(yy / 100)
    local h = (d + math.floor(13 * (mm + 1) / 5) + k + math.floor(k / 4) + math.floor(j / 4) + 5 * j) % 7
    return (h + 6) % 7
end

local function pad2(n)
    if n < 10 then return "0" .. tostring(n) end
    return tostring(n)
end

-- ISO first, then the legacy locale format the khal bug produced (M13):
-- `pleamar-calendar` normalises dates to ISO, and this tolerance means a worker
-- that has not normalised yet still shows its events instead of dropping them.
local function isodate_parts(s)
    if type(s) ~= "string" or #s < 10 then return nil end
    if string.sub(s, 5, 5) == "-" and string.sub(s, 8, 8) == "-" then
        local y = tonumber(string.sub(s, 1, 4))
        local m = tonumber(string.sub(s, 6, 7))
        local d = tonumber(string.sub(s, 9, 10))
        if y and m and d then return y, m, d end
        return nil
    end
    if string.sub(s, 3, 3) == "." and string.sub(s, 6, 6) == "." then
        local d = tonumber(string.sub(s, 1, 2))
        local m = tonumber(string.sub(s, 4, 5))
        local y = tonumber(string.sub(s, 7, 10))
        if y and m and d then return y, m, d end
    end
    return nil
end

local function fmt0(x)
    if type(x) ~= "number" or x ~= x then return "--" end
    return tostring(math.floor(x + 0.5))
end

local function fmt1(x)
    if type(x) ~= "number" or x ~= x then return "--" end
    return tostring(math.floor(x * 10 + 0.5) / 10)
end

local function rate_kibs(x)
    if type(x) ~= "number" or x ~= x then return "--" end
    if x >= 1024 then return fmt1(x / 1024) .. " MiB/s" end
    return fmt0(x) .. " KiB/s"
end

local function tone(level, warn_at, crit_at)
    if level >= crit_at then return 2 end
    if level >= warn_at then return 1 end
    return 0
end

-- WMO weather codes, as Open-Meteo and wttr.in report them.
local function cond_text(code)
    if type(code) ~= "number" then return "--" end
    if code == 0 then return "Clear sky" end
    if code == 1 then return "Mainly clear" end
    if code == 2 then return "Partly cloudy" end
    if code == 3 then return "Overcast" end
    if code == 45 or code == 48 then return "Fog" end
    if code >= 51 and code <= 57 then return "Drizzle" end
    if code >= 61 and code <= 67 then return "Rain" end
    if code >= 71 and code <= 77 then return "Snow" end
    if code >= 80 and code <= 82 then return "Rain showers" end
    if code >= 85 and code <= 86 then return "Snow showers" end
    if code >= 95 and code <= 99 then return "Thunderstorm" end
    return "Weather"
end

-- The moon, as `Helpers/WeatherIcons.js` works it: the phase from the new moon of 2000-01-06 18:14
-- UTC (the same reference the bar's capsule counts from), the illumination as 50 * (1 - cos), and
-- the eight names the reference's details row prints.
local MOON_NAMES = { "New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
                     "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent" }

local function moon_phase(epoch)
    if type(epoch) ~= "number" then return 0 end
    local days = (epoch - 947182440) / 86400
    local cycles = days / 29.53059
    local frac = cycles - math.floor(cycles)
    if frac < 0 then frac = frac + 1 end
    return frac
end

local function moon_illumination(phase)
    return 50 * (1 - math.cos(2 * math.pi * phase))
end

local function moon_name(phase)
    -- `Math.round(age * 8) % 8` of the reference: the eighth nearest phase, and 8 wraps to 0.
    local i = math.floor(phase * 8 + 0.5) % 8
    return MOON_NAMES[i + 1]
end

-- The Material Symbols name for a WMO code, the property of `WeatherIcons.materialSymbolForCode`
-- (Helpers/WeatherIcons.js: the same ladder the bar's capsule draws from). The card wants a picture
-- beside the words, and a ligature is how this tree draws one.
local function cond_glyph(code)
    if type(code) ~= "number" then return "cloud" end
    if code == 0 then return "sunny" end
    if code <= 2 then return "partly_cloudy_day" end
    if code == 3 then return "cloud" end
    if code == 45 or code == 48 then return "foggy" end
    if code <= 57 then return "rainy" end
    if code <= 67 then return "rainy" end
    if code <= 77 then return "weather_snowy" end
    if code <= 82 then return "rainy" end
    if code >= 95 then return "thunderstorm" end
    return "cloud"
end

local function cond_short(code)
    if type(code) ~= "number" then return "--" end
    if code == 0 then return "Clear" end
    if code <= 2 then return "Cloudy" end
    if code == 3 then return "Overcast" end
    if code == 45 or code == 48 then return "Fog" end
    if code <= 57 then return "Drizzle" end
    if code <= 67 then return "Rain" end
    if code <= 77 then return "Snow" end
    if code <= 82 then return "Showers" end
    if code <= 86 then return "Snow" end
    if code >= 95 then return "Storm" end
    return "Weather"
end

local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local function wind_dir(deg)
    if type(deg) ~= "number" or deg ~= deg then return "" end
    local i = math.floor((deg % 360) / 45 + 0.5) % 8
    return COMPASS[i + 1] .. " "
end

-- ======================= the audio service =======================
-- sys.watch gives the raw records (with ids); the service-bound models are a
-- fallback, in case the watch starts before the service is there.

local audio_raw = { outputs = {}, inputs = {}, apps = {} }
local audio_watch = false

local function ensure_audio_watch()
    if audio_watch then return end
    audio_watch = sys.watch("audio", function(a)
        if type(a) == "table" then audio_raw = a end
    end) ~= false
end

local DRAWER_IDLE_MS = 20000
local drawer_timer = nil

local function hide_drawer()
    if drawer_timer then
        cancel(drawer_timer)
        drawer_timer = nil
    end
    if fact.drawer ~= "none" then fact.drawer = "none" end
end

-- Whatever the hand did inside a card: the card stays, the clock restarts. Every event a drawer's
-- zones emit passes through here, and so do the two facts the scene changes on a press (the chosen
-- day and the page), which the logic watches below.
local function touch_drawer()
    if fact.drawer == "none" then return end
    if drawer_timer then cancel(drawer_timer) end
    drawer_timer = after(DRAWER_IDLE_MS, hide_drawer)
end
local function pick_rec(raw, model_rec, i)
    local rec = nil
    if type(raw) == "table" then rec = raw[i + 1] end
    if not rec and type(model_rec) == "table" then rec = model_rec[i + 1] end
    return rec
end

on("set_out", function(v)
    touch_drawer()
    sys.call("audio.volume", v)
end)
on("set_in", function(v)
    touch_drawer()
    sys.call("audio.input", v)
end)
on("toggle_out", function()
    touch_drawer()
    sys.call("audio.mute")
end)
on("toggle_in", function()
    touch_drawer()
    sys.call("audio.input_mute")
end)

-- The service hands a device's `id` as a NUMBER (PulseAudio's own index:
-- `platform/pulse.rs` builds `SysValue::Num(i.index)`), so a guard that took only strings
-- refused every id the service sent: the tiles and the app rows were drawn, clicked, and
-- nothing happened. On 2026-10-25 the default sink did not move through the drawer at all
-- (`pw-dump` still said `game-stereo` after `set_default_out 0` and `1`).
local function idOf(rec)
    if type(rec) ~= "table" then return nil end
    local id = rec.id
    if type(id) == "string" or type(id) == "number" then return id end
    return nil
end

on("set_default_out", function(i)
    local id = idOf(pick_rec(audio_raw.outputs, model.sinks, i))
    if id then sys.call("audio.default", id) end
end)
on("set_default_in", function(i)
    local id = idOf(pick_rec(audio_raw.inputs, model.sources, i))
    if id then sys.call("audio.default", id) end
end)

-- app_set packs the stream index and the volume into one number
-- (index * 1001 + round(volume * 1000)); an event payload is a number only. The odd base is what
-- keeps 100 % on its own stream: with 1000 the payload for the last step of stream `i` read as
-- the first step of stream `i + 1`, so dragging a slider to the right silenced its neighbour.
on("app_set", function(p)
    local i = math.floor(p / 1001)
    local v = (p % 1001) / 1000
    local rec = pick_rec(audio_raw.apps, model.streams, i)
    local id = idOf(rec)
    if id then sys.call("audio.app_volume", id, v) end
end)
on("app_mute", function(i)
    local rec = pick_rec(audio_raw.apps, model.streams, i)
    local id = idOf(rec)
    if id then sys.call("audio.app_mute", id) end
end)

-- ========================= the media service =========================
-- The now-playing card's identity rows (pages/media.plm). A scene cannot ask
-- whether a text is empty (the language compares numbers), and an icon with no
-- value is the defect that rule exists to avoid — so the emptiness test lives
-- here and the card draws only the rows it is handed.
--
-- Two rows come from the service itself (artist, album — MPRIS through
-- `media`); the rest of the reference's rows are the Meta plugin's, and a scene
-- cannot read a plugin's texts or facts from its logic (a plugin only sees what
-- its own library declares, and the other way round it exports only what its
-- .plm names). So the plugin hands its rows over as a model and the card draws
-- `Meta.rows` beside these. An icon with nothing after it is what neither side
-- may produce: the emptiness test happens where the values are.

-- What the card needs besides its rows: the length, so a press on the progress band can be turned
-- into a position. `media.length` is in seconds (the same unit `media.position` is reported in, and
-- the same one `media.seek` takes).
--
-- The position is kept here and carried on a second at a time while the player plays: the service
-- reports `position` only when the player says something (a pause, a seek, a new song), so a card
-- drawing the service's value stood still under a playing track — measured 2026-10-25 on MPD, where
-- `media.position` stayed at 2 while `mpc` counted 4:34. `bar.luau` does the same for its capsule.
local mediaNow = {}
local mediaPos = 0
local mediaPlaying = false

local function media_apply(m)
    if type(m) == "table" then
        mediaNow = m
        if type(m.position) == "number" then mediaPos = math.floor(m.position) end
        mediaPlaying = m.playing == true
        fact["media.pos"] = mediaPos
    end
    local rows = {}
    local function add(glyph, value)
        if type(value) == "string" and value ~= "" then
            rows[#rows + 1] = { glyph = glyph, value = value }
        end
    end
    if type(m) == "table" then
        add("person", m.artist)
        add("album", m.album)
    end
    model.media_rows = rows
end

sys.watch("media", media_apply)

-- A second per tick while the player plays, resynced from every report the service does send.
every(1000, function()
    if not mediaPlaying then return end
    mediaPos = mediaPos + 1
    fact["media.pos"] = mediaPos
end)

-- A press or a drag on the media card's progress band (pages/media.plm): QS's `seekFromX` maps the
-- pointer to a fraction of the track and calls `MusicManager.seek`.
--
-- The service refuses a player whose `CanSeek` is false with a runtime error in the journal (MPD's
-- MPRIS answers false while stopped, measured 2026-10-25: "mpd.instance4313 cannot seek"), and a
-- stream has no length to seek in at all, so both are checked here instead of asking for a seek
-- that will be refused. The band says the same thing on screen: its label and its cursor follow
-- `can_seek`.
--
-- Where the request lands is the player's business: pleamar sends `SetPosition` to a track that has
-- an id and `Seek` by the difference otherwise, and mpd-mpris (which has no id and reports a stale
-- `Position`) lands ~90 s off — measured: a press at the middle of a 525.8 s track ended at 353 s.
-- The fraction this scene computes was 0.5 exactly, so nothing here is off; a player that reports
-- where it is seeks exactly.
-- (permissions: "media", "media.*")
on("seek", function(frac)
    touch_drawer()
    if type(frac) ~= "number" then return end
    if mediaNow.can_seek ~= true then return end
    local length = tonumber(mediaNow.length) or 0
    if length <= 0 then return end
    local f = math.max(0, math.min(1, frac))
    local to = length * f
    sys.call("media.seek", to)
    -- The card's own position jumps at once, whatever the player reports back: a player that never
    -- says `Seeked` (MPD's MPRIS is one) would otherwise leave the line where it was.
    mediaPos = math.floor(to)
    fact["media.pos"] = mediaPos
end)

-- ==================== the session menu ====================

-- The five actions of pages/power.plm. Four are the engine's own commands; lock lifts the shell's
-- lock scene through its unit (the documented way to raise it — `session.lock` asks logind, and
-- nothing in this session answers that request with the pleamar lock). Lock closes the drawer
-- itself: the lock surface covers the monitor, and a drawer left open behind it would come back
-- when the screen is unlocked.
local function session_call(command)
    local ok, err = pcall(function() sys.call(command) end)
    if not ok then log("panels: " .. command .. " failed: " .. tostring(err)) end
end

on("power_suspend", function() session_call("session.suspend") end)
on("power_logout", function() session_call("session.logout") end)
on("power_reboot", function() session_call("session.reboot") end)
on("power_poweroff", function() session_call("session.poweroff") end)
on("power_lock", function()
    hide_drawer()
    local ok, err = pcall(function()
        run("systemctl", { "--user", "start", "pleamar-lock.service" }, function(_, code)
            if code ~= 0 then log("panels: the lock unit did not start (" .. tostring(code) .. ")") end
        end)
    end)
    if not ok then log("panels: the lock unit did not start: " .. tostring(err)) end
end)

-- ==================== bluetooth ====================

-- The `bluetooth` drawer's commands. The page carries a row INDEX — its rows are drawn from the
-- service's `bt_devices` model — so the address is read back from that model: the row the press was
-- on screen in is the record the command goes to. (`bt_raw` below is the same service's own order,
-- kept for the pending/error watch; it is not the list the rows are indexed by.)
local bt_raw = { devices = {} }

-- One attempt at a time. `bluetooth.connect` answers before the device is up — the engine pairs and
-- connects on a thread of its own, seconds later — and a failure reaches its journal, not this
-- scene. So the attempt is kept here: which row, connect or disconnect, and a deadline. While it
-- runs the row says so, and a second press is the same attempt rather than a new one; BlueZ used to
-- answer that repeat with `br-connection-busy`, which looked like a button that did nothing.
local bt_attempt = { address = nil, kind = nil, name = "", timer = nil }
local BT_CONNECT_MS = 25000
local BT_DISCONNECT_MS = 12000
local BT_PAIR_MS = 30000

local function bt_attempt_clear()
    if bt_attempt.timer then cancel(bt_attempt.timer) end
    bt_attempt.address, bt_attempt.kind, bt_attempt.name, bt_attempt.timer = nil, nil, "", nil
    fact.bt_pending = -1
    fact.bt_pending_kind = 0
    text.bt_pending_name = ""
end

local function bt_attempt_failed(what)
    local name = bt_attempt.name
    -- The patched engine carries BlueZ's own words for the last failed connect; when it does,
    -- that is the truth to show, and the timeout is only the fallback for an engine without it.
    local why = type(bt_raw.error) == "string" and bt_raw.error or ""
    bt_attempt_clear()
    fact.bt_failed = true
    if why ~= "" then
        if name ~= "" then
            text.bt_error = name .. ": " .. why
        else
            text.bt_error = why
        end
        return
    end
    text.bt_error = what
    if name ~= "" then text.bt_error = what .. ": " .. name end
end

local function bt_attempt_arm(ms)
    if not bt_attempt.address then return end
    if bt_attempt.timer then cancel(bt_attempt.timer) end
    local address = bt_attempt.address
    bt_attempt.timer = after(ms, function()
        if bt_attempt.address ~= address then return end
        bt_attempt.timer = nil
        -- A pairing question is BlueZ waiting for a person, not a connect that failed: give the
        -- question its own window instead of calling the device dead while it waits.
        if type(bt_raw.pairing) == "string" and bt_raw.pairing ~= "none" then
            bt_attempt_arm(BT_PAIR_MS)
            return
        end
        if bt_attempt.kind == "disconnect" then
            bt_attempt_failed("still connected")
        else
            bt_attempt_failed("no answer in " .. tostring(math.floor(ms / 1000)) .. " s")
        end
    end)
end

-- Forget is Android's two-step: the × arms the row and says so, a second press inside the window
-- does it. `bluetooth.forget` is BlueZ's RemoveDevice — the bond is gone and re-pairing is not an
-- undo — so a single stray press must not be enough. The arm remembers the ADDRESS, not the row's
-- place: the list reorders when a device connects, and a place is not a device.
local bt_forget_armed = nil
local bt_forget_timer = nil
local BT_FORGET_MS = 4000

local function bt_forget_clear()
    if bt_forget_timer then cancel(bt_forget_timer) end
    bt_forget_timer = nil
    bt_forget_armed = nil
    fact.bt_forget = -1
    text.bt_forget_name = ""
end

local function bt_forget_arm(index, address, name)
    bt_forget_clear()
    bt_forget_armed = address
    fact.bt_forget = index
    text.bt_forget_name = name
    bt_forget_timer = after(BT_FORGET_MS, function()
        bt_forget_timer = nil
        bt_forget_clear()
    end)
end

-- Rename: a name local to this computer (BlueZ's `Alias`), not the one the device broadcasts. The
-- band is a field and a yes; closing it throws the typed name away.
local bt_rename_address = nil

local function bt_rename_clear()
    bt_rename_address = nil
    fact.bt_renaming = -1
    text.bt_rename_from = ""
    text.bt_new_name = ""
end

sys.watch("bluetooth", function(b)
    if type(b) ~= "table" then return end
    bt_raw = b
    -- The page indexes a row; the command takes an address. The model is filled here from the same
    -- list the addresses come from, so the index a press carries cannot name a different device.
    if type(b.devices) == "table" then model.bt_devices = b.devices end
    if not bt_attempt.address then return end
    -- The radio went off under the attempt: there is nothing to connect to, and nothing to blame.
    if b.powered ~= true then
        bt_attempt_clear()
        fact.bt_failed = false
        text.bt_error = ""
        return
    end
    -- The patched engine names the reason a connect failed. If the attempt is still armed, the
    -- failure lands now instead of waiting for the window to close; the timeout stays the fallback.
    local why = type(b.error) == "string" and b.error or ""
    if bt_attempt.address and why ~= "" then
        bt_attempt_failed(why)
        return
    end
    local list = type(b.devices) == "table" and b.devices or {}
    for _, d in ipairs(list) do
        if d.address == bt_attempt.address then
            local done = (bt_attempt.kind == "connect" and d.connected == true)
                or (bt_attempt.kind == "disconnect" and d.connected ~= true)
            if done then
                bt_attempt_clear()
                fact.bt_failed = false
                text.bt_error = ""
            end
            return
        end
    end
end)

local function bt_device(index)
    -- The rows are drawn from `bt_devices`, which this logic fills from the same watch it takes
    -- the addresses from; the model is read back here, so the record and the index are one list.
    -- The raw list remains a fallback for a press that arrives before the first watch.
    local drawn = type(model.bt_devices) == "table" and model.bt_devices or {}
    local rec = drawn[index + 1]
    if type(rec) == "table" and type(rec.address) == "string" then return rec end
    local list = type(bt_raw.devices) == "table" and bt_raw.devices or {}
    return list[index + 1]
end

-- The arguments are passed through (a connect, a disconnect and a forget take one; a rename takes
-- two). `pcall` takes them itself: a closure cannot spell `...` for arguments it did not receive,
-- and Luau refuses that at compile time, which takes the whole logic down with it. The answer is
-- returned so a command that is refused outright (busy, no adapter, an unknown device) can be
-- said on the page instead of only in the log.
local function bt_call(command, ...)
    local ok, err = pcall(sys.call, command, ...)
    if not ok then log("panels: " .. command .. " failed: " .. tostring(err)) end
    return ok, err
end

on("bt_power", function()
    touch_drawer()
    -- The radio is the one command that ends an attempt and an armed forget: whatever was
    -- connecting is gone with it, and the row that was about to be forgotten is not.
    bt_attempt_clear()
    bt_forget_clear()
    bt_rename_clear()
    fact.bt_failed = false
    text.bt_error = ""
    bt_call("bluetooth.power", not (bt_raw.powered == true))
end)

on("bt_scan", function()
    touch_drawer()
    bt_call("bluetooth.scan", not (bt_raw.discovering == true))
end)

on("bt_device", function(index)
    touch_drawer()
    -- A press on the row is not the ×: an armed forget is over, and so is a rename band.
    bt_forget_clear()
    bt_rename_clear()
    local d = bt_device(index)
    if type(d) ~= "table" or type(d.address) ~= "string" then return end
    -- One attempt runs at a time: a press while another runs is that attempt, not a second one.
    -- Repeats used to reach BlueZ and come back busy with nothing on screen to show it.
    if bt_attempt.address then return end
    fact.bt_failed = false
    text.bt_error = ""
    local kind = "connect"
    if d.connected == true then kind = "disconnect" end
    bt_attempt.address, bt_attempt.kind = d.address, kind
    bt_attempt.name = tostring(d.name or d.address)
    fact.bt_pending = index
    fact.bt_pending_kind = 0
    if kind == "disconnect" then fact.bt_pending_kind = 1 end
    text.bt_pending_name = bt_attempt.name
    local ok, err = bt_call("bluetooth." .. kind, d.address)
    if not ok then
        local name = bt_attempt.name
        bt_attempt_clear()
        fact.bt_failed = true
        text.bt_error = kind .. " failed: " .. tostring(err) .. " (" .. name .. ")"
        return
    end
    if kind == "disconnect" then
        bt_attempt_arm(BT_DISCONNECT_MS)
    else
        bt_attempt_arm(BT_CONNECT_MS)
    end
end)

on("bt_forget", function(index)
    touch_drawer()
    local d = bt_device(index)
    if type(d) ~= "table" or type(d.address) ~= "string" then return end
    if d.paired ~= true then return end
    if bt_forget_armed ~= d.address then
        -- First press: arm this device, name it on the page, and wait for the second.
        bt_rename_clear()
        bt_forget_arm(index, d.address, tostring(d.name or d.address))
        return
    end
    -- Second press on the same address: this is the forgetting.
    bt_forget_clear()
    if bt_attempt.address == d.address then bt_attempt_clear() end
    fact.bt_failed = false
    text.bt_error = ""
    local ok, err = bt_call("bluetooth.forget", d.address)
    if not ok then
        fact.bt_failed = true
        text.bt_error = "forget failed: " .. tostring(err)
    end
end)

on("bt_rename_start", function(index)
    touch_drawer()
    local d = bt_device(index)
    if type(d) ~= "table" or type(d.address) ~= "string" then return end
    if d.paired ~= true then return end
    -- One thing at a time: a connect that runs keeps the keyboard.
    if bt_attempt.address then return end
    bt_forget_clear()
    bt_rename_address = d.address
    fact.bt_renaming = index
    text.bt_rename_from = tostring(d.name or d.address)
    text.bt_new_name = text.bt_rename_from
    fact.bt_failed = false
    text.bt_error = ""
end)

local function bt_rename_do()
    if not bt_rename_address then return end
    local name = tostring(text.bt_new_name or ""):match("^%s*(.-)%s*$")
    if name == "" then
        fact.bt_failed = true
        text.bt_error = "a device name cannot be empty"
        return
    end
    local ok, err = bt_call("bluetooth.rename", bt_rename_address, name)
    if not ok then
        fact.bt_failed = true
        text.bt_error = "rename failed: " .. tostring(err)
        return
    end
    bt_rename_clear()
    fact.bt_failed = false
    text.bt_error = ""
end

on("bt_rename_confirm", bt_rename_do)
on("submit:bt_new_name", bt_rename_do)

on("bt_rename_cancel", function()
    bt_rename_clear()
end)

-- Only the two questions that are answered with a yes are answered here. `pin` and `passkey` need a
-- field to type into, and `display` needs no answer: the page says so and offers only Cancel.
-- `confirm` and `authorize` are answered with a yes; `pin` and `passkey` with the code typed into
-- the band's field. `display` needs no answer, and the page offers only Cancel for it.
on("bt_confirm", function()
    touch_drawer()
    local id = bt_raw.pairing_id
    if type(id) ~= "string" or id == "" then return end
    local kind = tostring(bt_raw.pairing or "none")
    if kind == "pin" or kind == "passkey" then
        local code = tostring(text.pair_code or ""):match("^%s*(.-)%s*$")
        if code == "" then return end
        text.pair_code = ""
        local ok, err = pcall(function() sys.call("bluetooth.answer", id, code) end)
        if not ok then log("panels: bluetooth.answer failed: " .. tostring(err)) end
    else
        bt_call("bluetooth.confirm", id)
    end
end)

on("submit:pair_code", function()
    local id = bt_raw.pairing_id
    if type(id) ~= "string" or id == "" then return end
    local code = tostring(text.pair_code or ""):match("^%s*(.-)%s*$")
    if code == "" then return end
    text.pair_code = ""
    local ok, err = pcall(function() sys.call("bluetooth.answer", id, code) end)
    if not ok then log("panels: bluetooth.answer failed: " .. tostring(err)) end
end)

on("bt_cancel", function()
    touch_drawer()
    local id = bt_raw.pairing_id
    if type(id) ~= "string" or id == "" then return end
    bt_call("bluetooth.cancel", id)
end)

-- ==================== the quick toggles ====================

-- Two switches and one flag. The radios are the services' own commands (`network.wifi`,
-- `bluetooth.power`); do not disturb is the notifications scene's fact, so it is read back with
-- `--say … get` and written with `--say … fact` — the shell's cross-scene rule (§1.2) rather than a
-- second copy of the state here.
local net_state = {}

sys.watch("network", function(n)
    if type(n) ~= "table" then return end
    net_state = n
    -- `error` is why the last join did not get in (reference §17: none, password, timeout,
    -- unsupported, busy, failed). The page shows it instead of pretending the press worked.
    local err = tostring(n.error or "none")
    if err ~= "none" then
        fact.wifi_failed = true
        text.wifi_err = "cannot join: " .. err
    else
        fact.wifi_failed = false
        text.wifi_err = ""
    end
end)

-- ---- the Wi-Fi page (pages/wifi.plm)
local function wifi_call(command, arg)
    local ok, err = pcall(function() sys.call(command, arg) end)
    if not ok then log("panels: " .. command .. " failed: " .. tostring(err)) end
end

local function wifi_net(index)
    local list = type(net_state.networks) == "table" and net_state.networks or {}
    return list[index + 1]
end

local function wifi_join()
    local ssid = tostring(text.wifi_ssid or "")
    if ssid == "" then return end
    local password = tostring(text.wifi_pass or "")
    fact.wifi_ask = false
    text.wifi_pass = ""
    local ok, err = pcall(function() sys.call("network.connect", ssid, password) end)
    if not ok then log("panels: network.connect failed: " .. tostring(err)) end
end

on("wifi_power", function()
    touch_drawer()
    wifi_call("network.wifi", not (net_state.wifi == true))
end)

on("wifi_scan", function()
    touch_drawer()
    local ok, err = pcall(function() sys.call("network.scan") end)
    if not ok then log("panels: network.scan failed: " .. tostring(err)) end
end)

on("wifi_pick", function(index)
    touch_drawer()
    local n = wifi_net(index)
    if type(n) ~= "table" then return end
    if n.active == true then
        local ok, err = pcall(function() sys.call("network.disconnect") end)
        if not ok then log("panels: network.disconnect failed: " .. tostring(err)) end
    elseif n.secure == true and n.known ~= true then
        fact.wifi_ask = true
        fact.wifi_failed = false
        text.wifi_ssid = tostring(n.ssid or "")
        text.wifi_pass = ""
    else
        local ok, err = pcall(function() sys.call("network.connect", n.ssid) end)
        if not ok then log("panels: network.connect failed: " .. tostring(err)) end
    end
end)

on("wifi_forget", function(index)
    touch_drawer()
    local n = wifi_net(index)
    if type(n) ~= "table" or type(n.ssid) ~= "string" then return end
    local ok, err = pcall(function() sys.call("network.forget", n.ssid) end)
    if not ok then log("panels: network.forget failed: " .. tostring(err)) end
end)

on("wifi_connect", wifi_join)
on("submit:wifi_pass", wifi_join)
on("wifi_cancel", function()
    fact.wifi_ask = false
    text.wifi_pass = ""
end)

on("toggle_wifi", function()
    touch_drawer()
    local ok, err = pcall(function() sys.call("network.wifi", not (net_state.wifi == true)) end)
    if not ok then log("panels: network.wifi failed: " .. tostring(err)) end
end)

on("toggle_bt", function()
    touch_drawer()
    bt_call("bluetooth.power", not (bt_raw.powered == true))
end)

local function refresh_dnd()
    run("pleamar", { "--say", "notifications", "get", "dnd" }, function(out)
        local value = tostring(out or ""):match("%S+")
        fact.dnd = (value == "true")
    end)
end

on("toggle_dnd", function()
    touch_drawer()
    local next_value = not fact.dnd
    fact.dnd = next_value
    run("pleamar", { "--say", "notifications", "fact", "dnd", (next_value and "true" or "false") }, function() end)
end)

-- ==================== the key binds ====================

-- `hyprctl binds -j` is the compositor's own list: 276 binds on this host, so the drawer shows the
-- first twelve that match the field. The modmask is a bit field (1 shift, 4 ctrl, 8 alt, 64 super),
-- and the combo is written back in the order the reference prints it.
local key_binds = nil

local function key_combo(mods, key)
    mods = tonumber(mods) or 0
    local parts = {}
    if mods >= 64 then parts[#parts + 1] = "Super"; mods = mods - 64 end
    if mods >= 4 then parts[#parts + 1] = "Ctrl"; mods = mods - 4 end
    if mods >= 8 then parts[#parts + 1] = "Alt"; mods = mods - 8 end
    if mods % 2 == 1 then parts[#parts + 1] = "Shift" end
    local combo = tostring(key or "?")
    if #parts > 0 then combo = table.concat(parts, "+") .. "+" .. combo end
    return combo
end

local function keys_filter()
    local rows = {}
    local query = tostring(text.key_query or ""):lower()
    if key_binds then
        for _, b in ipairs(key_binds) do
            if query == ""
                or b.combo_lower:find(query, 1, true)
                or b.action_lower:find(query, 1, true)
                or b.submap_lower:find(query, 1, true)
            then
                rows[#rows + 1] = { combo = b.combo, action = b.action, submap = b.submap, has_submap = b.submap ~= "" }
                if #rows >= 12 then break end
            end
        end
    end
    model.key_rows = rows
end

local function keys_load()
    run("hyprctl", { "binds", "-j" }, function(out)
        local ok, list = pcall(json.decode, out or "")
        if not ok or type(list) ~= "table" then
            log("panels: hyprctl binds -j did not answer with a list")
            key_binds = nil
            keys_filter()
            return
        end
        local binds = {}
        for _, b in ipairs(list) do
            if type(b) == "table" then
                local combo = key_combo(b.modmask, b.key)
                local arg = b.arg
                local action = tostring(b.dispatcher or "")
                if arg ~= nil and tostring(arg) ~= "" then action = action .. " " .. tostring(arg) end
                local submap = tostring(b.submap or "")
                binds[#binds + 1] = {
                    combo = combo, action = action, submap = submap,
                    combo_lower = combo:lower(), action_lower = action:lower(), submap_lower = submap:lower(),
                }
            end
        end
        key_binds = binds
        keys_filter()
    end)
end

on("text:key_query", function() keys_filter() end)

-- ==================== the notes ====================

-- `notes.json` in this scene's own folder: the newest first, and the file is the whole state (a
-- hand edit is re-read when the drawer opens). The stamp is the clock service's, since `os` is
-- closed in the logic's sandbox.
local NOTES_FILE = "notes.json"
local notes = {}
local clock_now = { hour = 0, minute = 0 }

sys.watch("clock", function(c)
    if type(c) == "table" then clock_now = c end
end)

local function notes_publish()
    local rows = {}
    for _, n in ipairs(notes) do
        rows[#rows + 1] = { body = tostring(n.body or ""), at = tostring(n.at or "") }
    end
    model.notes = rows
end

local function notes_save()
    sys.call("files.write", NOTES_FILE, { notes = notes })
end

local function notes_load()
    local ok, got = pcall(function() return sys.ask("files.read", NOTES_FILE, "json") end)
    if ok and type(got) == "table" and type(got.notes) == "table" then
        notes = got.notes
    elseif not ok then
        notes = {}
        log("panels: notes.json is broken; starting empty")
    else
        notes = {}
    end
    notes_publish()
end

on("submit:note_input", function(value)
    touch_drawer()
    if type(value) ~= "string" then return end
    local body = value:match("^%s*(.-)%s*$")
    if body == "" then return end
    local hour = tonumber(clock_now.hour) or 0
    local minute = tonumber(clock_now.minute) or 0
    table.insert(notes, 1, { body = body, at = string.format("%02d:%02d", hour, minute) })
    text.note_input = ""
    notes_publish()
    notes_save()
end)

on("note_delete", function(index)
    touch_drawer()
    if type(index) ~= "number" then return end
    table.remove(notes, index + 1)
    notes_publish()
    notes_save()
end)

-- ==================== the timer ====================

local timer_left = 0

local function timer_publish()
    local minutes = math.floor(timer_left / 60)
    local seconds = timer_left % 60
    text.timer_text = string.format("%d:%02d", minutes, seconds)
    fact.timer_seconds = timer_left
end

on("timer_add", function(seconds)
    touch_drawer()
    if type(seconds) ~= "number" then return end
    timer_left = timer_left + seconds
    timer_publish()
end)

on("timer_toggle", function()
    touch_drawer()
    if timer_left <= 0 then return end
    fact.timer_running = not fact.timer_running
end)

on("timer_reset", function()
    touch_drawer()
    timer_left = 0
    fact.timer_running = false
    timer_publish()
end)

every(1000, function()
    if not fact.timer_running then return end
    if timer_left > 0 then
        timer_left = timer_left - 1
        timer_publish()
    end
    if timer_left <= 0 then
        fact.timer_running = false
        timer_publish()
        run("notify-send", { "-a", "pleamar", "-u", "critical", "Timer", "Time is up" }, function() end)
    end
end)

-- ==================== the contributions ====================

-- One GraphQL query through `gh`, once per scene run: the calendar changes at most daily, and the
-- token is already in `gh` (the shell must not keep a second one). `viewer` needs no login in the
-- query, so nothing here is pinned to an account. 53 weeks of 7 days arrive as nested tables and
-- land flattened in the model, which is the grid the page draws.
local gh_loaded = false

local function gh_level(count)
    if count <= 0 then return 0 end
    if count <= 2 then return 1 end
    if count <= 5 then return 2 end
    if count <= 9 then return 3 end
    return 4
end

local function gh_load()
    if gh_loaded then return end
    local query = "{ viewer { contributionsCollection { contributionCalendar { totalContributions weeks { contributionDays { contributionCount } } } } } }"
    run("gh", { "api", "graphql", "-f", "query=" .. query }, function(out)
        local ok, decoded = pcall(json.decode, out or "")
        if not ok or type(decoded) ~= "table" then
            text.gh_status = "gh did not answer"
            return
        end
        local data = decoded.data
        local calendar = type(data) == "table" and data.viewer and data.viewer.contributionsCollection
            and data.viewer.contributionsCollection.contributionCalendar
        if type(calendar) ~= "table" or type(calendar.weeks) ~= "table" then
            text.gh_status = "no calendar in the answer"
            return
        end
        local rows = {}
        for _, week in ipairs(calendar.weeks) do
            for _, day in ipairs(week.contributionDays or {}) do
                local count = tonumber(day.contributionCount) or 0
                rows[#rows + 1] = { level = gh_level(count) }
            end
        end
        model.gh_days = rows
        text.gh_total = string.format("%d in a year", tonumber(calendar.totalContributions) or 0)
        text.gh_status = ""
        gh_loaded = true
    end)
end

-- ==================== the bar's own settings ====================

-- The bar's `WIDGETS`, in the order the scene paints them; the page toggles by index, so the
-- list lives here as well as there. The state is read back with one `--say bar` call (a `get`,
-- one answer a line) and the writes go the other way: the bar owns its file.
local BAR_WIDGETS = {
    "clock", "workspaces", "keyboard", "pill", "network", "bluetooth", "sysmon", "weather",
    "media", "mpd", "volume", "mic", "genelec", "systray", "build",
}
local bar_on = {}

local function bar_parse(out)
    local lines = {}
    for line in tostring(out or ""):gmatch("[^\r\n]+") do lines[#lines + 1] = line end
    -- One answer a line, or the bar is not there (a `--say` to a closed scene exits 1 with an empty
    -- stdout). A short answer used to be read as "every widget is off", so the page blanked itself
    -- whenever the bar was restarting. Keep what the page had and say nothing.
    if #lines < 1 + #BAR_WIDGETS then
        log("panels: the bar did not answer with its settings")
        return
    end
    local edge = lines[1]
    if edge == "top" or edge == "bottom" then fact.bar_edge = edge end
    local rows = {}
    for i, name in ipairs(BAR_WIDGETS) do
        local on = (lines[i + 1] == "true")
        bar_on[i] = on
        rows[#rows + 1] = { name = name, on = on }
    end
    model.bar_widgets = rows
end

local function bar_state_load()
    local args = { "--say", "bar", "get bar_edge" }
    for _, name in ipairs(BAR_WIDGETS) do args[#args + 1] = "get widget." .. name end
    run("pleamar", args, bar_parse)
end

on("bar_set_edge", function(which)
    touch_drawer()
    local payload = (which == 1) and 1 or 0
    fact.bar_edge = (payload == 1) and "bottom" or "top"
    local ok, err = pcall(function() sys.call("say", "bar", "emit set_edge " .. payload) end)
    if not ok then log("panels: set_edge failed: " .. tostring(err)) end
end)

on("bar_set_widget", function(index)
    touch_drawer()
    if type(index) ~= "number" then return end
    local at = math.floor(index) + 1
    local name = BAR_WIDGETS[at]
    if not name then return end
    local next_on = not (bar_on[at] == true)
    bar_on[at] = next_on
    -- The page mirrors the press at once; the reload after the bar's answer corrects it if the
    -- write did not take. A widget's place cannot be changed from here: the scene paints in the
    -- order it is written.
    local rows = {}
    for i, widget in ipairs(BAR_WIDGETS) do
        rows[#rows + 1] = { name = widget, on = bar_on[i] == true }
    end
    model.bar_widgets = rows
    local payload = math.floor(index) * 2 + (next_on and 1 or 0)
    local ok, err = pcall(function() sys.call("say", "bar", "emit set_widget " .. payload) end)
    if not ok then log("panels: set_widget failed: " .. tostring(err)) end
    after(400, bar_state_load)
end)

-- The drawers that need something done when they open: the binds are read fresh (the compositor's
-- list may have changed since last time), the notes are re-read (a hand edit is honoured), and the
-- do-not-disturb switch is asked what the notifications scene says now.
on("fact:drawer", function(value)
    if value == "keys" then keys_load() end
    if value == "notes" then notes_load() end
    if value == "toggles" then refresh_dnd() end
    if value == "github" then gh_load() end
    if value == "bar" then bar_state_load() end
end)

notes_load()

-- ==================== samples into the drawing ====================

-- ---- sysmon: one `tiles` record per metric -------------------------------

-- The worker samples once a second for as long as the scene runs, not only while the drawer is
-- open: the chart is worth more when it holds the minute before the open. This ring keeps that
-- minute and survives a close/open — the samples in it are real time, so the page never has to
-- explain a gap it drew as data.
local SYS_HIST_LEN = 60
local sys_hist = {}

-- One record per pair of neighbours, the shape the flow card settled on: the scene can loop over a
-- model but cannot build a path from it or hold the previous point of a series, so a segment is
-- published as its two ends. `t` runs over the whole window, so the curve grows in from the left
-- until the window is full and slides after that, one sample a step.
local function sysmon_publish()
    local n = #sys_hist
    local span = math.max(SYS_HIST_LEN - 1, 1)
    local rows = {}
    for k = 2, n do
        local a, b = sys_hist[k - 1], sys_hist[k]
        rows[#rows + 1] = {
            t0 = (k - 2) / span, t1 = (k - 1) / span,
            cpu0 = a.cpu, cpu1 = b.cpu,
            ram0 = a.ram, ram1 = b.ram,
            temp0 = a.temp, temp1 = b.temp,
            -- The temperature is broken, not drawn to zero, where its reading is missing: the
            -- chart may not invent a dip the worker never measured.
            temp_ok = a.temp_ok and b.temp_ok,
        }
    end
    model.sys_hist = rows
end

local function sysmon_apply(d, topic)
    -- The `sysmon` topic carries the whole sample; a subtopic we did not
    -- subscribe to is not merged (its fields are the worker's, not this scene's).
    if topic ~= "" and topic ~= "sysmon" then return end
    local parts = type(d) == "table" and d or {}
    local cpu = type(parts.cpu) == "table" and parts.cpu or {}
    local mem = type(parts.mem) == "table" and parts.mem or {}
    local swap = type(parts.swap) == "table" and parts.swap or {}
    local disk = type(parts.disk) == "table" and parts.disk or {}
    local temp = type(parts.temp) == "table" and parts.temp or {}
    local cpu_pct = tonumber(cpu.percent) or 0

    local mp = tonumber(mem.percent) or 0
    local dp = tonumber(disk.percent) or 0
    local sp = tonumber(swap.percent) or 0
    local tc = tonumber(temp.celsius)
    local tp = tonumber(temp.percent) or 0

    local swap_value = "none"
    if swap.available == true then
        swap_value = fmt1(swap.used_gib) .. " / " .. fmt1(swap.total_gib) .. " GiB"
    end

    model.tiles = {
        { label = "CPU", value = fmt0(cpu_pct) .. " %", level = cpu_pct / 100,
          tone = tone(cpu_pct, 70, 90) },
        { label = "Memory", value = fmt1(mem.used_gib) .. " / " .. fmt1(mem.total_gib) .. " GiB",
          level = mp / 100, tone = tone(mp, 80, 95) },
        { label = "Swap", value = swap_value, level = sp / 100, tone = tone(sp, 60, 85) },
        { label = "Disk", value = "R " .. rate_kibs(disk.read_kibps) .. " · W " .. rate_kibs(disk.write_kibps),
          level = dp / 100, tone = tone(dp, 70, 90) },
        { label = "Temperature", value = tc and (fmt1(tc) .. " °C") or "--", level = tp / 100,
          tone = tc and tone(tc, 75, 90) or 0 },
    }

    -- Every series is stored as a 0..1 share, so the chart's one 0..100 % scale is a plain
    -- multiplication; `temp_ok` says whether the worker really reported that reading, so a missing
    -- one breaks its line instead of drawing a dip to zero. There is no GPU series: the worker's
    -- `gpu_busy_percent` reads 99-100 % on this card while it is idle, and a chart may not draw a
    -- reading nobody can stand by.
    local function share(v)
        if type(v) ~= "number" or v ~= v then return 0 end
        return math.min(1, math.max(0, v / 100))
    end
    sys_hist[#sys_hist + 1] = {
        cpu = share(cpu_pct), ram = share(mp), temp = share(tp),
        temp_ok = tc ~= nil and tp ~= nil,
    }
    if #sys_hist > SYS_HIST_LEN then table.remove(sys_hist, 1) end
    sysmon_publish()
    fact.sysmon_temp = (tc ~= nil) and 1 or 0
    fact.sysmon_online = 1
    text["sysmon.err"] = ""
end

-- ---- weather: formatted live texts plus the forecast ---------------------

local function weather_apply(d, topic)
    if topic ~= "" and topic ~= "weather" then return end
    fact.weather_ok = 1
    text["weather.err"] = ""

    local city = str(d.city, "")
    if city == "" then city = conf.weatherCity end
    if city == "" then city = "Weather" end
    text["weather.city"] = city
    -- The sample landed: the card stops saying it is loading and may paint real values.
    fact["weather.loading"] = false
    fact["weather.have"] = true
    -- The moon is the same computation the bar's capsule does (WeatherIcons.moonIllumination), and
    -- it needs nothing but the clock, so it is redone here rather than asked of the worker.
    local epoch = tonumber(d.fetched_at)
    if epoch then
        local phase = moon_phase(epoch)
        fact["weather.moonpct"] = math.floor(moon_illumination(phase) + 0.5)
        -- The index the card's moon shader takes (`MoonPhaseIcon`'s `phase`): 0 new, 0.5 full.
        fact["weather.moonphase"] = phase
        text["weather.moon"] = moon_name(phase)
    end

    local cur = type(d.current) == "table" and d.current or {}
    local t = tonumber(cur.temp_c)
    if t and fact.use_fahrenheit == true then t = t * 9 / 5 + 32 end
    text["weather.temp"] = t and fmt1(t) or "--"
    text["weather.unit"] = (fact.use_fahrenheit == true) and "°F" or "°C"
    text["weather.cond"] = cond_text(tonumber(cur.weather_code))
    text["weather.glyph"] = cond_glyph(tonumber(cur.weather_code))
    fact["weather.code"] = tonumber(cur.weather_code) or 2
    -- The reference turns its navigation glyph by `windRotation(wind_direction_10m)`; the port has
    -- the angle in degrees and the scene turns the glyph with it.
    -- `windRotation`: the arrow points where the wind blows TO, which is the reading + 180.
    fact["weather.dir"] = ((tonumber(cur.wind_dir_deg) or 0) + 180) % 360
    local wind = tonumber(cur.wind_ms)
    text["weather.wind"] = wind and (wind_dir(tonumber(cur.wind_dir_deg)) .. fmt1(wind) .. " m/s") or "--"
    local hum = tonumber(cur.humidity_pct)
    text["weather.humidity"] = hum and (fmt0(hum) .. " %") or "--"
    local press = tonumber(cur.pressure_hpa)
    text["weather.pressure"] = press and (fmt0(press) .. " hPa") or "--"

    local days = {}
    local daily = type(d.daily) == "table" and d.daily or {}
    for i, day in ipairs(daily) do
        if i > 5 then break end
        local y, m, dd = isodate_parts(day.date)
        local label = "--"
        if y then label = WDAY[weekday(y, m, dd) + 1] end
        local dcode = tonumber(day.weather_code)
        local hi = tonumber(day.tmax_c)
        local lo = tonumber(day.tmin_c)
        if fact.use_fahrenheit == true then
            if hi then hi = hi * 9 / 5 + 32 end
            if lo then lo = lo * 9 / 5 + 32 end
        end
        days[i] = { day = label, cond = cond_short(dcode), glyph = cond_glyph(dcode),
                    hi = fmt0(hi) .. "°", lo = fmt0(lo) .. "°" }
    end
    model.forecast = days
end

-- ---- calendar: the grid, the entries, the holidays -----------------------

local today = os.date("*t")
local today_y, today_m, today_d = today.year, today.month, today.day

local last_events = {}
local last_holidays = {}
-- The production calendar (isdayoff.ru, through the worker): the days the month holds that are not
-- plain working days, and the moved ones that are. `off` wins over the weekday arithmetic, so a
-- working Saturday stops looking like a day off and a holiday on a Tuesday starts.
local last_workdays = {}
local last_pills = {}
local last_streak = 0

local function label_for(y, m, d, inside)
    if inside then
        return "Select " .. MONTHS[m] .. " " .. tostring(d) .. ", " .. tostring(y)
    end
    return tostring(y) .. "-" .. pad2(m) .. "-" .. pad2(d) .. " (outside)"
end

-- ---- the pill tracker's days
-- Calendar.qml computed four states per cell (`computePillStatus`): a day with a history record
-- is taken or missed, today is taken or still pending, a past day with no record at all is "no
-- data", and a day still to come says nothing. A model field is a number, so the states are
-- numbers and the page says what each one is worth.
local PILL = { none = 0, taken = 1, missed = 2, pending = 3, nodata = 4 }

local function dkey(y, m, d)
    return string.format("%04d-%02d-%02d", y, m, d)
end

-- The pill tracker's history, as the `pleamar-calendar` worker reports it (`pills`, newest first),
-- as a date → taken table for the 42 cells. It comes from the worker and not from the pill plugin
-- because a scene's logic cannot read a plugin's boundary: `fact["Pill.streak"]` reads what the
-- library declared, not what its logic published — measured 2026-10-25, the calendar saw 0 while
-- `pleamar --say panels "get Pill.streak"` answered 1. The worker reads the tracker's own state
-- file instead, which is the same data from the same place.
local function pill_marks()
    local out = {}
    for _, d in ipairs(last_pills) do
        if type(d) == "table" and type(d.date) == "string" then
            out[d.date] = d.taken == true
        end
    end
    return out
end

-- ISO keys compare as dates, which is what the "past day" half of the reference test needs.
local function pill_status(key, day_today, taken_today, marks)
    local had = marks[key]
    if had ~= nil then return had and PILL.taken or PILL.missed end
    if day_today == "" then return PILL.none end
    if key == day_today then return taken_today and PILL.taken or PILL.pending end
    if key < day_today then return PILL.nodata end
    return PILL.none
end

-- Is that date a day off? The production calendar answers when it has the date (and then a working
-- Saturday answers "no"); without it the weekday's own answer stands — the grid is 42 cells over
-- three months, and the calendar covers the month on screen only.
--
-- The cell field is `dayoff` and not `off`: `off` is one of the language's own yes/no words, so a
-- record field with that name never reaches the drawing — the page read the literal and the wash
-- was never painted (measured 2026-10-26).
local function off_flag(y, m, d, off_by_date, moved_by_date)
    local key = dkey(y, m, d)
    if off_by_date[key] then return 1 end
    if moved_by_date[key] then return 0 end
    local wd = weekday(y, m, d)
    return (wd == 0 or wd == 6) and 1 or 0
end

-- The 42 cells of the month grid, Sunday first, adjacent months included so the
-- drawing never moves. Marks: 1 an event, 2 a public holiday. Pill: see PILL above.
local function cal_rebuild()
    local y, m = fact.cal_year, fact.cal_month
    if y == 0 or m < 1 or m > 12 then return end

    local evt_by_day, hol_by_day = {}, {}
    for _, e in ipairs(last_events) do evt_by_day[e.day] = true end
    for _, h in ipairs(last_holidays) do hol_by_day[h.day] = true end
    -- The work calendar speaks of dates, and the grid holds three months of them.
    local off_by_date, moved_by_date = {}, {}
    for _, w in ipairs(last_workdays) do
        local code = tonumber(w.code)
        if code == 1 then off_by_date[w.date] = true
        elseif code == 4 then moved_by_date[w.date] = true end
    end

    -- The pill history covers the whole 42-cell window, the adjacent months' days included: the
    -- reference precomputed the three months around the one on screen for the same reason.
    local marks = pill_marks()
    -- Today is the logic's own date (the tracker's `Pill.today` is a plugin text, and a scene's
    -- logic reads a plugin's boundary only as its declaration — see `pill_marks`), and "taken
    -- today" is the same history the marks come from.
    local pill_today = dkey(today_y, today_m, today_d)
    local pill_taken = marks[pill_today] == true

    local cells = {}
    local first = weekday(y, m, 1)
    local pm, py = m - 1, y
    if pm < 1 then pm, py = 12, y - 1 end
    local nm, ny = m + 1, y
    if nm > 12 then nm, ny = 1, y + 1 end

    local prev_dim = days_in_month(py, pm)
    for i = first - 1, 0, -1 do
        local d = prev_dim - i
        cells[#cells + 1] = { day = d, this = false, today = false,
                              weekend = (weekday(py, pm, d) == 0 or weekday(py, pm, d) == 6),
                              dayoff = off_flag(py, pm, d, off_by_date, moved_by_date),
                              mark = 0, label = label_for(py, pm, d, false),
                              pill = pill_status(dkey(py, pm, d), pill_today, pill_taken, marks) }
    end
    for d = 1, days_in_month(y, m) do
        local wd = weekday(y, m, d)
        local mark = 0
        if evt_by_day[d] then mark = 1 end
        if hol_by_day[d] then mark = 2 end
        cells[#cells + 1] = { day = d, this = true,
                              today = (y == today_y and m == today_m and d == today_d),
                              weekend = (wd == 0 or wd == 6),
                              dayoff = off_flag(y, m, d, off_by_date, moved_by_date), mark = mark,
                              label = label_for(y, m, d, true),
                              pill = pill_status(dkey(y, m, d), pill_today, pill_taken, marks) }
    end
    local nd = 1
    while #cells < 42 do
        cells[#cells + 1] = { day = nd, this = false, today = false,
                              weekend = (weekday(ny, nm, nd) == 0 or weekday(ny, nm, nd) == 6),
                              dayoff = off_flag(ny, nm, nd, off_by_date, moved_by_date),
                              mark = 0, label = label_for(ny, nm, nd, false),
                              pill = pill_status(dkey(ny, nm, nd), pill_today, pill_taken, marks) }
        nd = nd + 1
    end

    model.cells = cells
    model.events = last_events
    model.holidays = last_holidays
    text["cal.title"] = MONTHS[m] .. " " .. tostring(y)

    -- Today's holidays, when the month on screen is today's month.
    local names = {}
    if y == today_y and m == today_m then
        for _, h in ipairs(last_holidays) do
            if h.day == today_d then names[#names + 1] = h.name end
        end
    end
    text["cal.today"] = table.concat(names, " · ")

    -- The streak header (Calendar.qml:186-197): the run of days taken, with the word the
    -- reference pluralised by hand. The number is for the page to test, the words for it to draw.
    -- the worker computes it (lib/plugins/pill/pill.luau `streakNow`) beside the history
    local streak = tonumber(last_streak) or 0
    fact.cal_streak = streak
    text["cal.streak"] = (streak == 1) and "1 day" or (tostring(streak) .. " days")
end

local function calendar_apply(d, topic)
    if topic ~= "" and topic ~= "calendar" then return end
    text["cal.err"] = ""
    local events = {}
    local evts = type(d.events) == "table" and d.events or {}
    for _, e in ipairs(evts) do
        local y, m, day = isodate_parts(e.date)
        if day and y == fact.cal_year and m == fact.cal_month and #events < 60 then
            events[#events + 1] = { day = day, time = str(e.time, ""),
                                    title = str(e.title, ""), cal = str(e.calendar, "") }
        end
    end
    -- The production calendar; a payload from before it existed has no `workdays` at all, and a
    -- failed request has an empty list with `workdays_error` beside it, which is the same to draw.
    local workdays = {}
    for _, w in ipairs(type(d.workdays) == "table" and d.workdays or {}) do
        local date = tostring(w.date or "")
        if date ~= "" then
            workdays[#workdays + 1] = { date = date, code = tonumber(w.code) or 0 }
        end
    end
    last_workdays = workdays

    local holidays = {}
    local hs = type(d.holidays) == "table" and d.holidays or {}
    for _, h in ipairs(hs) do
        local y, m, day = isodate_parts(h.date)
        if day and y == fact.cal_year and m == fact.cal_month and #holidays < 10 then
            local name = str(h.name, "")
            if name == "" then name = str(h.name_en, "Holiday") end
            holidays[#holidays + 1] = { day = day, name = name }
        end
    end
    local pills = {}
    local ps = type(d.pills) == "table" and d.pills or {}
    for _, p in ipairs(ps) do
        if type(p) == "table" and type(p.date) == "string" and #pills < 120 then
            pills[#pills + 1] = { date = p.date, taken = p.taken == true }
        end
    end
    last_events, last_holidays = events, holidays
    last_pills, last_streak = pills, tonumber(d.streak) or 0
    cal_rebuild()
end

-- ======================= worker platform =======================

local WORKERS = {
    sysmon = { drawer = "system", spawn = "pleamar-sysmon", topic = "sysmon" },
    weather = { drawer = "weather", spawn = "pleamar-weather", topic = "weather" },
    calendar = { drawer = "calendar", spawn = "pleamar-calendar", topic = "calendar" },
}

local H = {}     -- name -> { id, tries, stopping, gave_up, timer }
local BACKOFF = { 1000, 2000, 5000 }

for name in pairs(WORKERS) do
    H[name] = { id = nil, tries = 0, stopping = false, gave_up = false, timer = nil }
end

local function month_arg()
    return tostring(fact.cal_year) .. "-" .. pad2(fact.cal_month)
end

-- Domain arguments only; the cadence travels in the subscribe command.
local function worker_args(name)
    if name == "sysmon" then
        return {}
    elseif name == "weather" then
        -- `--timeout 3`, not the helper's 8: it is one attempt's deadline, and eight seconds is a
        -- long time to wait for a failure. The worker dials both providers at once and takes the
        -- first payload, so this no longer decides what the card waits for — a reachable provider
        -- answers in ~0.4 s (measured 2026-11-04) and only a fetch where both fail reaches 3 s.
        local args = { "--forecast-days", "5", "--timeout", "3" }
        if conf.weatherCity ~= "" then
            table.insert(args, "--city")
            table.insert(args, conf.weatherCity)
        end
        return args
    elseif name == "calendar" then
        local args = { "--month", month_arg() }
        if conf.calendarCountry ~= "" then
            table.insert(args, "--country")
            table.insert(args, conf.calendarCountry)
        end
        return args
    end
    return {}
end

-- What the scene wants from the worker, per §7: one topic each, this cadence.
local function subscribe_line(name)
    if name == "sysmon" then
        return '{"cmd":"subscribe","topic":"sysmon","interval_ms":1000}\n'
    elseif name == "weather" then
        return '{"cmd":"subscribe","topic":"weather","interval_ms":300000}\n'
    elseif name == "calendar" then
        return '{"cmd":"subscribe","topic":"calendar","interval_ms":300000,"month":"'
            .. month_arg() .. '"}\n'
    end
    return ""
end

local function wanted(name)
    -- The system worker is the one that outlives its drawer: the chart is the minute BEFORE the
    -- open, so the sampling cannot start when the drawer does. It is one procfs read a second;
    -- the other two call the network and a calendar and stay tied to their drawer.
    if name == "sysmon" then return true end
    return fact.drawer == WORKERS[name].drawer
end

local function fail_worker(name, why)
    if name == "sysmon" then
        fact.sysmon_online = 0
        text["sysmon.err"] = "System monitor " .. why
    elseif name == "weather" then
        fact.weather_ok = 0
        fact["weather.loading"] = false
        text["weather.err"] = "Weather " .. why
    elseif name == "calendar" then
        text["cal.err"] = "Calendar " .. why
    end
end

local APPLY = { sysmon = sysmon_apply, weather = weather_apply, calendar = calendar_apply }

local start_worker, stop_worker

-- A worker this scene cannot talk to: report, then stop it for good until the
-- drawer is reopened.
local function hard_stop(name)
    local h = H[name]
    if h.timer then cancel(h.timer); h.timer = nil end
    if h.id then
        h.stopping = true
        h.gave_up = true
        write(h.id, '{"cmd":"stop"}\n')
        kill(h.id, "term")
        h.id = nil
    else
        h.gave_up = true
    end
end

-- One line, one JSON object: handshake, sample, error or ack (§7).
local function on_line(name, line)
    local ok, msg = pcall(json.decode, line)
    if not ok or type(msg) ~= "table" then
        fail_worker(name, "bad line")
        return
    end
    if msg.version ~= nil then
        if tonumber(msg.version) ~= 1 then
            fail_worker(name, "worker version " .. tostring(msg.version) .. " (this scene knows 1)")
            hard_stop(name)
        end
        return
    end
    local data = msg.data
    if type(data) ~= "table" and type(msg.ok) == "table" then data = msg.ok end
    if type(data) == "table" then
        local topic = msg.topic ~= nil and tostring(msg.topic) or ""
        APPLY[name](data, topic)
        return
    end
    if msg.err ~= nil then
        fail_worker(name, tostring(msg.err))
    elseif msg.ok == false then
        fail_worker(name, "worker error")
    end
    -- Anything else is an ack; nothing to apply.
end

function start_worker(name)
    local h = H[name]
    if h.id or h.timer or h.gave_up then return end
    local ok, id = pcall(spawn, WORKERS[name].spawn, worker_args(name),
        function(line) on_line(name, line) end,
        function(_, code)
            h.id = nil
            if h.stopping then h.stopping = false; h.tries = 0; return end
            h.tries = h.tries + 1
            fail_worker(name, "worker stopped (" .. tostring(code) .. ")")
            if h.tries <= #BACKOFF and wanted(name) then
                h.timer = after(BACKOFF[h.tries], function()
                    h.timer = nil
                    if wanted(name) then start_worker(name) end
                end)
            else
                h.gave_up = true
            end
        end,
        { stdin = "open" })

    if ok and id then
        h.id = id
        h.stopping = false
        write(id, subscribe_line(name))
    else
        -- Not on PATH (or spawn refused it): not available; do not hammer the
        -- system, wait for the drawer to be reopened.
        h.gave_up = true
        fail_worker(name, "helper not available")
    end
end

function stop_worker(name)
    local h = H[name]
    if h.timer then cancel(h.timer); h.timer = nil end
    if h.id then
        h.stopping = true
        -- §7 courtesy line, then the hard stop: the hard stop is what makes
        -- "no worker outlives its drawer" true whatever the worker does.
        write(h.id, '{"cmd":"stop"}\n')
        kill(h.id, "term")
        h.id = nil
    end
    h.tries = 0
    h.gave_up = false
end

-- ---- month navigation (ask the worker for the new month) ------------------

local function set_month(y, m, want_day)
    fact.cal_year = y
    fact.cal_month = m
    -- A walked-onto day is carried across the month's edge; a plain month flip comes back to today
    -- (the reference's own behaviour when a popup reopens).
    fact.sel_day = want_day or ((y == today_y and m == today_m) and today_d or 0)
    last_events, last_holidays = {}, {}
    cal_rebuild()
    local h = H.calendar
    if h.id then
        -- §7 month navigation: the same worker re-asks khal and re-emits.
        write(h.id, '{"cmd":"sample","month":"' .. tostring(y) .. "-" .. pad2(m) .. '"}\n')
    end
end

-- The arrow keys (see `cal_step` in panels.plm): the walk is a date, and the month follows it. The
-- selection is a day of the month on screen, so a walk off the edge needs the same call the
-- prev/next buttons make — with the day carried over instead of a reset to today.
local function cal_walk(days)
    local y, m, d = fact.cal_year, fact.cal_month, fact.sel_day
    if y == 0 or m < 1 or m > 12 then return end
    if d == 0 then
        d = (y == today_y and m == today_m) and today_d or 1
    end
    if d > days_in_month(y, m) then d = days_in_month(y, m) end
    local nd = d + days
    while nd < 1 do
        m = m - 1
        if m < 1 then y, m = y - 1, 12 end
        nd = nd + days_in_month(y, m)
    end
    while nd > days_in_month(y, m) do
        nd = nd - days_in_month(y, m)
        m = m + 1
        if m > 12 then y, m = y + 1, 1 end
    end
    if y ~= fact.cal_year or m ~= fact.cal_month then
        set_month(y, m, nd)
    else
        fact.sel_day = nd
    end
end

-- One press, one step. A single synthetic press reaches the rule four times here (measured
-- 2026-10-26: `pleamar --say panels "key Right"` answers four `cal_step` events from one rule, and
-- the day moved by four), so steps that arrive within 12 ms of each other are the same press and
-- only the first counts. Twelve, not more: a held arrow repeats every 28 ms on this engine, and a
-- repeat is a step of its own.
local last_step_ms = 0
on("cal_step", function(days)
    touch_drawer()
    if type(days) ~= "number" or days == 0 then return end
    local now = math.floor(os.clock() * 1000)
    if now - last_step_ms < 12 then return end
    last_step_ms = now
    cal_walk(math.floor(days))
end)

on("cal_prev", function()
    touch_drawer()
    local y, m = fact.cal_year, fact.cal_month - 1
    if m < 1 then y, m = y - 1, 12 end
    set_month(y, m)
end)
on("cal_next", function()
    touch_drawer()
    local y, m = fact.cal_year, fact.cal_month + 1
    if m > 12 then y, m = y + 1, 1 end
    set_month(y, m)
end)

-- The pill tracker published (`Pill.rev` moved): a toggle in the bar, the midnight rollover, or
-- the state file written by the other instance of the plugin. Only the grid changes, but a
-- running calendar worker is asked for a fresh sample so a toggle does not wait for its tick.
on("pill_sync", function()
    cal_rebuild()
    -- The grid is rebuilt from the last sample; while the drawer is open the worker is alive,
    -- so ask it for a fresh one instead of waiting for the 300 s tick.
    local h = H.calendar
    if h.id then
        write(h.id, '{"cmd":"sample","month":"' .. tostring(fact.cal_year) .. "-" .. pad2(fact.cal_month) .. '"}\n')
    end
end)

-- ==================== link, internet and the tunnel ====================
-- QS answers two questions about a connection and never confuses them
-- (Services/Connectivity.qml): is there a LINK — some non-loopback interface that is up — and is
-- there INTERNET — a ping that comes back. Which of the three states that leaves is what the
-- drawer's detail row says, in the reference's own words (NetClusterCapsule.qml:231-235:
-- "No connection" / "Local network, no internet" / "Internet: available", then "VPN: …"), with
-- the tunnel read off the same interface list (ConnectivityState.qml:25-46).
--
-- WHY THIS IS HERE AND IN bar.luau TOO: QS has one Connectivity singleton for the whole shell;
-- pleamar's scenes cannot read each other's facts, and an IPC round trip for a sentence that
-- changes every four seconds is worse than the duplication. Both copies carry the same timings
-- and the same commands, and each names the reference line it comes from.
--
-- The timings are the reference's: the link every 4 s (Connectivity.qml:47-49, Theme.qml:754
-- `networkLinkPollMs`), the ping every 30 s (Connectivity.qml:86-88, Settings.qml:217
-- `networkPingIntervalMs`), and every 500 ms for the 10 s after a link comes up
-- (Connectivity.qml:23-26 and 115-127, `fastIntervalMs` / `fastDurationMs`), against 8.8.8.8
-- (Settings.qml:218 `networkPingTarget`). The tunnel is recomputed on each link poll, which is
-- where QS does it (ConnectivityState.qml:66-71) — `network.vpnPollMs` (Theme.qml:752) is a
-- token nothing in the reference reads.
local PING_TARGET = "8.8.8.8"
local LINK_POLL_MS = 4000
local PING_SLOW_MS = 30000
local PING_FAST_MS = 500
local PING_FAST_FOR_MS = 10000

local net_link, net_internet, net_vpn, net_vpn_name = false, false, false, ""
local net_fast, net_ping_busy = false, false
local net_link_timer, net_slow_timer, net_fast_timer, net_fast_stop = nil, nil, nil, nil

-- ConnectivityState.qml:25-46: a tunnel is an interface whose name says so (`awg`, `amnez`,
-- `tun`, `outline-tun`) and that has an address on it.
local function net_tunnel_of(name, addrs)
    local lower = name:lower()
    local looks = lower:find("awg", 1, true) ~= nil
        or lower:find("amnez", 1, true) ~= nil
        or lower:sub(1, 3) == "tun"
        or lower:sub(1, 11) == "outline-tun"
    return looks and addrs > 0
end

-- The sentence the drawer prints, and the two facts the dot beside it is coloured by.
local function net_publish()
    if fact["net.link"] ~= net_link then fact["net.link"] = net_link end
    if fact["net.internet"] ~= net_internet then fact["net.internet"] = net_internet end
    local line
    if not net_link then
        line = "No connection"
    elseif not net_internet then
        line = "Local network, no internet"
    else
        line = "Internet: available"
    end
    if net_vpn then
        line = line .. " · VPN: " .. (net_vpn_name ~= "" and net_vpn_name or "connected")
    end
    if text["net.state"] ~= line then text["net.state"] = line end
end

local function net_leave_fast()
    if not net_fast then return end
    net_fast = false
    if net_fast_stop then
        cancel(net_fast_stop)
        net_fast_stop = nil
    end
end

local net_ping

local function net_enter_fast()
    if net_fast then return end
    net_fast = true
    -- Connectivity.qml:123-127: the fast mode stops by itself after 10 s.
    if net_fast_stop then cancel(net_fast_stop) end
    net_fast_stop = after(PING_FAST_FOR_MS, function()
        net_fast_stop = nil
        net_fast = false
    end)
    net_ping()
end

net_ping = function()
    -- One ping in flight at a time, as the reference guards its slow path (Connectivity.qml:87-93).
    if net_ping_busy then return end
    if not net_link then
        -- Connectivity.qml:90-92: no link, no internet, and nothing to wait for.
        net_internet = false
        net_publish()
        return
    end
    net_ping_busy = true
    run("ping", { "-n", "-c", "1", "-W", "1", PING_TARGET }, function(_, code)
        net_ping_busy = false
        local ok = (code == 0)
        if ok == net_internet then return end
        net_internet = ok
        -- Connectivity.qml:55-58: the internet answered, so the fast mode has done its job.
        if ok then net_leave_fast() end
        net_publish()
    end)
end

local function net_probe_link()
    run("ip", { "-j", "-br", "a" }, function(out, code)
        if code ~= 0 or type(out) ~= "string" then return end
        local ok, list = pcall(json.decode, out)
        if not ok or type(list) ~= "table" then return end
        -- Connectivity.qml:59-76: an interface `UP`, or one that says `UNKNOWN` and has an
        -- address; the loopback never counts.
        local link, vpn, name = false, false, ""
        for _, it in ipairs(list) do
            if type(it) == "table" and type(it.ifname) == "string" and it.ifname ~= "lo" then
                local state = (type(it.operstate) == "string") and it.operstate or ""
                local addrs = (type(it.addr_info) == "table") and #it.addr_info or 0
                if state == "UP" or (state == "UNKNOWN" and addrs > 0) then link = true end
                if net_tunnel_of(it.ifname, addrs) then vpn, name = true, it.ifname end
            end
        end
        local was_link = net_link
        net_link, net_vpn, net_vpn_name = link, vpn, name
        if not link then
            -- Connectivity.qml:52-55: the link went, so the internet went with it.
            net_internet = false
            net_leave_fast()
        end
        net_publish()
        if link and not was_link then
            -- Connectivity.qml:44-51: a link that has just come up is asked at once, and then
            -- every 500 ms until it answers or the 10 s are gone.
            net_enter_fast()
        end
    end)
end

-- The probes live exactly as long as their drawer does, like the flow stream.
local function net_start()
    if net_link_timer then return end
    net_publish()
    net_probe_link()
    net_link_timer = every(LINK_POLL_MS, net_probe_link)
    -- The two cadences kept apart, as the reference keeps them: the slow one off while the fast
    -- mode holds (Connectivity.qml:86-88) and the fast one only then (Connectivity.qml:114-121).
    net_slow_timer = every(PING_SLOW_MS, function()
        if not net_fast then net_ping() end
    end)
    net_fast_timer = every(PING_FAST_MS, function()
        if net_fast and net_link then net_ping() end
    end)
end

local function net_stop()
    if not net_link_timer then return end
    cancel(net_link_timer)
    cancel(net_slow_timer)
    cancel(net_fast_timer)
    net_link_timer, net_slow_timer, net_fast_timer = nil, nil, nil
    net_leave_fast()
end

-- ========================= the flow dashboard =========================
-- The `network` drawer (pages/network.plm). QS streams `flow -json-stream`
-- into NetFlowPopup and keeps the last 600 samples in QML; a scene cannot hold
-- an array of its own, so the ring lives here and the card draws what it is
-- handed. The stream is started when the drawer opens and killed when it
-- closes — no process outlives its drawer, the same rule the workers follow
-- (INTERFACES §7).

-- The card plots the stream itself: every sample is a point of one continuous curve, and what the
-- model carries is the segment between two neighbours — `t0, t1` along the window and `rx0, rx1` /
-- `tx0, tx1` as shares of the window's own peak. No bucketing and no smoothing: an earlier version
-- published one column a second (the peak of ten samples) because 600 boxes cost 17-20 ms a frame
-- (measured 2026-10-25); two `line`s per sample is the geometry of a curve, and it is what the
-- stream says rather than a shape it is squeezed into. The frame cost of the curve is in PARITY.
--
-- `-refresh 250ms`, and not the program's own 100 ms, because of what the kernel gives it: the
-- interface counters move about four times a second, so a 100 ms poll reads the same counter four
-- times (a rate) and then zero six times (a counter that did not budge) — the readout blinked
-- between 0 B/s and a spike, and the curve was a comb. Measured against `/sys/…/statistics/rx_bytes`
-- under a ~150 KB/s download: 250 ms gives a mean of 158 KB/s for a real 152 KB/s with one zero in
-- twenty samples, 100 ms gives 16 KB/s mean for 15.5 KB/s real with twelve zeros in twenty — the
-- average is right either way, the samples are only honest at 250 ms. That is also the window the
-- reference keeps: 60 s at 4 Hz.
local FLOW_POINTS = 240 -- the window: 60 s at the stream's 4 Hz
local FLOW_REFRESH = "250ms"
local flow_id, flow_ring = nil, {}

-- `1.2K` / `3.4M`: the axis labels the reference prints beside the grid.
local function compact(v)
    if v >= 1e9 then return string.format("%.1fG", v / 1e9) end
    if v >= 1e6 then return string.format("%.1fM", v / 1e6) end
    if v >= 1e3 then return string.format("%.0fK", v / 1e3) end
    return tostring(math.floor(v + 0.5))
end

-- The scale of the plot: the window's peak with a little headroom, its thirds printed on the right.
-- Each direction keeps its own peak, so one 7 MB/s download does not flatten the upload curve.
local function axis_publish(mx, mt)
    local ymax = math.max(mx, mt, 1) * 1.15
    text["net.ax1"] = compact(ymax / 3)
    text["net.ax2"] = compact(ymax * 2 / 3)
    text["net.ax3"] = compact(ymax)
    text["net.peak_rx"] = compact(mx) .. "B/s"
    text["net.peak_tx"] = compact(mt) .. "B/s"
end

local function flow_publish()
    local n = #flow_ring
    local mx, mt = 1, 1
    for i = 1, n do
        local s = flow_ring[i]
        if s.rx > mx then mx = s.rx end
        if s.tx > mt then mt = s.tx end
    end
    -- A segment per pair of neighbours. `t` runs over the whole window, so the curve grows in from
    -- the left until the window is full and slides after that, one sample a step.
    local span = math.max(FLOW_POINTS - 1, 1)
    local rows = {}
    for k = 2, n do
        local a, b = flow_ring[k - 1], flow_ring[k]
        rows[#rows + 1] = {
            t0 = (k - 2) / span,
            t1 = (k - 1) / span,
            rx0 = a.rx / mx,
            rx1 = b.rx / mx,
            tx0 = a.tx / mt,
            tx1 = b.tx / mt,
        }
    end
    model.flow = rows
    axis_publish(mx, mt)
end

local function flow_stop()
    if flow_id then
        kill(flow_id, "term")
        flow_id = nil
    end
    fact.net_live = false
end

local function flow_line(line)
    local ok, v = pcall(json.decode, line)
    if not ok or type(v) ~= "table" then return end
    local rx = tonumber(v.download_bps) or 0
    local tx = tonumber(v.upload_bps) or 0
    if type(v.interface) == "string" and v.interface ~= "" then text["net.iface"] = v.interface end
    if type(v.download_human) == "string" then text["net.rx"] = v.download_human end
    if type(v.upload_human) == "string" then text["net.tx"] = v.upload_human end
    fact.net_live = (rx > 1) or (tx > 1)
    flow_ring[#flow_ring + 1] = { rx = rx, tx = tx }
    if #flow_ring > FLOW_POINTS then table.remove(flow_ring, 1) end
    flow_publish()
end

local function flow_start()
    if flow_id then return end
    flow_ring = {}
    model.flow = {}
    text["net.peak_rx"], text["net.peak_tx"] = "--", "--"
    -- A spawn that cannot start must not take the fact handler down with it
    -- (the overlay's inhibitor does the same): pcall, then say why.
    local ok = pcall(function()
        flow_id = spawn("flow", { "-json-stream", "-refresh", FLOW_REFRESH }, flow_line, function()
            flow_id = nil
            fact.net_live = false
        end)
    end)
    if not ok or flow_id == nil then
        flow_id = nil
        text["net.err"] = "flow could not start"
        log("flow: could not start")
    else
        text["net.err"] = ""
    end
end

-- ==================== drawer lifecycle ====================

-- One worker at a time, and one of them without a drawer (`sysmon`: see `wanted`). Whatever
-- changed the drawer fact (a scene rule, --say from a bind, the bar's logic), this brings the
-- workers in line; the half-second pass is the safety net, not the main path (the fact listener
-- below is).
local sysmon_ticks = 0
local function reconcile()
    -- The date is the logic's own, and a scene lives for days: the "today" marker, the holidays row
    -- and the pill's `pending` are all decided against `today_*` when the grid is built. Turn them
    -- over here — the check is one `os.date` per reconcile, and without it a shell left running
    -- overnight keeps yesterday's frame around today's date.
    local stamp = os.date("*t")
    if stamp.year ~= today_y or stamp.month ~= today_m or stamp.day ~= today_d then
        today_y, today_m, today_d = stamp.year, stamp.month, stamp.day
        cal_rebuild()
    end
    ensure_audio_watch()
    -- The system worker is never stopped by a drawer closing, so a give-up is never cleared by one
    -- either. Time it instead: one attempt a minute, so a helper that comes back is picked up
    -- without a restart of the shell.
    sysmon_ticks = sysmon_ticks + 1
    if sysmon_ticks >= 120 then
        sysmon_ticks = 0
        local h = H.sysmon
        if h.gave_up and not h.id and not h.timer then
            h.gave_up = false
            h.tries = 0
        end
    end
    for name in pairs(WORKERS) do
        if wanted(name) then
            if name == "calendar" and fact.cal_year == 0 then
                fact.cal_year, fact.cal_month = today_y, today_m
                fact.sel_day = today_d
                cal_rebuild()
            end
            start_worker(name)
        else
            stop_worker(name)
        end
    end
end

-- The journal worker (`pleamar-journal`): one JSON snapshot per call, counts and
-- the last few entries. Nothing streams here — a dashboard opened on demand does
-- not need a process of its own to sit there.
local function journal_refresh()
    local ok = pcall(run, "pleamar-journal", {}, function(out)
        if type(out) ~= "string" then return end
        local got, v = pcall(json.decode, out:match("[^\n]+") or out)
        if not got or type(v) ~= "table" or type(v.data) ~= "table" then return end
        local d = v.data
        text["sys.logs"] = d.logs and tostring(d.logs) or "--"
        text["sys.errors"] = d.errors and tostring(d.errors) or "--"
        text["sys.services"] = d.services and tostring(d.services) or "--"
        local rows, lines = {}, {}
        for _, e in ipairs(d.entries or {}) do
            rows[#rows + 1] = { time = e.time or "", service = e.service or "", msg = e.msg or "" }
            lines[#lines + 1] = "[" .. (e.time or "") .. "] " .. (e.service or "") .. ": " .. (e.msg or "")
        end
        model.journal = rows
        -- The reference copies the journal's problems to the clipboard every time the dashboard is
        -- opened (SystemMonitorPopup.qml:17-40, `onOpened` -> `copyProblemsToClipboard`), so a paste
        -- into a chat carries the lines; the worker hands over the problems themselves, with no
        -- level to filter on. A clipboard with nothing to say is left alone.
        if #lines > 0 then
            local copied = pcall(run, "wl-copy", {}, nil, { input = table.concat(lines, "\n") })
            if not copied then log("panels: the journal was not copied") end
        end
        fact.journal_ok = true
        fact["sys.have"] = true
    end)
    if not ok then
        text["sys.logs"], text["sys.errors"], text["sys.services"] = "--", "--", "--"
        fact.journal_ok = false
    end
end

-- A drawer closes on Escape, on a press outside it, on `WIN+SPACE` (the bind asks this scene the
-- same way it asks the notification centre), or when the fact is set to `none`.
--
-- It also closes itself when left alone: a card nobody dismisses would otherwise stand there for
-- the rest of the session, which is what "the plates hang forever" looked like. The first timer
-- was six seconds (`DRAWER_TIMEOUT_MS`, 6000) and it closed cards while they were being read —
-- the calendar turned to the wrong month, the system dashboard went away mid-look — so the wait
-- is twenty now, and every new fact, drawer change or press on the card's own zones starts it
-- over (`touch_drawer`).
-- ==================== the theme drawer ====================

-- One row per theme file in ~/.config/pleamar/themes, as `pleamar-themes list
-- --plain` answers it: name, font, corners, the file, and 1 when theme.plm was made
-- from that file. The paths are kept here because an event payload is a number, and
-- a row's press carries its index.
local THEME_ROWS = 8
local theme_paths = {}

local function theme_refresh()
    local ok = pcall(run, "pleamar-themes", { "list", "--plain" }, function(out)
        local rows = {}
        theme_paths = {}
        for line in tostring(out):gmatch("[^\n]+") do
            local name, path, selected, accent_r, accent_g, accent_b, light =
                line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
            if name and #rows < THEME_ROWS then
                local idx = #rows
                theme_paths[idx] = path
                rows[#rows + 1] = {
                    idx = idx,
                    name = name,
                    detail = (light == "1" and "light" or "dark"),
                    selected = selected == "1",
                    accent_r = tonumber(accent_r) or 0,
                    accent_g = tonumber(accent_g) or 0,
                    accent_b = tonumber(accent_b) or 0,
                }
            end
        end
        model.themes = rows
        text["theme.err"] = ""
    end)
    if not ok then
        model.themes = {}
        theme_paths = {}
        text["theme.err"] = "pleamar-themes is not available"
    end
end

-- The light theme's one number: the paper is the temperature, and the tool
-- rebuilds theme.plm, palette.json and the facts every scene draws from it.
-- Dragging sends at most one run per 120 ms; the knob follows the hand at once.
on("theme_warm", function(value)
    touch_drawer()
    local normalized = math.min(math.max(value, 0), 1)
    local kelvin = math.floor(2700 + normalized * 3800 + 0.5)
    fact.warm = (kelvin - 2700) / 3800
    text["theme.warm"] = string.format("%d K", kelvin)
    warm_hold = true
    if warm_timer then cancel(warm_timer) end
    warm_timer = after(120, function()
        warm_timer = nil
        run("pleamar-themes", { "warm", tostring(kelvin) }, function(_, code)
            if code ~= 0 then text["theme.warm"] = "warmth failed" end
            after(400, function() warm_hold = false end)
        end)
    end)
end)

-- ==================== the shell page (settings, live) ====================
-- Every control writes its fact at once, so the drawer repaints as it is
-- dragged, and the value goes into settings.json (`files.write`), which is the
-- one place the defaults live and the next start reads. The scene's own settings
-- watcher applies what is written; a slider is debounced so a drag is a few
-- writes and not one per pixel.
local settings_timer = nil

local function persist_settings()
    local ok, failure = pcall(function()
        local table_out = {}
        for key, value in pairs(raw_conf) do table_out[key] = value end
        table_out.closeOnEscape = fact.close_on_escape == true
        table_out.closeOnOutside = fact.close_on_outside == true
        -- Three decimals: the number is a float in the engine, and a user file
        -- should read back as what was set, not as 0.8000000044703484.
        table_out.scale = math.floor(fact.zoom * 1000 + 0.5) / 1000
        table_out.fontScale = math.floor(fact.text_scale * 1000 + 0.5) / 1000
        table_out.useFahrenheit = fact.use_fahrenheit == true
        table_out.nightLight = fact.night_light == true
        table_out.weatherCity = conf.weatherCity
        table_out.calendarCountry = conf.calendarCountry
        sys.call("files.write", FILE, table_out)
    end)
    if not ok then log("panels: cannot write settings.json: " .. tostring(failure)) end
end

on("toggle_night", function()
    touch_drawer()
    fact.night_light = not fact.night_light
    night_apply(fact.night_light)
    persist_settings()
end)

local function persist_soon()
    if settings_timer then cancel(settings_timer) end
    settings_timer = after(150, function()
        settings_timer = nil
        persist_settings()
    end)
end

on("shell_zoom", function(value)
    touch_drawer()
    fact.zoom = num(0.5 + math.min(math.max(value, 0), 1) * 1.5, 0.5, 2.0, D.scale)
    persist_soon()
end)

on("shell_type", function(value)
    touch_drawer()
    fact.text_scale = num(0.5 + math.min(math.max(value, 0), 1) * 1.5, 0.5, 2.0, D.fontScale)
    persist_soon()
end)

on("shell_toggle_escape", function()
    touch_drawer()
    fact.close_on_escape = not (fact.close_on_escape == true)
    persist_settings()
end)

on("shell_toggle_outside", function()
    touch_drawer()
    fact.close_on_outside = not (fact.close_on_outside == true)
    persist_settings()
end)

on("shell_toggle_fahrenheit", function()
    touch_drawer()
    fact.use_fahrenheit = not (fact.use_fahrenheit == true)
    persist_settings()
end)

-- A submitted field: the city reaches the weather worker through its command
-- line, so a running one is stopped and started again with the new argument; the
-- country is the calendar worker's, and it is restarted only when that drawer is
-- the one open.
on("submit:city", function()
    touch_drawer()
    local value = (text.city or ""):match("^%s*(.-)%s*$")
    if value == "" then return end
    conf.weatherCity = value
    persist_settings()
    if fact.drawer == "weather" then stop_worker("weather") end
end)

on("submit:country", function()
    touch_drawer()
    local value = (text.country or ""):match("^%s*(.-)%s*$")
    conf.calendarCountry = value
    persist_settings()
    if fact.drawer == "calendar" then stop_worker("calendar") end
end)

on("theme_apply", function(i)
    touch_drawer()
    local path = theme_paths[i]
    if not path then return end
    -- What it writes is theme.plm; every scene imports it, so the shell re-themes
    -- on the reload and this card closes with the scene.
    run("pleamar-themes", { "apply", path }, function(_, code)
        if code ~= 0 then text["theme.err"] = "could not apply that theme" end
    end)
end)

on("fact:sel_day", function() touch_drawer() end)
on("fact:page", function() touch_drawer() end)

on("fact:drawer", function(v)
    -- Every change of the fact re-arms the idle wait, so moving from one drawer to the next (or
    -- re-opening the same one) starts the count again.
    if drawer_timer then
        cancel(drawer_timer)
        drawer_timer = nil
    end
    if v ~= "none" then
        drawer_timer = after(DRAWER_IDLE_MS, hide_drawer)
    end
    if v == "weather" then
        -- The card is never a blank plate while the worker answers: placeholders and a line that
        -- says it is loading, until the first sample (the reference shows a spinner and "--°C").
        if fact["weather.have"] ~= true then
            text["weather.err"] = ""
            text["weather.temp"] = "--"
            text["weather.unit"] = (fact.use_fahrenheit == true) and "°F" or "°C"
            text["weather.cond"] = ""
            text["weather.city"] = conf.weatherCity
            fact["weather.loading"] = true
        end
    end
    if v == "calendar" then
        -- Like the legacy popup: opening the calendar comes back to today.
        fact.cal_year, fact.cal_month = today_y, today_m
        fact.sel_day = today_d
        last_events, last_holidays = {}, {}
        cal_rebuild()
    end
    -- The flow stream and the connection's two probes follow their drawer, like a worker does.
    if v == "network" then
        flow_start()
        net_start()
    else
        flow_stop()
        net_stop()
    end

    -- The system dashboard reads the journal once, when it opens: the worker prints a single line
    -- and exits. The history ring is not touched here — sysmon sampled all along, so the chart
    -- already holds the minute before the open.
    if v == "system" then
        journal_refresh()
    end

    -- The theme card is a list of files, so it is read when the card opens and
    -- after every apply (which reloads the scene anyway).
    if v == "theme" then
        theme_refresh()
    end

    -- The analyser runs only while the card that draws it is up. A scene rule
    -- cannot set a plugin fact — it compiles and silently does nothing — so the
    -- logic says it over IPC, the same way the bar opens a drawer.
    -- `--say` takes the whole command as one argument: split into words it
    -- answered "I do not understand 'false'" and set a fact called ''.
    run("pleamar", { "--say", "panels", "fact Spectrum.active " .. ((v == "media") and "true" or "false") })
    reconcile()
end)

every(500, reconcile)

-- The grid is ready before the first open; the only worker that runs without a drawer is sysmon.
fact.cal_year, fact.cal_month = today_y, today_m
fact.sel_day = today_d
cal_rebuild()
reconcile()

-- The same for the flow stream: reloading the logic while its drawer is open
-- (saving the file during a session) must not leave it without data — the
-- `fact:drawer` listener only hears changes, and the change already happened.
if fact.drawer == "network" then
    flow_start()
    net_start()
end
