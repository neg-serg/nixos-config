-- trash.lua
-- Move the currently playing local file to /tmp/trash instead of deleting it,
-- so a wrong click is recoverable and the file keeps playing from the open
-- descriptor. Bound to D in ~/.config/mpv/input.conf (script-message
-- trash-move); the binding is duplicated for the ru layout in input.nix.
--
-- The trash is a plain directory: nothing cleans it up automatically, remove
-- its contents when they are no longer wanted.

local TRASH_DIR = "/tmp/trash"

local function osd(text, seconds)
  mp.osd_message(text, seconds or 2)
end

-- mpv runs from arbitrary working directories (file manager, shell, playlist
-- entry), so a relative `path` is resolved against the player's CWD.
local function absolute(path)
  if path:sub(1, 1) == "/" then
    return path
  end
  local cwd = mp.get_property("working-directory")
  if cwd then
    return cwd .. "/" .. path
  end
  return path
end

-- mpv 0.41 dropped the mp.utils Lua module; a read-open is the only
-- stat-like probe the script sandbox offers (trash entries are plain files).
local function exists(path)
  local handle = io.open(path, "r")
  if not handle then
    return false
  end
  handle:close()
  return true
end

local function run(args)
  local result = mp.command_native({
    name = "subprocess",
    args = args,
    playback_only = false,
    capture_stdout = true,
    capture_stderr = true,
    capture_size = 4096,
  })
  return result ~= nil and result.status == 0, result
end

-- Never overwrite an earlier trashed copy: same name gets a unix timestamp
-- between stem and extension ("clip.mp4" -> "clip.1762345678.mp4").
local function target_path(name)
  local target = TRASH_DIR .. "/" .. name
  if not exists(target) then
    return target
  end
  local stem, ext = name:match("^(.*)(%.[^./]+)$")
  if not stem then
    stem, ext = name, ""
  end
  return string.format("%s/%s.%d%s", TRASH_DIR, stem, os.time(), ext)
end

local function move_to_trash()
  local path = mp.get_property("path")
  if not path or path == "" then
    osd("Нет файла")
    return
  end
  -- Streams and other URL-like paths (http, ytdl, edl, memory://) have no
  -- file to move.
  if path:match("^%a[%w+.-]*://") then
    osd("Только локальные файлы")
    return
  end
  path = absolute(path)
  local name = path:match("([^/]+)$") or path

  local ok, result = run({ "mkdir", "-p", TRASH_DIR })
  if not ok then
    osd("Не удалось создать " .. TRASH_DIR, 3)
    return
  end

  local target = target_path(name)
  ok, result = run({ "mv", "-n", "--", path, target })
  if ok then
    osd("В корзине: " .. (target:match("([^/]+)$") or target))
  else
    local err = result and result.stderr or ""
    err = err:gsub("%s+$", "")
    osd("Не удалось переместить" .. (err ~= "" and ": " .. err or ""), 3)
  end
end

mp.register_script_message("trash-move", move_to_trash)
