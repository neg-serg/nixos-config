-- bar.luau — the thin logic behind bar.plm.
--
-- The declarative scene draws, animates and reads its services on its own; only
-- what no rule can do is here: merge the bar's settings from the scene's own
-- folder and command the services. Nothing here paints or knows coordinates.

local FILE = "settings.json"

-- How many monitors the per-monitor scale reaches: the engine repeats a `screens: each` surface
-- on 4 monitors at most unless a scene says otherwise (reference §surfaces), which is exactly what
-- these facts cover. The read is `mon_scale[min(screen.index, 3)]` in the scene, because reading a
-- numbered name past its last element is -1 there, and a negative scale would draw backwards.
local MAX_SCREENS = 4

-- Defaults live in code; the file holds what the user changed. The frozen keys
-- of INTERFACES §6.3 that this slice still cannot apply (height, animations,
-- startupClean) are left untouched in the file, each with its reason — the
-- compiler's, not a guess — in bar.plm's settings note.
--
-- The `media*` keys are this scene's own (INTERFACES §6.3 asks for them here). The first four are
-- QS Settings.json's player policy under the names the bar uses; `mediaRecent` is the reference's
-- MRU stack (its StateCache `lastActivePlayers`), which this logic keeps and writes itself:
--   mediaPinned    array of text, max 24,      — ids that win a tie (QS `pinnedPlayers`)
--                  default []
--   mediaIgnored   array of text, max 24,      — ids the bar never shows (QS `ignoredPlayers`)
--                  default []
--   mediaPriority  array of text, default ["mpdPlaying", "anyPlaying", "mpdRecent", "recent",
--                  "manual", "first"] — the rule order (QS `playerSelectionPriority`). The default
--                  is this host's own list, Settings.json:49, not the code's longer fallback in
--                  MusicPlayers.qml:186 — `pinned` is not in it, so a pinned player only wins once
--                  the user puts the rule back.
--   mediaPreset    text, default "default"     — manualFirst | playingFirst | mpdBias | default
--                  (QS `playerSelectionPreset`), read only when `mediaPriority` holds no known rule
--   mediaRecent    array of text, default []   — the MRU stack, at most five ids, kept by the logic
local D = {
    edge = "bottom", -- top | bottom; bottom on trantor
    scale = 1.0,     -- user multiplier on top of ui and the per-monitor fit
    -- Type only, the way the reference's `fontSizeMultiplier` is: the plates keep the
    -- widths their design gives them, and the glyphs inside them take this.
    fontScale = 1.0,
    -- Per monitor, read through `screen.index`; empty or short means 1.0 for the monitors the
    -- array does not reach (the reference's `monitorScaleOverrides`, also an array).
    monitorScale = {},
    mediaPinned = {},
    mediaIgnored = {},
    mediaPriority = { "mpdPlaying", "anyPlaying", "mpdRecent", "recent", "manual", "first" },
    mediaPreset = "default",
    mediaRecent = {},
    -- The reference reads these from Settings.qml (`weatherCity`, `useFahrenheit`); the port had
    -- them written into the URL and the readout. Empty city means the coordinates below, so a host
    -- that never writes the file keeps the weather it had.
    weatherCity = "",
    weatherLat = 59.9375,
    weatherLon = 30.3086,
    useFahrenheit = false,
}

-- The widgets this slice draws; `widgets` in the file is read as the visible
-- set. An order cannot be applied at runtime (the scene paints in the order it
-- is written), and entries this slice does not know yet (pill, keyboard, media,
-- …) are kept in the file for the slices that do.
-- The place and the unit the reference keeps in Settings.qml; `apply` below fills them.
local weatherCity = ""
local weatherLat, weatherLon = 59.9375, 30.3086
local useFahrenheit = false

local WIDGETS = { "clock", "workspaces", "keyboard", "pill", "network", "sysmon", "weather", "media", "mpd", "volume", "mic", "genelec", "systray", "build" }

-- The canonical clamp of INTERFACES §6.1: a wrong type and NaN keep the default.
local function num(v, lo, hi, def)
    if type(v) ~= "number" or v ~= v then return def end
    return math.max(lo, math.min(hi, v))
end

-- ---------------------------------------------------------------- player policy
-- QS picks the bar's player itself (Services/MusicPlayers.qml) and everything that shows or
-- commands music reads that pick. The service here picks one too — the one playing, else the one
-- that played last, else the first — but it cannot know the reference's rules: a pinned player, an
-- ignored one, MPD first. So the rules live in this logic, and the pick is pinned into the service
-- with `media.choose`; that is what makes `media.player`, the track fields and `media.toggle`,
-- `next` and `previous` all speak of the same player.
--
-- The rule names, in the order the reference's own header lists them (MusicPlayers.qml:9), and the
-- set it accepts (:156). A name it does not know is dropped and a repeat ignored, as
-- `_sanitizeRules` does (:157-171).
local MEDIA_RULES = { "pinnedPlaying", "mpdPlaying", "anyPlaying", "mpdRecent", "pinned", "recent", "manual", "first" }

-- The presets, verbatim from `presetRules` (:172-188); there `default` and `mpdBias` are one list.
local MEDIA_PRESETS = {
    mpdBias = { "pinnedPlaying", "mpdPlaying", "anyPlaying", "mpdRecent", "pinned", "recent", "manual", "first" },
    manualFirst = { "manual", "pinnedPlaying", "anyPlaying", "pinned", "recent", "first" },
    playingFirst = { "pinnedPlaying", "anyPlaying", "mpdPlaying", "pinned", "manual", "recent", "first" },
}

-- The id lists a settings file may carry: strings, empties and repeats dropped, and never more
-- than the cap (INTERFACES §6.2 — a huge array is a typo, not a wish).
local function id_list(v, cap)
    local out, seen = {}, {}
    if type(v) == "table" then
        for i = 1, math.min(#v, cap) do
            local id = v[i]
            if type(id) == "string" and id ~= "" and not seen[id] then
                seen[id] = true
                out[#out + 1] = id
            end
        end
    end
    return out
end

local function id_set(list)
    local s = {}
    for _, id in ipairs(list) do s[id] = true end
    return s
end

-- `playerSelectionPriority` wins whenever it holds one usable rule; otherwise the preset, whose
-- unknown name falls back to `default` (:189-199).
local function media_rules_from(priority, preset)
    local known = id_set(MEDIA_RULES)
    local out = {}
    for _, rule in ipairs(id_list(priority, 8)) do
        if known[rule] then out[#out + 1] = rule end
    end
    if #out > 0 then return out end
    return MEDIA_PRESETS[preset] or MEDIA_PRESETS.mpdBias
end

-- What the file says, resolved once and again on every change of it.
local mediaPinned = id_set(D.mediaPinned)
local mediaIgnored = id_set(D.mediaIgnored)
local mediaRules = media_rules_from(D.mediaPriority, D.mediaPreset)
-- The MRU stack, front first, at most five ids (:37): what was heard last, and the order the
-- `recent` and `mpdRecent` rules read. Loaded from the file once (:216-224), then kept here.
local mediaStack = {}
local mediaStackLoaded = false
-- What each player's `playing` was when it was last heard, by id: a change is what moves a player
-- to the front of the stack (:233-241).
local mediaSeen = {}

-- Read only: a missing file is the defaults; a broken one keeps the defaults
-- too, and says so (`pcall`: `files.read` raises when the JSON cannot be read).
-- Reads never write (INTERFACES §6.1).
local function read_file()
    local ok, got = pcall(function() return sys.ask("files.read", FILE, "json") end)
    if not ok then
        log("settings: unreadable, the defaults are used")
        return {}
    end
    if type(got) == "table" then return got end
    return {}
end

local function apply(raw)
    local edge = raw.edge
    if edge ~= "top" and edge ~= "bottom" then edge = D.edge end
    fact.bar_edge = edge

    fact.user_scale = num(raw.scale, 0.5, 2.0, D.scale)

    -- INTERFACES §6.2: `fontScale` multiplies the type and nothing else, `monitorScale` is one
    -- multiplier per monitor. Both are read here and applied by bar.plm's components, whose
    -- `scale:` default is read at the use site — that is what makes a per-monitor value possible
    -- at all (`mon_scale[screen.index]`, one fact per monitor, defaulting to the fourth).
    fact.text_scale = num(raw.fontScale, 0.5, 2.0, D.fontScale)
    local mon = (type(raw.monitorScale) == "table") and raw.monitorScale or {}
    for i = 0, MAX_SCREENS - 1 do
        fact["mon_scale." .. i] = num(mon[i + 1], 0.5, 2.5, 1.0)
    end

    local wanted = nil
    if type(raw.widgets) == "table" then
        wanted = {}
        for i = 1, math.min(#raw.widgets, 24) do
            if type(raw.widgets[i]) == "string" then wanted[raw.widgets[i]] = true end
        end
    end
    for _, name in ipairs(WIDGETS) do
        fact["widget." .. name] = (wanted == nil) or (wanted[name] == true)
    end

    -- The weather's own two settings, clamped like everything else here.
    weatherCity = (type(raw.weatherCity) == "string") and raw.weatherCity or ""
    weatherLat = num(raw.weatherLat, -90, 90, 59.9375)
    weatherLon = num(raw.weatherLon, -180, 180, 30.3086)
    useFahrenheit = (raw.useFahrenheit == true)

    -- The player policy, same rule: a wrong type is ignored, never fatal.
    mediaPinned = id_set(id_list(raw.mediaPinned, 24))
    mediaIgnored = id_set(id_list(raw.mediaIgnored, 24))
    mediaRules = media_rules_from(raw.mediaPriority, raw.mediaPreset)
    -- Read once. After that the stack belongs to the running logic: re-reading it on every save
    -- would pull an older front back in, and the file is written by this very logic (see
    -- `media_touch`).
    if not mediaStackLoaded then
        mediaStack = id_list(raw.mediaRecent, 5)
        mediaStackLoaded = true
    end
end

-- The table as it was read: `apply` does not keep it, but a write must (INTERFACES §6.1 — mutate
-- this one, never build another), and the media stack below is written back through it.
local raw = read_file()
apply(raw)

-- An editor, or another copy of the scene, changed the file: read it again and
-- take the new values, clamped the same way (the file is the source, so the
-- change is honoured live).
sys.watch("files:" .. FILE, function()
    raw = read_file()
    apply(raw)
end)

-- Writes arrive with the settings UI of a later slice: mutate `raw` (`raw[key]
-- = value`) and `sys.call("files.write", FILE, raw)`, never a table built from
-- scratch, so keys another version put there survive (INTERFACES §6.1). The
-- media stack below is the one writer this slice has.

-- ---------------------------------------------------------------- commands
-- Show a workspace by id. No press of the strip emits this: the workspace capsule shows the
-- workspace that is already in force and its click is the overview (`open_overview` below), as
-- in the reference. It stays as the bar's IPC entry point — `pleamar --say bar "emit
-- focus_workspace 3"` — and it is why the payload is checked: an emit without one used to
-- reach `sys.call` as nil and the runtime answered "I don't know how to do 'workspaces.focus'
-- with that" in the journal.
-- (permissions: "workspaces", "workspaces.focus")
on("focus_workspace", function(id)
    if type(id) ~= "number" then
        log("bar: focus_workspace needs a workspace id, got " .. tostring(id))
        return
    end
    sys.call("workspaces.focus", id)
end)

-- A player is there (the QS `hasPlayer`): the capsule shows only then. The
-- scene cannot compare `media.player` with "" itself — the language compares
-- numbers only — so the logic decides and hands over a fact.
-- (permissions: "media")
-- QS shows the capsule only while a player has something to play: `hasPlayer
-- && (isPlaying || isPaused)` (Bar/Modules/Media.qml:112). A player that is
-- there but stopped (mpc with an empty queue) is not enough, and that is what
-- made the port draw a capsule the reference did not have. "There" is the
-- reference's answer and not the service's: the player the rules below pick.
-- The paused half used to be guessed: the service answered `playing` alone, so the port held
-- `media.present` for ten seconds after `playing` was last true and let a longer pause fall
-- through the gap. The engine answers `paused` since the `pleamar-media-state.patch` build, so
-- the capsule is the reference's own `playing || paused` and nothing here holds a timer.
local mediaShown = false

local function showMedia(on)
    if mediaShown == on then return end
    mediaShown = on
    fact["media.present"] = on
end

-- ------------------------------------------------- cover accent (QS MusicManager)
-- QS samples the current cover with Helpers/AccentSampler.js — the mean of its
-- saturated pixels, two passes — and paints the time's brackets and separator with
-- it. A colour is not a fact, so the scene reads it from an imported file the way
-- it reads theme.plm: this writes ~/.config/pleamar/art.plm and the running scene
-- re-reads that import when it changes.
--
-- It lives here and not in the Cover plugin, because that plugin's logic is
-- approved for `ls` alone: sampling wants magick, and a plugin asking for a new
-- command stops the scene until somebody approves it by hand. The bar runs dash
-- already.
local ACCENT_SCRIPT = [[
set -e
art="$1"
[ -n "$art" ] || exit 0
case "$art" in http*|"") exit 0 ;; esac
art="${art#file://}"
[ -r "$art" ] || exit 0
hex=$(magick "$art" -resize 48x48! -depth 8 txt:- 2>/dev/null | awk '
  $2 ~ /^\(/ {
    t = $2; gsub(/[()]/, "", t); n = split(t, a, ",")
    if (n < 3) next
    r = a[1] + 0; g = a[2] + 0; b = a[3] + 0
    hi = r; if (g > hi) hi = g; if (b > hi) hi = b
    lo = r; if (g < lo) lo = g; if (b < lo) lo = b
    sat = hi - lo; lum = (r + g + b) / 3
    if (sat >= 10 && lum >= 20 && lum <= 235) { r1 += r; g1 += g; b1 += b; n1++ }
    if (sat >= 8  && lum >= 20 && lum <= 240) { r2 += r; g2 += g; b2 += b; n2++ }
  }
  END {
    if (n1 > 0)      printf "#%02x%02x%02x", r1 / n1, g1 / n1, b1 / n1
    else if (n2 > 0) printf "#%02x%02x%02x", r2 / n2, g2 / n2, b2 / n2
  }')
[ -n "$hex" ] || exit 0
mkdir -p "$HOME/.config/pleamar"
printf '// generated from the cover\nlibrary Art strict {\n\n    let cover_accent = %s\n}\n' "$hex" > "$HOME/.config/pleamar/art.plm"
]]

local lastArt = nil

local function accentFrom(art)
    if type(art) ~= "string" or art == "" or art == lastArt then return end
    lastArt = art
    run("dash", { "-c", ACCENT_SCRIPT, "accent", art })
end

local mediaPos = 0
local mediaPlaying = false
-- The last media record, kept for the media tooltip: logic does not get the scene's
-- service binding as a variable, so `media.title` there would index nil.
local mediaNow = {}

-- The stack, as `touchActive` keeps it (MusicPlayers.qml:27-44): the player that changed goes to
-- the front, and only the front five are worth keeping.
local function media_touch(id)
    if type(id) ~= "string" or id == "" then return end
    if mediaStack[1] == id then return end
    local out = { id }
    for _, old in ipairs(mediaStack) do
        if old ~= id and #out < 5 then out[#out + 1] = old end
    end
    mediaStack = out
    -- Written back as the reference writes it (:36-42), so a restart still knows what was heard
    -- last. The whole table is mutated, never rebuilt (INTERFACES §6.1). A failed write is no
    -- reason to lose the media logic — `sys.call` raises — so it is caught, not left to skip the
    -- rest of the handler.
    raw.mediaRecent = mediaStack
    local ok = pcall(function() sys.call("files.write", FILE, raw) end)
    if not ok then log("settings: mediaRecent not saved") end
end

-- MusicIds.js:1-10 — MPD and the players built on it, by bus name and by the name the player
-- gives itself. The reference's regex is `(mpd|mpdris|mopidy|music\s*player\s*daemon)`, folded to
-- lower case; Lua patterns have no alternation, and `mpd` already covers `mpdris`.
local function media_is_mpd(p)
    for _, s in ipairs({ p.id, p.name }) do
        if type(s) == "string" then
            local low = string.lower(s)
            if low:find("mpd", 1, true) or low:find("mopidy", 1, true)
                or low:find("music player daemon", 1, true) or low:find("musicplayerdaemon", 1, true) then
                return true
            end
        end
    end
    return false
end

-- The player the reference would have picked (:87-206), by id; "" when it would have none.
local function media_pick(list)
    -- `getAvailablePlayers` (:76-85): what the service lists, minus the ignored. (QS also drops
    -- the players it cannot control; `players` carries only the ones it can.)
    local avail, by_id = {}, {}
    if type(list) == "table" then
        for _, p in ipairs(list) do
            if type(p) == "table" and type(p.id) == "string" and p.id ~= "" and not mediaIgnored[p.id] then
                avail[#avail + 1] = p
                by_id[p.id] = p
            end
        end
    end

    -- `pruneStack` (:46-56): a player that has gone leaves the stack. Not saved here — the
    -- reference does not save it either; the next touch writes what is left.
    local kept = {}
    for _, id in ipairs(mediaStack) do
        if by_id[id] then kept[#kept + 1] = id end
    end
    mediaStack = kept

    -- `touchActive` on a state change (:233-241). Only `playing` is visible here, and a change in
    -- either direction is one: a pause moves a player to the front in the reference as a play does.
    local seen = {}
    if type(list) == "table" then
        for _, p in ipairs(list) do
            if type(p) == "table" and type(p.id) == "string" and p.id ~= "" then
                local now = p.playing == true
                if mediaSeen[p.id] ~= nil and mediaSeen[p.id] ~= now then media_touch(p.id) end
                seen[p.id] = now
            end
        end
    end
    mediaSeen = seen

    local function in_stack(test)
        for _, id in ipairs(mediaStack) do
            local p = by_id[id]
            if p and test(p) then return p end
        end
        return nil
    end

    local function in_list(test)
        for _, p in ipairs(avail) do
            if test(p) then return p end
        end
        return nil
    end

    local function playing(p) return p.playing == true end
    local function pinned(p) return mediaPinned[p.id] == true end

    -- One rule each, and the same order of attempts as the reference: the stack first, the whole
    -- list after it (:94-152).
    local RULE = {
        pinnedPlaying = function() -- :96-102
            return in_stack(function(p) return playing(p) and pinned(p) end)
                or in_list(function(p) return playing(p) and pinned(p) end)
        end,
        mpdPlaying = function() -- :103-116
            return in_stack(function(p) return playing(p) and media_is_mpd(p) end)
                or in_list(function(p) return playing(p) and media_is_mpd(p) end)
        end,
        anyPlaying = function() return in_stack(playing) or in_list(playing) end, -- :117-124
        mpdRecent = function() return in_stack(media_is_mpd) or in_list(media_is_mpd) end, -- :125-131
        pinned = function() return in_stack(pinned) or in_list(pinned) end, -- :132-138
        recent = function() return in_stack(function() return true end) end, -- :139-144
        -- `selectedPlayerIndex` is 0 in the reference and nothing ever sets it (:14), so `manual`
        -- is its first available player; here, the first the service lists.
        manual = function() return avail[1] end, -- :145-147
        first = function() return avail[1] end, -- :148-149
    }

    for _, rule in ipairs(mediaRules) do
        local check = RULE[rule]
        local hit = check and check()
        if hit then return hit.id end
    end
    -- :205 — past every rule, the reference still answers with the first available player.
    return avail[1] and avail[1].id or ""
end

-- The pick, pinned into the service. `media.choose` takes an id from `players` and makes it the
-- one `media` reports and commands, for the whole process; "" goes back to the service's own
-- default. The pin is only asked for when it is not already in force: a choice makes the service
-- report again, and this runs inside that report.
-- (permissions: "media.*")
local function media_select(list)
    local want = media_pick(list)
    local now = ""
    if type(list) == "table" then
        for _, p in ipairs(list) do
            if type(p) == "table" and p.chosen == true and type(p.id) == "string" then
                now = p.id
                break
            end
        end
    end
    if want ~= now then sys.call("media.choose", want) end
    return want
end

sys.watch("media", function(m)
    local players = (type(m) == "table") and m.players or nil
    if type(m) == "table" then
        mediaNow = m
        accentFrom(m.art)
    end
    -- The reference's pick, with the service pinned on it: from here on `media.player`, the track
    -- and the transport all speak of that player.
    local picked = media_select(players)
    -- A report that carries no `players` at all (an engine older than the field, or one that could
    -- not read the bus) cannot be chosen from: the pick falls back to the player the service names
    -- itself, which is what the bar showed before these rules. Wrong wherever the rules would have
    -- disagreed — and better than a capsule that never comes back.
    if type(players) ~= "table" then
        picked = (type(m) == "table" and type(m.player) == "string") and m.player or ""
    end
    -- Nobody the reference would show — no player on the bus, or every one of them ignored. The
    -- service still reports the ignored player it kept, so the capsule is taken down here.
    if picked == "" then
        showMedia(false)
        return
    end
    -- A player that is there is enough: QS's Media.qml keeps the capsule for
    -- `isPlaying || isPaused`, and the paused half is what the reference shows while the queue
    -- sits where the owner left it. Both halves come from the player's own `PlaybackStatus`
    -- now, so this is the reference's condition and not a timer's guess: a pause keeps the
    -- cover, a stop takes it down at once.
    --
    -- A stopped player also has an empty title — the queue let go of the song — and that keeps
    -- the plate from standing blank for a player with nothing loaded.
    local title = (type(m.title) == "string") and m.title or ""
    local artist = (type(m.artist) == "string") and m.artist or ""
    -- How wide the track's box has to be, in design px. QS sizes the capsule by
    -- `trackContainer.implicitWidth`, which is the title text's own width (Media.qml:103-106),
    -- so the plate hugs the string it holds. The scene cannot ask a measured text for its
    -- width and cap it: a text with `measure:` reports the width it was given, not the
    -- string's own (pleamar's `Layout::size` is `width.unwrap_or(w)`), so `min(tw.width,
    -- 420)` always returned 420. The width is therefore a fact: Iosevka's advance is half
    -- an em, so at the capsule's 14 design px every character is exactly 7. Beyond 420 the
    -- text keeps that width and the engine draws the ellipsis; below it the plate hugs the
    -- string with no hole.
    local MEDIA_TRACK_CHAR = 7
    local MEDIA_TRACK_MAX = 420
    local track = (artist ~= "" and title ~= "") and (artist .. " — " .. title) or title
    local n = utf8.len(track) or #track
    fact.media_w = math.min(MEDIA_TRACK_MAX, n * MEDIA_TRACK_CHAR)
    showMedia((m.playing == true or m.paused == true) and title ~= "")
end)

-- The engine reports `media.position` when the player says something, and never polls it, so
-- the bar's clock would stand still while the track plays. The logic keeps its own: a second
-- per tick while the player is playing, resynced from every report.
sys.watch("media", function(m)
    if type(m) ~= "table" then return end
    if type(m.position) == "number" then mediaPos = math.floor(m.position) end
    mediaPlaying = m.playing == true
    fact["media.pos"] = mediaPos
end)

every(1000, function()
    if not mediaPlaying then return end
    mediaPos = mediaPos + 1
    fact["media.pos"] = mediaPos
end)

-- The transport strip: the three glyph buttons of the media capsule.
-- (permissions: "media.*")
on("media_toggle", function()
    sys.call("media.toggle")
end)

on("media_next", function()
    sys.call("media.next")
end)

-- The transport pill rides out to the left of the capsule, and the cursor has to be
-- able to cross the gap between them: QS holds it open with a 300 ms closeGrace
-- (MediaTransport.qml), and the scene can only say "entered" and "left", so the
-- timer lives here.
local HOVER_HOLD_MS = 300
local hoverTimer = nil

on("media_hover", function(hot)
    if hot then
        if hoverTimer then cancel(hoverTimer) end
        hoverTimer = nil
        fact["media.hot"] = true
        return
    end
    if not fact["media.hot"] then return end
    if hoverTimer then cancel(hoverTimer) end
    hoverTimer = after(HOVER_HOLD_MS, function()
        hoverTimer = nil
        fact["media.hot"] = false
    end)
end)

-- The pill capsule is the tracker's other writer: a press toggles it, and the midnight rollover
-- moves what `bar.plm` mirrors into the scene's `pill.taken`/`pill.streak`. The panels scene draws
-- the same tracker in its calendar grid and cannot see these facts (a plugin's boundary is its
-- own), so it is told over the same `say` the trays and the drawers use; `services: "say:panels"`
-- in bar.plm is what makes the call legal, and a panels scene that is not running is not an error.
local function pill_published()
    pcall(sys.call, "say", "panels", "emit pill_sync")
end
on("fact:pill.taken", pill_published)
on("fact:pill.streak", pill_published)

on("media_prev", function()
    sys.call("media.previous")
end)

-- The bar opens drawers in the `panels` scene: the cover opens the now-playing
-- card, the network capsule opens the flow dashboard — QS's two side panels.
-- That scene is not resident (its only surface is the drawer itself), so it
-- exits a couple of seconds after the last drawer closes; starting the unit and
-- saying where to go is one step. The fact has to arrive *after* the scene has
-- loaded: a `--say` that lands while it is still starting is overwritten by its
-- own defaults (drawer = none), no surface opens, and the scene exits. So wait
-- past the load, then keep asserting the fact for a moment — it is a state, not
-- a press, and saying it twice costs nothing.
-- The drawer is a fact in the panels scene, which runs all the time: the press sends it and
-- nothing else. This used to start the unit, sleep a whole 1.1 s "so it is up", and only then talk
-- to it — a click that arrived in its frame and was answered a second later.
local PLEAMAR = "/run/current-system/sw/bin/pleamar"

-- QS's `OverlayManager.registerOverlay` dismisses whatever was open before it
-- (`Services/OverlayManager.qml:47-53`), and the tray's menu is an overlay like any other — so a
-- drawer opens with the menu shut, and the menu opens with the drawer shut (below). The bar owns
-- only half of that pair: the drawers live in the `panels` scene, which is why one direction is a
-- `--say` and the other is a local call.
-- Forward-declared: the menu's own state machine (`setMenu`) is written after the tray section,
-- because it needs the holds and the collapse; this is the one call the drawer path makes into it.
local close_tray_menu

local function open_drawer(name)
    if close_tray_menu then close_tray_menu() end
    run("dash", {
        "-c",
        "\'" .. PLEAMAR .. "\' --say panels \'fact drawer " .. name .. "\' >/dev/null 2>&1 && exit 0; "
            .. "systemctl --user start pleamar-panels.service; "
            .. "for i in 1 2 3 4 5 6 7 8 9 10; do "
            .. "\'" .. PLEAMAR .. "\' --say panels \'fact drawer " .. name .. "\' >/dev/null 2>&1 && exit 0; "
            .. "sleep 0.05; done",
    })
end

-- A capsule's press toggles the drawer it owns: every one of them is QS's
-- `OverlayToggleCapsule` with `autoToggleOnTap: true` (ClockWidget.qml:32's
-- `calendar.toggle()`, WeatherButton.qml, SystemMonitorCapsule.qml:22, BuildStatus.qml:53,
-- and Media.qml's `toggleSidePanel`), so the press that opened a drawer closes it, and a
-- press on another capsule swaps it. The compositor binds (M4+SH+u/x) call the same
-- function. The drawer's current name comes back from the panels scene in one `--say` — a
-- fact is readable, which a press is not — so nothing here has to remember what is on
-- screen. A closed scene answers nothing, which reads as "not open" and takes the
-- `open_drawer` path.
local function toggle_drawer(name)
    if close_tray_menu then close_tray_menu() end
    local said = '"' .. PLEAMAR .. '" --say panels \'get drawer\' 2>/dev/null'
    run("dash", {
        "-c",
        "cur=$(" .. said .. "); "
            .. "if [ \"$cur\" = \"" .. name .. "\" ]; then "
            .. '"' .. PLEAMAR .. '" --say panels \'fact drawer none\' >/dev/null 2>&1; exit 0; fi; '
            .. '"' .. PLEAMAR .. '" --say panels \'fact drawer ' .. name .. '\' >/dev/null 2>&1 && exit 0; '
            .. "systemctl --user start pleamar-panels.service; "
            .. "for i in 1 2 3 4 5 6 7 8 9 10; do "
            .. '"' .. PLEAMAR .. '" --say panels \'fact drawer ' .. name .. '\' >/dev/null 2>&1 && exit 0; '
            .. "sleep 0.05; done",
    })
end

-- The open-only events stay for callers that want a drawer shown regardless of what is on
-- screen (IPC, or a rule in another scene); the bar's own presses use the toggles below.
on("open_media_panel", function() open_drawer("media") end)
on("open_network_panel", function() open_drawer("network") end)
on("open_calendar_panel", function() open_drawer("calendar") end)
on("open_weather_panel", function() open_drawer("weather") end)
on("open_system_panel", function() open_drawer("system") end)
on("open_build_panel", function() open_drawer("build") end)

-- Each pressable capsule's drawer, by the name `panels` declares (`panels.plm`'s `drawer`
-- enum) — nothing here invents a name.
on("toggle_media_panel", function() toggle_drawer("media") end)
on("toggle_network_panel", function() toggle_drawer("network") end)
on("toggle_calendar_panel", function() toggle_drawer("calendar") end)
on("toggle_weather_panel", function() toggle_drawer("weather") end)
on("toggle_system_panel", function() toggle_drawer("system") end)
on("toggle_build_panel", function() toggle_drawer("build") end)

-- The workspace capsule's press: QS's WsIndicator calls `Expo.toggle()`, which is the
-- `hypr-expo` helper this host's hyprexpo is loaded and configured by. The capsule shows the
-- workspace that is already active, so focusing it would be a press that does nothing — and
-- used to be worse than that: `emit focus` carried no payload, so `workspaces.focus` was
-- called with none and the runtime answered "I don't know how to do 'workspaces.focus' with
-- that" (`bar.luau:78` in the journal).
-- (permissions: "hypr-expo")
on("open_overview", function()
    run("hypr-expo", { "toggle" }, function(_, code)
        if code ~= 0 then log("bar: hypr-expo toggle exited " .. tostring(code)) end
    end)
end)

-- The keyboard capsule's press: QS's KeyboardLayoutHypr calls `switchKeyboardLayout()`, which is
-- `hyprctl switchxkblayout current next` — and `current` is wrong on this host: kanata's virtual
-- keyboard is the last active device, so `current` switches that one alone and leaves the layouts
-- of the boards actually typed on behind ("ok" is all it answers either way). The compositor's own
-- bind says so and uses `all` (`files/gui/hypr/hyprland.lua`, SUPER+S). The label does not change
-- here: the event socket above reports it, and the two-second poll is the net under it.
-- (permissions: "hyprctl")
on("next_layout", function()
    run("hyprctl", { "switchxkblayout", "all", "next" }, function(_, code)
        if code ~= 0 then log("bar: hyprctl switchxkblayout exited " .. tostring(code)) end
    end)
end)

-- The wheel turned over the volume capsule: one step per notch (+ is upwards;
-- the step is the frozen QS one, not yet a settings key).
--
-- QS does not just add the step: `Audio.qml:43,81-88` rounds the level to whole
-- percent and then to the nearest 5 (`roundToStep`), so the wheel lands on 0, 5, 10
-- and never on 43 — and one notch on 43 goes to 50, because 48 rounds up. The engine
-- only offers the relative `audio.step`, so the snap is computed here and the
-- difference handed over; the service still clamps.
-- (permissions: "audio", "audio.*")
-- The last audio sample, kept for the wheel handlers and the tooltip: only the logic can compose a
-- line, and the volume capsule's line is two numbers out of this table.
local audioNow = {}

local function step5(pct, notches, step)
    local target = math.floor((pct + (tonumber(notches) or 0) * step) / step + 0.5) * step
    return math.max(0, math.min(100, target))
end

on("wheel_volume", function(notches)
    local cur = tonumber(audioNow.volume) or 0
    local pct = math.max(0, math.min(100, math.floor(cur * 100 + 0.5)))
    local target = step5(pct, notches, 5)
    if target == pct then return end
    sys.call("audio.step", target / 100 - cur)
end)

-- ------***---------------------- audio capsules
-- QS AudioEndpointCapsule hides itself for two reasons, and the bar has to do
-- the same or the right end is heavier than the reference:
--   · the endpoint is muted (autoHideWhenMuted) — for the microphone that is
--     the whole story;
--   · the sink sits at 100 %: `fullHideTimer` (panel.volume.fullHideMs = 800)
--     collapses the capsule once it has been there that long, and a level that
--     leaves 100 % brings it straight back.
-- The pill text and the icon stay the scene's (`audio.volume`/`audio.input`);
-- only the presence is decided here, because it needs timers and the two
-- fields the language cannot compare.
local FULL_HIDE_MS = 800
local fullHide = nil

local function hideVolume()
    fullHide = nil
    fact["vol.shown"] = false
end

-- (`audioNow`, the last sample, is declared above the wheels that read it.
-- The route the capsule prints instead of the software percentage, and the line the tooltip
-- appends. QS only shows it for a pro-audio sink (`Volume.qml`'s `labelText` and `tooltipValue`
-- are the route's short label when `device.profile.pro` is set); pleamar's audio service does not
-- report that property, so the proxy is `pwroute current` answering something other than
-- `unknown` — which is the same statement from the hardware's side: there is an RME sink and it
-- has an active output pair.
local ROUTE_LABEL = { an = "Analog", aes = "AES/EBU", spdif = "SPDIF", phones = "Phones" }
-- QS's `routeShortLabels`, the ones its capsule prints: the plate is 46 px wide at most and
-- "AES/EBU" does not fit in it, which is why the reference keeps two sets of names.
local ROUTE_SHORT = { an = "AN", aes = "AES", spdif = "SPDIF", phones = "HP" }
local routeNow = "unknown"

-- What the capsule prints while the pointer is on it: the route on a pro sink, the software
-- percentage everywhere else (QS: `labelText` + `labelSuffix`). One live text, because a scene
-- cannot choose between two strings from an `if` and the tile wants a `text`.
local function vol_readout()
    local route = ROUTE_SHORT[routeNow]
    if route then
        text["vol.readout"] = route
        return
    end
    local pct = math.floor((tonumber(audioNow.volume) or 0) * 100 + 0.5)
    text["vol.readout"] = string.format("%d%%", pct)
end

local function route_read()
    run("pwroute", { "current" }, function(out, code)
        local key = (code == 0) and (tostring(out or ""):match("^%s*([%a]+)")) or nil
        if key == nil then key = "unknown" end
        routeNow = key
        fact["vol.pro"] = (key ~= "unknown")
        text["vol.route"] = ROUTE_LABEL[key] or ""
        vol_readout()
    end)
end

local function audioChanged(a)
    if type(a) ~= "table" then return end
    audioNow = a
    -- The icon follows the state, not a constant: what the capsule shows is the first
    -- thing that should say "muted". The scene cannot choose an image from an `if`, so
    -- it gets a number: 0 up, 1 down, 2 off for the sink; 0 live, 1 muted for the source.
    fact["mic.kind"] = (a.input_muted == true) and 1 or 0
    local lvl = tonumber(a.volume) or 0
    fact["vol.kind"] = (a.muted == true) and 2 or (lvl < 0.5 and 1 or 0)
    fact["mic.shown"] = a.input_muted ~= true
    if a.muted == true then
        if fullHide then cancel(fullHide) end
        hideVolume()
        return
    end
    local volume = tonumber(a.volume) or 0
    if volume >= 0.995 then
        if fullHide == nil then fullHide = after(FULL_HIDE_MS, hideVolume) end
    else
        if fullHide then cancel(fullHide) end
        fullHide = nil
        fact["vol.shown"] = true
    end
    -- The reading is composed here as well: a percentage that moves while the pointer is on the
    -- capsule has to move, and the route is the only other thing it can say.
    vol_readout()
end

-- Registered here, not at the top of the section: the service reports as soon as it is watched,
-- and `audioChanged` ends by asking for the reading, which needs the route definitions above.
sys.watch("audio", audioChanged)

-- Once at start, then slowly: a route changes when somebody changes it, and the press below asks
-- again after its own toggle. Two seconds is the keyboard layout's cadence for the same reason.
local ROUTE_POLL_MS = 2000
route_read()
every(ROUTE_POLL_MS, route_read)

-- The volume capsule was pressed. QS's Volume.qml does one thing there — `Services.Audio.
-- toggleRoute()`, which is `pwroute toggle`: the RME AIO Pro's output pair moves between AES/EBU
-- and Analog (this repo's own `packages/pwroute`), whatever sink is default. The port muted
-- instead, which was the only sound command the audio service had, and the capsule said nothing
-- either way.
--
-- `pwroute` exits non-zero when there is no RME sink to move (a laptop, or the card unplugged),
-- and then the press keeps the mute it used to have rather than doing nothing at all. That is a
-- fallback, not parity: the reference had no mute on this press.
-- (permissions: "pwroute", "audio", "audio.*")
on("toggle_route", function()
    run("pwroute", { "toggle" }, function(_, code)
        if code ~= 0 then
            log("bar: pwroute toggle exited " .. tostring(code) .. "; muting instead")
            sys.call("audio.mute")
        end
        route_read()
    end)
end)

-- A press on the microphone capsule: `audio.input_mute` flips the source's
-- silence (QS Microphone.toggleMicMute). (permissions: "audio", "audio.*")
on("toggle_mic", function()
    sys.call("audio.input_mute")
end)

-- The wheel over the microphone tile: QS's Microphone.qml calls
-- `changeMicVolume(notches * 0.05)`, which goes through `Audio.setMicVolume` and its
-- own 5 % snap (`Audio.qml:43,98-104`) — the same rule the sink follows above. The
-- service has no `audio.input_step`, only the absolute `audio.input(0..1)`, so the
-- notch is added to the last sample here.
on("mic_step", function(notches)
    local cur = tonumber(audioNow.input) or 0
    local pct = math.max(0, math.min(100, math.floor(cur * 100 + 0.5)))
    sys.call("audio.input", step5(pct, notches, 5) / 100)
end)

-- ------------------------------------------------------------ workspaces
-- QS's WsIndicator draws ONE capsule: the active workspace's icon and its
-- name. The icon is the Nerd Font glyph `Bar/Icons/workspaces/icon-map.json`
-- gives that workspace's slug (the tree renders them from the SVGs generated
-- out of the same codepoints), and the name is what follows the `𐌸:`-style
-- prefix Hyprland stores in the workspace name.
--
-- Both are text, so they travel to the scene as `text` declarations; the map
-- is by workspace id (the manifest's own numbering), which is what the bar
-- sees for a workspace that was never renamed.
local WS_GLYPH = {
    [1] = "\u{EA85}",  -- term
    [2] = "\u{F269}",  -- web
    [3] = "\u{F4B0}",  -- dev
    [4] = "\u{F1B7}",  -- games
    [5] = "\u{F15C}",  -- doc
    [6] = "\u{F008}",  -- vid
    [7] = "\u{273D}",  -- obs
    [8] = "\u{F03E}",  -- pic
    [9] = "\u{EA7A}",  -- vm
    [10] = "\u{F1CB}", -- wine
    [12] = "\u{F001}", -- daw
    [13] = "\u{F0ED}", -- dw
    [14] = "\u{F11C}", -- keyboard
    [15] = "\u{F086}", -- im
    [16] = "\u{F019}", -- remote
    [17] = "\u{F24D}", -- notes
    [18] = "\u{F1DE}", -- vital
    [19] = "\u{F02C1}", -- rack
}

-- The name as Hyprland stores it, minus a leading private-use glyph — the rule QS
-- keeps in Helpers/WorkspaceName.js (`restAfterIcon`): one leading glyph, nothing
-- else. This used to cut everything up to the first colon, so a workspace the owner
-- named "p:term" was drawn as "term" and the port disagreed with the reference about
-- a name it had no business editing (measured on the bars: QS "p:term", here "term").
local function label_of(name)
    if type(name) ~= "string" or name == "" then return "" end
    local ok, cp = pcall(utf8.codepoint, name, 1)
    if ok and cp >= 0xE000 and cp <= 0xF8FF then
        local after = utf8.offset(name, 2) or (#name + 1)
        name = name:sub(after)
    end
    return (name:gsub("^%s+", ""))
end

-- The workspace names the owner set carry an Old Italic letter in front
-- (`𐌰:term`), and no face the bar uses has it: Iosevka and FiraCode both fall
-- back, fontconfig answers U+10330 with Code2001 while cosmic-text picks another
-- font, so the same name came out with two shapes. The letter is handed to the
-- scene on its own, to be drawn in Code2001 — the face Qt lands on for it.
local function split_lead(name)
    if type(name) ~= "string" or name == "" then return "", "" end
    local ok, cp = pcall(utf8.codepoint, name, 1)
    if ok and cp >= 0x10300 and cp <= 0x1034F then
        local after = utf8.offset(name, 2) or (#name + 1)
        return name:sub(1, after - 1), name:sub(after)
    end
    return "", name
end

local function workspacesChanged(w)
    if type(w) ~= "table" or type(w.list) ~= "table" then return end
    for _, ws in ipairs(w.list) do
        if type(ws) == "table" and ws.active == true then
            local lead, rest = split_lead(label_of(ws.name))
            -- A workspace with no name (or a name that is only a private-use glyph) drew an
            -- empty plate; the reference falls back to the number, and so does this.
            if rest == "" then rest = tostring(ws.id) end
            text.ws_lead = lead
            text.ws_label = rest
            text.ws_icon = WS_GLYPH[tonumber(ws.id) or -1] or ""
            return
        end
    end
    text.ws_lead = ""
    text.ws_label = ""
    text.ws_icon = ""
end

sys.watch("workspaces", workspacesChanged)

-- ---------------------------------------------- link, internet and the tunnel
-- QS asks three separate questions about the connection and never confuses them
-- (Services/Connectivity.qml): is there a LINK — some non-loopback interface that is up —, is
-- there INTERNET — a ping that comes back —, and is there a TUNNEL among those interfaces
-- (Components/ConnectivityState.qml). The kernel's `network.online` is one flag: it cannot say
-- "the cable is in and the router has no uplink", which is the state the capsule's warning ink
-- exists for (NetClusterCapsule.qml:41-43).
--
-- The timings are the reference's own:
--   · the link is read from `ip -j -br a` every 4 s   — Connectivity.qml:47-49, Theme.qml:754
--                                                       (`networkLinkPollMs`)
--   · the ping runs every 30 s                         — Connectivity.qml:86-88, Settings.qml:217
--                                                       (`networkPingIntervalMs`)
--   · and every 500 ms for 10 s after a link comes up  — Connectivity.qml:23-26 and 115-127
--                                                       (`fastIntervalMs` / `fastDurationMs`)
--   · the target is 8.8.8.8                            — Settings.qml:218 (`networkPingTarget`)
-- The reference wraps the ping in `dash -c … && echo OK || echo FAIL` (Connectivity.qml:107-110)
-- because its ProcessRunner collects lines rather than exit codes; `ping`'s own exit code says
-- the same, so the command is asked directly and nothing is spawned in between.
local PING_TARGET = "8.8.8.8"
local LINK_POLL_MS = 4000
local PING_SLOW_MS = 30000
local PING_FAST_MS = 500
local PING_FAST_FOR_MS = 10000

local net_link, net_internet, net_vpn = false, false, false
-- "ifname: address" for the links that are up, at most two, the way the reference's tooltip names
-- them (`NetClusterCapsule.qml:229-245`: one hint per interface, `name: 1.2.3.4`).
local net_hints = {}
local net_vpn_state = ""
local net_fast, net_ping_busy = false, false
local net_fast_stop = nil
-- The Hiddify tray item (ConnectivityState.qml:48-60): the reference finds it by id or title,
-- draws its icon in the VPN slot and gives the slot's presses to it.
local net_hiddify, net_hiddify_key = false, ""

-- ConnectivityState.qml:25-46: a tunnel is an interface whose name says so (`awg`, `amnez`,
-- `tun`, `outline-tun`) and that has an address on it; its name is what the tooltip prints.
local function tunnel_of(name, addrs)
    local lower = name:lower()
    local looks = lower:find("awg", 1, true) ~= nil
        or lower:find("amnez", 1, true) ~= nil
        or lower:sub(1, 3) == "tun"
        or lower:sub(1, 11) == "outline-tun"
    return looks and addrs > 0
end

local function net_publish()
    if fact["net.link"] ~= net_link then fact["net.link"] = net_link end
    if fact["net.internet"] ~= net_internet then fact["net.internet"] = net_internet end
    if fact["net.vpn"] ~= net_vpn then fact["net.vpn"] = net_vpn end
    -- `vpnInterface` when it has one, "connected" otherwise: the reference's own word for the
    -- tooltip is "VPN: connected" (NetClusterCapsule.qml:234), and the name is the detail.
    local state = net_vpn and (net_vpn_state ~= "" and net_vpn_state or "connected") or ""
    if text["net.vpn_state"] ~= state then text["net.vpn_state"] = state end
end

-- The reference's hint line, verbatim (NetClusterCapsule.qml:231-235).
local function net_state_line()
    local line
    if not net_link then
        line = "No connection"
    elseif not net_internet then
        line = "Local network, no internet"
    else
        line = "Internet: available"
    end
    if net_vpn then
        line = line .. " · VPN: " .. (net_vpn_state ~= "" and net_vpn_state or "connected")
    end
    -- The links themselves, named with their first IPv4 address, as the reference's tooltip does
    -- (`NetClusterCapsule.qml:229-245`: one hint per interface, `name: 1.2.3.4`); the card holds
    -- two of them, so the probe keeps two.
    if #net_hints > 0 then line = line .. " · " .. table.concat(net_hints, " · ") end
    return line
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
    -- Connectivity.qml:123-127: the fast mode stops by itself after 10 s, however the ping went.
    if net_fast_stop then cancel(net_fast_stop) end
    net_fast_stop = after(PING_FAST_FOR_MS, function()
        net_fast_stop = nil
        net_fast = false
    end)
    net_ping()
end

net_ping = function()
    -- One ping in flight at a time: at 500 ms a probe against a black-holed target would
    -- otherwise pile up processes (the reference guards its slow path the same way,
    -- Connectivity.qml:87-93).
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
        local hints = {}
        for _, it in ipairs(list) do
            if type(it) == "table" and type(it.ifname) == "string" and it.ifname ~= "lo" then
                local state = (type(it.operstate) == "string") and it.operstate or ""
                local addrs = (type(it.addr_info) == "table") and #it.addr_info or 0
                if state == "UP" or (state == "UNKNOWN" and addrs > 0) then
                    link = true
                    -- The address the reference's tooltip prints beside the interface: the first
                    -- IPv4 one, and the name alone when the link carries none yet.
                    if #hints < 2 then
                        local ip = ""
                        for _, a in ipairs((type(it.addr_info) == "table") and it.addr_info or {}) do
                            -- `local` is a reserved word in Lua and `ip -j -br a` names the field that
                            -- way, so it is read with a bracket; brief mode leaves `family` out
                            -- entirely (measured), and an address with a colon is the IPv6 one.
                            local addr = type(a) == "table" and a["local"] or nil
                            if type(addr) == "string" and not addr:find(":") then
                                ip = addr
                                break
                            end
                        end
                        hints[#hints + 1] = (ip ~= "") and (it.ifname .. ": " .. ip) or it.ifname
                    end
                end
                if tunnel_of(it.ifname, addrs) then vpn, name = true, it.ifname end
            end
        end
        net_hints = hints
        local was_link = net_link
        net_link, net_vpn, net_vpn_state = link, vpn, name
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

-- Connectivity.qml:129-130: one link check on start-up, then the poll.
net_probe_link()
every(LINK_POLL_MS, net_probe_link)
-- The two ping cadences, exactly as the reference keeps them apart: the slow one is off while
-- the fast mode holds (Connectivity.qml:86-88, `running: !root.fastMode`) and the fast one runs
-- only then (Connectivity.qml:114-121).
every(PING_SLOW_MS, function()
    if not net_fast then net_ping() end
end)
every(PING_FAST_MS, function()
    if net_fast and net_link then net_ping() end
end)

-- ConnectivityState.qml:48-60: the Hiddify item is the tray record whose id or title says so.
-- `net.hiddify` is what the scene can act on — the item has a picture to draw in the VPN slot;
-- the key stays here, because an activation and a menu both take it.
local function net_read_hiddify(list)
    local found, key, icon = false, "", ""
    for _, it in ipairs(list or {}) do
        if type(it) == "table" then
            local id = (type(it.id) == "string") and it.id:lower() or ""
            local title = (type(it.title) == "string") and it.title:lower() or ""
            if id:find("hiddify", 1, true) ~= nil or title:find("hiddify", 1, true) ~= nil then
                found = true
                key = (type(it.key) == "string") and it.key or ""
                icon = (type(it.icon) == "string") and it.icon or ""
                break
            end
        end
    end
    net_hiddify_key = found and key or ""
    -- QS hides the shield only when it has a picture to put in its place
    -- (`hiddifyHasTrayIcon`, NetClusterCapsule.qml:35): an item without one keeps the shield.
    local has_icon = found and icon ~= ""
    if has_icon ~= net_hiddify then
        net_hiddify = has_icon
        fact["net.hiddify"] = has_icon
    end
    if text["net.hiddify_icon"] ~= icon then text["net.hiddify_icon"] = icon end
end

-- ------------------------------------------------------------- tooltips
-- QS gives every capsule a PanelTooltip whose text TooltipText.compose builds
-- out of a title, a value and a list of hints. The scene says which capsule the
-- cursor is on (`emit tip(n)`), and the line is written here, because only the
-- logic can compose text.
-- (permissions: "clock", nothing else — the rest it already watches)
local tipClock = ""

sys.watch("clock", function(c)
    if type(c) == "table" and type(c.date) == "string" then tipClock = c.date end
end)

local function tip_line(i)
    if i == 0 then
        -- `compose("Clock", <date>, ["Click — calendar"])` (ClockWidget.qml:19-29): the card's first
        -- line is the title and its value, then the hints, one per line.
        return "Clock: " .. (tipClock ~= "" and tipClock or "—") .. "\nClick — calendar"
    elseif i == 1 then
        -- `compose("Workspace", <id>, [<description>, "Click — workspace overview"])`
        -- (WsIndicator.qml:90-98). The port has no description table, so the hint is the click.
        return "Workspace: " .. (text.ws_label ~= "" and text.ws_label or "?")
            .. "\nClick — workspace overview"
    elseif i == 2 then
        -- `compose("Layout", layout, ["Device: <name>", "Mode: <submap>", "Click — next layout"])`,
        -- the reference's own three hints (KeyboardLayoutHypr.qml:12-18); the wheel was added on
        -- this bar and the hint says so.
        local lines = { "Layout: " .. (text.kb_layout ~= "" and text.kb_layout or "?") }
        if text.kb_device ~= "" then lines[#lines + 1] = "Device: " .. text.kb_device end
        if text.kb_mode ~= "" then lines[#lines + 1] = "Mode: " .. text.kb_mode end
        lines[#lines + 1] = "Click or scroll — next layout"
        return table.concat(lines, "\n")
    elseif i == 3 then
        -- ConnUi prints the pair as "<rx> / <tx>"; the tooltip says both, and under them the
        -- connection's state in the reference's own words (NetClusterCapsule.qml:229-245):
        -- "No connection" / "Local network, no internet" / "Internet: available", then
        -- "VPN: connected". The card takes the second line (its `lines:` is three).
        return "Throughput " .. (text.net_rx ~= "" and (text.net_rx .. text.net_rx_unit) or "--")
            .. " down, " .. (text.net_tx ~= "" and (text.net_tx .. text.net_tx_unit) or "--") .. " up"
            .. "\n" .. net_state_line()
    elseif i == 4 then
        -- SystemMonitorCapsule.qml:22-35, `TooltipText.compose("Monitoring", "", hints)`: CPU, GPU
        -- (only when the probe found one), RAM with the pair, the temperature, and the click line.
        local lines = { "Monitoring" }
        lines[#lines + 1] = string.format("CPU: %d%%", math.floor((fact.cpu or 0) * 100 + 0.5))
        if fact["has.gpu"] == true then
            lines[#lines + 1] = string.format("GPU: %d%%", math.floor((fact.gpu or 0) * 100 + 0.5))
        end
        lines[#lines + 1] = string.format("RAM: %d%% (%.1f / %d GiB)",
            math.floor((fact.ram or 0) * 100 + 0.5), tonumber(fact.ram_used_gib) or 0,
            tonumber(fact.ram_total_gib) or 0)
        local c = (tonumber(fact.temp) or 0) * 70 + 30
        lines[#lines + 1] = string.format("Temperature: %d°C", math.floor(c + 0.5))
        lines[#lines + 1] = "Click — monitoring panel"
        return table.concat(lines, "\n")
    elseif i == 6 then
        -- (the media card is built below from `mediaNow`, a *service* — those are live for this
        -- logic, unlike a plugin's boundary; the quality line is added by `media_tip` on hover)
        -- The media card: title — artist, then one compact line of album and player. The album
        -- is dropped when it repeats the artist (MPD often hands the same string for both).
        local l1 = (mediaNow.title or "") .. ((mediaNow.artist and mediaNow.artist ~= "") and (" — " .. mediaNow.artist) or "")
        if l1 == "" then l1 = "Nothing playing" end
        local meta = {}
        local album = mediaNow.album or ""
        if album ~= "" and album ~= (mediaNow.artist or "") then meta[#meta + 1] = album end
        if mediaNow.player and mediaNow.player ~= "" then meta[#meta + 1] = mediaNow.player end
        if #meta > 0 then return l1 .. "\n" .. table.concat(meta, " · ") end
        return l1
    elseif i == 7 then
        -- The volume capsule: the mixer's own numbers, as the capsule prints them, and the RME
        -- route beside them when there is one — QS's Volume.qml prints the route through
        -- `tooltipValue` and its "Left click to toggle AES / Analog." hint on a pro-audio sink.
        local pct = math.floor((tonumber(audioNow.volume) or 0) * 100 + 0.5)
        local line = string.format("Volume %d %%%s", pct, audioNow.muted == true and " (muted)" or "")
        local route = ROUTE_LABEL[routeNow]
        if route then line = line .. " · " .. route .. " (click toggles)" end
        return line
    elseif i == 8 then
        local pct = math.floor((tonumber(audioNow.input) or 0) * 100 + 0.5)
        return string.format("Microphone %d %%%s", pct, audioNow.input_muted == true and " (muted)" or "")
    elseif i == 9 then
        -- The pill (QS PillCapsule's PanelTooltip): "Taken at <time>", or that it is not taken —
        -- with the streak the plugin keeps, which the reference only drew in the calendar.
        -- The scene's mirror of the plugin's state (`bar.plm`'s `pill.*` rules): the plugin's own
        -- facts do not reach this logic (measured 2026-10-31 — the scene had `Pill.taken` true and
        -- this card answered «Pill not taken yet»).
        local streak = tonumber(fact["pill.streak"]) or 0
        local line
        if fact["pill.taken"] == true then
            local at = tostring(text["pill.at"] or "")
            line = (at ~= "") and ("Pill taken at " .. at) or "Pill taken"
        elseif fact["pill.reminder"] == true then
            line = "Pill not taken yet!"
        else
            line = "Pill not taken yet"
        end
        if streak > 0 then line = line .. " · streak " .. streak end
        return line
    -- 10 and 11 never reach here: `on("tip")` sends them to `mpd_tip()` and `genelec_tip()`,
    -- which read the scene's own mirror of the plugin state — the plugins' facts are stale for this
    -- logic (measured 2026-10-31), and a branch here read exactly those.
    elseif i == 12 then
        return text.tip_title ~= "" and text.tip_title or "Tray item"
    elseif i == 5 then
        local parts = { "Weather" }
        if text["weather.temp"] ~= "" then parts[#parts + 1] = text["weather.temp"] end
        if text["weather.hum"] ~= "" then parts[#parts + 1] = text["weather.hum"] end
        if text["weather.wind"] ~= "" then parts[#parts + 1] = text["weather.wind"] .. " m/s" end
        return table.concat(parts, " · ")
    end
    return ""
end

-- QS's tooltip waits `tooltip.delayMs` (Settings/Theme.qml, 150 ms) before it appears, so a
-- pointer crossing the strip does not flash a card per capsule. The scene emits `tip(n)` on
-- enter and `tip_hide` on leave; a leave inside the 150 ms window cancels the pending card.
--
-- The card's size is not guessed here. The bar measures the text it draws (`measure tipw` and
-- `tiph` in `bar.plm`), and a measure is what the frame before produced — so the surface the
-- card lives on goes up at once (`tip_hover`) and the card follows after the delay: by the time
-- it shows, the words have been shaped in the room it is drawn in. What was here before — six
-- px a character, fifteen a line — was the advance of Iosevka at 12 px, and wrong for every
-- face that is not: a tray title, a wide glyph, a Cyrillic word.
local TIP_DELAY = 150
local tipTimer = nil

local function hideTip()
    if tipTimer then
        cancel(tipTimer)
        tipTimer = nil
    end
    fact.tip_open = false
    fact.tip_hover = false
end

local function showTip(i)
    text.tip_body = tip_line(i or 0)
    fact.tip_hover = true
    if tipTimer then cancel(tipTimer) end
    tipTimer = after(TIP_DELAY, function()
        tipTimer = nil
        fact.tip_open = true
    end)
end

on("tip_hide", hideTip)

-- The MPD card is built from `mpc status`, not from the flags plugin: those facts are live for the
-- renderer and stale here (measured 2026-10-31 — `Mpd.repeat` true in the scene, the tool saying
-- `repeat: on`, and this card answering "unknown / No active flags"), which is the same boundary the
-- build badge hit. One `mpc status` per hover is the cheapest way to be right.
local function mpd_tip()
    text.tip_body = "MPD · …"
    fact.tip_hover = true
    if tipTimer then cancel(tipTimer) end
    tipTimer = after(TIP_DELAY, function()
        tipTimer = nil
        fact.tip_open = true
    end)
    run("mpc", { "status" }, function(out)
        local s = tostring(out or "")
        -- `mpc status` prints the volume line and, only while something plays or pauses, a
        -- `[playing]`/`[paused]` line under it: no marker is stopped, not "unknown".
        local state = s:match("%[playing%]") and "playing"
            or s:match("%[paused%]") and "paused"
            or "stopped"
        local on = {}
        for _, name in ipairs({ "repeat", "random", "single", "consume" }) do
            if s:match(name .. ":%s*on") then on[#on + 1] = name end
        end
        text.tip_body = "MPD · " .. state .. "\n"
            .. ((#on > 0) and table.concat(on, " · ") or "No active flags")
    end)
end

-- The Genelec card, for the same reason as the MPD one: the plugin's facts do not reach this logic.
-- Measured 2026-10-31 — the scene said `Genelec.volume` -50, `glm-vol read` said -50, and the card
-- said «-40 dB · host GLM adapter», which is the library's declared default *and* the wrong path
-- (`genlc discover` answers "GLM USB adapter not found", so the adapter is in the VM).
-- `glm-vol read` is the live level; the cap and the mode are left out rather than printed stale.
local function genelec_tip()
    text.tip_body = "Genelec SAM · …"
    fact.tip_hover = true
    if tipTimer then cancel(tipTimer) end
    tipTimer = after(TIP_DELAY, function()
        tipTimer = nil
        fact.tip_open = true
    end)
    run("glm-vol", { "read" }, function(out, code)
        local level = tostring(out or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if code ~= 0 or level == "" then
            text.tip_body = "Genelec SAM · no reading"
            return
        end
        text.tip_body = "Genelec SAM · " .. level .. " dB\nwheel — level · press — mute"
    end)
end

-- The media card's quality line (QS prints "Quality: codec · bitrate · sample rate · bit depth").
-- The base lines come from the `media` service, which this logic reads live; the figures need the
-- track's own file, so they come from `playerctl` and `ffprobe` on hover — the same two tools the
-- Meta plugin uses for the sidebar rows.
local function quality_of(url)
    local path = url:match("^file://(.+)$") or url:match("^(/.+)$")
    if not path then return nil end
    path = path:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
    local done = false
    run("ffprobe", {
        "-v", "error", "-show_entries",
        "stream=codec_name,bit_rate,sample_rate,bits_per_raw_sample,channels",
        "-of", "default=nw=1:nk=0", path,
    }, function(out)
        -- The first stream wins: a track with embedded cover art has a second one, and ffprobe
        -- prints `N/A` for what a stream does not carry (a FLAC's bit_rate is one of those).
        local f = {}
        for key, value in tostring(out or ""):gmatch("([%w_]+)=([^\r\n]+)") do
            if f[key] == nil then f[key] = value end
        end
        local parts = {}
        if f.codec_name and f.codec_name ~= "" and f.codec_name ~= "N/A" then
            parts[#parts + 1] = f.codec_name
        end
        local kbps = math.floor((tonumber(f.bit_rate) or 0) / 1000 + 0.5)
        if kbps > 0 then parts[#parts + 1] = kbps .. " kbps" end
        local khz = (tonumber(f.sample_rate) or 0) / 1000
        if khz > 0 then parts[#parts + 1] = string.format("%.1f kHz", khz) end
        local bits = tonumber(f.bits_per_raw_sample) or 0
        if bits > 0 then parts[#parts + 1] = bits .. "-bit" end
        if #parts == 0 then return end
        text.tip_body = text.tip_body .. "\nQuality: " .. table.concat(parts, " · ")
    end)
end

local function media_tip()
    showTip(6)
    run("playerctl", { "metadata", "xesam:url" }, function(out)
        local url = tostring(out or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if url == "" or url == "No player could handle this command" then return end
        quality_of(url)
    end)
end

on("tip", function(i)
    if i == 6 then
        media_tip()
    elseif i == 10 then
        mpd_tip()
    elseif i == 11 then
        genelec_tip()
    else
        showTip(i)
    end
end)

-- The build badge's card. QS keeps the tool's own text in `statusTooltip` and hands it to a
-- `PanelTooltip`; this logic cannot read the plugin's boundary (a plugin's facts are live for the
-- renderer and stale here — measured 2026-10-31), so it asks the tool the plugin runs, once, on
-- hover. `--format plain` is the state line, `--format list` one line per build; together they are
-- the card, capped at the six lines `bartip` holds.
local function build_tip()
    run("nixbuild-status", { "--format", "plain", "--icons", "none", "--no-color" }, function(out)
        local head = tostring(out or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if head == "" then head = "nothing running" end
        run("nixbuild-status", { "--format", "list", "--icons", "none", "--no-color" }, function(lines)
            local body = { "Nix build: " .. head }
            local seen = 0
            for line in tostring(lines or ""):gmatch("[^\r\n]+") do
                if seen >= 3 then break end
                seen = seen + 1
                body[#body + 1] = line
            end
            body[#body + 1] = "Click — build drawer"
            text.tip_body = table.concat(body, "\n")
        end)
    end)
end

on("build_hover", function(inside)
    if inside ~= 1 then
        hideTip()
        return
    end
    -- `showTip`'s shape, with an asynchronous body: the card opens on the same delay, and the text
    -- lands in it whenever the tool answers (a live text, so the card fills itself).
    text.tip_body = "Nix build: …"
    fact.tip_hover = true
    if tipTimer then cancel(tipTimer) end
    tipTimer = after(TIP_DELAY, function()
        tipTimer = nil
        fact.tip_open = true
    end)
    build_tip()
end)

-- ---------------------------------------------------------------- tray
-- The icons come from the StatusNotifier host as they are: a record's fields are
-- `key`, `title`, `icon` (a name or a path) with the rest ignored, so the list
-- goes straight into the model. A click comes back as the record's INDEX — an
-- event carries a number — so the keys are kept here, in the same order.
local trayItems = {}

-- An item that brings no picture is drawn with the reference's stand-in glyph
-- (`Components/TrayIcon.qml:126` — no source, or one that failed to load — with
-- `trayFallbackIcon`, "broken_image" on this host). The scene compares numbers only and cannot
-- look inside a text, so each row carries the answer as a flag of its own; a picture that fails
-- to load is the engine's to report and cannot be seen from here at all.
sys.watch("tray", function(list)
    trayItems = (type(list) == "table") and list or {}
    local rows = {}
    for i, item in ipairs(trayItems) do
        if type(item) == "table" then
            rows[i] = {
                key = item.key,
                id = item.id,
                title = item.title,
                icon = item.icon,
                menu = item.menu,
                no_icon = (type(item.icon) ~= "string" or item.icon == ""),
            }
        end
    end
    model.icons = rows
    -- The Hiddify item among them: the VPN slot in the network capsule draws its icon and takes
    -- its presses (NetClusterCapsule.qml:34-36, 96-131).
    net_read_hiddify(trayItems)
end)

-- ------------------------------------------------ tray: the hold/collapse machine
-- QS keeps four timers in `Services/TrayController.qml` and the flags they move in
-- `Bar/Modules/SystemTray.qml`. A rule cannot run a program, and a scene cannot hold a timer, so
-- both live here: the scene reports where the pointer is (`tray_hot`, `tray_icons`, `tray_panel`)
-- and what was pressed (`tray_toggle`, `tray_press`, `tray_menu`, `tray_close`), and reads back
-- one fact — `tray.expanded` — to draw the icons or nothing.
--
-- Durations, each with the token it is: `panel.tray.longHoldMs` 2500 (Settings/Theme.qml:721),
-- `panel.tray.shortHoldMs` 1500 (:722), `panel.tray.guardMs` 120 (:723),
-- `panel.tray.overlayDismissDelayMs` 5000 (:724). palette.plm already carries the same four
-- (`tray.long`, `tray.short`, `tray.guard`, `tray.dismiss`), but a scene's import is not readable
-- from the logic, so they are written again here and the palette stays the one the drawing reads.
local TRAY_LONG_HOLD, TRAY_SHORT_HOLD = 2500, 1500
local TRAY_GUARD, TRAY_DISMISS = 120, 5000

local trayOn = false        -- `expanded`        (SystemTray.qml:76)
local trayHot = false       -- `hotHover`        (:25) — the corner over the bar's bottom right
local trayOverIcons = false -- the icons' own hover, QS's inline box (:129-132)
local trayPanel = false     -- `panelHover`      (:14) — the whole strip
local trayHold = false      -- `holdOpen`        (:26) — the tray's menu has been seen
local trayShort = false     -- `shortHoldActive` (:27)
local trayGuard = false     -- `openGuard`       (:77)
local longT, shortT, guardT, dismissT = nil, nil, nil, nil

local function stopLongHold()
    if longT then
        cancel(longT)
        longT = nil
    end
end

-- `shortHoldActive` is the caller's flag in the reference (TrayController only stops the timer,
-- SystemTray clears it) and both are always cleared together, so the flag goes with the timer.
local function stopShortHold()
    if shortT then
        cancel(shortT)
        shortT = nil
    end
    trayShort = false
end

local function stopDismiss()
    if dismissT then
        cancel(dismissT)
        dismissT = nil
    end
end

-- Forward-declared: the tray going out closes its menu, and the menu closing is what arms the
-- long hold, so one of the two has to name the other before either is written.
local setMenu

--- The one fact the drawing reads. Going out takes the menu with it (SystemTray.qml:232-237).
local function trayShow(on)
    if trayOn == on then return end
    trayOn = on
    fact["tray.expanded"] = on
    if on then return end
    -- A tray that is out has no collapse delay left to run: QS's programmatic dismissal stops it
    -- before it folds the tray away (`SystemTray.qml:92-95`).
    stopDismiss()
    -- The icons are gone, so nothing can be over them: a zone that disappears takes its pointer
    -- with it and the scene says no `leave`, which would leave this flag set for good.
    trayOverIcons = false
    if fact.tray_open == true then setMenu(false) end
end

--- A collapse asked for while the trigger's guard is up is dropped. The reference arms `openGuard`
--- and clears it 120 ms later (`SystemTray.qml:77`, `:226`, `:35`) and then never reads it; what the
--- name says it is for is this, and a press on the trigger is the only thing that sets it.
local function trayCollapse()
    if trayGuard then return end
    trayShow(false)
end

--- `onLongHold` (SystemTray.qml:32): the menu has been gone for 2500 ms and the tray goes with it,
--- whatever the pointer is doing.
local function startLongHold()
    stopLongHold()
    longT = after(TRAY_LONG_HOLD, function()
        longT = nil
        trayHold = false
        trayCollapse()
    end)
end

--- `onShortHold` (:33): the pointer left the corner and nothing else holds the tray.
local function startShortHold()
    stopShortHold()
    trayShort = true
    shortT = after(TRAY_SHORT_HOLD, function()
        shortT = nil
        trayShort = false
        if trayPanel or trayHot or trayHold then return end
        trayCollapse()
    end)
end

--- `onCollapseDelay` (:34): a press outside the tray's menu gives it 5000 ms, not an instant exit.
local function startDismiss()
    stopDismiss()
    dismissT = after(TRAY_DISMISS, function()
        dismissT = nil
        trayCollapse()
    end)
end

--- `onGuardOff` (:35).
local function startGuard()
    trayGuard = true
    if guardT then cancel(guardT) end
    guardT = after(TRAY_GUARD, function()
        guardT = nil
        trayGuard = false
    end)
end

--- The menu's own visibility, and what QS does around it (SystemTray.qml:239-253): while it is
--- open the tray cannot go away and both holds are called off; when it closes, `holdOpen` stays
--- set and the long hold runs, so the tray stands 2500 ms more and then leaves.
setMenu = function(open)
    if fact.tray_open == open then return end
    fact.tray_open = open
    -- A new menu opens with no row under the cursor: the wash is the pointer's, and the last menu's
    -- row would be lit on a menu the pointer never touched.
    if open then fact["tm.hot"] = 0 end
    if open then
        trayShow(true)
        trayHold = true
        stopLongHold()
        stopShortHold()
    else
        trayHold = true
        startLongHold()
    end
end

close_tray_menu = function()
    if fact.tray_open == true then setMenu(false) end
end

-- An event carries a number, so the scene's `emit tray_hot(1)` arrives here as 1 and not as `true`
-- — `1 == true` is false in Luau, and every one of the tray's three hover handlers compared it that
-- way: the reveal corner, the icons and the strip all did nothing, and the tray could only be
-- opened by `--say bar "emit tray_toggle"`. Measured 2026-10-26: three StatusNotifier items were
-- registered and the bar drew none of them.
local function truthy(v)
    if v == true then return true end
    return (tonumber(v) or 0) ~= 0
end

--- The corner over the bar's bottom right — QS's hot zone, `Bar.qml:1246-1260` — whose only job is
--- this (`onHotHoverChanged`, SystemTray.qml:38-50): coming onto it brings the tray out at once and
--- calls off a pending short hold; leaving it starts one, unless the menu or the strip hold it.
on("tray_hot", function(hot)
    local on = truthy(hot)
    if trayHot == on then return end
    trayHot = on
    if on then
        stopShortHold()
        trayShow(true)
        return
    end
    if trayPanel or fact.tray_open == true or trayHold then return end
    startShortHold()
end)

--- The icons themselves keep the tray out while the pointer is on them (the reference's inline
--- hover area, SystemTray.qml:129-132): entering brings it out, leaving takes it away at once
--- unless the strip, the corner, the menu or a short hold still want it.
on("tray_icons", function(over)
    local on = truthy(over)
    if trayOverIcons == on then return end
    trayOverIcons = on
    if on then
        trayShow(true)
        return
    end
    if trayPanel or trayHot or trayHold or trayShort then return end
    trayCollapse()
end)

--- The whole strip (`panelHover`): it never brings the tray out, it only keeps it up — leaving the
--- bar is what `Bar.qml:1284-1290` does after its 350 ms grace, and the grace is not reproduced,
--- so the tray goes as the pointer leaves.
on("tray_panel", function(over)
    local on = truthy(over)
    if trayPanel == on then return end
    trayPanel = on
    if on then return end
    if trayHot or trayHold or trayShort or fact.tray_open == true then return end
    trayCollapse()
end)

--- A press on the collapsed trigger (SystemTray.qml:224-229): it turns the tray over and, when it
--- brings it out, arms the guard.
on("tray_toggle", function()
    if trayOn then
        trayShow(false)
        return
    end
    trayShow(true)
    startGuard()
end)

-- QS's left click on an icon is `modelData.activate()`, which is what
-- `tray.activate` asks the item for. The right button is the item's own menu, and
-- the reference's SystemTray asks the application for it rather than drawing one:
-- `tray.context` is that request, so this scene needs no popup surface for it. A
-- drawn menu (`sys.ask("tray.menu", key)` as a tree, `lib/menu.plm` painting it)
-- is the parity step that still waits for a popup here.

on("tray_press", function(index)
    setMenu(false)
    local item = trayItems[(index or 0) + 1]
    if type(item) == "table" and type(item.key) == "string" then
        sys.call("tray.activate", item.key)
    end
    -- SystemTray.qml:185-189: the press also folds the tray away, it does not only activate.
    trayCollapse()
end)

--- Raise the window behind the tray item whose menu was just clicked. `window-activate` is a
--- no-op for a label that is not an open request (exit 1), so the helper can be asked on every
--- row; only a real failure (2) is worth a line in the scene's log.
local function raise_tray()
    local id = text["tray_id"]
    local title = text["tray_title"]
    if type(id) ~= "string" or id == "" then return end
    run("window-activate", { "--raise-for", id, "--tray-title", title or "", "--stdout-report" }, function(out, code)
        if code == 0 then
            log("raise: " .. tostring(out))
        elseif code == 2 then
            log("raise failed: " .. tostring(out))
        end
    end)
end

-- The menu's rows, as the last `open_tray_menu` published them, and the ids that go with them: the
-- scene draws the model and hands back a row number, and a model is one way — the id that
-- `tray.menu_click` wants stays here, at the same place in this list.
-- How many rows the menu can hold at all (a tray menu that long is a menu nobody reads), and how
-- many of them fit in the plate at once: the rest scroll, so a longer menu is reachable instead of
-- being cut off at the edge of the window.
local TRAY_MENU_MAX = 64
local TRAY_MENU_ROWS = 14
local tray_menu_ids = {}

-- The right button on an icon: the item's own menu, drawn by the bar. The scene hands over
-- the record's index; the key that names the bus name and the object path is looked up here.
-- A second press closes it, and a left click does too.
-- The engine wants the icon's key *and* the line's id (`tray.menu_click`, tray.rs:command),
-- and it raises when it does not get both — which is why a press used to leave the menu open:
-- the handler died before it could close it.
on("tray_click", function(n)
    local at = tonumber(n) or 0
    local key = text["tray_key"]
    local id = tray_menu_ids[at]
    setMenu(false)
    if type(key) == "string" and key ~= "" and type(id) == "number" and id > 0 then
        -- Wrapped: a failing call must not roll back `tray_open` — a menu that stays up after a
        -- press is worse than a click that did nothing.
        local ok, err = pcall(function() sys.call("tray.menu_click", key, id) end)
        if not ok then log("TRAYCLICK failed: " .. tostring(err)) end
    end
    -- "Open Telegram" is a request for a window, and the menu item alone does not bring one up
    -- on this compositor. The reference uses its `window-activate` helper, which owns the policy
    -- (which labels mean "bring it up", and the tray-id -> class exceptions) and finds the window
    -- through Hyprland, special workspaces included. The bar calls the same helper: its own
    -- `hyprctl dispatch focuswindow` is the deprecated shorthand under Hyprland's Lua config and
    -- mangles the dispatcher, while the helper knows the runtime API.
    raise_tray()
end)

-- Esc closes the menu: the surface asks for the keyboard while it is open (`keyboard:
-- exclusive while tray_open`), so the key reaches this scene and not the application under it.
on("key", function(name)
    if name == "Escape" and fact.tray_open then
        setMenu(false)
    end
end)

-- A press anywhere else is QS's dismissed overlay (SystemTray.qml:88-98): the menu goes first —
-- and closing it is what arms the long hold, so that is the whole answer — while a tray without a
-- menu gets the 5000 ms collapse delay instead of being taken away under the pointer.
on("tray_close", function()
    if fact.tray_open then
        setMenu(false)
        return
    end
    if not trayOn then return end
    if trayHold or trayHot or trayPanel then return end
    startDismiss()
end)

-- One menu, opened for an item's key: the item's own tree when the engine can read it, the
-- application's own context menu otherwise (`tray.context`). The tray icons' right button and
-- the Hiddify slot of the network capsule both land here.
local function open_tray_menu(key)
    if type(key) ~= "string" or key == "" then return end
    -- The other half of the one-overlay rule: a menu opening dismisses the drawer, exactly as
    -- `registerOverlay` dismisses the overlay that was active. No silence when nothing is open —
    -- the scene is asked and answers `none`.
    sys.call("say", "panels", "fact drawer none")
    local ok, tree = pcall(function() return sys.ask("tray.menu", key) end)
    if not ok then
        tray_menu_ids = {}
        local why = tostring(tree)
        model.tray_menu = { { label = why, sep = false, depth = 0, sub = false } }
        fact["tm.count"] = 1
        fact["tm.panel_h"] = 12 + 20
        text.tm_widest = why
        setMenu(true)
        return
    end
    if type(tree) ~= "table" or #tree == 0 then
        sys.call("tray.context", key)
        return
    end
    -- The plate is sized by its widest label, and the scene measures it: the logic hands over the
    -- one string to shape (`text.tm_widest`), not a width in pixels. The rows are drawn in
    -- Iosevka, monospaced at half an em, so the longest label by characters is also the widest in
    -- pixels; a proportional face would need every row measured and the widest of them taken,
    -- which the language has no runtime `max` for.
    --
    -- The tree, not its top level: `tray.menu` answers every node with its `children`
    -- (src/platform/tray.rs:322), and the reference opens those as a submenu flyout
    -- (`SubmenuHost`). A menu here is one plate and `lib/menu.plm` indents by `depth`, so a
    -- submenu is drawn as its rows indented under the parent, with the parent carrying the
    -- reference's chevron and no action of its own — a dbusmenu parent is a container.
    local rows, ids, widest = {}, {}, ""
    local deepest = 0
    local function walk(nodes, depth)
        for _, it in ipairs(nodes) do
            if #rows >= TRAY_MENU_MAX then return end
            if type(it) == "table" then
                local label = tostring(it.label or "")
                local kids = type(it.children) == "table" and it.children or {}
                local under = 0
                for _, c in ipairs(kids) do
                    if type(c) == "table" and c.separator ~= true then under = under + 1 end
                end
                rows[#rows + 1] = { label = label, sep = it.separator == true, depth = depth, sub = under > 0 }
                ids[#ids + 1] = (under == 0 and tonumber(it.id)) or 0
                -- Characters, not bytes: a Cyrillic letter is two bytes, and counting those ranked a
                -- short menu above a long one.
                local n = utf8.len(label) or #label
                if n > (utf8.len(widest) or #widest) then widest = label end
                if depth > deepest then deepest = depth end
                if under > 0 then walk(kids, depth + 1) end
            end
        end
    end
    walk(tree, 0)
    model.tray_menu = rows
    tray_menu_ids = ids
    local shown = #rows
    fact["tm.count"] = shown
    fact["tm.indent"] = deepest
    fact["tm.panel_h"] = 12 + 20 * math.min(shown, TRAY_MENU_ROWS)
    text.tm_widest = widest
    setMenu(true)
end

-- The right button on the Hiddify slot of the network capsule asks for the same menu the tray
-- icon's right button does (NetClusterCapsule.qml:120-127 opens `hiddifyMenu` over the slot).
-- `tray_key` is set too, because a press on one of the menu's lines comes back here and needs it.
on("vpn_menu", function()
    if net_hiddify_key == "" then return end
    if fact.tray_open then
        setMenu(false)
        return
    end
    text.tray_key = net_hiddify_key
    open_tray_menu(net_hiddify_key)
end)

-- The slot's left press: QS's MouseArea over it calls `hiddifyTrayItem.activate()`
-- (NetClusterCapsule.qml:112-118), the same `tray.activate` every tray icon answers.
on("vpn_press", function()
    if net_hiddify_key == "" then return end
    setMenu(false)
    sys.call("tray.activate", net_hiddify_key)
end)

on("tray_menu", function(index)
    if fact.tray_open then
        setMenu(false)
        return
    end
    open_tray_menu(text["tray_key"])
end)

-- ----------------------------------------------------------- throughput
-- QS's ConnectivityState.throughputText: the bar shows receive over transmit,
-- each as three digits and a decimal (ConnUi.formatRxText / formatTxText).
-- Two samples of /proc/net/dev, every timers.genericTickMs (2000), summing
-- every interface but the loopback.
--
-- The interval is the timer's, not a clock reading: the sandbox closes `os`, so
-- the logic has no wall clock of its own. A missed tick makes the figure read
-- low for one sample, nothing worse.
local through = nil

-- ConnUi.formatScaledKiBps: KiB/s auto-scaled to K/M/G/T, the integer part
-- zero-padded to three digits and one decimal. QS drops the decimal only when
-- everything is zero ("000").
--
-- The letter is *not* part of the readout: measured on the two bars at the same
-- moment, the reference capsule showed "022.6" beside its link glyph while the
-- port showed "015.7K". The letter belongs to the glyph and to the tooltip.
local UNITS = { "K", "M", "G", "T" }

local function fmt_rate(kib)
    if type(kib) ~= "number" or kib ~= kib or kib < 0 then return "--" end
    local v, unit = kib, 1
    while v >= 999.95 and unit < #UNITS do
        v = v / 1024
        unit = unit + 1
    end
    local fixed = string.format("%.1f", v)
    local int, dec = fixed:match("^(%d+)%.(%d)$")
    if not int then int, dec = fixed, "0" end
    local padded = string.rep("0", 3 - #int) .. int
    if #int > 3 then padded = int end
    local body = (padded == "000" and dec == "0") and padded or (padded .. "." .. dec)
    return body, UNITS[unit] or ""
end

local function sample()
    run("cat", { "/proc/net/dev" }, function(out)
        if type(out) ~= "string" then return end
        local rx, tx = 0, 0
        for line in out:gmatch("[^\n]+") do
            local name, rest = line:match("^%s*([%w%._%-]+):%s*(.*)$")
            if name and name ~= "lo" then
                local fields = {}
                for f in rest:gmatch("%S+") do fields[#fields + 1] = tonumber(f) end
                if fields[1] and fields[9] then
                    rx = rx + fields[1]
                    tx = tx + fields[9]
                end
            end
        end
        if through then
            local rxb, rxu = fmt_rate((rx - through.rx) / 2048)
            local txb, txu = fmt_rate((tx - through.tx) / 2048)
            text.net_rx, text.net_rx_unit = rxb, rxu
            text.net_tx, text.net_tx_unit = txb, txu
            -- QS dims the leading zeros of the integer part (NetClusterCapsule's
            -- _dimLeadingZeros, in textDisabled). A scene's text cannot look at its own
            -- characters, so the count travels as a fact and letter_opacity uses it.
            local function zeros(body)
                local n = 0
                for i = 1, #body do
                    if body:sub(i, i) == "0" then n = n + 1 else break end
                end
                return n
            end
            fact.net_rx_zeros = zeros(rxb)
            fact.net_tx_zeros = zeros(txb)
            -- QS draws the unit letter in the accent and drops "K" altogether, so the
            -- boolean travels too: a component cannot compare a text fact.
            fact.net_rx_show_unit = (rxu ~= "" and rxu ~= "K")
            fact.net_tx_show_unit = (txu ~= "" and txu ~= "K")
        end
        through = { rx = rx, tx = tx }
    end)
end

sample()
every(2000, sample)

-- -------------------------------------------------------------- weather
-- QS WeatherButton: the WMO code as a Material glyph, N °C, water_drop + N %,
-- a navigation arrow turned by the wind direction with the speed beside it, and
-- the moon's phase on the end. The answer is cached on disk and the capsule fills
-- from the cache first — the fetch only refreshes it.
--
-- The source is wttr.in's compact text format, the same one `pleamar-weather` reads, and not
-- open-meteo: Open-Meteo cannot be reached from this host, so every fetch failed and the capsule
-- sat on whatever the cache held — three days old on 2026-10-26, which is what "the weather does
-- not work" looked like. Its `%t` is °C, `%w` is km/h (divided by 3.6 for the metres per second
-- WeatherIcons prints), and the sky comes as words, which the ladder below turns back into the
-- WMO numbers the capsule's glyph is chosen by.
--
-- The reference refreshes every `ttlMs` 60 s (Services/Weather.qml:15); the port refreshed every
-- 15 minutes, which is longer than anyone stares at a bar.
-- (permissions: "files", "files.write", "curl")
-- `wttr.in/<place>?format=…` takes either "lat,lon" or a name, and a name has to be escaped
-- byte by byte: a Cyrillic city is UTF-8, and curl is given the URL as one argument, so nothing
-- else would encode it.
local function url_escape(s)
    return (tostring(s):gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local WEATHER_FORMAT = "?format=%c|%t|%h|%w|%C|%p|%P"

local function weather_url()
    if weatherCity ~= "" then return "https://wttr.in/" .. url_escape(weatherCity) .. WEATHER_FORMAT end
    return string.format("https://wttr.in/%.4f,%.4f%s", weatherLat, weatherLon, WEATHER_FORMAT)
end
local WEATHER_CACHE = "weather.json"
local WEATHER_REFRESH_MS = 60000

-- WeatherIcons.materialSymbolForCode, the same ladder: 0 sunny, 1 partly cloudy,
-- 2 cloudy, 3 fog, 4 rain, 5 snow, 6 thunderstorm.
local function weather_icon(code)
    if code == 0 then return 0 end
    if code == 1 or code == 2 then return 1 end
    if code == 3 then return 2 end
    if code >= 45 and code <= 48 then return 3 end
    if code >= 51 and code <= 67 then return 4 end
    if code >= 71 and code <= 77 then return 5 end
    if code >= 80 and code <= 82 then return 4 end
    if code >= 95 and code <= 99 then return 6 end
    return 2
end

-- The synodic month from the new moon of 2000-01-06 18:14 UTC — the same
-- reference WeatherIcons.moonAge counts from.
local function moon_phase(epoch)
    if type(epoch) ~= "number" then return 0 end
    local days = (epoch - 947182440) / 86400
    local cycles = days / 29.53059
    local frac = cycles - math.floor(cycles)
    if frac < 0 then frac = frac + 1 end
    return frac
end

local function show_weather(w)
    if type(w) ~= "table" then return end
    local code = tonumber(w.code)
    local temp = tonumber(w.temp)
    if not code or not temp then return end
    local hum = tonumber(w.hum)
    local wind = tonumber(w.wind)
    fact["weather.kind"] = weather_icon(code)
    -- The reference converts at the point it prints (`useFahrenheit`: `t * 9 / 5 + 32`).
    if useFahrenheit then temp = temp * 9 / 5 + 32 end
    text["weather.temp"] = string.format("%d°%s", math.floor(temp + 0.5), useFahrenheit and "F" or "C")
    if hum then text["weather.hum"] = string.format("%d%%", math.floor(hum + 0.5)) end
    -- WeatherIcons.formatWindSpeed: one decimal, no unit in the bar.
    if wind then text["weather.wind"] = string.format("%.1f", wind) end
    -- The arrow points where the wind goes, the reading says where it comes from:
    fact["weather.dir"] = ((tonumber(w.dir) or 0) + 180) % 360
    fact["weather.have"] = true
end

local function weather_cached()
    local ok, got = pcall(function() return sys.ask("files.read", WEATHER_CACHE, "json") end)
    if ok then show_weather(got) end
end

-- `%c|%t|%h|%w|%C|%p|%P`: an arrow, the temperature, the humidity, the wind, the sky in words,
-- the precipitation and the pressure. Each field is read for its first number, and the sky's words
-- go through the same ladder the worker uses (`packages/pleamar-weather/src/wttr.rs`), so
-- both halves of the shell name a WMO code the same way.
local function weather_fetch()
    run("curl", { "-s", "--max-time", "6", weather_url() }, function(out, code)
        if code ~= 0 or type(out) ~= "string" or out == "" then return end
        local _, temp, hum, wind, cond, _, pres = out:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)")
        local num = function(s) return tonumber((tostring(s or "")):match("[-+]?%d+%.?%d*")) end
        local arrow = tostring(wind or ""):match("^%s*(%S+)")
        local WIND_DIR = { ["↑"] = 0, ["↗"] = 45, ["→"] = 90, ["↘"] = 135,
                           ["↓"] = 180, ["↙"] = 225, ["←"] = 270, ["↖"] = 315 }
        local c = tostring(cond or "")
        local wcode = 2
        if c:find("Thunder") then wcode = 95
        elseif c:find("Snow") or c:find("Sleet") or c:find("Blizzard") then wcode = 71
        elseif c:find("Rain") or c:find("Drizzle") or c:find("Shower") then wcode = 61
        elseif c:find("Fog") or c:find("Mist") or c:find("Haze") then wcode = 45
        elseif c:find("Overcast") then wcode = 3
        elseif c:find("Cloud") then wcode = 2
        elseif c:find("Sun") or c:find("Clear") then wcode = 0
        end
        local w = {
            code = wcode,
            temp = num(temp),
            hum = num(hum) or 0,
            wind = (num(wind) or 0) / 3.6,
            dir = WIND_DIR[arrow] or 0,
            pres = num(pres),
        }
        if not w.temp then return end
        show_weather(w)
        sys.call("files.write", WEATHER_CACHE,
            string.format('{\n  "code": %d,\n  "dir": %d,\n  "hum": %d,\n  "temp": %.1f,\n  "wind": %.1f\n}\n',
                w.code, w.dir or 0, w.hum or 0, w.temp, w.wind or 0))
    end)
end

local function moon_tick()
    run("date", { "+%s" }, function(out)
        local epoch = tonumber(out)
        if epoch then fact["weather.moon"] = moon_phase(epoch) end
    end)
end

weather_cached()
-- The scene's own defaults land after the logic's first pass — the same trap the drawer fact hits
-- — so everything written above is overwritten by what the scene declared, and the next pass is a
-- whole refresh away. Say it again once the scene has its feet: the moon was drawing a new moon for
-- a quarter of an hour, and the cached reading sat on "--°C" until curl answered (or for a minute,
-- with no network at all).
after(1500, weather_cached)
after(1500, moon_tick)
weather_fetch()
moon_tick()
every(WEATHER_REFRESH_MS, weather_fetch)
every(WEATHER_REFRESH_MS, moon_tick)

-- ------------------------------------------------------------- keyboard
-- QS KeyboardLayoutHypr reads the active keymap out of `hyprctl devices -j`;
-- the first keyboard that reports one is the one Hyprland types with, and its
-- first keymap is the active layout.
-- `active_keymap` is the name of the layout in force ("Russian", "English (US)");
-- QS shortens it (KeyboardLayoutHypr.shortenLayout maps the same names to the
-- two-letter code the bar shows).
local SHORT = {
    ["english (us)"] = "en", ["english (uk)"] = "en-uk", ["russian"] = "ru",
    ["us"] = "en", ["us-intl"] = "en", ["us(international)"] = "en",
    ["en_us"] = "en", ["en-us"] = "en", ["ru"] = "ru", ["ru_ru"] = "ru",
    ["ru-ru"] = "ru", ["german"] = "de", ["french"] = "fr", ["finnish"] = "fi",
}

local function shorten(name)
    if type(name) ~= "string" then return nil end
    local key = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if key == "" then return nil end
    if SHORT[key] then return SHORT[key] end
    local inner = key:match("%(([^)]+)%)")
    if inner then
        inner = inner:lower()
        if inner == "us" or inner:sub(1, 2) == "en" then return "en" end
        if inner == "ru" or inner:sub(1, 2) == "ru" then return "ru" end
        return inner:sub(1, 2)
    end
    return key:sub(1, 3)
end

-- Which keyboard the indicator follows. The reference's `pickDevice`
-- (KeyboardLayoutHypr.qml:230-252) walks the list with a reason behind every step: the pinned device
-- first, then the one Hyprland calls `main`, then the first that is not a virtual helper and has a
-- keymap, then whatever is there. Reading the first `active_keymap` in the file — which is what this
-- did — is what made the capsule say `en` while the hands typed Russian: the list opens with the
-- receiver's consumer-control nodes, and the layout of a pseudo-device is not the one in force.
-- The device it picked, kept: `main` on this host moves between two helper devices (`neru-scroll`
-- and `neru-keyboard-proxy` both claim it within seconds — measured 2026-10-26), and following it
-- is what made the capsule flip between `ru` and `en`. The reference pins its device for the same
-- reason (`deviceName`/`deviceNeedle`, KeyboardLayoutHypr.qml:230-240), only from settings.
local kb_pin = ""

local function pick_keyboard(devs)
    local list = type(devs) == "table" and devs.keyboards or nil
    if type(list) ~= "table" or #list == 0 then return nil end
    -- The one already chosen, while it is still there.
    if kb_pin ~= "" then
        for _, k in ipairs(list) do
            if type(k) == "table" and (k.name == kb_pin or k.identifier == kb_pin) then return k end
        end
        kb_pin = ""
    end
    local chosen
    for _, k in ipairs(list) do
        if type(k) == "table" and k.main == true then chosen = k break end
    end
    if not chosen then
        for _, k in ipairs(list) do
            local name = type(k) == "table" and tostring(k.name or "") or ""
            if name ~= "" and not name:lower():find("virtual", 1, true)
                and (k.active_keymap or k.layout) then
                chosen = k
                break
            end
        end
    end
    chosen = chosen or list[1]
    if type(chosen) == "table" then kb_pin = tostring(chosen.name or chosen.identifier or "") end
    return chosen
end

local function layout()
    run("hyprctl", { "devices", "-j" }, function(out)
        if type(out) ~= "string" then return end
        local ok, devs = pcall(json.decode, out)
        if not ok then return end
        local k = pick_keyboard(devs)
        if type(k) ~= "table" then return end
        local short = shorten(k.active_keymap or k.layout)
        if short then text.kb_layout = short end
        local name = k.name or k.identifier or ""
        if name ~= "" and name ~= text.kb_device then text.kb_device = name end
    end)
end

layout()
every(2000, layout)

-- Hyprland says every layout change down its event socket (`activelayout>>device,Layout`,
-- the event HyprlandWatcherImpl reads: Services/HyprlandWatcherImpl.qml:156), so the label
-- changes on the keystroke instead of on the next poll. The two-second `hyprctl devices -j`
-- above stays as the safety net: a missed event, or the socket going away, costs a tick.
--
-- `nc -U` writes one line per event and runs until the socket closes; re-arming after a
-- second is the backoff the MPD flags plugin uses (lib/plugins/mpd/mpd.luau).
-- A Hyprland submap is the reference's badge: `_submapGlyph` (KeyboardLayoutHypr.qml:295-303) knows
-- four of them, and `_richLabel` prints that glyph in the accent before the layout, so the strip says
-- which mode the keyboard is in. Hyprland announces it on the same socket the layout arrives on —
-- `submap>>music` as it is entered, `submap>>` (nothing) as it ends — and `hyprctl submap` answers
-- `default` for "no mode of its own".
local SUBMAP_GLYPH = { special = "✦", resize = "⇔", tiling = "▩", wallpaper = "🖼" }
local function set_submap(name)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "default" then name = "" end
    if name ~= text.kb_mode then text.kb_mode = name end
    local glyph = SUBMAP_GLYPH[name:lower()] or ""
    if glyph ~= text.kb_badge then text.kb_badge = glyph end
    -- The scene cannot ask a text whether it is empty, so the badge's presence is a fact.
    if fact.kb_badge_on ~= (glyph ~= "") then fact.kb_badge_on = (glyph ~= "") end
end

local watcher = nil
local function watch_layout()
    if watcher then return end
    local dir, sig = sys.ask("env", "XDG_RUNTIME_DIR"), sys.ask("env", "HYPRLAND_INSTANCE_SIGNATURE")
    if type(dir) ~= "string" or type(sig) ~= "string" or dir == "" or sig == "" then return end
    local ok, handle = pcall(spawn, "nc", { "-U", dir .. "/hypr/" .. sig .. "/.socket2.sock" }, function(line)
        local head, payload = tostring(line):match("^([%w_]+)>>(.*)$")
        if head == "submap" then
            set_submap(payload)
            return
        end
        if head ~= "activelayout" and head ~= "activelayoutv2" then return end
        -- `activelayout>>device,Layout`. The device that announces the change is the one being
        -- typed on, so it becomes the pin: it used to be chosen once from `main` (false on every
        -- board here) and the first name in the list, and a switch on the keyboard actually in
        -- use — Alt+Shift, or the compositor's own bind — was dropped by the filter below, so the
        -- capsule stood still while the layout changed. The two-second poll then asks this device.
        local device, name = payload:match("^([^,]*),%s*(.+)$")
        if device and device ~= "" and device ~= text.kb_device then
            text.kb_device = device
            kb_pin = device
        end
        local short = shorten(name)
        if short and short ~= text.kb_layout then text.kb_layout = short end
    end, function()
        watcher = nil
        after(1000, watch_layout)
    end)
    if ok then watcher = handle end
end
watch_layout()
-- The mode the session starts in, before any event: the socket only says what changes.
run("hyprctl", { "submap" }, function(out) set_submap(out) end)

-- ------------------------------------------------------------- system monitor
-- QS Services/SystemMonitor.qml, same probe and same arithmetic: one dash and
-- one awk over the four procfs files plus the GPU and CPU-temperature paths
-- discovered once per probe. The bar shows the same six metrics with the same
-- thresholds and the same idle rule (panel: systemMonitorHideIdle, 3%).
local SYS_PROBE = [[
tp=''
for h in /sys/class/hwmon/hwmon*/; do
  n=$(cat "$h/name" 2>/dev/null)
  case $n in k10temp|coretemp|zenpower) f="${h}temp1_input"; [ -r "$f" ] && tp=$f && break;; esac
done
[ -n "$tp" ] || tp=/sys/class/thermal/thermal_zone0/temp
gp=''; bv=0
for d in /sys/class/drm/card[0-9]*/device; do
  [ -f "$d/gpu_busy_percent" ] || continue
  v=$(cat "$d/mem_info_vram_total" 2>/dev/null) || v=0
  [ "$v" -gt "$bv" ] && bv=$v && gp=$d/gpu_busy_percent
done
awk -v tp="$tp" -v gp="$gp" '
  FILENAME=="/proc/stat"      { if (FNR==1) print "cpu", $2,$3,$4,$5,$6,$7,$8,$9; next }
  FILENAME=="/proc/meminfo"   { if ($1=="MemTotal:") t=$2; else if ($1=="MemAvailable:") a=$2; next }
  FILENAME=="/proc/swaps"     { if (FNR>1) { st+=$3; su+=$4 } next }
  FILENAME=="/proc/diskstats" { if ($3 ~ /^(sd[a-z]|nvme[0-9]+n[0-9]+|vd[a-z])$/) { r+=$6; w+=$10 } next }
  FILENAME==tp                { print "temp", $1+0; next }
  FILENAME==gp                { print "gpu", $1+0; next }
  END { print "mem", t+0, a+0; print "swap", st+0, su+0; print "io", r+0, w+0 }
' /proc/stat /proc/meminfo /proc/swaps /proc/diskstats "$tp" "$gp" 2>/dev/null
]]

local POLL_MS = 2000
local IO_MAX_KIBPS = 512000
local prevCpu, prevIo = nil, nil

local function clamp01(v)
    if v ~= v then return 0 end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function applyLine(line)
    local tag, rest = line:match("^(%a+)%s+(.*)$")
    if not tag then return end
    local n = {}
    for f in rest:gmatch("%S+") do n[#n + 1] = tonumber(f) or 0 end
    if tag == "cpu" and #n >= 8 then
        local total = 0
        for i = 1, 8 do total = total + n[i] end
        local idle = n[4] + n[5]
        if prevCpu then
            local dTotal = total - prevCpu.total
            local dIdle = idle - prevCpu.idle
            if dTotal > 0 then fact.cpu = clamp01((dTotal - dIdle) / dTotal) end
        end
        prevCpu = { total = total, idle = idle }
    elseif tag == "mem" and #n >= 2 then
        local total, avail = n[1], n[2]
        fact.ram = total > 0 and clamp01((total - avail) / total) or 0
        -- The tooltip prints the pair beside the share, as the reference does ("7.2 / 16 GiB").
        fact.ram_total_gib = math.floor(total / 1048576 + 0.5)
        fact.ram_used_gib = math.floor((total - avail) / 104857.6 + 0.5) / 10
    elseif tag == "swap" and #n >= 2 then
        local total, used = n[1], n[2]
        fact["has.swap"] = total > 0
        fact.swap = total > 0 and clamp01(used / total) or 0
    elseif tag == "io" and #n >= 2 then
        local sectors = n[1] + n[2]
        if prevIo then
            local kbps = (sectors - prevIo) / 2 / (POLL_MS / 1000)
            fact.io = clamp01(kbps / IO_MAX_KIBPS)
        end
        prevIo = sectors
    elseif tag == "temp" and #n >= 1 then
        local c = n[1] / 1000
        fact.temp = clamp01((c - 30) / 70)
    elseif tag == "gpu" and #n >= 1 then
        fact["has.gpu"] = true
        fact.gpu = clamp01(n[1] / 100)
    end
end

local function sysmon()
    run("dash", { "-c", SYS_PROBE }, function(out)
        if type(out) ~= "string" then return end
        for line in out:gmatch("[^\n]+") do applyLine(line) end
    end)
end

sysmon()
every(POLL_MS, sysmon)
