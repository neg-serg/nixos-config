-- swayimg config for neg-serg/fork (Lua API)
-- Converted from legacy key=value config

local actions = os.getenv("HOME") .. "/.local/bin/swayimg-actions.sh"

local function exec(cmd)
  os.execute(cmd .. " &")
end

local function cp(file)
  return '"' .. file:gsub("'", "'\\''") .. '"'
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

-- Safe position accessor (get_position() may return nil coords in edge cases)
local function get_pos()
  local pos = swayimg.viewer.get_position()
  return { x = pos.x or 0, y = pos.y or 0 }
end

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
swayimg.viewer.on_key("J", function()
  local pos = get_pos()
  swayimg.viewer.set_abs_position(pos.x, pos.y + 50)
end)

-- File navigation
swayimg.viewer.on_key("BackSpace", function() swayimg.viewer.open("prev") end)
swayimg.viewer.on_key("g", function() swayimg.viewer.open("first") end)
swayimg.viewer.on_key("G", function() swayimg.viewer.open("last") end)
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

-- Toggle fullscreen / antialiasing / info
swayimg.viewer.on_key("f", function() swayimg.toggle_fullscreen() end)
swayimg.viewer.on_key("a", function()
  -- TODO: query state when API supports it
  swayimg.enable_antialiasing(not swayimg.enable_antialiasing(true))
end)
swayimg.viewer.on_key("i", function() swayimg.text.show() end)
-- File operations (exec swayimg-actions.sh)
swayimg.viewer.on_key("c", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " copyname " .. cp(img['path']))
end)
swayimg.viewer.on_key("s", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " copyname " .. cp(img['path']))
end)
swayimg.viewer.on_key("Ctrl-c", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " cp " .. cp(img['path']))
end)
swayimg.viewer.on_key("d", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " mv " .. cp(img['path']) .. " " .. os.getenv("HOME") .. "/trash/1st-level/pic")
end)
swayimg.viewer.on_key("Ctrl-d", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " mv " .. cp(img['path']) .. " " .. os.getenv("HOME") .. "/trash/1st-level/pic")
end)
swayimg.viewer.on_key("v", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " mv " .. cp(img['path']))
end)
swayimg.viewer.on_key("r", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " repeat " .. cp(img['path']))
end)

-- Range operations
swayimg.viewer.on_key("C", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " range-cp " .. cp(img['path']))
end)
swayimg.viewer.on_key("D", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " range-trash " .. cp(img['path']))
end)
swayimg.viewer.on_key("Shift+d", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " range-trash " .. cp(img['path']))
end)
swayimg.viewer.on_key("M", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " range-mark " .. cp(img['path']))
end)
swayimg.viewer.on_key("R", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " range-clear " .. cp(img['path']))
end)
swayimg.viewer.on_key("V", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " range-mv " .. cp(img['path']))
end)

-- Rotate via ImageMagick (mogrify)
swayimg.viewer.on_key("Ctrl-comma", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " rotate-left " .. cp(img['path']))
end)
swayimg.viewer.on_key("Ctrl-less", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " rotate-ccw " .. cp(img['path']))
end)
swayimg.viewer.on_key("Ctrl-period", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " rotate-right " .. cp(img['path']))
end)
swayimg.viewer.on_key("Ctrl-slash", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " rotate-180 " .. cp(img['path']))
end)

-- Wallpapers via swww
swayimg.viewer.on_key("Ctrl-1", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " wall-mono " .. cp(img['path']))
end)
swayimg.viewer.on_key("Ctrl-2", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " wall-fill " .. cp(img['path']))
end)
swayimg.viewer.on_key("Ctrl-3", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " wall-full " .. cp(img['path']))
end)
swayimg.viewer.on_key("Ctrl-4", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " wall-tile " .. cp(img['path']))
end)
swayimg.viewer.on_key("Ctrl-5", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " wall-center " .. cp(img['path']))
end)
swayimg.viewer.on_key("Ctrl-w", function()
  local img = swayimg.viewer.current_image()
  exec(actions .. " wall-cover " .. cp(img['path']))
end)

-- Viewer: Russian layout duplicates (ЙЦУКЕН)
key2({"р"}, function() local p=get_pos() swayimg.viewer.set_abs_position(p.x-50,p.y) end)
key2({"о"}, function() local p=get_pos() swayimg.viewer.set_abs_position(p.x+50,p.y) end)
key2({"л"}, function() local p=get_pos() swayimg.viewer.set_abs_position(p.x,p.y-50) end)
key2({"д"}, function() local p=get_pos() swayimg.viewer.set_abs_position(p.x,p.y+50) end)
key2({"О"}, function() local p=get_pos() swayimg.viewer.set_abs_position(p.x,p.y+50) end)
key2({"т"}, function() swayimg.viewer.open("next") end)
key2({"з"}, function() swayimg.viewer.open("prev") end)
key2({"п"}, function() swayimg.viewer.open("first") end)
key2({"й"}, function() swayimg.exit(0) end)
key2({"а"}, function() swayimg.toggle_fullscreen() end)
key2({"ф"}, function() swayimg.enable_antialiasing(not swayimg.enable_antialiasing(true)) end)
key2({"ш"}, function() swayimg.text.show() end)
key2({"с","ы"}, function() local i=swayimg.viewer.current_image() exec(actions.." copyname "..cp(i['path'])) end)
key2({"в"}, function() local i=swayimg.viewer.current_image() exec(actions.." mv "..cp(i['path']).." "..os.getenv("HOME").."/trash/1st-level/pic") end)
key2({"м"}, function() local i=swayimg.viewer.current_image() exec(actions.." mv "..cp(i['path'])) end)
key2({"к"}, function() local i=swayimg.viewer.current_image() exec(actions.." repeat "..cp(i['path'])) end)
key2({"С"}, function() local i=swayimg.viewer.current_image() exec(actions.." range-cp "..cp(i['path'])) end)
key2({"В"}, function() local i=swayimg.viewer.current_image() exec(actions.." range-trash "..cp(i['path'])) end)
key2({"Ь"}, function() local i=swayimg.viewer.current_image() exec(actions.." range-mark "..cp(i['path'])) end)
key2({"К"}, function() local i=swayimg.viewer.current_image() exec(actions.." range-clear "..cp(i['path'])) end)
key2({"М"}, function() local i=swayimg.viewer.current_image() exec(actions.." range-mv "..cp(i['path'])) end)
key2({"Ctrl-с"}, function() local i=swayimg.viewer.current_image() exec(actions.." cp "..cp(i['path'])) end)
key2({"Ctrl-в"}, function() local i=swayimg.viewer.current_image() exec(actions.." mv "..cp(i['path']).." "..os.getenv("HOME").."/trash/1st-level/pic") end)
key2({"Ctrl-ц"}, function() local i=swayimg.viewer.current_image() exec(actions.." wall-cover "..cp(i['path'])) end)

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
swayimg.gallery.on_key("G", function() swayimg.gallery.select("last") end)
swayimg.gallery.on_key("h", function() swayimg.gallery.select("left") end)
swayimg.gallery.on_key("l", function() swayimg.gallery.select("right") end)
swayimg.gallery.on_key("k", function() swayimg.gallery.select("up") end)
swayimg.gallery.on_key("j", function() swayimg.gallery.select("down") end)
swayimg.gallery.on_key("Up", function() swayimg.gallery.select("up") end)
swayimg.gallery.on_key("Down", function() swayimg.gallery.select("down") end)
swayimg.gallery.on_key("J", function() swayimg.gallery.select("down") end)

-- Grid paging
swayimg.gallery.on_key("Prior", function() swayimg.gallery.select("pgup") end)
swayimg.gallery.on_key("Next", function() swayimg.gallery.select("pgdown") end)

-- Sequential browse (same muscle memory as viewer)
swayimg.gallery.on_key("n", function() swayimg.gallery.select("right") end)
swayimg.gallery.on_key("p", function() swayimg.gallery.select("left") end)

-- Open selected in viewer / go back to gallery
swayimg.gallery.on_key("Return", function() swayimg.set_mode("viewer") end)
swayimg.gallery.on_key("f", function() swayimg.toggle_fullscreen() end)

-- Image info
swayimg.gallery.on_key("i", function() swayimg.text.show() end)

-- File operations
swayimg.gallery.on_key("c", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " copyname " .. cp(img['path']))
end)
swayimg.gallery.on_key("s", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " copyname " .. cp(img['path']))
end)
swayimg.gallery.on_key("Ctrl-c", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " cp " .. cp(img['path']))
end)
swayimg.gallery.on_key("d", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " mv " .. cp(img['path']) .. " " .. os.getenv("HOME") .. "/trash/1st-level/pic")
end)
swayimg.gallery.on_key("Ctrl-d", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " mv " .. cp(img['path']) .. " " .. os.getenv("HOME") .. "/trash/1st-level/pic")
end)
swayimg.gallery.on_key("v", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " mv " .. cp(img['path']))
end)
swayimg.gallery.on_key("r", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " repeat " .. cp(img['path']))
end)

-- Range operations
swayimg.gallery.on_key("C", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " range-cp " .. cp(img['path']))
end)
swayimg.gallery.on_key("D", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " range-trash " .. cp(img['path']))
end)
swayimg.gallery.on_key("Shift+d", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " range-trash " .. cp(img['path']))
end)
swayimg.gallery.on_key("M", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " range-mark " .. cp(img['path']))
end)
swayimg.gallery.on_key("R", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " range-clear " .. cp(img['path']))
end)
swayimg.gallery.on_key("V", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " range-mv " .. cp(img['path']))
end)

-- Rotate via ImageMagick
swayimg.gallery.on_key("Ctrl-comma", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " rotate-left " .. cp(img['path']))
end)
swayimg.gallery.on_key("Ctrl-less", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " rotate-ccw " .. cp(img['path']))
end)
swayimg.gallery.on_key("Ctrl-period", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " rotate-right " .. cp(img['path']))
end)
swayimg.gallery.on_key("Ctrl-slash", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " rotate-180 " .. cp(img['path']))
end)

-- Wallpapers
swayimg.gallery.on_key("Ctrl-1", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " wall-mono " .. cp(img['path']))
end)
swayimg.gallery.on_key("Ctrl-2", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " wall-fill " .. cp(img['path']))
end)
swayimg.gallery.on_key("Ctrl-3", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " wall-full " .. cp(img['path']))
end)
swayimg.gallery.on_key("Ctrl-4", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " wall-tile " .. cp(img['path']))
end)
swayimg.gallery.on_key("Ctrl-5", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " wall-center " .. cp(img['path']))
end)
swayimg.gallery.on_key("Ctrl-w", function()
  local img = swayimg.gallery.current_image()
  exec(actions .. " wall-cover " .. cp(img['path']))
end)

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
key2g({"р"}, function() swayimg.gallery.select("left") end)
key2g({"д"}, function() swayimg.gallery.select("right") end)
key2g({"л"}, function() swayimg.gallery.select("up") end)
key2g({"о"}, function() swayimg.gallery.select("down") end)
key2g({"т"}, function() swayimg.gallery.select("next") end)
key2g({"з"}, function() swayimg.gallery.select("prev") end)
key2g({"О"}, function() swayimg.gallery.select("down") end)
key2g({"а"}, function() swayimg.toggle_fullscreen() end)
key2g({"ш"}, function() swayimg.text.show() end)
key2g({"с","ы"}, function() local i=swayimg.gallery.current_image() exec(actions.." copyname "..cp(i['path'])) end)
key2g({"в"}, function() local i=swayimg.gallery.current_image() exec(actions.." mv "..cp(i['path']).." "..os.getenv("HOME").."/trash/1st-level/pic") end)
key2g({"м"}, function() local i=swayimg.gallery.current_image() exec(actions.." mv "..cp(i['path'])) end)
key2g({"к"}, function() local i=swayimg.gallery.current_image() exec(actions.." repeat "..cp(i['path'])) end)
key2g({"С"}, function() local i=swayimg.gallery.current_image() exec(actions.." range-cp "..cp(i['path'])) end)
key2g({"В"}, function() local i=swayimg.gallery.current_image() exec(actions.." range-trash "..cp(i['path'])) end)
key2g({"Ь"}, function() local i=swayimg.gallery.current_image() exec(actions.." range-mark "..cp(i['path'])) end)
key2g({"К"}, function() local i=swayimg.gallery.current_image() exec(actions.." range-clear "..cp(i['path'])) end)
key2g({"М"}, function() local i=swayimg.gallery.current_image() exec(actions.." range-mv "..cp(i['path'])) end)
key2g({"Ctrl-с"}, function() local i=swayimg.gallery.current_image() exec(actions.." cp "..cp(i['path'])) end)
key2g({"Ctrl-в"}, function() local i=swayimg.gallery.current_image() exec(actions.." mv "..cp(i['path']).." "..os.getenv("HOME").."/trash/1st-level/pic") end)
key2g({"Ctrl-ц"}, function() local i=swayimg.gallery.current_image() exec(actions.." wall-cover "..cp(i['path'])) end)

-- ── Slideshow ────────────────────────────────────────────────────────────
swayimg.slideshow.set_timeout(3)

-- Slideshow keybindings
swayimg.slideshow.bind_reset()

swayimg.slideshow.on_key("f", function() swayimg.toggle_fullscreen() end)
swayimg.slideshow.on_key("q", function() swayimg.exit(0) end)
swayimg.slideshow.on_key("s", function()
  local img = swayimg.slideshow.current_image()
  exec(actions .. " copyname " .. cp(img['path']))
end)

swayimg.slideshow.on_key("d", function()
  local img = swayimg.slideshow.current_image()
  exec(actions .. " mv " .. cp(img['path']) .. " " .. os.getenv("HOME") .. "/trash/1st-level/pic")
end)

swayimg.slideshow.on_key("Ctrl-d", function()
  local img = swayimg.slideshow.current_image()
  exec(actions .. " mv " .. cp(img['path']) .. " " .. os.getenv("HOME") .. "/trash/1st-level/pic")
end)

swayimg.slideshow.on_key("C", function()
  local img = swayimg.slideshow.current_image()
  exec(actions .. " range-cp " .. cp(img['path']))
end)
swayimg.slideshow.on_key("D", function()
  local img = swayimg.slideshow.current_image()
  exec(actions .. " range-trash " .. cp(img['path']))
end)
swayimg.slideshow.on_key("Shift+d", function()
  local img = swayimg.slideshow.current_image()
  exec(actions .. " range-trash " .. cp(img['path']))
end)
swayimg.slideshow.on_key("M", function()
  local img = swayimg.slideshow.current_image()
  exec(actions .. " range-mark " .. cp(img['path']))
end)
swayimg.slideshow.on_key("R", function()
  local img = swayimg.slideshow.current_image()
  exec(actions .. " range-clear " .. cp(img['path']))
end)
swayimg.slideshow.on_key("V", function()
  local img = swayimg.slideshow.current_image()
  exec(actions .. " range-mv " .. cp(img['path']))
end)

-- Toggle pause
swayimg.slideshow.on_key("Space", function()
  if swayimg.get_mode() == "slideshow" then
    swayimg.set_mode("viewer")
  else
    swayimg.set_mode("slideshow")
  end
end)

-- Slideshow: Russian layout duplicates (ЙЦУКЕН)
key2s({"й"}, function() swayimg.exit(0) end)
key2s({"а"}, function() swayimg.toggle_fullscreen() end)
key2s({"с","ы"}, function() local i=swayimg.slideshow.current_image() exec(actions.." copyname "..cp(i['path'])) end)
key2s({"в"}, function() local i=swayimg.slideshow.current_image() exec(actions.." mv "..cp(i['path']).." "..os.getenv("HOME").."/trash/1st-level/pic") end)
key2s({"Ctrl-в"}, function() local i=swayimg.slideshow.current_image() exec(actions.." mv "..cp(i['path']).." "..os.getenv("HOME").."/trash/1st-level/pic") end)
key2s({"С"}, function() local i=swayimg.slideshow.current_image() exec(actions.." range-cp "..cp(i['path'])) end)
key2s({"В"}, function() local i=swayimg.slideshow.current_image() exec(actions.." range-trash "..cp(i['path'])) end)
key2s({"Ь"}, function() local i=swayimg.slideshow.current_image() exec(actions.." range-mark "..cp(i['path'])) end)
key2s({"К"}, function() local i=swayimg.slideshow.current_image() exec(actions.." range-clear "..cp(i['path'])) end)
key2s({"М"}, function() local i=swayimg.slideshow.current_image() exec(actions.." range-mv "..cp(i['path'])) end)
