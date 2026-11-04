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
        -- A file that is not there is the first run, not a defect (§6.1); only one that is there
        -- and unreadable deserves a line in the journal.
        local ok_ex, there = pcall(function() return sys.ask("files.exists", FILE) end)
        if ok_ex and there == true then log("launcher: settings.json is broken; defaults kept") end
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
    -- An empty list is an answer too: the service reports what is installed, and the watch above
    -- takes it the same way. Refusing it left the fallback showing applications that are gone.
    if type(list) == "table" then
        apps_all = list
        apps_n = #list
    end
    if #apps_all >= MAX_APPS and not announced_cap then
        announced_cap = true
        log("launcher: the apps model is at its " .. tostring(MAX_APPS)
            .. "-record cap; entries past it are not searched")
    end
end

-- ==================== emoji and kaomoji ====================
-- A query that starts with `:` is a lookup in this table instead of the application list: the
-- rows are the characters themselves, Enter copies one to the clipboard (`wl-copy`) and closes.
-- The set is curated rather than complete: it is what a shell's picker is for — the faces one
-- actually types — and every entry is searchable by its English name. `:` alone lists them all.
-- (The reference kept whole Unicode tables in `files/emoji.json`; a scene cannot read files
-- outside its own folder, and a thousand rows behind a fourteen-pixel list is not a picker.)
local EMOJI = {
    { "😀", "grinning" }, { "😃", "smile open" }, { "😄", "smile" }, { "😁", "beaming" },
    { "😆", "laughing" }, { "😅", "sweat smile" }, { "🤣", "rofl" }, { "😂", "joy tears" },
    { "🙂", "slight smile" }, { "🙃", "upside down" }, { "😉", "wink" }, { "😊", "blush" },
    { "😇", "innocent halo" }, { "🥰", "love hearts" }, { "😍", "heart eyes" }, { "🤩", "star struck" },
    { "😘", "kiss" }, { "😗", "kissing" }, { "😚", "kissing closed" }, { "😙", "kissing smile" },
    { "😋", "yum" }, { "😛", "tongue" }, { "😜", "wink tongue" }, { "🤪", "zany" },
    { "😝", "squint tongue" }, { "🤑", "money mouth" }, { "🤗", "hug" }, { "🤭", "hand over mouth" },
    { "🤫", "shush" }, { "🤔", "thinking" }, { "🤐", "zipper mouth" }, { "🤨", "raised eyebrow" },
    { "😐", "neutral" }, { "😑", "expressionless" }, { "😶", "no mouth" }, { "😏", "smirk" },
    { "😒", "unamused" }, { "🙄", "eye roll" }, { "😬", "grimace" }, { "🤥", "lying" },
    { "😌", "relieved" }, { "😔", "pensive" }, { "😪", "sleepy" }, { "🤤", "drool" },
    { "😴", "sleeping" }, { "😷", "mask" }, { "🤒", "thermometer" }, { "🤕", "bandage" },
    { "🤢", "nauseated" }, { "🤮", "vomit" }, { "🤧", "sneeze" }, { "🥵", "hot" },
    { "🥶", "cold" }, { "🥴", "woozy" }, { "😵", "dizzy" }, { "🤯", "exploding head" },
    { "🤠", "cowboy" }, { "🥳", "party" }, { "😎", "sunglasses cool" }, { "🤓", "nerd" },
    { "🧐", "monocle" }, { "😕", "confused" }, { "😟", "worried" }, { "🙁", "frown" },
    { "😮", "surprised" }, { "😯", "hushed" }, { "😲", "astonished" }, { "😳", "flushed" },
    { "🥺", "pleading" }, { "😦", "frowning" }, { "😧", "anguished" }, { "😨", "fearful" },
    { "😰", "anxious" }, { "😥", "sad relieved" }, { "😢", "cry" }, { "😭", "sob" },
    { "😱", "scream" }, { "😖", "confounded" }, { "😣", "persevere" }, { "😞", "disappointed" },
    { "😓", "downcast sweat" }, { "😩", "weary" }, { "😫", "tired" }, { "🥱", "yawn" },
    { "😤", "triumph" }, { "😡", "rage" }, { "😠", "angry" }, { "🤬", "cursing" },
    { "😈", "devil" }, { "👿", "imp" }, { "💀", "skull" }, { "☠️", "skull crossbones" },
    { "💩", "poop" }, { "🤡", "clown" }, { "👹", "ogre" }, { "👻", "ghost" },
    { "👽", "alien" }, { "🤖", "robot" }, { "😺", "cat smile" }, { "😸", "cat grin" },
    { "😻", "cat heart eyes" }, { "🙀", "cat scream" }, { "😿", "cat cry" }, { "🙈", "see no evil" },
    { "🙉", "hear no evil" }, { "🙊", "speak no evil" }, { "❤️", "heart red" }, { "🧡", "heart orange" },
    { "💛", "heart yellow" }, { "💚", "heart green" }, { "💙", "heart blue" }, { "💜", "heart purple" },
    { "🖤", "heart black" }, { "🤍", "heart white" }, { "💔", "broken heart" }, { "❣️", "heart exclamation" },
    { "💕", "two hearts" }, { "💖", "sparkling heart" }, { "💘", "cupid" }, { "💝", "gift heart" },
    { "🔥", "fire" }, { "✨", "sparkles" }, { "⭐", "star" }, { "🌟", "glowing star" },
    { "💫", "dizzy star" }, { "⚡", "zap lightning" }, { "☀️", "sun" }, { "🌙", "moon" },
    { "🌈", "rainbow" }, { "☁️", "cloud" }, { "❄️", "snowflake" }, { "🌊", "wave water" },
    { "🌱", "seedling" }, { "🌿", "herb" }, { "🍀", "clover luck" }, { "🌵", "cactus" },
    { "🌴", "palm" }, { "🌸", "cherry blossom" }, { "🌹", "rose" }, { "🌻", "sunflower" },
    { "🍁", "maple leaf" }, { "🎃", "pumpkin" }, { "🎄", "christmas tree" }, { "🎁", "gift" },
    { "🎉", "party popper" }, { "🎊", "confetti" }, { "🎈", "balloon" }, { "🎵", "music note" },
    { "🎶", "music notes" }, { "🎧", "headphones" }, { "🎸", "guitar" }, { "🎹", "piano" },
    { "🥁", "drum" }, { "🎮", "gamepad" }, { "🎯", "dart target" }, { "🎲", "dice" },
    { "🏆", "trophy" }, { "🥇", "gold medal" }, { "⚽", "soccer" }, { "🏀", "basketball" },
    { "🚀", "rocket" }, { "🛸", "ufo" }, { "🌍", "earth" }, { "🗺️", "map" },
    { "🧭", "compass" }, { "⛰️", "mountain" }, { "🏔️", "snow mountain" }, { "🏕️", "camping" },
    { "🍕", "pizza" }, { "🍔", "burger" }, { "🍟", "fries" }, { "🌮", "taco" },
    { "🍣", "sushi" }, { "🍜", "ramen" }, { "🍩", "donut" }, { "🍪", "cookie" },
    { "🍰", "cake" }, { "☕", "coffee" }, { "🍵", "tea" }, { "🍺", "beer" },
    { "🍷", "wine" }, { "🥃", "whisky" }, { "🍎", "apple" }, { "🍋", "lemon" },
    { "🥑", "avocado" }, { "🌶️", "chili" }, { "🧄", "garlic" }, { "🧠", "brain" },
    { "👀", "eyes" }, { "👁️", "eye" }, { "🫀", "heart organ" }, { "🦴", "bone" },
    { "👍", "thumbs up" }, { "👎", "thumbs down" }, { "👌", "ok" }, { "🤌", "pinched fingers" },
    { "✌️", "victory peace" }, { "🤞", "fingers crossed" }, { "🤟", "love you" }, { "🤘", "rock" },
    { "👏", "clap" }, { "🙌", "raised hands" }, { "🤝", "handshake" }, { "🙏", "pray thanks" },
    { "💪", "muscle" }, { "🖕", "middle finger" }, { "✍️", "writing" }, { "🧑‍💻", "developer" },
    { "💻", "laptop" }, { "🖥️", "desktop" }, { "⌨️", "keyboard" }, { "🖱️", "mouse" },
    { "💾", "floppy save" }, { "📀", "dvd" }, { "📱", "phone" }, { "🔋", "battery" },
    { "🔌", "plug" }, { "💡", "bulb idea" }, { "🔍", "search" }, { "📌", "pin" },
    { "📎", "paperclip" }, { "✂️", "scissors" }, { "🔧", "wrench" }, { "🔨", "hammer" },
    { "⚙️", "gear settings" }, { "🧲", "magnet" }, { "🔒", "lock" }, { "🔓", "unlock" },
    { "🔑", "key" }, { "🗝️", "old key" }, { "🛡️", "shield" }, { "⚔️", "swords" },
    { "🏹", "bow arrow" }, { "💣", "bomb" }, { "🧨", "firecracker" }, { "🕯️", "candle" },
    { "📖", "book" }, { "📚", "books" }, { "✏️", "pencil" }, { "🖊️", "pen" },
    { "📝", "memo note" }, { "📅", "calendar" }, { "⏰", "alarm clock" }, { "⏳", "hourglass" },
    { "⌛", "hourglass done" }, { "💯", "hundred" }, { "✅", "check" }, { "❌", "cross" },
    { "⚠️", "warning" }, { "❓", "question" }, { "❗", "exclamation" }, { "♻️", "recycle" },
}

local KAOMOJI = {
    { "(╯°□°）╯︵ ┻━┻", "table flip" },
    { "┬─┬ノ( º _ ºノ)", "table back" },
    { "( ͡° ͜ʖ ͡°)", "lenny" },
    { "¯\\_(ツ)_/¯", "shrug" },
    { "(╥﹏╥)", "cry" },
    { "(◕‿◕)", "happy" },
    { "(︶︹︺)", "sad" },
    { "ヽ(´▽`)/", "cheer" },
    { "(•_•) ( •_•)>⌐■-■ (⌐■_■)", "deal with it" },
    { "ʕ•ᴥ•ʔ", "bear" },
    { "(づ｡◕‿‿◕｡)づ", "hug" },
    { "ᕕ( ᐛ )ᕗ", "run" },
    { "OwO", "owo" },
    { "UwU", "uwu" },
    { "o(*^▽^*)o", "joy" },
    { "(=^･ω･^=)", "cat" },
    { "~(￣▽￣)~", "dance" },
    { "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧", "sparkle" },
    { "Σ(°△°|||)︴", "shock" },
    { "(ง'̀-'́)ง", "fight" },
}

local emoji_mode = false
local emoji_picks = {}

local function emoji_rows(needle, by_time)
    local out, picks = {}, {}
    local function add(list, kind)
        for _, e in ipairs(list) do
            if needle == "" or lower(e[2]):find(needle, 1, true) then
                out[#out + 1] = { name = "", exec = "", icon = "face-smile", id = kind, local_name = e[1] .. "   " .. e[2] }
                picks[#out] = e[1]
                if #out >= by_time then return true end
            end
        end
        return false
    end
    if add(EMOJI, "emoji") then return out, picks end
    add(KAOMOJI, "kaomoji")
    return out, picks
end

local function rebuild()
    local q = trim(lower(text.query))

    -- `:` (or `:name`) is the emoji lookup; anything else is the application list.
    if q:sub(1, 1) == ":" then
        local rows, picks = emoji_rows(trim(q:sub(2)), math.min(#EMOJI + #KAOMOJI, math.floor(fact.max_results)))
        emoji_mode = true
        emoji_picks = picks
        model.results = rows
        fact.selected = 0
        return
    end
    emoji_mode = false

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
        -- A model assignment is atomic and a bad field would keep the old list;
        -- the image field gets a string or nothing.
        local icon = rec.icon
        if type(icon) ~= "string" then icon = "" end
        out[i] = {
            name = tostring(rec.name or ""),
            exec = tostring(rec.exec or ""),
            icon = icon,
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
    -- A second ask in the same turn (a row press, a repeated submit) must not
    -- launch twice.
    if not fact.open then return end

    -- An emoji row is copied, not launched: it has no program behind it.
    if emoji_mode then
        local pick = emoji_picks[(tonumber(i) or 0) + 1]
        if type(pick) == "string" and pick ~= "" then
            run("wl-copy", { pick }, function() end)
        end
        fact.open = false
        fact.armed = false
        text.query = ""
        fact.selected = 0
        return
    end

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
    fact.armed = false
    text.query = ""
    fact.selected = 0
end

-- Escape closes the launcher only after it has been up for a moment: the runtime delivers an Escape
-- of its own as soon as the surface takes the keyboard (see the `armed` fact in launcher.plm), so an
-- unguarded `on key Escape` shut the launcher a second after it opened.
local ARM_MS = 1500
local arm_timer = nil

local function disarm()
    fact.armed = false
    if arm_timer then
        cancel(arm_timer)
        arm_timer = nil
    end
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

-- Enter in the field. `submit:query` carries the text, so a one-shot
-- `--say launcher "submit query kitty"` re-slices from the submitted value
-- before launching; the typed route has already re-sliced on every keystroke.
on("submit:query", function(value)
    if type(value) == "string" then text.query = value end
    rebuild()
    launch(fact.selected)
end)

-- Closing by any route (Escape, the catcher, --say "fact open false") clears
-- the filter; opening through the fact alone (--say "fact open true", a
-- compositor bind) does what open_launcher does, so both routes are complete.
on("fact:open", function(v)
    -- The runtime's own Escape arrives about 1.5 s after the keyboard hand-over, so `armed` stays
    -- false until that has passed (see the fact in launcher.plm) and the phantom key finds the
    -- Escape rule unarmed.
    disarm()
    if v then
        refresh()
        focus("query")
        arm_timer = after(ARM_MS, function()
            arm_timer = nil
            fact.armed = true
        end)
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

-- ======================= the live palette =======================
-- `pleamar-themes push` leaves the theme's channels in this scene's own folder
-- (a scene reads only its own), and the scene draws lib/palette-live.plm's
-- `live.*` colours from the facts named here. A theme change is then a change of
-- facts: no file is rewritten and nothing reloads. The poll is one small read
-- every two seconds; a value that has not moved is not written again.
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
