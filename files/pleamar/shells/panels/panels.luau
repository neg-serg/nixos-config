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

-- Defaults live here; the file holds only what the user changed.
local D = {
    closeOnEscape = true,
    closeOnOutside = true,
    scale = 1.0,                       -- user multiplier on top of ui and the fit
    fontScale = 1.0,                   -- multiplies type.* sizes
    weatherCity = "Saint Petersburg",  -- the legacy Quickshell default
    useFahrenheit = false,
    calendarCountry = "",              -- ISO country for public holidays; empty: none
}

local conf = { weatherCity = D.weatherCity, calendarCountry = D.calendarCountry }

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
    fact.close_on_escape = flag(raw.closeOnEscape, D.closeOnEscape)
    fact.close_on_outside = flag(raw.closeOnOutside, D.closeOnOutside)
    fact.zoom = num(raw.scale, 0.5, 2.0, D.scale)
    fact.text_scale = num(raw.fontScale, 0.5, 2.0, D.fontScale)
    fact.use_fahrenheit = flag(raw.useFahrenheit, D.useFahrenheit)
    conf.weatherCity = str(raw.weatherCity, D.weatherCity)
    conf.calendarCountry = str(raw.calendarCountry, D.calendarCountry)
end

apply_settings()
-- Another copy, or an editor, changed the file: re-read and re-apply.
sys.watch("files:" .. FILE, function() apply_settings() end)

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

local function pick_rec(raw, model_rec, i)
    local rec = nil
    if type(raw) == "table" then rec = raw[i + 1] end
    if not rec and type(model_rec) == "table" then rec = model_rec[i + 1] end
    return rec
end

on("set_out", function(v) sys.call("audio.volume", v) end)
on("set_in", function(v) sys.call("audio.input", v) end)
on("toggle_out", function() sys.call("audio.mute") end)
on("toggle_in", function() sys.call("audio.input_mute") end)

on("set_default_out", function(i)
    local rec = pick_rec(audio_raw.outputs, model.sinks, i)
    if rec and type(rec.id) == "string" then sys.call("audio.default", rec.id) end
end)
on("set_default_in", function(i)
    local rec = pick_rec(audio_raw.inputs, model.sources, i)
    if rec and type(rec.id) == "string" then sys.call("audio.default", rec.id) end
end)

-- app_set packs the stream index and the volume into one number
-- (index * 1000 + round(volume * 1000)); an event payload is a number only.
on("app_set", function(p)
    local i = math.floor(p / 1000)
    local v = (p % 1000) / 1000
    local rec = pick_rec(audio_raw.apps, model.streams, i)
    if rec and type(rec.id) == "string" then sys.call("audio.app_volume", rec.id, v) end
end)
on("app_mute", function(i)
    local rec = pick_rec(audio_raw.apps, model.streams, i)
    if rec and type(rec.id) == "string" then sys.call("audio.app_mute", rec.id) end
end)

-- ==================== samples into the drawing ====================

-- ---- sysmon: one `tiles` record per metric -------------------------------

local function sysmon_apply(d, topic)
    -- The `sysmon` topic carries the whole sample; a subtopic we did not
    -- subscribe to is not merged (its fields are the worker's, not this scene's).
    if topic ~= "" and topic ~= "sysmon" then return end
    local parts = type(d) == "table" and d or {}
    local cpu = type(parts.cpu) == "table" and parts.cpu or {}
    local mem = type(parts.mem) == "table" and parts.mem or {}
    local swap = type(parts.swap) == "table" and parts.swap or {}
    local disk = type(parts.disk) == "table" and parts.disk or {}
    local gpu = type(parts.gpu) == "table" and parts.gpu or {}
    local temp = type(parts.temp) == "table" and parts.temp or {}
    local cpu_pct = tonumber(cpu.percent) or 0

    local mp = tonumber(mem.percent) or 0
    local dp = tonumber(disk.percent) or 0
    local sp = tonumber(swap.percent) or 0
    local gp = tonumber(gpu.percent)
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
        { label = "GPU", value = gp and (fmt0(gp) .. " %") or "--", level = (gp or 0) / 100,
          tone = tone(gp or 0, 80, 95) },
        { label = "Temperature", value = tc and (fmt1(tc) .. " °C") or "--", level = tp / 100,
          tone = tc and tone(tc, 75, 90) or 0 },
    }

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

    local cur = type(d.current) == "table" and d.current or {}
    local t = tonumber(cur.temp_c)
    if t and fact.use_fahrenheit == true then t = t * 9 / 5 + 32 end
    text["weather.temp"] = t and fmt1(t) or "--"
    text["weather.cond"] = cond_text(tonumber(cur.weather_code))
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
        days[i] = { day = label, cond = cond_short(tonumber(day.weather_code)),
                    hi = fmt0(tonumber(day.tmax_c)) .. "°", lo = fmt0(tonumber(day.tmin_c)) .. "°" }
    end
    model.forecast = days
end

-- ---- calendar: the grid, the entries, the holidays -----------------------

local today = os.date("*t")
local today_y, today_m, today_d = today.year, today.month, today.day

local last_events = {}
local last_holidays = {}

local function label_for(y, m, d, inside)
    if inside then
        return "Select " .. MONTHS[m] .. " " .. tostring(d) .. ", " .. tostring(y)
    end
    return tostring(y) .. "-" .. pad2(m) .. "-" .. pad2(d) .. " (outside)"
end

-- The 42 cells of the month grid, Sunday first, adjacent months included so the
-- drawing never moves. Marks: 1 an event, 2 a public holiday.
local function cal_rebuild()
    local y, m = fact.cal_year, fact.cal_month
    if y == 0 or m < 1 or m > 12 then return end

    local evt_by_day, hol_by_day = {}, {}
    for _, e in ipairs(last_events) do evt_by_day[e.day] = true end
    for _, h in ipairs(last_holidays) do hol_by_day[h.day] = true end

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
                              mark = 0, label = label_for(py, pm, d, false) }
    end
    for d = 1, days_in_month(y, m) do
        local wd = weekday(y, m, d)
        local mark = 0
        if evt_by_day[d] then mark = 1 end
        if hol_by_day[d] then mark = 2 end
        cells[#cells + 1] = { day = d, this = true,
                              today = (y == today_y and m == today_m and d == today_d),
                              weekend = (wd == 0 or wd == 6), mark = mark,
                              label = label_for(y, m, d, true) }
    end
    local nd = 1
    while #cells < 42 do
        cells[#cells + 1] = { day = nd, this = false, today = false,
                              weekend = (weekday(ny, nm, nd) == 0 or weekday(ny, nm, nd) == 6),
                              mark = 0, label = label_for(ny, nm, nd, false) }
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
    last_events, last_holidays = events, holidays
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
        local args = { "--forecast-days", "5" }
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
    return fact.drawer == WORKERS[name].drawer
end

local function fail_worker(name, why)
    if name == "sysmon" then
        fact.sysmon_online = 0
        text["sysmon.err"] = "System monitor " .. why
    elseif name == "weather" then
        fact.weather_ok = 0
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

local function set_month(y, m)
    fact.cal_year = y
    fact.cal_month = m
    fact.sel_day = (y == today_y and m == today_m) and today_d or 0
    last_events, last_holidays = {}, {}
    cal_rebuild()
    local h = H.calendar
    if h.id then
        -- §7 month navigation: the same worker re-asks khal and re-emits.
        write(h.id, '{"cmd":"sample","month":"' .. tostring(y) .. "-" .. pad2(m) .. '"}\n')
    end
end

on("cal_prev", function()
    local y, m = fact.cal_year, fact.cal_month - 1
    if m < 1 then y, m = y - 1, 12 end
    set_month(y, m)
end)
on("cal_next", function()
    local y, m = fact.cal_year, fact.cal_month + 1
    if m > 12 then y, m = y + 1, 1 end
    set_month(y, m)
end)

-- ==================== drawer lifecycle ====================

-- One worker at a time, only while its drawer is open. Whatever changed the
-- drawer fact (a scene rule, --say from a bind, the bar's logic), this brings
-- the workers in line; the half-second pass is the safety net, not the main
-- path (the fact listener below is).
local function reconcile()
    ensure_audio_watch()
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

on("fact:drawer", function(v)
    if v == "calendar" then
        -- Like the legacy popup: opening the calendar comes back to today.
        fact.cal_year, fact.cal_month = today_y, today_m
        fact.sel_day = today_d
        last_events, last_holidays = {}, {}
        cal_rebuild()
    end
    reconcile()
end)

every(500, reconcile)

-- The grid is ready before the first open; no worker runs while drawer == none.
fact.cal_year, fact.cal_month = today_y, today_m
fact.sel_day = today_d
cal_rebuild()
reconcile()
