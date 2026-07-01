-- gf for Python: follow import / from-import statements to their source files.
-- Handles: relative imports (from . / from ..), absolute imports (project + venv).
-- Complements pyright's LSP gd — works without LSP and opens the file directly.

local nav = require('utils.nav')
local uv  = vim.uv

local PY_EXTS = { '.py', '/__init__.py' }

local function import_at_cursor()
  local line = vim.api.nvim_get_current_line()

  -- Relative: from .mod, from ..mod.sub, from . import X (mod = '')
  local dots, mod = line:match('^%s*from%s+(%.+)([%w%.]*)')
  if dots then
    return { kind = 'relative', ndots = #dots, mod_path = mod:gsub('%.', '/') }
  end

  -- Absolute from-import: from package.module import X
  local from_mod = line:match('^%s*from%s+([%w%.]+)%s+import')
  if from_mod then return { kind = 'absolute', path = from_mod:gsub('%.', '/') } end

  -- Plain import: import package.module
  local imp_mod = line:match('^%s*import%s+([%w%.]+)')
  if imp_mod then return { kind = 'absolute', path = imp_mod:gsub('%.', '/') } end

  return nil
end

-- Locate site-packages: prefer $VIRTUAL_ENV, fall back to .venv in project root.
local function venv_sitepackages()
  local venv = vim.env.VIRTUAL_ENV
  if not venv then
    local root = nav.project_root()
    local local_venv = root .. '/.venv'
    if uv.fs_stat(local_venv) then venv = local_venv end
  end
  if not venv then return nil end
  local matches = vim.fn.glob(venv .. '/lib/python*', false, true)
  return #matches > 0 and (matches[1] .. '/site-packages') or nil
end

-- Try base path with each extension; skip directories; return absolute path or nil.
local function try_py_path(base)
  for _, ext in ipairs(PY_EXTS) do
    local p  = base .. ext
    local st = uv.fs_stat(p)
    if st and st.type ~= 'directory' then return vim.fn.fnamemodify(p, ':p') end
  end
end

local function follow_import()
  local imp = import_at_cursor()
  if not imp then return vim.cmd('normal! gf') end

  if imp.kind == 'relative' then
    -- Walk up (ndots - 1) levels from the current file's directory.
    -- 1 dot → stay in current dir;  2 dots → go up one level; etc.
    local base = vim.fn.expand('%:p:h')
    for _ = 1, imp.ndots - 1 do base = vim.fn.fnamemodify(base, ':h') end
    local full     = imp.mod_path ~= '' and (base .. '/' .. imp.mod_path) or base
    local resolved = try_py_path(full)
    if resolved then nav.open_file(resolved); return end
    -- fzf fallback: use the final module name component as query
    local tail = imp.mod_path:match('[^/]+$') or 'init'
    local ok, fzf = pcall(require, 'fzf-lua')
    if ok then fzf.files({ query = tail, cwd = nav.project_root(base) }) end
    return
  end

  -- Absolute import: project src/ dirs (via 'path' from 04-aucmds) first, then venv.
  local resolved = nav.resolve_path(imp.path, { extensions = PY_EXTS, fzf_fallback = false })
  if not resolved then
    local sp = venv_sitepackages()
    if sp then resolved = try_py_path(sp .. '/' .. imp.path) end
  end

  if resolved then
    nav.open_file(resolved)
  else
    local ok, fzf = pcall(require, 'fzf-lua')
    if ok then fzf.files({ query = imp.path:match('[^/]+$') or imp.path, cwd = nav.project_root() }) end
  end
end

vim.keymap.set('n', 'gf', follow_import, { buffer = true, desc = 'Follow import to source' })
vim.keymap.set('n', '<CR>', follow_import, { buffer = true, desc = 'Follow import to source' })
