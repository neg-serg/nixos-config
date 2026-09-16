-- swayimg config for neg-serg/fork (Lua API)
-- Converted from legacy key=value config

local actions = os.getenv("HOME") .. "/.local/bin/swayimg-actions.sh"

local function exec(cmd)
  os.execute(cmd .. " &")
end

local function cp(file)
  return '"' .. file:gsub("'", "'\\''") .. '"'
end

-- Factory: a key handler that runs `swayimg-actions.sh <cmd> <quoted path>` on
-- the current image of a mode. `to_trash` also appends the 1st-level trash dir.
local function act(mode, cmd, to_trash)
  return function()
    local img = swayimg[mode].current_image()
    exec(actions .. " " .. cmd .. " " .. cp(img['path'])
      .. (to_trash and (" " .. os.getenv("HOME") .. "/trash/1st-level/pic") or ""))
  end
end

-- Helper: bind the same action to multiple key names (for dual layout support)
local function key2(layouts, fn)
  for _, k in ipairs(layouts) do
    swayimg.viewer.on_key(k, fn)
  end
end
local function key2g(layouts, fn)
  for _, k in ipairs(layouts) do
    swayimg.gallery.on_key(k, fn)
  end
end
local function key2s(layouts, fn)
  for _, k in ipairs(layouts) do
    swayimg.slideshow.on_key(k, fn)
  end
end

-- Position accessors. Fork returns table {x=..., y=...} (viewer); slideshow may
-- return a tuple. Handle both shapes.
local function get_pos()
  local x, y = swayimg.viewer.get_position()
  if type(x) == "table" then
    return { x = x.x or 0, y = x.y or 0 }
  end
  return { x = x or 0, y = y or 0 }
end
local function get_slideshow_pos()
  local x, y = swayimg.slideshow.get_position()
  if type(x) == "table" then
    return { x = x.x or 0, y = x.y or 0 }
  end
  return { x = x or 0, y = y or 0 }
end

-- Antialiasing state (API has no getter)
local aa_enabled = true

-- ── General ──────────────────────────────────────────────────────────────
swayimg.enable_decoration(false)
swayimg.enable_overlay(true)
swayimg.enable_antialiasing(true)

-- Session: auto mode (default)
swayimg.session.set_mode("auto")

-- ── Image list ───────────────────────────────────────────────────────────
swayimg.imagelist.set_order("none")
swayimg.imagelist.enable_reverse(false)
swayimg.imagelist.enable_recursive(false)
swayimg.imagelist.set_ignore_patterns({
  ".git", ".svn", ".hg", ".DS_Store", "node_modules"
})

-- ── Text / Font ──────────────────────────────────────────────────────────
swayimg.text.set_font("Iosevka")
swayimg.text.set_size(14)
swayimg.text.set_foreground(0xffb8c5d9)  -- #b8c5d9ff
swayimg.text.set_shadow(0xee000000)       -- #000000ee
swayimg.text.set_background(0xee000000)   -- #000000ee
swayimg.text.set_timer(1)                 -- info timeout
swayimg.text.set_status_timer(2)          -- status timeout

-- ── Viewer ───────────────────────────────────────────────────────────────
swayimg.viewer.set_default_scale("optimal")
swayimg.viewer.set_default_position("center")
swayimg.viewer.set_window_background(0x00000000)   -- #00000000
swayimg.viewer.set_image_background(0xff000000)    -- #000000ff (transparent bg)
swayimg.viewer.enable_loop(false)
swayimg.viewer.set_preload_limit(16)
swayimg.viewer.set_history_limit(4)
swayimg.viewer.enable_freemove(true)  -- allow panning when image fits entirely in window

-- Text layout: bottom-left=path, bottom-right=index/status
swayimg.viewer.set_text_bl({"{path}"})
swayimg.viewer.set_text_br({"{list.index}/{list.total}"})

-- Viewer keybindings
swayimg.viewer.bind_reset()

-- vim-style navigation
swayimg.viewer.on_key("h", function()
  local pos = get_pos()
  swayimg.viewer.set_abs_position(pos.x - 50, pos.y)
end)
swayimg.viewer.on_key("l", function()
  local pos = get_pos()
  swayimg.viewer.set_abs_position(pos.x + 50, pos.y)
end)
swayimg.viewer.on_key("k", function()
  local pos = get_pos()
  swayimg.viewer.set_abs_position(pos.x, pos.y - 50)
end)
swayimg.viewer.on_key("j", function()
  local pos = get_pos()
  swayimg.viewer.set_abs_position(pos.x, pos.y + 50)
end)

-- Arrow-key navigation (same as h/j/k/l)
swayimg.viewer.on_key("Up", function()
  local pos = get_pos()
  swayimg.viewer.set_abs_position(pos.x, pos.y - 50)
end)
swayimg.viewer.on_key("Down", function()
  local pos = get_pos()
  swayimg.viewer.set_abs_position(pos.x, pos.y + 50)
end)
swayimg.viewer.on_key("Shift-j", function()
  local pos = get_pos()
  swayimg.viewer.set_abs_position(pos.x, pos.y + 50)
end)

-- File navigation
swayimg.viewer.on_key("g", function() swayimg.viewer.open("first") end)
swayimg.viewer.on_key("Shift-g", function() swayimg.viewer.open("last") end)
swayimg.viewer.on_key("n", function() swayimg.viewer.open("next") end)
swayimg.viewer.on_key("p", function() swayimg.viewer.open("prev") end)

-- Zoom
swayimg.viewer.on_key("0", function() swayimg.viewer.set_fix_scale("real") end)

-- Exit
swayimg.viewer.on_key("q", function() swayimg.exit(0) end)

-- Mode switching
swayimg.viewer.on_key("Return", function() swayimg.set_mode("gallery") end)
swayimg.viewer.on_key("Escape", function() swayimg.set_mode("gallery") end)
swayimg.viewer.on_key("Space", function() swayimg.viewer.open("next") end)
swayimg.viewer.on_key("Shift+Space", function() swayimg.viewer.open("prev") end)

-- Antialiasing / info
-- Pseudo-fullscreen is handled by Hyprland (rule "pic-pseudo-fullscreen"),
-- so swayimg's own toggle_fullscreen() / -F are intentionally unused.
swayimg.viewer.on_key("a", function()
  aa_enabled = not aa_enabled
  swayimg.enable_antialiasing(aa_enabled)
end)
swayimg.viewer.on_key("i", function() swayimg.text.show() end)
-- File operations (exec swayimg-actions.sh)
swayimg.viewer.on_key("c", act("viewer", "copyname"))
swayimg.viewer.on_key("s", act("viewer", "copyname"))
swayimg.viewer.on_key("Ctrl-c", act("viewer", "cp"))
swayimg.viewer.on_key("d", act("viewer", "mv", true))
swayimg.viewer.on_key("Ctrl-d", act("viewer", "mv", true))
swayimg.viewer.on_key("v", act("viewer", "mv"))
swayimg.viewer.on_key("r", act("viewer", "repeat"))

-- Range operations
swayimg.viewer.on_key("Shift-c", act("viewer", "range-cp"))
swayimg.viewer.on_key("Shift-d", act("viewer", "range-trash"))
swayimg.viewer.on_key("Shift+d", act("viewer", "range-trash"))
swayimg.viewer.on_key("Shift-m", act("viewer", "range-mark"))
swayimg.viewer.on_key("Shift-r", act("viewer", "range-clear"))
swayimg.viewer.on_key("Shift-v", act("viewer", "range-mv"))

-- Rotate via ImageMagick (mogrify)
swayimg.viewer.on_key("Ctrl-comma", act("viewer", "rotate-left"))
swayimg.viewer.on_key("Ctrl-Shift-comma", act("viewer", "rotate-ccw"))
swayimg.viewer.on_key("Ctrl-Shift-less", act("viewer", "rotate-ccw"))
swayimg.viewer.on_key("Ctrl-Shift-greater", act("viewer", "rotate-right"))
swayimg.viewer.on_key("Ctrl-slash", act("viewer", "rotate-180"))
-- Viewer: Russian rotate duplicates (ЙЦУКЕН)
key2({"Ctrl-б"}, act("viewer", "rotate-left"))
key2({"Ctrl-Shift-б"}, act("viewer", "rotate-ccw"))
key2({"Ctrl-ю"}, act("viewer", "rotate-right"))
key2({"Ctrl-."}, act("viewer", "rotate-180"))

-- Wallpapers via swww
swayimg.viewer.on_key("Ctrl-1", act("viewer", "wall-mono"))
swayimg.viewer.on_key("Ctrl-2", act("viewer", "wall-fill"))
swayimg.viewer.on_key("Ctrl-3", act("viewer", "wall-full"))
swayimg.viewer.on_key("Ctrl-4", act("viewer", "wall-tile"))
swayimg.viewer.on_key("Ctrl-5", act("viewer", "wall-center"))
swayimg.viewer.on_key("Ctrl-w", act("viewer", "wall-cover"))

-- Viewer: Russian layout duplicates (ЙЦУКЕН)
key2({"р"}, function() local p=get_pos() swayimg.viewer.set_abs_position(p.x-50,p.y) end)
key2({"о"}, function() local p=get_pos() swayimg.viewer.set_abs_position(p.x,p.y+50) end)
key2({"л"}, function() local p=get_pos() swayimg.viewer.set_abs_position(p.x,p.y-50) end)
key2({"д"}, function() local p=get_pos() swayimg.viewer.set_abs_position(p.x+50,p.y) end)
key2({"Shift-о"}, function() local p=get_pos() swayimg.viewer.set_abs_position(p.x,p.y+50) end)
key2({"т"}, function() swayimg.viewer.open("next") end)
key2({"з"}, function() swayimg.viewer.open("prev") end)
key2({"п"}, function() swayimg.viewer.open("first") end)
key2({"Shift-п"}, function() swayimg.viewer.open("last") end)
key2({"й"}, function() swayimg.exit(0) end)
key2({"ф"}, function() aa_enabled = not aa_enabled swayimg.enable_antialiasing(aa_enabled) end)
key2({"ш"}, function() swayimg.text.show() end)
key2({"с","ы"}, act("viewer", "copyname"))
key2({"в"}, act("viewer", "mv", true))
key2({"м"}, act("viewer", "mv"))
key2({"к"}, act("viewer", "repeat"))
key2({"Shift-с"}, act("viewer", "range-cp"))
key2({"Shift-в"}, act("viewer", "range-trash"))
key2({"Shift-ь"}, act("viewer", "range-mark"))
key2({"Shift-к"}, act("viewer", "range-clear"))
key2({"Shift-м"}, act("viewer", "range-mv"))
key2({"Ctrl-с"}, act("viewer", "cp"))
key2({"Ctrl-в"}, act("viewer", "mv", true))
key2({"Ctrl-ц"}, act("viewer", "wall-cover"))

-- Zoom and reset (restored after bind_reset())
swayimg.viewer.on_key("Equal", function() local s = swayimg.viewer.get_scale() swayimg.viewer.set_abs_scale(s + s/10) end)
swayimg.viewer.on_key("Minus", function() local s = swayimg.viewer.get_scale() swayimg.viewer.set_abs_scale(s - s/10) end)
swayimg.viewer.on_key("BackSpace", function() swayimg.viewer.reset_scale() end)

-- ── Gallery ──────────────────────────────────────────────────────────────
swayimg.gallery.set_thumb_size(200)
swayimg.gallery.set_cache_size(100000)
swayimg.gallery.enable_preload(true)
swayimg.gallery.enable_pstore(true)
swayimg.gallery.set_aspect("fill")
swayimg.gallery.set_window_color(0xff000000)     -- #000000ff
swayimg.gallery.set_background_color(0x00000000) -- #00000000
swayimg.gallery.set_selected_color(0xff404040)   -- #404040ff
swayimg.gallery.set_border_color(0xff000000)     -- #000000ff

-- Gallery keybindings
swayimg.gallery.bind_reset()

swayimg.gallery.on_key("q", function() swayimg.exit(0) end)
swayimg.gallery.on_key("g", function() swayimg.gallery.select("first") end)
swayimg.gallery.on_key("Shift-g", function() swayimg.gallery.select("last") end)
swayimg.gallery.on_key("h", function() swayimg.gallery.select("left") end)
swayimg.gallery.on_key("l", function() swayimg.gallery.select("right") end)
swayimg.gallery.on_key("k", function() swayimg.gallery.select("up") end)
swayimg.gallery.on_key("j", function() swayimg.gallery.select("down") end)
swayimg.gallery.on_key("Up", function() swayimg.gallery.select("up") end)
swayimg.gallery.on_key("Down", function() swayimg.gallery.select("down") end)
swayimg.gallery.on_key("Left", function() swayimg.gallery.select("left") end)
swayimg.gallery.on_key("Right", function() swayimg.gallery.select("right") end)

-- Grid paging
swayimg.gallery.on_key("Prior", function() swayimg.gallery.select("pgup") end)
swayimg.gallery.on_key("Next", function() swayimg.gallery.select("pgdown") end)

-- Sequential browse (same muscle memory as viewer)
swayimg.gallery.on_key("n", function() swayimg.gallery.select("right") end)
swayimg.gallery.on_key("p", function() swayimg.gallery.select("left") end)

-- Open selected in viewer / go back to gallery
swayimg.gallery.on_key("Return", function() swayimg.set_mode("viewer") end)

-- Image info
swayimg.gallery.on_key("i", function() swayimg.text.show() end)

-- File operations
swayimg.gallery.on_key("c", act("gallery", "copyname"))
swayimg.gallery.on_key("s", act("gallery", "copyname"))
swayimg.gallery.on_key("Ctrl-c", act("gallery", "cp"))
swayimg.gallery.on_key("d", act("gallery", "mv", true))
swayimg.gallery.on_key("Ctrl-d", act("gallery", "mv", true))
swayimg.gallery.on_key("v", act("gallery", "mv"))
swayimg.gallery.on_key("r", act("gallery", "repeat"))

-- Range operations
swayimg.gallery.on_key("Shift-c", act("gallery", "range-cp"))
swayimg.gallery.on_key("Shift-d", act("gallery", "range-trash"))
swayimg.gallery.on_key("Shift+d", act("gallery", "range-trash"))
swayimg.gallery.on_key("Shift-m", act("gallery", "range-mark"))
swayimg.gallery.on_key("Shift-r", act("gallery", "range-clear"))
swayimg.gallery.on_key("Shift-v", act("gallery", "range-mv"))

-- Rotate via ImageMagick
swayimg.gallery.on_key("Ctrl-comma", act("gallery", "rotate-left"))
swayimg.gallery.on_key("Ctrl-Shift-comma", act("gallery", "rotate-ccw"))
swayimg.gallery.on_key("Ctrl-Shift-less", act("gallery", "rotate-ccw"))
swayimg.gallery.on_key("Ctrl-Shift-greater", act("gallery", "rotate-right"))
swayimg.gallery.on_key("Ctrl-slash", act("gallery", "rotate-180"))
-- Gallery: Russian rotate duplicates (ЙЦУКЕН)
key2g({"Ctrl-б"}, act("gallery", "rotate-left"))
key2g({"Ctrl-Shift-б"}, act("gallery", "rotate-ccw"))
key2g({"Ctrl-ю"}, act("gallery", "rotate-right"))
key2g({"Ctrl-."}, act("gallery", "rotate-180"))

-- Wallpapers
swayimg.gallery.on_key("Ctrl-1", act("gallery", "wall-mono"))
swayimg.gallery.on_key("Ctrl-2", act("gallery", "wall-fill"))
swayimg.gallery.on_key("Ctrl-3", act("gallery", "wall-full"))
swayimg.gallery.on_key("Ctrl-4", act("gallery", "wall-tile"))
swayimg.gallery.on_key("Ctrl-5", act("gallery", "wall-center"))
swayimg.gallery.on_key("Ctrl-w", act("gallery", "wall-cover"))

-- Thumb size
swayimg.gallery.on_key("Equal", function()
  local s = swayimg.gallery.get_thumb_size()
  swayimg.gallery.set_thumb_size(s + 16)
end)
swayimg.gallery.on_key("Minus", function()
  local s = swayimg.gallery.get_thumb_size()
  swayimg.gallery.set_thumb_size(math.max(32, s - 16))
end)

-- Gallery: Russian layout duplicates (ЙЦУКЕН)
key2g({"й"}, function() swayimg.exit(0) end)
key2g({"п"}, function() swayimg.gallery.select("first") end)
key2g({"Shift-п"}, function() swayimg.gallery.select("last") end)
key2g({"р"}, function() swayimg.gallery.select("left") end)
key2g({"д"}, function() swayimg.gallery.select("right") end)
key2g({"л"}, function() swayimg.gallery.select("up") end)
key2g({"о"}, function() swayimg.gallery.select("down") end)
key2g({"т"}, function() swayimg.gallery.select("right") end)
key2g({"з"}, function() swayimg.gallery.select("left") end)
key2g({"О"}, function() swayimg.gallery.select("down") end)
key2g({"ш"}, function() swayimg.text.show() end)
key2g({"с","ы"}, act("gallery", "copyname"))
key2g({"в"}, act("gallery", "mv", true))
key2g({"м"}, act("gallery", "mv"))
key2g({"к"}, act("gallery", "repeat"))
key2g({"Shift-с"}, act("gallery", "range-cp"))
key2g({"Shift-в"}, act("gallery", "range-trash"))
key2g({"Shift-ь"}, act("gallery", "range-mark"))
key2g({"Shift-к"}, act("gallery", "range-clear"))
key2g({"Shift-м"}, act("gallery", "range-mv"))
key2g({"Ctrl-с"}, act("gallery", "cp"))
key2g({"Ctrl-в"}, act("gallery", "mv", true))
key2g({"Ctrl-ц"}, act("gallery", "wall-cover"))

-- ── Slideshow ────────────────────────────────────────────────────────────
swayimg.slideshow.set_timeout(3)

-- Slideshow keybindings
swayimg.slideshow.bind_reset()

swayimg.slideshow.on_key("q", function() swayimg.exit(0) end)
swayimg.slideshow.on_key("s", act("slideshow", "copyname"))
swayimg.slideshow.on_key("c", act("slideshow", "copyname"))

swayimg.slideshow.on_key("d", act("slideshow", "mv", true))

swayimg.slideshow.on_key("Ctrl-d", act("slideshow", "mv", true))

swayimg.slideshow.on_key("Shift-c", act("slideshow", "range-cp"))
swayimg.slideshow.on_key("Shift-d", act("slideshow", "range-trash"))
swayimg.slideshow.on_key("Shift+d", act("slideshow", "range-trash"))
swayimg.slideshow.on_key("Shift-m", act("slideshow", "range-mark"))
swayimg.slideshow.on_key("Shift-r", act("slideshow", "range-clear"))
swayimg.slideshow.on_key("Shift-v", act("slideshow", "range-mv"))

-- Toggle pause
swayimg.slideshow.on_key("Space", function()
  if swayimg.get_mode() == "slideshow" then
    swayimg.set_mode("viewer")
  else
    swayimg.set_mode("slideshow")
  end
end)

-- Navigation (mirror viewer)
swayimg.slideshow.on_key("n", function() swayimg.slideshow.open("next") end)
swayimg.slideshow.on_key("p", function() swayimg.slideshow.open("prev") end)
swayimg.slideshow.on_key("BackSpace", function() swayimg.slideshow.open("prev") end)
swayimg.slideshow.on_key("Return", function() swayimg.set_mode("gallery") end)
swayimg.slideshow.on_key("Escape", function() swayimg.set_mode("gallery") end)
swayimg.slideshow.on_key("i", function() swayimg.text.show() end)
-- Pan navigation (fork returns tuple x,y, not table)
swayimg.slideshow.on_key("h", function() local p=get_slideshow_pos() swayimg.slideshow.set_abs_position(p.x-50,p.y) end)
swayimg.slideshow.on_key("l", function() local p=get_slideshow_pos() swayimg.slideshow.set_abs_position(p.x+50,p.y) end)
swayimg.slideshow.on_key("k", function() local p=get_slideshow_pos() swayimg.slideshow.set_abs_position(p.x,p.y-50) end)
swayimg.slideshow.on_key("j", function() local p=get_slideshow_pos() swayimg.slideshow.set_abs_position(p.x,p.y+50) end)
swayimg.slideshow.on_key("Left", function() local p=get_slideshow_pos() swayimg.slideshow.set_abs_position(p.x-50,p.y) end)
swayimg.slideshow.on_key("Right", function() local p=get_slideshow_pos() swayimg.slideshow.set_abs_position(p.x+50,p.y) end)
swayimg.slideshow.on_key("Up", function() local p=get_slideshow_pos() swayimg.slideshow.set_abs_position(p.x,p.y-50) end)
swayimg.slideshow.on_key("Down", function() local p=get_slideshow_pos() swayimg.slideshow.set_abs_position(p.x,p.y+50) end)

-- Slideshow: Russian layout duplicates (ЙЦУКЕН)
key2s({"й"}, function() swayimg.exit(0) end)
key2s({"с","ы"}, act("slideshow", "copyname"))
key2s({"в"}, act("slideshow", "mv", true))
key2s({"Ctrl-в"}, act("slideshow", "mv", true))
key2s({"Shift-с"}, act("slideshow", "range-cp"))
key2s({"Shift-в"}, act("slideshow", "range-trash"))
key2s({"Shift-ь"}, act("slideshow", "range-mark"))
key2s({"Shift-к"}, act("slideshow", "range-clear"))
key2s({"Shift-м"}, act("slideshow", "range-mv"))
key2s({"т"}, function() swayimg.slideshow.open("next") end)
key2s({"з"}, function() swayimg.slideshow.open("prev") end)
key2s({"р"}, function() local p=get_slideshow_pos() swayimg.slideshow.set_abs_position(p.x-50,p.y) end)
key2s({"о"}, function() local p=get_slideshow_pos() swayimg.slideshow.set_abs_position(p.x,p.y+50) end)
key2s({"л"}, function() local p=get_slideshow_pos() swayimg.slideshow.set_abs_position(p.x,p.y-50) end)
key2s({"д"}, function() local p=get_slideshow_pos() swayimg.slideshow.set_abs_position(p.x+50,p.y) end)
key2s({"ш"}, function() swayimg.text.show() end)
