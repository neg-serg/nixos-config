-- FilesystemExplorer: port of lusty/src/lusty/filesystem-explorer.rb.

local util = require('lusty.util')
local mercury = require('lusty.mercury')
local fuzzy = require('lusty.fuzzy')
local ls_colors = require('lusty.ls_colors')
local E = require('lusty.explorer')

local M = {}

local e = E.Explorer.new({
  title = 'LustyExplorer--Files',
  filesystem = true,
})

-- dircolors-style cell coloring (LS_COLORS); nil when the entry has no rule.
e.color_entry = function(entry)
  return ls_colors.group_for(entry)
end



-- Directory contents are memoized per view; <C-r> refreshes the current one.
local dir_cache = {}
local deep_cache = {} -- view -> { depth = n, entries = [...] }

-- g:LustyExplorerSearchDepth: include files in subdirectories up to N levels
-- below the current view (default 2, like 'fd --max-depth 2'); 1 = classic
-- single-directory listing.
local function search_depth()
  local v = tonumber(vim.g.LustyExplorerSearchDepth)
  if v == nil then
    return 2
  end
  return math.max(1, math.min(6, math.floor(v)))
end

local function always_show_dotfiles()
  local v = vim.g.LustyExplorerAlwaysShowDotFiles
  return v ~= nil and v ~= false and v ~= 0 and v ~= '0'
end

-- Canonical view (directory whose contents are shown), no trailing slash.
local function view_path()
  local v = e.prompt:value()
  if e.prompt:at_dir() and #v > 1 then
    return v:sub(1, -2)
  end
  return e.prompt:dirname()
end

-- Query used to filter the current directory.
local function current_abbreviation()
  if e.prompt:at_dir() then
    return ''
  end
  return util.basename(e.prompt:value())
end

local function list_remote(view)
  local host, path = view:match('^scp://([^/]+)/(.*)$')
  if not host then
    return {}
  end
  local flag = always_show_dotfiles() and 'a' or ''
  local out = vim.fn.system({ 'ssh', host, 'ls', '-1pL' .. flag, '--', path })
  local entries = {}
  for line in vim.fn.split(out, '\n') do
    if line ~= '.' and line ~= '..' then
      local is_dir = line:sub(-1) == '/'
      entries[#entries + 1] = {
        label = line,
        name = line:gsub('/+$', ''),
        is_dir = is_dir,
      }
    end
  end
  return entries
end

-- List the directory (masks applied, dotfile filtering is separate).
local function fetch_view(view)
  local view_str = view
  if view_str:sub(1, 6) == 'scp://' then
    return list_remote(view)
  end
  if vim.fn.isdirectory(view) ~= 1 then
    return {}
  end
  local ok, names = pcall(vim.fn.readdir, view)
  if not ok or type(names) ~= 'table' then
    return {}
  end
  local entries = {}
  for _, name in ipairs(names) do
    if name == '.' then
      -- skip
    elseif name == '..' and always_show_dotfiles() then
      -- skip (upstream hides ".." when AlwaysShowDotFiles is set)
    else
      if not util.masked(name, e.masks) then
        local full = view .. '/' .. name
        local ftype = vim.fn.getftype(full)
        local is_dir = vim.fn.isdirectory(full) == 1
        local is_link = ftype == 'link'
        local entry = {
          label = is_dir and (name .. '/') or name,
          name = name,
          is_dir = is_dir,
          is_link = is_link,
          is_socket = ftype == 'socket',
          is_pipe = ftype == 'fifo',
        }
        if ftype == 'file' then
          local perm = vim.fn.getfperm(full)
          entry.is_exec = type(perm) == 'string' and perm:find('x') ~= nil
        end
        entries[#entries + 1] = entry
      end
    end
  end
  -- vim.fn.readdir never yields '..'; add it like Dir.foreach would.
  -- (Hidden by the dotfile filter unless the query starts with '.'; upstream
  -- hides it entirely when LustyExplorerAlwaysShowDotFiles is set.)
  if not always_show_dotfiles() then
    entries[#entries + 1] = { label = '../', name = '..', is_dir = true }
  end
  return entries
end

-- Raw children of a directory (no '..', no masks, no dotfile filtering);
-- used to build the depth > 1 listing.  Symlinked dirs are listed but not
-- recursed into (avoids loops/duplicates).
local function raw_children(dir)
  if vim.fn.isdirectory(dir) ~= 1 then
    return {}
  end
  local ok, names = pcall(vim.fn.readdir, dir)
  if not ok or type(names) ~= 'table' then
    return {}
  end
  local out = {}
  for _, name in ipairs(names) do
    if name ~= '.' and name ~= '..' and not util.masked(name, e.masks) then
      local full = dir .. '/' .. name
      local ftype = vim.fn.getftype(full)
      local is_dir = vim.fn.isdirectory(full) == 1
      local entry = {
        name = name,
        is_dir = is_dir,
        is_link = ftype == 'link',
        is_socket = ftype == 'socket',
        is_pipe = ftype == 'fifo',
        full = full,
      }
      if ftype == 'file' then
        local perm = vim.fn.getfperm(full)
        entry.is_exec = type(perm) == 'string' and perm:find('x') ~= nil
      end
      out[#out + 1] = entry
    end
  end
  return out
end

-- Build the depth-aware entry list relative to `view`.
local function build_deep(view)
  local depth = search_depth()
  local entries = {}
  -- level = number of path components below the view (root = 0).  A child
  -- at level+1 is listed when level+1 <= depth and recursed into when
  -- level+1 < depth, so depth 2 covers view/sub/file and view/sub/dir/file.
  local function walk(abs_dir, rel, level)
    for _, c in ipairs(raw_children(abs_dir)) do
      local rel2 = rel == '' and c.name or (rel .. '/' .. c.name)
      if level + 1 <= depth then
        entries[#entries + 1] = {
          label = c.is_dir and (rel2 .. '/') or rel2,
          name = c.name,
          is_dir = c.is_dir,
          is_link = c.is_link,
          is_socket = c.is_socket,
          is_pipe = c.is_pipe,
          is_exec = c.is_exec,
        }
      end
      if c.is_dir and not c.is_link and level + 1 < depth then
        walk(c.full, rel2, level + 1)
      end
    end
  end
  walk(view, '', 0)
  if not always_show_dotfiles() then
    entries[#entries + 1] = { label = '../', name = '..', is_dir = true }
  end
  return entries
end

local function deep_entries(view)
  local depth = search_depth()
  local cached = deep_cache[view]
  if cached and cached.depth == depth then
    return cached.entries
  end
  local entries = build_deep(view)
  deep_cache[view] = { depth = depth, entries = entries }
  return entries
end

-- Does any path component of the label start with '.' ('../', '.git/x', ...)?
local function label_has_dot_component(label)
  local p = label:gsub('/+$', '')
  if p == '' then
    return false
  end
  for comp in vim.gsplit(p, '/', { plain = true }) do
    if comp:sub(1, 1) == '.' then
      return true
    end
  end
  return false
end

local function all_files_at_view()
  local view = view_path()
  local abbrev = current_abbreviation()
  local show_dots = always_show_dotfiles() or abbrev:sub(1, 1) == '.'

  local all
  if search_depth() > 1 then
    all = deep_entries(view)
  else
    if not dir_cache[view] then
      dir_cache[view] = fetch_view(view)
    end
    all = dir_cache[view]
  end

  if show_dots then
    return all
  end
  local visible = {}
  for _, entry in ipairs(all) do
    if not label_has_dot_component(entry.label) then
      visible[#visible + 1] = entry
    end
  end
  return visible
end

e.compute_sorted_matches = function()
  local abbrev = current_abbreviation()
  local unsorted = all_files_at_view()

  if abbrev == '' then
    table.sort(unsorted, function(a, b)
      return a.label < b.label
    end)
    return unsorted
  end

  local matches = {}
  -- g:LustyExplorerFuzzyEngine = 'mercury' restores the original scorer.
  local use_mercury = tostring(vim.g.LustyExplorerFuzzyEngine or '') == 'mercury'
  for _, entry in ipairs(unsorted) do
    entry.score = use_mercury and mercury.score(entry.label, abbrev) or fuzzy.score(entry.label, abbrev)
    if entry.score ~= 0.0 then
      matches[#matches + 1] = entry
    end
  end
  if abbrev == '.' then
    table.sort(matches, function(a, b)
      return a.label < b.label
    end)
  else
    table.sort(matches, function(a, b)
      return a.score > b.score
    end)
  end
  return matches
end

local function is_dir_label(label)
  return label:sub(-1) == '/'
end

local function load_file(path, mode)
  local rel = vim.fn.fnamemodify(path, ':.')
  local cmd = mode == 'current_tab' and 'e'
    or mode == 'new_tab' and 'tabe'
    or mode == 'new_split' and 'sp'
    or mode == 'new_vsplit' and 'vs'
    or 'e'
  vim.cmd('silent ' .. cmd .. ' ' .. vim.fn.fnameescape(rel))
end

e.open_entry = function(_, entry, mode)
  local view = view_path()
  local path
  if view == '/' then
    path = '/' .. entry.label
  else
    path = view .. '/' .. entry.label
  end

  if is_dir_label(entry.label) then
    -- Recurse into the directory.
    e.prompt:set(path)
    e.selected = 0
  else
    -- File entries may carry a relative path (depth > 1 listing).
    e:cleanup()
    pcall(load_file, path, mode)
  end
end

-- <C-a>/<Shift-Enter>: open all non-directories currently in view.
-- <C-e>: create a new buffer from the prompt text.
-- <C-r>: refresh the current directory.
e.key_pressed = function(self, code)
  if code == 1 or code == 10 then
    local matches = e.matches
    e:cleanup()
    for _, entry in ipairs(matches) do
      local path
      if e.prompt:at_dir() then
        path = e.prompt:value() .. entry.label
      else
        local d = e.prompt:dirname()
        path = d == '/' and (d .. entry.label) or (d .. '/' .. entry.label)
      end
      if not is_dir_label(entry.label) then
        pcall(load_file, path, 'current_tab')
      end
    end
    return
  elseif code == 5 then
    -- <C-e> create file with the given name and path.
    if not e.prompt:at_dir() then
      local path = e.prompt:value()
      local v = view_path()
      dir_cache[v] = nil
      deep_cache[v] = nil
      e:cleanup()
      pcall(load_file, path, 'current_tab')
    end
    return
  elseif code == 18 then
    -- <C-r> refresh directory contents.
    local v = view_path()
    dir_cache[v] = nil
    deep_cache[v] = nil
    e.selected = 0
    e:refresh('full')
    return
  end
  E.Explorer.key_pressed(self, code)
end

--- Open the filesystem explorer.
--- @param path string|nil start directory ('' or nil = cwd)
function M.run(path)
  if e.running then
    return
  end
  if path == nil or path == '' then
    path = vim.fn.getcwd()
  end
  e.masks = util.read_masks()
  e.prompt:set(path .. '/')
  e.selected = 0
  e:start()
end

function M.explorer()
  return e
end

function M.clear_cache()
  dir_cache = {}
  deep_cache = {}
end

return M
