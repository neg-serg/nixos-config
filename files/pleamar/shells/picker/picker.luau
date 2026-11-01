-- picker.luau — the wallpaper deck's reading and applying (scene `picker`).
--
-- What the declarative scene cannot do itself:
--   · read settings.json and push its defaults into `folder` and `command`, and write it back
--     when the settings screen is saved (the table it read is what it writes, so a key another
--     version put there stays);
--   · list the wallpaper folder and page through it: one page of cards is what the model holds,
--     and the deck draws the page it is on;
--   · read the colour schemes of the page's wallpapers with `pleamar-wallpaper-palettes` and
--     fill the cards' chips as the lines arrive (the pictures are there from the first frame);
--   · hand the chosen card to `pleamar-wallpaper-apply` (caches, the wallpaper command, matugen)
--     and close.
--
-- Settings (`~/.local/share/pleamar/picker/settings.json`):
--   folder    text    ~/pic/wl        the wallpapers to browse
--   command   text    wl img {}       the tool that paints the desktop; {} is the path
-- The settings screen (picker.plm, `g`) is one writer of that file and an editor is another: the
-- watcher below re-reads it, and a folder that moved is listed again there and then.
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
local schemes = {}   -- name -> {{ r, g, b }, …}, what the reader has answered so far
local reader = nil   -- the palettes process, while it runs
local skipped = 0    -- files left out because they are clips
local listed = false -- whether the folder has been listed since the scene started

-- Declared here, defined below: the settings screen may be saved at any moment, and what it
-- saves moves the folder the deck reads and the line it says about it.
local list, status

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
    return math.max(1, math.ceil(#names / PAGE))
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
        log("picker: settings.json is broken; defaults kept")
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
local function publish()
    local at = fact.page * PAGE
    local rows = {}
    local n = 0
    for r = 0, PAGE / COLS - 1 do
        local cells = {}
        for k = 0, COLS - 1 do
            local name = names[at + r * COLS + k + 1]
            if name == nil then break end
            cells[#cells + 1] = {
                name = name,
                picture = dir .. "/" .. name,
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
    if #names > 0 then line = line .. " · " .. tostring(#names) .. " wallpapers" end
    if skipped > 0 then line = line .. " · " .. tostring(skipped) .. " clip(s) skipped" end
    if #names == 0 then line = "no wallpapers in " .. text.folder end
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

    local at = fact.page * PAGE
    local page_names = {}
    for k = 1, PAGE do
        local name = names[at + k]
        if name == nil then break end
        page_names[k] = name
    end
    if #page_names == 0 then return end

    local args = { dir }
    for _, name in ipairs(page_names) do args[#args + 1] = name end

    local ok, why = pcall(spawn, "pleamar-wallpaper-palettes", args, read_line, function(_, code)
        reader = nil
        if code ~= 0 then log("picker: the palette reader exited with " .. tostring(code)) end
    end)
    if not ok then
        text.status = "the palette reader is not installed"
        log("picker: " .. tostring(why))
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

function list()
    if type(reader) == "number" then
        kill(reader)
        reader = nil
    end
    names = {}
    schemes = {}
    fact.page = 0
    fact.sel = 0
    publish()
    text.status = "reading " .. text.folder

    local ok, why = pcall(run, "pleamar-wallpaper-palettes", { "--names", dir }, function(out, code)
        if code ~= 0 then
            text.status = "could not read " .. text.folder
            log("picker: listing the folder exited with " .. tostring(code))
            return
        end
        names = listed_names(out)
        fact.pages = pages()
        listed = true
        publish()
        status()
        read_page()
    end)

    if not ok then
        text.status = "the palette reader is not installed"
        log("picker: " .. tostring(why))
    end
end

-- ======================= applying =======================

local function choose(i)
    local name = names[fact.page * PAGE + i + 1]
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
    fact.open = true
end)

-- The folder may have changed on disk (a download, a new wallpaper): read it again.
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

-- The folder and the command are known before the first open.
read_settings()
fact.pages = 1
status()
