-- Unified file navigation utilities: project root (cached), path resolution,
-- URL dispatch, and vim-fetch-aware file opening.
-- Used by ftplugin/markdown.lua, ftplugin/sh.lua, ftplugin/lua.lua,
-- and indirectly by utils/fzf.lua and 04-aucmds.lua.
local M = {}
local uv = vim.uv

-- Ordered by specificity so ecosystem markers win over generic VCS roots,
-- which gives correct behaviour inside monorepo sub-projects.
-- Superset of the old markers in 04-aucmds.lua and utils/fzf.lua.
local ROOT_MARKERS = {
  'Cargo.toml', 'pyproject.toml', 'go.mod', 'package.json',
  'CMakeLists.txt', 'Makefile', 'mix.exs',
  '.zk', '.obsidian', 'justfile',
  '.git', '.hg',
}

-- Module-level cache: startpath → root.  Lives for the whole Neovim session.
-- Invalidation is not needed — project roots don't move during a session.
local _root_cache = {}

-- Return the project root for startpath (or cwd if omitted).
-- Cached: repeated calls for the same path are O(1) table lookups.
function M.project_root(startpath)
  startpath = startpath or vim.fn.getcwd()
  if _root_cache[startpath] then return _root_cache[startpath] end
  local found = vim.fs.find(ROOT_MARKERS, { path = startpath, upward = true, limit = 1 })
  local root = (#found > 0) and vim.fs.dirname(found[1]) or startpath
  _root_cache[startpath] = root
  return root
end

-- Platform-agnostic URL / file:// opener.
function M.open_url(url)
  if not (url:match('^https?://') or url:match('^file://')) then return end
  local cmd = vim.fn.has('mac') == 1 and { 'open', url }
           or vim.fn.has('wsl') == 1 and { 'wslview', url }
           or { 'handlr', 'open', url }
  vim.fn.jobstart(cmd, { detach = true })
end

-- Resolve a file path with a prioritised search chain.
-- Returns the absolute path when found, or nil after opening the fzf picker.
--
-- opts fields:
--   extensions     list  suffixes to try when path has no extension
--   preferred_dirs list  relative dirs searched before cwd (no-slash names only)
--   fzf_fallback   bool  open fzf-lua picker when nothing found (default true)
function M.resolve_path(path, opts)
  opts = opts or {}
  local extensions    = opts.extensions    or {}
  local preferred_dirs = opts.preferred_dirs or {}
  local buf_dir       = vim.fn.expand('%:p:h')

  local function stat(p) return uv.fs_stat(p) ~= nil end
  local function abs(p)  return vim.fn.fnamemodify(p, ':p') end

  -- 1. Explicit relative (starts with . or ..): resolve from buf_dir only.
  --    Do NOT escalate to cwd or path option — the author was explicit.
  if path:sub(1, 1) == '.' then
    local base = vim.fn.simplify(buf_dir .. '/' .. path)
    if stat(base) then return base end
    for _, ext in ipairs(extensions) do
      local p = base .. ext
      if stat(p) then return p end
    end
    return nil
  end

  -- 2. Absolute path: trust it as-is.
  if path:sub(1, 1) == '/' then
    return stat(path) and path or nil
  end

  -- 3. preferred_dirs (wiki-style bare names without slashes, e.g. "FooBar").
  local has_slash = path:find('/') ~= nil
  local has_ext   = path:match('%.[%w%.]+$') ~= nil
  if not has_slash and #preferred_dirs > 0 then
    for _, d in ipairs(preferred_dirs) do
      local base = d .. '/' .. path
      if stat(base) then return abs(base) end
      if not has_ext then
        for _, ext in ipairs(extensions) do
          local p = base .. ext
          if stat(p) then return abs(p) end
        end
      end
    end
  end

  -- 4. cwd (= project root after auto-lcd) + extensions.
  local cwd = vim.fn.getcwd()
  local r = cwd .. '/' .. path
  if stat(r) then return abs(r) end
  if not has_ext then
    for _, ext in ipairs(extensions) do
      local p = r .. ext
      if stat(p) then return abs(p) end
    end
  end

  -- 5. vim 'path' option via findfile (includes ft-preferred dirs from 04-aucmds).
  local found = vim.fn.findfile(path, vim.o.path)
  if found ~= '' then return abs(found) end
  if not has_ext then
    for _, ext in ipairs(extensions) do
      found = vim.fn.findfile(path .. ext, vim.o.path)
      if found ~= '' then return abs(found) end
    end
  end

  -- 6. fzf-lua fallback: show a picker instead of erroring with E447.
  if opts.fzf_fallback ~= false then
    local ok, fzf = pcall(require, 'fzf-lua')
    if ok then
      fzf.files({
        query = vim.fn.fnamemodify(path, ':t'),
        cwd   = M.project_root(buf_dir),
      })
    end
  end
  return nil
end

-- Open path in the current window, cooperating with vim-fetch for file:line.
-- The key contract: fnameescape only the path, append :line:col as a raw
-- suffix so vim-fetch's BufReadCmd pattern *[0-9] can intercept it.
--
-- opts fields:
--   line       number  line to jump to (passed as :line suffix)
--   col        number  column (appended after line)
--   anchor     string  anchor string (markdown heading, etc.)
--   anchor_fn  func    called with anchor after BufRead (scheduled)
function M.open_file(path, opts)
  opts = opts or {}
  local suffix = ''
  if opts.line then
    suffix = ':' .. opts.line
    if opts.col then suffix = suffix .. ':' .. opts.col end
  end
  vim.cmd.edit(vim.fn.fnameescape(path) .. suffix)
  if opts.anchor and opts.anchor_fn then
    vim.schedule(function() opts.anchor_fn(opts.anchor) end)
  end
end

return M
