-- lock.luau — the logic behind lock.plm. Security-critical; read it whole.
--
-- Three jobs, and nothing else:
--   1. merge the scene's settings (clock24h, uiScale, retryDelayMs, wallpaper,
--      avatar, user) with the frozen defaults and clamps of INTERFACES.md §6;
--   2. publish the live texts the card draws (wallpaper, avatar, user, host,
--      monogram, the 12-hour clock);
--   3. be the only reader of `text.password` and the only caller of the `auth`
--      service: `sys.ask("auth.check", password)`, the real PAM check behind
--      the legacy PamContext. The password is handed straight over, never
--      logged, never written to a file, and the field is cleared before the
--      answer is reported — on success and on failure alike.
--
-- The handover (README.md, "The handover"): a true answer emits `unlocked`,
-- raises `fact.unlocked` and leaves `fact.locked` alone — the integration
-- writes the session marker and only then runs
-- `pleamar --say lock "fact locked false"` to release the lock surface.

local FILE = "settings.json"
local WP = "wallpaper.path"

-- Defaults live in code; the file holds what the user changed. `clock24h` and
-- `uiScale` are the frozen lock keys (§6.3: true / 1.2, 0.8–2.0); the rest
-- are this scene's own and are documented in the lock.plm header.
local D = {
    clock24h = true,
    uiScale = 1.2,
    retryDelayMs = 800,
}

-- The canonical clamp of INTERFACES.md §6.1: a wrong type and NaN keep the
-- default. Unknown keys are never written, so they survive.
local function num(v, lo, hi, def)
    if type(v) ~= "number" or v ~= v then return def end
    return math.max(lo, math.min(hi, v))
end

-- `image … = from` takes an icon name for anything that is not an absolute
-- path, so only an absolute path is published; everything else means "none".
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

-- The wallpaper: the setting wins; otherwise the file the integration may
-- publish into this scene's own folder (`wallpaper.path`, one absolute path).
-- An integration that cannot write the folder should prefer
-- `pleamar --say lock text wallpaper <path>`.
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

-- An editor or another copy rewrote the file: the same defaults and clamps.
sys.watch("files:" .. FILE, function()
    raw = read_file()
    apply(raw)
end)
-- `wallpaper.path` may not exist yet; watching a missing file must not break
-- the scene, so the watch is best-effort.
pcall(function()
    sys.watch("files:" .. WP, function() apply(raw) end)
end)

-- The identity line's machine half: /etc/hostname, a fixed read-only path
-- (permission `run: "cat"`).
run("cat", { "/etc/hostname" }, function(out, code)
    if code == 0 and type(out) == "string" then
        local host = out:gsub("%s+$", "")
        text.host = host ~= "" and ("@" .. host) or ""
    end
end)

-- `clock24h = false` needs a 12-hour form; the clock service writes 24-hour
-- `time` itself, so the logic derives and publishes it once a second.
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

-- Give the caret to the field as soon as there is a surface to hold it, and
-- again after every answer: the screen is the only way in.
focus("password")
after(400, function() focus("password") end)

-- Enter in the field (or `pleamar --say lock "submit password <text>"`).
-- While a check runs, or while the retry window is closed, another submit is
-- ignored on purpose: a wrong password reaches PAM at most once per window.
on("submit:password", function(value)
    if busy or not armed or fact.unlocked then return end
    if type(value) ~= "string" or value == "" then return end

    busy = true
    fact.busy = true
    fact.failed = false
    set_status("проверка пароля…")

    local ok, answer = pcall(function() return sys.ask("auth.check", value) end)

    -- The field and this function let the password go here, whatever the
    -- answer: cleared before any state below is reported.
    text.password = ""
    busy = false
    fact.busy = false

    if ok and answer == true then
        fact.failed = false
        fact.unlocked = true
        -- `fact.locked` stays true: the session is released by the integration
        -- after the login marker is on disk (README.md, "The handover").
        set_status("Вход разрешён")
        emit("unlocked")
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
