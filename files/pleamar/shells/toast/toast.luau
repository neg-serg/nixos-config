-- toast.luau — the logic of the toast scene (PH2-D).
--
-- The scene draws; this file owns what a rule cannot: the screenshot event
-- file, the auto-hide timer and the OCR/copy/open actions. Nothing here paints
-- or knows coordinates.
--
-- The event file lives OUTSIDE the scene's own folder, one of the cache
-- signals of INTERFACES §1.2 (`$XDG_CACHE_HOME/pleamar/screenshot-event.json`),
-- and the `files` service never leaves the folder — so it is read with
-- `run("cat", …)` (declared in the scene: `run: "cat"`). Polling stands in for
-- the legacy FileView watch; 700 ms is the cadence, and `cat` runs only for
-- this one path.
--
-- Actions: the legacy `pic-ocr --engine=tesseract|nn`, `wl-copy <path>` and
-- `xdg-open <path>`; the card is hidden first, as the legacy hid itself as soon
-- as it launched the program. Paths with a fresh `?<n>` counter are handed to
-- the scene so the renderer reloads a shot written again under the same name.
--
-- Settings (INTERFACES §6.3, defaults and clamps here, unknown keys survive):
--   anchor  text   "bottom_right", a surface.anchor value, where the card sits
--   margin  number 24, 0..64, design px from that edge

local FILE = "settings.json"

local D = {
    anchor = "bottom_right",
    margin = 24,
}

local ANCHORS = {
    top = true, bottom = true, left = true, right = true,
    top_left = true, top_right = true, bottom_left = true, bottom_right = true,
    center = true,
}

local function num(v, lo, hi, def)
    if type(v) ~= "number" or v ~= v then return def end
    return math.max(lo, math.min(hi, v))
end

local raw = {}
local function read_file()
    local ok, got = pcall(function() return sys.ask("files.read", FILE, "json") end)
    if ok and type(got) == "table" then return got end
    return {}
end

local function apply()
    local a = raw.anchor
    if type(a) ~= "string" or not ANCHORS[a] then a = D.anchor end
    fact.card_anchor = a
    fact.card_margin = num(raw.margin, 0, 64, D.margin)
end

raw = read_file()
apply()

-- An editor, or a later settings UI, changed the file: honoured live.
sys.watch("files:" .. FILE, function()
    raw = read_file()
    apply()
end)

-- ------***------------------------- where the event is
local HOME = "/tmp"
local CACHE = "/tmp/.cache"

local ok_home, home = pcall(function() return sys.ask("env", "HOME") end)
if ok_home and type(home) == "string" and home ~= "" then HOME = home end

local ok_cache, cache = pcall(function() return sys.ask("env", "XDG_CACHE_HOME") end)
if ok_cache and type(cache) == "string" and cache ~= "" then CACHE = cache end

local EVENT = CACHE .. "/pleamar/screenshot-event.json"

-- ------***--------------------- show, hide and the timer
local POLL_MS = 700
local AUTO_HIDE_MS = 8000 -- the legacy autoHideMs

local last = nil       -- the event file as last read
local primed = false   -- a baseline has been taken
local busy = false     -- one `cat` at a time
local path = ""        -- the shot path, without the reload counter
local ver = 0          -- the counter that forces a reload
local timer = nil

local function hide()
    if timer then cancel(timer); timer = nil end
    fact.shown = false
    fact.visible = 0
end

local function arm()
    if timer then cancel(timer) end
    timer = after(AUTO_HIDE_MS, hide)
end

-- The legacy showed the path with HOME as `~`; the scene cannot rewrite a
-- string, so the short form is made here.
local function short(p)
    if HOME ~= "" and p:sub(1, #HOME) == HOME then
        return "~" .. p:sub(#HOME + 1)
    end
    return p
end

local function show(raw_json)
    local okj, data = pcall(json.decode, raw_json)
    if not okj or type(data) ~= "table" then
        log("screenshot-event: not JSON, ignored")
        return
    end

    path = (type(data.path) == "string") and data.path or ""
    if path == "" then
        fact.shot_ok = false
        text.shot_path = ""
    else
        ver = ver + 1
        text.shot_path = path .. "?" .. tostring(ver)
        fact.shot_ok = true
    end

    -- "1920 x 1080 · 1.21 MB · 8-bit RGBA", the legacy size line.
    local meta = ""
    if type(data.w) == "number" and type(data.h) == "number" then
        meta = tostring(math.floor(data.w)) .. " x " .. tostring(math.floor(data.h))
    end
    if type(data.sizeHr) == "string" and data.sizeHr ~= "" then
        meta = meta .. (meta ~= "" and " · " or "") .. data.sizeHr
    end
    if type(data.depth) == "string" and data.depth ~= "" then
        meta = meta .. (meta ~= "" and " · " or "") .. data.depth
    end

    text.shot_meta = meta
    text.shot_short = short(path)
    text.shot_ts = (type(data.ts) == "string") and data.ts or ""

    fact.ever_shown = true
    fact.shown = true
    fact.visible = 1
    arm()
end

-- ------***------------------------- the event file
-- `cat` on a missing file fails: the first successful read after that is a new
-- event. A file that is already there when the scene starts is a leftover and
-- only becomes the baseline (the legacy FileView did not fire on load either).
local function poll()
    if busy then return end
    busy = true
    run("cat", { EVENT }, function(out, code)
        busy = false
        if code ~= 0 or type(out) ~= "string" then
            primed = true
            return
        end
        if not primed then
            primed = true
            last = out
            return
        end
        if out ~= last then
            last = out
            show(out)
        end
    end)
end

every(POLL_MS, poll)
poll()

-- ------***------------------------- the actions
-- Everything hangs up after pressing an action, exactly as the legacy did.
local function act(cmd, args)
    if path == "" then return end
    hide()
    run(cmd, args)
end

on("ocr_tess", function() act("pic-ocr", { "--engine=tesseract", path }) end)
on("ocr_nn", function() act("pic-ocr", { "--engine=nn", path }) end)
on("copy_path", function() act("wl-copy", { path }) end)
on("open_shot", function() act("xdg-open", { path }) end)

on("hide", function() hide() end)

-- Hovering the card keeps it: the legacy stopped its auto-hide on hover.
on("hover_in", function()
    if timer then cancel(timer); timer = nil end
end)
on("hover_out", function()
    if fact.shown then arm() end
end)
