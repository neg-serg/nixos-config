-- picker.luau — the wallpaper deck's reading and applying (scene `picker`).
--
-- What the declarative scene cannot do itself:
--   · read settings.json and push its defaults into `folder` and `command`, and write it back
--     when the settings screen is saved (the table it read is what it writes, so a key another
--     version put there stays);
--   · list the wallpaper folder and page through it: one page of cards is what the model holds,
--     and the deck draws the page it is on;
--   · put that page in order — by name, or the newest wallpaper first (`ls -t`: no service
--     reports a file's modification time, so it is the documented stopgap) — and follow the sort
--     as it is turned over;
--   · read the colour schemes of the page's wallpapers with `pleamar-wallpaper-palettes` and
--     fill the cards' chips as the lines arrive (the pictures are there from the first frame);
--   · hand the chosen card to `pleamar-wallpaper-apply` (caches, the wallpaper command, matugen)
--     and close;
--   · keep the favourites in favourites.json (`f` marks the card the keyboard is on) and lead
--     the deck with them, or show only them (`tab`).
--
-- Settings (`~/.local/share/pleamar/picker/settings.json`):
--   folder    text    ~/pic/wl        the wallpapers to browse
--   command   text    wl img {}       the tool that paints the desktop; {} is the path
-- The settings screen (picker.plm, `g`) is one writer of that file and an editor is another: the
-- watcher below re-reads it, and a folder that moved is listed again there and then.
--
-- Favourites (`favourites.json`, the reference's WallpaperFavorites.qml):
--   favourites  array of text   []      wallpapers by bare file name, the marked ones
-- The logic is the only writer (`f`, or `--say picker "emit favourite 2"`), and a name the folder
-- no longer holds stays in the file: the wallpaper may come back.
--
-- Why pages: a card is a picture, and a picture costs the atlas — ~290 x 180 of it each. The
-- reference read the schemes of the cards in view for the same reason. A folder of five hundred
-- wallpapers is eight pages of cards here, and only the page on screen is read, so the deck opens
-- in the time a page takes rather than the folder's.
--
-- Wallpapers are still pictures. An animated GIF/WebP or a video was drawn by the Quickshell
-- layer the deck used to run under, and the port has no such layer, so those files are left out
-- and counted in the status line instead of being offered as cards wl cannot paint.

local FILE = "settings.json"
-- The favourites, in a file of their own so they never touch settings.json (the reference kept
-- its own `wallpaper-favorites.json` beside them for the same reason).
local FAV = "favourites.json"

-- Defaults live here; the file holds only what the user changed.
local D = {
    folder = "~/pic/wl",
    command = "wl img {}",
}

local PAGE = 64 -- cards a page holds: sixteen rows of four (the model's cap, picker.plm)
local COLS = 4  -- cards a row: the deck's `cols` (picker.plm)

-- What wl can paint. Everything else in the folder is left out of the deck (see the header).
local CLIPS = {
    mp4 = true,
    webm = true,
    mkv = true,
    mov = true,
    m4v = true,
    gif = true,
    webp = true,
}

-- The scheme's roles a card shows, in the order its chips are drawn: the wallpaper's own
-- dominant colour first, then what the desktop's accent and second/third colours would become.
local CHIPS = { "source_color", "primary", "secondary", "tertiary" }

local home = sys.ask("env", "HOME") or ""
local dir = D.folder -- the folder as a program reads it (no ~)
local names = {}     -- every wallpaper in the folder, in name order
local by_time = {}   -- the same names, newest file first (what `ls -t` answered)
local favs = {}      -- name -> true, the ones marked favourite (from favourites.json)
local vis = {}       -- what the deck shows: `names` in the sort's order, favourites first
local current = ""  -- the wallpaper file the desktop wears (the theme pipeline's cache)
local schemes = {}   -- name -> {{ r, g, b }, …}, what the reader has answered so far
local reader = nil   -- the palettes process, while it runs
-- Which read the reader on screen belongs to. A worker that is killed can still have a line in
-- flight, and that line would paint a card of the page the deck has already left — or of a folder
-- that is no longer the one on screen. The reader's lines are dropped unless they carry the
-- current number.
local reader_gen = 0
local skipped = 0    -- files left out because they are clips
local listed = false -- whether the folder has been listed since the scene started

-- Declared here, defined below: the settings screen may be saved at any moment and the favourites
-- marked at any moment, and either moves the folder the deck reads, the page it shows and the line
-- it says about them.
local list, status, refresh

-- ======================= small helpers =======================

local function trim(s)
    return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local function expand(path)
    if type(path) ~= "string" or path == "" then return D.folder end
    if string.sub(path, 1, 1) == "~" then return home .. string.sub(path, 2) end
    return path
end

-- "#rrggbb" -> three numbers from 0 to 1, which is what `rgb()` takes in the scene.
local function channels(hex)
    if type(hex) ~= "string" then return nil end
    local body = string.gsub(hex, "^#", "")
    if #body ~= 6 then return nil end
    local r = tonumber(string.sub(body, 1, 2), 16)
    local g = tonumber(string.sub(body, 3, 4), 16)
    local b = tonumber(string.sub(body, 5, 6), 16)
    if not (r and g and b) then return nil end
    return r / 255, g / 255, b / 255
end

local function extension(name)
    return string.match(string.lower(name), "%.([%w]+)$") or ""
end

-- A path as the deck keeps it: no surrounding space, no trailing slashes, `/` still `/`.
local function tidy(path)
    local p = trim(path)
    while #p > 1 and string.sub(p, -1) == "/" do p = string.sub(p, 1, -2) end
    return p
end

local function pages()
    return math.max(1, math.ceil(#vis / PAGE))
end

-- `names` in the order the deck is sorting by. A name `ls -t` did not mention (a file that
-- appeared after it answered) goes last, in name order, so the sort is always a total one.
-- The favourites come first, in that same order, and with `only_favourites` they are all there
-- is — the reference's leading sort key and its Favourites source in one place.
local function ordered()
    local out = {}
    -- The finder filters the whole folder, so the deck is what the question asks for and not the
    -- page that happened to be on screen when it was typed.
    local q = tostring(text.query or ""):lower()
    for i = 1, #names do
        if q == "" or names[i]:lower():find(q, 1, true) then out[#out + 1] = names[i] end
    end
    if fact.order == "newest" and #by_time > 0 then
        local rank = {}
        for i = 1, #by_time do rank[by_time[i]] = i end
        table.sort(out, function(a, b)
            local ra, rb = rank[a] or math.huge, rank[b] or math.huge
            if ra ~= rb then return ra < rb end
            return a < b
        end)
    end

    local sorted = {}
    if fact.only_favourites then
        for _, name in ipairs(out) do
            if favs[name] then sorted[#sorted + 1] = name end
        end
        return sorted
    end
    for _, name in ipairs(out) do
        if favs[name] then sorted[#sorted + 1] = name end
    end
    for _, name in ipairs(out) do
        if not favs[name] then sorted[#sorted + 1] = name end
    end
    return sorted
end

-- ======================= settings =======================

-- What the file holds, kept as it was read: `save_settings` writes this same table back, so a
-- key neither this version nor the screen knows about survives the round trip.
local raw = {}

-- `raw` -> the deck: the folder it lists (as a program reads it) and the command it applies
-- with, both shown as they were written. Answers whether the folder moved, which is what asks
-- for a listing.
local function apply_settings()
    local folder = raw.folder
    if type(folder) ~= "string" or trim(folder) == "" then folder = D.folder end
    local command = raw.command
    if type(command) ~= "string" then command = D.command end

    local was = dir
    dir = expand(tidy(folder))
    text.folder = tidy(folder)
    text.command = command
    return was ~= dir
end

-- The file -> `raw` -> the deck. Answers whether the folder moved.
local function read_settings()
    local ok, got = pcall(function() return sys.ask("files.read", FILE, "json") end)
    if not ok then
        -- Missing is the first run; only a file that is there and unreadable is a defect (§6.1).
        local ok_ex, there = pcall(function() return sys.ask("files.exists", FILE) end)
        if ok_ex and there == true then log("picker: settings.json is broken; defaults kept") end
        got = nil
    end
    if type(got) ~= "table" then got = {} end
    raw = got
    return apply_settings()
end

-- The settings screen's Save: the two fields into the file, the file back into the deck. A path
-- that is not absolute is refused rather than saved, because the folder is read by a program and
-- `~` is the only shorthand this knows how to expand.
local function save_settings()
    local folder = tidy(text.field_folder or "")
    local command = text.field_command or ""
    if folder ~= "" and string.sub(folder, 1, 1) ~= "/" and string.sub(folder, 1, 1) ~= "~" then
        text.note = "use a full path, or one starting with ~/"
        return
    end
    if folder == "" then folder = D.folder end

    raw.folder = folder
    raw.command = command
    local ok, why = pcall(function() sys.call("files.write", FILE, raw) end)
    if not ok then
        text.note = "could not save the settings"
        log("picker: " .. tostring(why))
        return
    end

    local moved = apply_settings()
    text.field_folder = text.folder
    text.field_command = text.command
    text.note = "saved"
    if moved then
        list()
    else
        status()
    end
end

-- ======================= favourites =======================

-- The file this holds what it read, the same way settings.json is held: every change mutates it,
-- so a key another version put there survives.
local fav_raw = { favourites = {} }
local fav_list = {} -- the names that read gave, in the file's order

-- Whether two lists of names say the same thing, in the same order.
local function same_names(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

-- favourites.json -> `favs`, the count the deck shows, and whether that set moved (which is what
-- asks for the deck to be laid down again). A name the folder no longer holds is kept: the
-- wallpaper may come back, and the reference kept them too.
local function read_favourites()
    local ok, got = pcall(function() return sys.ask("files.read", FAV, "json") end)
    if not ok then
        log("picker: favourites.json is broken; starting without")
        got = nil
    end
    if type(got) ~= "table" then got = {} end
    fav_raw = got
    if type(fav_raw.favourites) ~= "table" then fav_raw.favourites = {} end

    local list = {}
    favs = {}
    for _, name in ipairs(fav_raw.favourites) do
        if type(name) == "string" and name ~= "" and not favs[name] then
            favs[name] = true
            list[#list + 1] = name
        end
    end
    local moved = not same_names(list, fav_list)
    fav_list = list
    fact.favourites = #list
    return moved
end

-- `f` on the card the keyboard is on: marked, or unmarked. Written at once — a mark is a small
-- thing to lose — and the deck laid down again, since the order leads with the favourites.
local function toggle_favourite(i)
    local name = vis[fact.page * PAGE + i + 1]
    if type(name) ~= "string" then return end

    local kept = {}
    local removed = false
    for _, other in ipairs(fav_raw.favourites) do
        if other == name then
            removed = true
        else
            kept[#kept + 1] = other
        end
    end
    if not removed then kept[#kept + 1] = name end
    fav_raw.favourites = kept

    local ok, why = pcall(function() sys.call("files.write", FAV, fav_raw) end)
    if not ok then
        text.status = "could not save the favourites"
        log("picker: " .. tostring(why))
        return
    end
    read_favourites()
    refresh()
end

-- What the screen says about the folder it is on: how many wallpapers are there, or that there
-- are none yet (the deck's own line says why when it could not read it at all).
local function note_here()
    if #names == 0 then return "no wallpapers here yet" end
    if #names == 1 then return "1 wallpaper here" end
    return tostring(#names) .. " wallpapers here"
end

-- ======================= the page =======================

-- The cards of the page on screen: every one of them at once (the model is atomic), each with
-- the chips the reader has answered for it so far — a card without a scheme yet just has none.
-- The wallpaper the desktop wears, from the cache the theme pipeline leaves every time it paints
-- one: the file's last line is its path. Read once when the deck opens, so the card is marked.
local function read_current()
    local home = nil
    local ok_home, value = pcall(function() return sys.ask("env", "HOME") end)
    if ok_home and type(value) == "string" and value ~= "" then home = value end
    if not home then return end
    run("cat", { home .. "/.cache/pleamar/wallpaper-path" }, function(out)
        local path = trim(tostring(out or ""))
        current = path:match("([^/]+)$") or ""
        if listed then refresh() end
    end)
end

local function publish()
    local at = fact.page * PAGE
    local rows = {}
    local n = 0
    for r = 0, PAGE / COLS - 1 do
        local cells = {}
        for k = 0, COLS - 1 do
            local name = vis[at + r * COLS + k + 1]
            if name == nil then break end
            cells[#cells + 1] = {
                name = name,
                picture = dir .. "/" .. name,
                fav = favs[name] == true,
                now = (name == current),
                sw = schemes[name] or {},
            }
            n = n + 1
        end
        if #cells == 0 then break end
        rows[#rows + 1] = { cells = cells }
    end
    model.walls = rows
    fact.shown = n

    if fact.sel > n - 1 then fact.sel = math.max(n - 1, 0) end
    if fact.sel < 0 then fact.sel = 0 end
end

function status()
    local line = "page " .. tostring(fact.page + 1) .. " / " .. tostring(fact.pages)
    if #vis > 0 then
        line = line .. " · " .. tostring(#vis) .. (#vis == 1 and " wallpaper" or " wallpapers")
    end
    if fact.order == "newest" then line = line .. " · newest first" end
    if fact.only_favourites then line = line .. " · favourites only" end
    if fact.favourites > 0 then
        line = line .. " · " .. tostring(fact.favourites)
            .. (fact.favourites == 1 and " favourite" or " favourites")
    end
    if skipped > 0 then line = line .. " · " .. tostring(skipped) .. " clip(s) skipped" end
    if #vis == 0 then
        if fact.only_favourites then
            line = "no favourites yet: press f on a wallpaper you like"
        else
            line = "no wallpapers in " .. text.folder
        end
    end
    text.status = line
end

-- One line of the reader: {"n": name, "c": {role: "#rrggbb", …}, …}
local function read_line(line)
    line = trim(line)
    if line == "" then return end
    local ok, rec = pcall(json.decode, line)
    if not ok or type(rec) ~= "table" or type(rec.n) ~= "string" then
        log("picker: could not read a palette line")
        return
    end

    local colors = rec.c
    local sw = {}
    if type(colors) == "table" then
        for _, role in ipairs(CHIPS) do
            local r, g, b = channels(colors[role])
            if r then sw[#sw + 1] = { r = r, g = g, b = b } end
        end
    end
    schemes[rec.n] = sw
    publish()
end

-- The colour schemes of the page on screen. The reader answers the names it was given, out of
-- order (three workers), which does not matter: a record goes back to the card it belongs to.
local function read_page()
    if type(reader) == "number" then
        kill(reader)
        reader = nil
    end
    reader_gen = reader_gen + 1
    local mine = reader_gen

    local at = fact.page * PAGE
    -- Only what has not been read yet: a re-sort moves names the reader already answered onto
    -- the page, and running matugen over them again would be work for nothing.
    local page_names = {}
    for k = 1, PAGE do
        local name = vis[at + k]
        if name == nil then break end
        if schemes[name] == nil then page_names[#page_names + 1] = name end
    end
    if #page_names == 0 then return end

    local args = { dir }
    for _, name in ipairs(page_names) do args[#args + 1] = name end

    local ok, id = pcall(spawn, "pleamar-wallpaper-palettes", args, function(line)
        -- A line from a read the deck has already left is not this page's business.
        if mine ~= reader_gen then return end
        read_line(line)
    end, function(_, code)
        if mine == reader_gen then reader = nil end
        if code ~= 0 then log("picker: the palette reader exited with " .. tostring(code)) end
    end)
    if not ok then
        text.status = "the palette reader is not installed"
        log("picker: " .. tostring(id))
    else
        -- The id is what `kill` takes: without it every read leaves its worker (and the three
        -- matugen children it starts) running for the rest of the session.
        reader = id
    end
end

local function show_page(p)
    p = math.max(0, math.min(p, pages() - 1))
    if p == fact.page then return end
    fact.page = p
    fact.sel = 0
    fact.pages = pages()
    publish()
    status()
    read_page()
end

-- ======================= the folder =======================

-- Every name the folder holds, in name order, with the clips left out (and counted).
local function listed_names(out)
    local got = {}
    skipped = 0
    for line in string.gmatch(out or "", "[^\n]+") do
        local name = trim(line)
        if name ~= "" then
            if CLIPS[extension(name)] then
                skipped = skipped + 1
            else
                got[#got + 1] = name
            end
        end
    end
    table.sort(got)
    return got
end

-- What the deck holds now: `names` through the sort, the page the chosen card lands on, the
-- cards laid down. Called by the listing and by every change of sort, so one place decides what
-- the deck shows. The card the keyboard is on keeps hold of its wallpaper across a re-sort, as
-- the reference's refocus() did, instead of the number staying put and another card taking it.
function refresh()
    local had = vis[fact.page * PAGE + fact.sel + 1]
    vis = ordered()
    fact.pages = pages()
    local at = nil
    if type(had) == "string" then
        for i = 1, #vis do
            if vis[i] == had then
                at = i - 1
                break
            end
        end
    end
    if at then
        fact.page = math.min(math.floor(at / PAGE), fact.pages - 1)
        fact.sel = at % PAGE
    else
        if fact.page > fact.pages - 1 then fact.page = fact.pages - 1 end
        if fact.sel > fact.shown - 1 then fact.sel = math.max(fact.shown - 1, 0) end
    end
    publish()
    status()
    read_page()
end

-- The folder's list, from the palette helper: one bare name a line, in name order.
local function read_names()
    local ok, why = pcall(run, "pleamar-wallpaper-palettes", { "--names", dir }, function(out, code)
        if code ~= 0 then
            text.status = "could not read " .. text.folder
            log("picker: listing the folder exited with " .. tostring(code))
            return
        end
        names = listed_names(out)
        listed = true
        refresh()
    end)

    if not ok then
        text.status = "the palette reader is not installed"
        log("picker: " .. tostring(why))
    end
end

function list()
    if type(reader) == "number" then
        kill(reader)
        reader = nil
    end
    names = {}
    vis = {}
    by_time = {}
    schemes = {}
    fact.page = 0
    fact.sel = 0
    fact.shown = 0
    publish()
    text.status = "reading " .. text.folder

    -- The folder by time, newest first, which is the whole of the "newest" sort. No service
    -- reports a file's modification time, so it is `ls -t`: the documented stopgap until one
    -- exists -- a scene sees the system through services, and the helpers own the rest.
    local ok, why = pcall(run, "ls", { "-1", "-t", dir }, function(out, code)
        by_time = {}
        if code == 0 then
            for line in string.gmatch(out or "", "[^\n]+") do
                local name = trim(line)
                if name ~= "" then by_time[#by_time + 1] = name end
            end
        end
        -- A folder that cannot be read is the names run's to report: it says so in the status.
        read_names()
    end)

    if not ok then
        text.status = "could not read " .. text.folder
        log("picker: " .. tostring(why))
    end
end

-- ======================= applying =======================

local function choose(i)
    local name = vis[fact.page * PAGE + i + 1]
    if type(name) ~= "string" then return end
    local path = dir .. "/" .. name

    local ok, why = pcall(run, "pleamar-wallpaper-apply", { path, text.command }, function(_, code)
        if code ~= 0 then
            log("picker: applying " .. name .. " failed with " .. tostring(code))
            return
        end
        log("picker: set " .. name)
    end)
    if not ok then
        text.status = "could not apply " .. name
        log("picker: " .. tostring(why))
        return
    end

    -- The deck has done its job: the caches and the wallpaper command land first, matugen after.
    text.status = "set " .. name
    fact.open = false
end

-- ======================= events =======================

on("open_picker", function()
    if not listed then list() end
    read_current()
    fact.open = true
end)

-- The folder may have changed on disk (a download, a new wallpaper): read it again.
-- The finder's own trigger: a new question starts at the first page, since the old one may not
-- exist in the new list.
on("text:query", function()
    fact.page = 0
    fact.sel = 0
    refresh()
end)

on("reload", function()
    list()
end)

-- n / p (and Page_Down / Page_Up): the next page of cards.
on("flip", function(delta)
    if type(delta) == "number" then show_page(fact.page + delta) end
end)

on("choose", function(i)
    if type(i) == "number" then choose(math.floor(i)) end
end)

-- The sort turned over (`s`, or `--say picker "fact order newest"`): the page is laid down again
-- in the new order. Everything already read stays read: the schemes are looked up by name.
on("fact:order", function(which)
    if #names == 0 then return end
    refresh()
    log("picker: sorted by " .. tostring(which))
end)

-- `f` on a card: mark it favourite, or take the mark away. The deck is laid down again in
-- `toggle_favourite`, because the favourites lead the order.
on("favourite", function(i)
    if type(i) == "number" then toggle_favourite(math.floor(i)) end
end)

-- `tab`: the deck shows the favourites and nothing else, or everything again.
on("fact:only_favourites", function()
    if #names == 0 then return end
    refresh()
end)

-- An editor or a second copy changed the favourites: read them again, and lay the deck down if
-- the set moved. Our own write lands here too, on the same answer it already has.
sys.watch("files:" .. FAV, function()
    if read_favourites() and #names > 0 then refresh() end
end)

-- The settings screen: opened, it says what is set now and puts the caret in the folder, so a
-- person types over it; closed, the caret goes back to the deck's keys (`g`, the arrows, Enter).
-- The fact is the scene's, so this covers every way in and out of the screen, not just the keys.
on("fact:settings", function(open)
    if open then
        text.field_folder = text.folder
        text.field_command = text.command
        text.note = note_here()
        focus("field_folder")
    else
        focus()
    end
end)

-- Enter in either field, or the screen's Save: the two settings into settings.json. Enter is
-- heard here and not in a rule of the scene's, because the fields live inside the settings card
-- (a component): `submit field_folder` at the scene's own level names the live text, not the
-- field the copy holds, so a rule there never fires.
local function save_from(what)
    return function(value)
        if type(value) == "string" then text[what] = value end
        save_settings()
    end
end

on("submit:field_folder", save_from("field_folder"))
on("submit:field_command", save_from("field_command"))

on("save_settings", function()
    save_settings()
end)

-- An editor or a second copy changed the settings: re-read, and list again if the folder moved.
-- The screen's own save lands here too; it has already applied the same values by then, so the
-- folder has not moved and the deck is not listed twice.
sys.watch("files:" .. FILE, function()
    if read_settings() then list() end
end)

-- The folder and the command are known before the first open, and so are the favourites: the
-- deck's order leads with them from its first page.
read_settings()
read_favourites()
fact.pages = 1
status()

-- A logic saved while the deck is up starts from nothing, and the scene stays as it was: read
-- the folder again, or the deck would show cards this logic no longer knows about.
if fact.open then list() end

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
