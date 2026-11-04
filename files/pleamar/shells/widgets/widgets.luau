-- widgets.luau — the logic behind widgets.plm.
--
-- What the declarative scene cannot do itself:
--   · read widgets.json (which widgets are there, where they sit) and write it
--     back when one is moved or switched on/off;
--   · keep the live palette's facts current (the same `palette.json` the other
--     converted scenes read: `pleamar-themes push` leaves it in this scene's own
--     folder, and a theme change is then a change of facts, no reload);
--   · compose the readouts the language cannot shape: "1:23", "4:05", "42 %",
--     "7.2 / 60 GiB";
--   · carry the transport and quote presses to the service;
--   · run pleamar-sysmon while the scene is up, as the bar and the system drawer
--     do, and turn its samples into facts and a history for the sparkline.
--
-- The scene is the owner of every fact and text named here; this file only writes
-- them. Everything it needs of the system is declared in widgets.plm
-- (permissions: pleamar-sysmon, clock, media, media.*, files, files.write).

-- ======================= the live palette =======================
-- The same block as panels.luau and bar.luau (lib/palette-live.plm says what it is
-- for): the theme's channels land in this scene's own folder, and drawing them is
-- `rgb(r, g, b)` over these facts. A value that has not moved is not written again.
local PALETTE_ROLES = { "coal", "surface", "ink", "ink_dim", "accent", "on_accent" }

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
end

palette_load()
every(2000, palette_load)

-- ======================= settings =======================

local FILE = "widgets.json"
local NAMES = { "clock", "music", "quote", "sysmon", "cava" }

-- The reference's own corners (services/DesktopWidgets.qml): clock top left, music
-- top right, quote bottom left, system monitor bottom right; the analyser has no
-- reference default of its own and sits low, centred.
local D = {
    clock = true,
    music = true,
    quote = true,
    sysmon = true,
    cava = false,
    positions = {
        clock = { 0.03000, 0.05556 },
        music = { 0.68750, 0.05556 },
        quote = { 0.03000, 0.79630 },
        sysmon = { 0.68750, 0.62963 },
        cava = { 0.39583, 0.72222 },
    },
}

local function num(value, lo, hi, def)
    if type(value) ~= "number" or value ~= value then return def end
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

local function flag(value, def)
    if type(value) ~= "boolean" then return def end
    return value
end

local function read_settings()
    local ok, got = pcall(function() return sys.ask("files.read", FILE, "json") end)
    if ok and type(got) == "table" then return got end
    if not ok then log("widgets: widgets.json is broken; defaults kept") end
    return {}
end

local function write_settings(raw)
    sys.call("files.write", FILE, raw)
end

local function apply_settings()
    local raw = read_settings()
    for _, name in ipairs(NAMES) do
        fact["has." .. name] = flag(raw[name], D[name])
    end
    local positions = raw.positions
    if type(positions) ~= "table" then positions = {} end
    for _, name in ipairs(NAMES) do
        local p = positions[name]
        local dx, dy = D.positions[name][1], D.positions[name][2]
        local x = type(p) == "table" and num(p.x, 0, 1, dx) or dx
        local y = type(p) == "table" and num(p.y, 0, 1, dy) or dy
        if fact[name .. ".nx"] ~= x then fact[name .. ".nx"] = x end
        if fact[name .. ".ny"] ~= y then fact[name .. ".ny"] = y end
        -- The press-start facts follow the position on load: a drag taken before
        -- the first press reads the same place, not zero.
        if fact[name .. ".gx"] ~= x then fact[name .. ".gx"] = x end
        if fact[name .. ".gy"] ~= y then fact[name .. ".gy"] = y end
    end
end

apply_settings()
-- Another copy, or an editor, changed the file: re-read and re-apply.
sys.watch("files:" .. FILE, function() apply_settings() end)

-- A widget was let go: what it sits at becomes the file's. The position facts were
-- moved by the scene's own drag rule, so they are the truth at this point.
local function save_positions()
    local raw = read_settings()
    local positions = {}
    for _, name in ipairs(NAMES) do
        positions[name] = { x = fact[name .. ".nx"], y = fact[name .. ".ny"] }
    end
    raw.positions = positions
    write_settings(raw)
end

for _, name in ipairs(NAMES) do
    on(name .. "_moved", save_positions)
end

on("reset_positions", function()
    for _, name in ipairs(NAMES) do
        fact[name .. ".nx"] = D.positions[name][1]
        fact[name .. ".ny"] = D.positions[name][2]
    end
    save_positions()
end)

-- ======================= the edit strip =======================

on("edit", function() fact.editing = not fact.editing end)

local function set_widget(name, on_off)
    fact["has." .. name] = on_off
    local raw = read_settings()
    raw[name] = on_off
    write_settings(raw)
end

for _, name in ipairs(NAMES) do
    on("toggle_" .. name, function()
        set_widget(name, not fact["has." .. name])
    end)
end

-- ======================= the media readout =======================
-- `media` reports when the player changes what it plays and, for a player that
-- does, its position. The language cannot print "4:05" out of a number, so the
-- readouts are texts kept here: the length from the report, the position counted
-- on from it once a second while something plays (what the bar does, and what the
-- reference's own MusicWidget shows through Qt's formatter).

local mediaLen = 0
local mediaPos = 0

local function clock_text(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function media_apply(m)
    if type(m) ~= "table" then return end
    local has_track = type(m.title) == "string" and m.title ~= ""
    fact.playing = has_track and m.playing == true
    text.track = has_track and m.title or ""
    text.artist = has_track and (type(m.artist) == "string" and m.artist or "") or ""
    mediaLen = tonumber(m.length) or 0
    mediaPos = tonumber(m.position) or 0
    text["media.len"] = has_track and mediaLen > 0 and clock_text(mediaLen) or "--:--"
    text["media.pos"] = has_track and clock_text(mediaPos) or "--:--"
    fact["media.progress"] = (has_track and mediaLen > 0) and math.min(math.max(mediaPos / mediaLen, 0), 1) or 0
end

sys.watch("media", media_apply)

every(1000, function()
    if not fact.playing then return end
    mediaPos = mediaPos + 1
    -- The readout stops at the track's length: the position only moves on reports, and one that
    -- stops coming ran the clock past the end (the bar had the same defect).
    if mediaLen > 0 and mediaPos > mediaLen then mediaPos = mediaLen end
    text["media.pos"] = clock_text(mediaPos)
    if mediaLen > 0 then
        fact["media.progress"] = math.min(math.max(mediaPos / mediaLen, 0), 1)
    end
end)

local function transport(command)
    local ok, err = pcall(function() sys.call(command) end)
    if not ok then log("widgets: " .. command .. " failed: " .. tostring(err)) end
end

on("media_toggle", function() transport("media.toggle") end)
on("media_next", function() transport("media.next") end)
on("media_previous", function() transport("media.previous") end)

-- ======================= the quote =======================
-- The reference's quote is a dad joke fetched from an API (services/DesktopWidgets).
-- The port keeps the widget and drops the request: a local list, a different one
-- every ten minutes, and a press asks for the next.

local QUOTES = {
    { "The best way out is always through.", "Robert Frost" },
    { "Simplicity is the soul of efficiency.", "Austin Freeman" },
    { "A ship in harbour is safe, but that is not what ships are built for.", "John A. Shedd" },
    { "The quieter you become, the more you can hear.", "Ram Dass" },
    { "Make it work, make it right, make it fast.", "Kent Beck" },
    { "Programs must be written for people to read.", "Harold Abelson" },
    { "Slow is smooth, smooth is fast.", "US Navy SEALs" },
    { "What I cannot create, I do not understand.", "Richard Feynman" },
    { "Tension is who you think you should be; relaxation is who you are.", "Chinese proverb" },
    { "The obstacle is the way.", "Marcus Aurelius" },
    { "A desk is a dangerous place from which to view the world.", "John le Carre" },
    { "Weeks of coding can save you hours of planning.", "Anonymous" },
}

local quote_at = 1

local function quote_show()
    local q = QUOTES[quote_at]
    text["quote.body"] = q[1]
    text["quote.by"] = q[2]
end

local function quote_next()
    quote_at = quote_at % #QUOTES + 1
    quote_show()
end

quote_show()
every(600000, quote_next)
on("next_quote", quote_next)

-- ======================= the system monitor =======================
-- The worker does the arithmetic (packages/pleamar-sysmon, the same one the bar and
-- the system drawer subscribe to): one JSON object per line with the ratios already
-- scaled, an unavailable GPU or temperature carried as `{ err = ... }`. This scene
-- keeps the thresholds and draws what comes.

local SYS_INTERVAL_MS = 2000
local SYS_HISTORY = 40
local sysmon_handle = nil
local sysmon_restart = nil
local history = {}

local function clamp01(v)
    if v ~= v then return 0 end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function percent_text(value)
    return string.format("%.0f %%", value * 100)
end

local function push_history(value)
    history[#history + 1] = value
    while #history > SYS_HISTORY do table.remove(history, 1) end
    local rows = {}
    for _, v in ipairs(history) do rows[#rows + 1] = { v = v } end
    model.hist = rows
end

local function apply_sample(data)
    if type(data) ~= "table" then return end

    local cpu = data.cpu
    if type(cpu) == "table" and type(cpu.percent) == "number" then
        fact.cpu = clamp01(cpu.percent / 100)
        text["cpu.read"] = percent_text(fact.cpu)
        push_history(fact.cpu)
    end

    local mem = data.mem
    if type(mem) == "table" and type(mem.percent) == "number" then
        fact.ram = clamp01(mem.percent / 100)
        text["ram.read"] = percent_text(fact.ram)
        if type(mem.used_gib) == "number" and type(mem.total_gib) == "number" then
            text["ram.pair"] = string.format("%.1f / %.0f GiB", mem.used_gib, mem.total_gib)
        end
    end

    local temp = data.temp
    if type(temp) == "table" then
        if type(temp.percent) == "number" then fact.temp = clamp01(temp.percent / 100) end
        if type(temp.celsius) == "number" then
            text["temp.read"] = string.format("%.0f °C", temp.celsius)
        end
    end

    local disk = data.disk
    if type(disk) == "table" and type(disk.percent) == "number" then
        fact.disk = clamp01(disk.percent / 100)
        text["disk.read"] = percent_text(fact.disk)
    end

    local gpu = data.gpu
    if type(gpu) == "table" and type(gpu.percent) == "number" then
        fact["has.gpu"] = true
        fact.gpu = clamp01(gpu.percent / 100)
        text["gpu.read"] = percent_text(fact.gpu)
    else
        fact["has.gpu"] = false
    end
end

local function sysmon_start()
    if sysmon_handle or sysmon_restart then return end
    -- `--interval-ms` sets the worker's own cadence; stdin stays open so it does not
    -- read EOF and exit after the handshake (INTERFACES.md §7).
    local ok, handle = pcall(spawn, "pleamar-sysmon", { "--interval-ms", tostring(SYS_INTERVAL_MS) }, function(line)
        local parsed, msg = pcall(json.decode, line)
        if not parsed or type(msg) ~= "table" or type(msg.data) ~= "table" then return end
        apply_sample(msg.data)
    end, function()
        sysmon_handle = nil
        sysmon_restart = after(2000, function()
            sysmon_restart = nil
            sysmon_start()
        end)
    end, { stdin = "open" })
    if ok then sysmon_handle = handle end
end

sysmon_start()
