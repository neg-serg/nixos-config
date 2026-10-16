-- launcher.luau — the filter and the launch path of the `launcher` scene (PH3-O).
--
-- What the declarative scene cannot do itself:
--   · read settings.json and push the defaults/clamps into `max_results`/`zoom`;
--   · keep a snapshot of the `apps` service's list and cut the `results` slice
--     for the current `query` (the model slice the panel draws);
--   · hand the chosen record's `exec` to `sys.call("apps.launch", …)` and close.
--
-- The service records are `{ name, exec, icon, id, wmclass, local_name,
-- categories }` (logic doc, `apps` row). The filter is case-insensitive:
-- exact name, prefix, substring, then id/wmclass substring, then a subsequence
-- pass over the display name — "fuzzy-ish", and deterministic: equal scores sort
-- by display name, so the list does not reshuffle between keystrokes.
--
-- Settings (`~/.local/share/pleamar/launcher/settings.json`):
--   maxResults   number   8     1 – 20     the results slice's cap
--   scale        number   1.0   0.5 – 2.0  user multiplier on ui and the fit
-- There is no settings UI yet, so nothing writes the file; the logic only reads,
-- and it never rebuilds the table it read, so keys another version put there
-- survive when a later slice starts writing.

local FILE = "settings.json"

-- Defaults live here; the file holds only what the user changed.
local D = {
    maxResults = 8,
    scale = 1.0,
}

local MAX_RESULTS = 20   -- INTERFACES.md §6.3: maxResults clamps to 1..20
local MAX_APPS = 256     -- the `apps` model's cap (launcher.plm)

local raw = {}           -- the parsed settings file, exactly as it was read
local apps_all = {}      -- the newest snapshot of the apps service records
local apps_n = -1        -- how many records that snapshot had (reconcile)
local last_query = nil   -- the query the current slice was built from
local announced_cap = false

-- ======================= small helpers =======================

local function num(v, lo, hi, def)
    if type(v) ~= "number" or v ~= v then return def end
    return math.max(lo, math.min(hi, v))
end

local function lower(v)
    if type(v) ~= "string" then return "" end
    return string.lower(v)
end

local function trim(s)
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

local function display_name(rec)
    local n = rec.local_name
    if type(n) ~= "string" or n == "" then n = rec.name end
    if type(n) ~= "string" then return "" end
    return n
end

local function subsequence(haystack, needle)
    local i, j = 1, 1
    while i <= #haystack and j <= #needle do
        if string.sub(haystack, i, i) == string.sub(needle, j, j) then j = j + 1 end
        i = i + 1
    end
    return j > #needle
end

-- A record's rank for the query; 0 means it does not match.
local function score(rec, q)
    if q == "" then return 1 end
    local name = lower(display_name(rec))
    if name == q then return 100 end
    local at = string.find(name, q, 1, true)
    if at == 1 then return 90 end
    if at then return math.max(20, 70 - at) end
    if string.find(lower(rec.id), q, 1, true) then return 40 end
    if string.find(lower(rec.wmclass), q, 1, true) then return 30 end
    if subsequence(name, q) then return 10 end
    return 0
end

-- ======================= settings =======================

local function read_settings()
    local ok, got = pcall(function() return sys.ask("files.read", FILE, "json") end)
    raw = {}
    if ok and type(got) == "table" then
        raw = got
    elseif not ok then
        log("launcher: settings.json is broken; defaults kept")
    end
end

local function apply_settings()
    read_settings()
    fact.max_results = math.floor(num(raw.maxResults, 1, MAX_RESULTS, D.maxResults))
    fact.zoom = num(raw.scale, 0.5, 2.0, D.scale)
end

-- ======================= the results slice =======================

local function snapshot()
    local list = model.apps
    if type(list) == "table" and #list > 0 then
        apps_all = list
        apps_n = #list
    end
    if #apps_all >= MAX_APPS and not announced_cap then
        announced_cap = true
        log("launcher: the apps model is at its " .. tostring(MAX_APPS)
            .. "-record cap; entries past it are not searched")
    end
end

local function rebuild()
    local q = trim(lower(text.query))

    local hits = {}
    for _, rec in ipairs(apps_all) do
        if type(rec) == "table" then
            local s = score(rec, q)
            if s > 0 then hits[#hits + 1] = { s = s, rec = rec } end
        end
    end
    table.sort(hits, function(x, y)
        if x.s ~= y.s then return x.s > y.s end
        return lower(display_name(x.rec)) < lower(display_name(y.rec))
    end)

    local limit = math.min(#hits, math.floor(fact.max_results))
    local out = {}
    for i = 1, limit do
        local rec = hits[i].rec
        out[i] = {
            name = tostring(rec.name or ""),
            exec = tostring(rec.exec or ""),
            icon = rec.icon,
            id = tostring(rec.id or ""),
            local_name = display_name(rec),
        }
    end
    model.results = out
    last_query = text.query

    if fact.selected > #out - 1 then fact.selected = math.max(0, #out - 1) end
    if fact.selected < 0 then fact.selected = 0 end
end

local function refresh()
    snapshot()
    rebuild()
end

-- ======================= the launch path =======================

local function launch(i)
    -- A second ask arriving in the same turn (Enter and Return both fire, or a
    -- row press after Enter) must not launch twice.
    if not fact.open then return end

    local rec = model.results[i + 1]
    if type(rec) == "table" then
        local exec = rec.exec
        if type(exec) == "string" and exec ~= "" then
            local ok, err = pcall(sys.call, "apps.launch", exec)
            if not ok then log("launcher: apps.launch failed: " .. tostring(err)) end
        else
            log("launcher: the chosen record has no exec")
        end
    end

    fact.open = false
    text.query = ""
    fact.selected = 0
end

-- ======================= events =======================

-- Opening: a clean query and selection, the freshest apps snapshot, and the
-- caret in the field (`focus()` is the documented route for a search opened
-- from a shortcut; the scene's `on change open` rule is the same-frame backstop).
on("open_launcher", function()
    fact.selected = 0
    text.query = ""
    refresh()
    fact.open = true
    focus("query")
end)

on("launch_app", function(i)
    launch(i)
end)

-- Typing re-slices; the selection goes back to the top of the new list.
on("text:query", function()
    fact.selected = 0
    rebuild()
end)

-- Closing by any route (Escape, the catcher, --say "fact open false") clears
-- the filter; opening through the fact alone (--say "fact open true", a
-- compositor bind) does what open_launcher does, so both routes are complete.
on("fact:open", function(v)
    if v then
        refresh()
        focus("query")
    else
        text.query = ""
        fact.selected = 0
    end
end)

-- ======================= watchers and reconciliation =======================

-- An editor or a second copy changed the settings: re-apply and re-slice.
sys.watch("files:" .. FILE, function()
    apply_settings()
    rebuild()
end)

-- The service is watched directly where the platform offers it; the declared
-- `service apps` model below still fills the scene, and `snapshot()`/the timer
-- are the fallback when this watch is refused.
local apps_watch = sys.watch("apps", function(list)
    if type(list) ~= "table" then return end
    apps_all = list
    apps_n = #list
    if fact.open then rebuild() end
end)
if apps_watch == false then
    log("launcher: the apps service is not watchable here; the declared model is the fallback")
end

-- Safety net while the launcher is open: the declarative service fills
-- `model.apps` even where sys.watch has no listener, and its report can land
-- after the first open. A query written straight into the text by IPC
-- (`pleamar --say launcher "text query kitty"`) may not raise `text:query`, so
-- the same pass watches it too. Only a change costs a re-slice.
every(750, function()
    if not fact.open then return end
    local changed = false
    local list = model.apps
    if type(list) == "table" and #list ~= apps_n then
        apps_n = #list
        apps_all = list
        changed = true
    end
    if text.query ~= last_query then
        fact.selected = 0
        changed = true
    end
    if changed then rebuild() end
end)

-- The settings decide the cap and the scale before the first open.
apply_settings()
rebuild()
