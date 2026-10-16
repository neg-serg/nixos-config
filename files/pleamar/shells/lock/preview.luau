-- preview.luau — the logic of preview.plm, the look harness of the lock card.
--
-- Same settings merge and same wallpaper pipeline as lock.luau, with one
-- difference: PREVIEW_WALLPAPER (and `preview.wallpaper` in the settings file,
-- if it is ever wanted) overrides the wallpaper, so the card can be looked at
-- over a chosen picture. The password path is the real one —
-- `sys.ask("auth.check", …)` — because a preview that guessed would be a
-- promise this file cannot keep; the answer is only shown, never handed
-- anywhere: no `locked`, no `unlocked`, no marker.
--
-- Nothing here is a security boundary: the lock scene has its own logic, and
-- only lock.luau can release anything.

local FILE = "settings.json"
local WP = "wallpaper.path"

local D = { clock24h = true, uiScale = 1.2, retryDelayMs = 800 }

local function num(v, lo, hi, def)
    if type(v) ~= "number" or v ~= v then return def end
    return math.max(lo, math.min(hi, v))
end

local function path_or_empty(v)
    if type(v) ~= "string" then return "" end
    v = v:gsub("^%s+", ""):gsub("%s+$", "")
    if string.sub(v, 1, 1) ~= "/" then return "" end
    return v
end

local function read_file()
    local ok, got = pcall(function() return sys.ask("files.read", FILE, "json") end)
    if ok and type(got) == "table" then return got end
    if not ok then log("settings: unreadable, the defaults are used") end
    return {}
end

local raw = {}

local function set_wallpaper(path)
    text.wallpaper = path
    fact.wall_ok = path ~= ""
end

local function apply(settings)
    fact.clock_24h = settings.clock24h ~= false
    fact.ui_scale = num(settings.uiScale, 0.8, 2.0, D.uiScale)
    fact.retry_delay = num(settings.retryDelayMs, 300, 5000, D.retryDelayMs)

    local wallpaper = path_or_empty(settings.wallpaper)
    if wallpaper == "" then
        local ok, got = pcall(function() return sys.ask("files.read", WP) end)
        if ok and type(got) == "string" then wallpaper = path_or_empty(got) end
    end
    -- The legacy preview's override, honoured only in the preview.
    local ok_env, override = pcall(function() return sys.ask("env", "PREVIEW_WALLPAPER") end)
    if ok_env then
        local chosen = path_or_empty(override)
        if chosen ~= "" then wallpaper = chosen end
    end
    set_wallpaper(wallpaper)

    text.avatar = path_or_empty(settings.avatar)
    fact.avatar_ok = text.avatar ~= ""

    local ok, user = pcall(function() return sys.ask("env", "USER") end)
    local name = settings.user
    if type(name) ~= "string" or name == "" then
        name = (ok and type(user) == "string") and user or ""
    end
    text.user = name
    text.monogram = name ~= "" and string.upper(string.sub(name, 1, 1)) or "?"
end

raw = read_file()
apply(raw)

sys.watch("files:" .. FILE, function()
    raw = read_file()
    apply(raw)
end)
pcall(function()
    sys.watch("files:" .. WP, function() apply(raw) end)
end)

run("cat", { "/etc/hostname" }, function(out, code)
    if code == 0 and type(out) == "string" then
        local host = out:gsub("%s+$", "")
        text.host = host ~= "" and ("@" .. host) or ""
    end
end)

local function clock12()
    local hour = fact["now.hour"]
    local minute = fact["now.minute"]
    if type(hour) ~= "number" or type(minute) ~= "number" then return end
    hour = hour % 24
    local suffix = hour < 12 and "AM" or "PM"
    local shown = hour % 12
    if shown == 0 then shown = 12 end
    text.clock12 = string.format("%d:%02d %s", shown, minute, suffix)
end

every(1000, clock12)
clock12()

-- ------------------------------------------------------------- the card state
local busy = false
local armed = true

local function set_status(message)
    text.status = message
    fact.status_ok = message ~= ""
end

set_status("")

focus("password")
after(400, function() focus("password") end)

-- The same flow as lock.luau, with the answer kept: the preview never releases
-- a session, so a wrong password and a right one differ only in what is said.
on("submit:password", function(value)
    if busy or not armed then return end
    if type(value) ~= "string" or value == "" then return end

    busy = true
    fact.busy = true
    fact.failed = false
    set_status("проверка пароля…")

    local ok, answer = pcall(function() return sys.ask("auth.check", value) end)

    text.password = ""
    busy = false
    fact.busy = false

    if ok and answer == true then
        fact.failed = false
        set_status("пароль верный (предпросмотр)")
    else
        fact.failed = true
        set_status(ok and "Неверный пароль" or "Проверка пароля не удалась")
        emit("rejected")
        armed = false
        fact.armed = false
        after(fact.retry_delay, function()
            armed = true
            fact.armed = true
        end)
    end

    focus("password")
end)
