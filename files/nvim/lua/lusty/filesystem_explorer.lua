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

-- g:LustyExplorerFollowMountPoints: when 0 (default) the depth-aware listing
-- does not descend into directories that are mount points (music libraries,
-- /proc, other filesystems, ...) - they are still shown, just not walked.
local function follow_mounts()
  local v = vim.g.LustyExplorerFollowMountPoints
  return v == 1 or v == true or v == '1'
end

-- g:LustyExplorerSkipDirs: comma-separated directory names (or paths, with
-- optional '~' / '*' '?' wildcards) that the depth-aware listing must not
-- descend into.  Defaults to 'pic,tmp' (the user's large non-project dirs);
-- set to '' to disable.
local DEFAULT_SKIP = 'pic,tmp'
local function skip_patterns()
  local raw = vim.g.LustyExplorerSkipDirs
  if raw == nil then
    raw = DEFAULT_SKIP
  end
  local out = {}
  for _, item in ipairs(vim.split(tostring(raw), ',')) do
    local it = item:gsub('^%s+', ''):gsub('%s+$', '')
    if it ~= '' then
      out[#out + 1] = it
    end
  end
  return out
end

local function skip_signature()
  local raw = vim.g.LustyExplorerSkipDirs
  return raw == nil and 'DEFAULT' or tostring(raw)
end

-- Simple glob ('*' and '?') full-string matcher.
local function glob_match(pattern, value)
  if not pattern:find('[*?]') then
    return pattern == value
  end
  local out = { '^' }
  local i = 1
  while i <= #pattern do
    local c = pattern:sub(i, i)
    if c == '*' then
      out[#out + 1] = '.*'
    elseif c == '?' then
      out[#out + 1] = '.'
    elseif c:find('[%^%$%(%)%%%.%+%-]') then
      out[#out + 1] = '%' .. c
    else
      out[#out + 1] = c
    end
    i = i + 1
  end
  out[#out + 1] = '$'
  return value:find(table.concat(out)) ~= nil
end

local function expand_home(p)
  if p:sub(1, 1) == '~' then
    local home = os.getenv('HOME') or vim.fn.expand('~')
    local head, rest = p:match('^(~[^/]*)(.*)$')
    if head == '~' and home then
      return home .. rest
    end
    local ex = vim.fn.expand(head)
    if ex ~= '' and ex ~= head then
      return ex .. rest
    end
  end
  return p
end

-- Is this directory excluded from depth traversal?
local function dir_skipped(c)
  local patterns = skip_patterns()
  if #patterns == 0 then
    return false
  end
  for _, pat in ipairs(patterns) do
    if pat:find('/') or pat:sub(1, 1) == '~' then
      -- path-style pattern: compare against the absolute directory path
      local target = c.full:gsub('/+$', '')
      if glob_match(expand_home(pat):gsub('/+$', ''), target) then
        return true
      end
    elseif glob_match(pat, c.name) then
      -- bare name: matches any directory with that basename
      return true
    end
  end
  return false
end

-- Mount point set parsed from /proc/self/mountinfo (field 5 of the part
-- before ' - '), cached for the session.
local mount_set = nil
local function mount_points()
  if mount_set then
    return mount_set
  end
  mount_set = {}
  local ok, content = pcall(vim.fn.readfile, '/proc/self/mountinfo')
  if ok and type(content) == 'table' then
    for _, line in ipairs(content) do
      -- Split on the ' - ' separator: the mount point is field 5 of the
      -- first half (paths may themselves contain '-', so do not split on it).
      local parts = vim.split(line, ' - ', { plain = true })
      if parts[1] then
        local fields = vim.split(parts[1], ' ')
        if fields[5] then
          local mp = fields[5]
          mp = mp:gsub('/+$', '')
          if mp == '' then
            mp = '/'
          end
          mount_set[mp] = true
        end
      end
    end
  end
  mount_set['/'] = true
  return mount_set
end

local function is_mount_point(path)
  -- Normalise: collapse '//' (walk builds '/'-prefixed paths under '/').
  local p = path:gsub('/+', '/')
  p = p:gsub('/+$', '')
  if p == '' then
    p = '/'
  end
  return mount_points()[p] ~= nil
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
        -- One lstat per entry (exec colour is resolved lazily at paint time).
        local ftype = vim.fn.getftype(full)
        local is_dir = ftype == 'dir'
        local is_link = ftype == 'link'
        if is_link then
          is_dir = vim.fn.isdirectory(full) == 1 -- label symlink-to-dir with '/'
        end
        entries[#entries + 1] = {
          label = is_dir and (name .. '/') or name,
          name = name,
          path = full,
          is_dir = is_dir,
          is_link = is_link,
          is_socket = ftype == 'socket',
          is_pipe = ftype == 'fifo',
        }
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
  -- Skip unreadable dirs quietly (e.g. /root): readdir would raise E484.
  if vim.uv.fs_access(dir, 'R') ~= true then
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
      -- One lstat per child; exec colour resolves lazily at paint time.
      local ftype = vim.fn.getftype(full)
      local is_dir = ftype == 'dir'
      local is_link = ftype == 'link'
      if is_link then
        is_dir = vim.fn.isdirectory(full) == 1
      end
      out[#out + 1] = {
        name = name,
        is_dir = is_dir,
        is_link = is_link,
        is_socket = ftype == 'socket',
        is_pipe = ftype == 'fifo',
        full = full,
      }
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
          path = c.full,
          is_dir = c.is_dir,
          is_link = c.is_link,
          is_socket = c.is_socket,
          is_pipe = c.is_pipe,
          is_exec = nil, -- resolved lazily at paint time
        }
      end
      if c.is_dir and not c.is_link and level + 1 < depth then
        -- Do not descend into mount points or excluded dirs unless enabled.
        if dir_skipped(c) then
          -- entry stays visible, contents are not walked
        elseif follow_mounts() or not is_mount_point(c.full) then
          walk(c.full, rel2, level + 1)
        end
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
  local follow = follow_mounts()
  local skip = skip_signature()
  local cached = deep_cache[view]
  if cached and cached.depth == depth and cached.follow == follow and cached.skip == skip then
    return cached.entries
  end
  local entries = build_deep(view)
  deep_cache[view] = { depth = depth, follow = follow, skip = skip, entries = entries }
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

-- Nesting level of a label (path components below the view): 'src/' = 1,
-- 'src/foo/' = 2, 'src/foo/bar.txt' = 3.  Shallower entries always sort
-- above deeper ones so the top of the list stays near the current dir.
local function label_depth(label)
  local p = label:gsub('/+$', '')
  if p == '' then
    return 0
  end
  local n = 1
  for _ in vim.gsplit(p, '/', { plain = true }) do
    n = n + 1
  end
  return n - 1
end

e.compute_sorted_matches = function()
  local abbrev = current_abbreviation()
  local unsorted = all_files_at_view()

  if abbrev == '' then
    table.sort(unsorted, function(a, b)
      local da, db = label_depth(a.label), label_depth(b.label)
      if da ~= db then
        return da < db
      end
      return a.label < b.label
    end)
    return unsorted
  end

  local matches = {}
  -- g:LustyExplorerFuzzyEngine = 'mercury' restores the original scorer.
  local use_mercury = tostring(vim.g.LustyExplorerFuzzyEngine or '') == 'mercury'
  -- The first query letter must be a prefix of the entry's basename (not just
  -- appear somewhere in the path), so typing 'c' cannot match 'pic.jpg' etc.
  local first = abbrev ~= '.' and abbrev:sub(1, 1):lower() or nil
  for _, entry in ipairs(unsorted) do
    if not first or (entry.name or ''):sub(1, 1):lower() == first then
      entry.score = use_mercury and mercury.score(entry.label, abbrev) or fuzzy.score(entry.label, abbrev)
      if entry.score ~= 0.0 then
        matches[#matches + 1] = entry
      end
    end
  end
  if abbrev == '.' then
    table.sort(matches, function(a, b)
      local da, db = label_depth(a.label), label_depth(b.label)
      if da ~= db then
        return da < db
      end
      return a.label < b.label
    end)
  else
    table.sort(matches, function(a, b)
      local da, db = label_depth(a.label), label_depth(b.label)
      if da ~= db then
        return da < db
      end
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
