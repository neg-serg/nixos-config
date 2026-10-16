-- overview.luau — the hypr-expo bridge behind the `overview` scene (PH3-O).
--
-- The scene draws nothing: its one job is to turn the shell's stable IPC name
-- into the legacy plugin's toggle. Rules cannot run programs, so this is the
-- logic's work:
--
--   pleamar --say overview "emit toggle_overview"  ->  hypr-expo toggle
--
-- The `hypr-expo` helper (modules/user/nix-maid/hyprland/main.nix) loads and
-- configures hyprexpo before toggling, which is the same command the old
-- SUPER+grave bind and Services/Expo.qml ran. `run` is given a callback only so
-- a non-zero exit is visible in the journal; a handler that fails changes no
-- fact.
--
-- Settings (`~/.local/share/pleamar/overview/settings.json`):
--   enabled      bool     true    the toggle is ignored while false
--   cooldownMs   number   250     0 – 2000  ignore a repeat toggle inside this window
-- There is no settings UI yet, so nothing writes the file; the logic only reads,
-- and it never rebuilds the table it read, so keys another version put there
-- survive when a later slice starts writing.

local FILE = "settings.json"

-- Defaults live here; the file holds only what the user changed.
local D = {
    enabled = true,
    cooldownMs = 250,
}

local conf = { enabled = D.enabled, cooldownMs = D.cooldownMs }
local cooling = false

local function num(v, lo, hi, def)
    if type(v) ~= "number" or v ~= v then return def end
    return math.max(lo, math.min(hi, v))
end

local function flag(v, def)
    if type(v) ~= "boolean" then return def end
    return v
end

local function apply_settings()
    local raw = {}
    local ok, got = pcall(function() return sys.ask("files.read", FILE, "json") end)
    if ok and type(got) == "table" then
        raw = got
    elseif not ok then
        log("overview: settings.json is broken; defaults kept")
    end
    conf.enabled = flag(raw.enabled, D.enabled)
    conf.cooldownMs = num(raw.cooldownMs, 0, 2000, D.cooldownMs)
    fact.enabled = conf.enabled
end

apply_settings()
sys.watch("files:" .. FILE, function() apply_settings() end)

on("toggle_overview", function()
    if not conf.enabled then return end
    if cooling then return end

    -- A compositor bind and a click can land together; the cooldown swallows the
    -- second one. `after` is the platform's timer (the logic's clock is the
    -- scene's, so nothing here needs os.time).
    if conf.cooldownMs > 0 then
        cooling = true
        after(conf.cooldownMs, function() cooling = false end)
    end

    fact.toggles = fact.toggles + 1
    local ok, err = pcall(run, "hypr-expo", { "toggle" }, function(_, code)
        if code ~= 0 then
            log("overview: hypr-expo toggle exited " .. tostring(code))
        end
    end)
    if not ok then
        log("overview: hypr-expo could not be run: " .. tostring(err))
    end
end)
