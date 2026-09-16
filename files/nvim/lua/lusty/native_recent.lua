-- Native recent-file explorer: LustyRecent rendered in the native bottom
-- float. Items come from nvim's oldfiles (v:oldfiles, most recent first),
-- restricted to files that still exist, deduped, capped at 150. Labels are
-- relative to the cwd when possible so the same basename from different
-- directories stays distinguishable.

local pick = require('lusty.native_pick')
local frecency = require('lusty.frecency')
local filter = require('lusty.filter')
local lsc = require('lusty.ls_colors')
local native = require('lusty.native')

local M = {}

-- Remember the last filter between runs.
local previous_input = ''

-- Which MRU is shown: 'files' (v:oldfiles + journal files) or 'dirs'
-- (journal directories). C-r toggles while the picker is open.
local mode = 'files'

function M.set_mode(m)
  mode = m == 'dirs' and 'dirs' or 'files'
end

function M.mode()
  return mode
end

-- Test seam / future source override; default reads v:oldfiles.
local recent_fn = nil
function M.set_recent_fn(fn)
  recent_fn = fn
end

local function recent_paths()
  if recent_fn then
    return recent_fn()
  end
  -- v:oldfiles only refreshes at nvim startup, so files opened through the
  -- pickers this session (recorded in the frecency journal) would stay
  -- invisible until a restart. Union the journal in; snapshot_items scores
  -- journal entries by frecency so recently/often visited files rank first.
  local out = {}
  local seen = {}
  for _, p in ipairs(vim.v.oldfiles or {}) do
    out[#out + 1] = p
    seen[p] = true
  end
  for _, p in ipairs(frecency.paths()) do
    if not seen[p] then
      out[#out + 1] = p
      seen[p] = true
    end
  end
  return out
end

local function open_path(path, mode)
  local cmd = mode == 'enter' and 'edit ' or mode == 'tab' and 'tabedit ' or mode == 'split' and 'split ' or 'vsplit '
  vim.cmd('silent ' .. cmd .. vim.fn.fnameescape(path))
end

local function dir_paths()
  local out = {}
  for _, p in ipairs(frecency.paths()) do
    if vim.fn.isdirectory(p) == 1 then
      out[#out + 1] = p
    end
  end
  return out
end

local function snapshot_items()
  local seen = {}
  local scored = {}
  local rest = {}
  local is_dir_mode = mode == 'dirs'
  local paths = is_dir_mode and dir_paths() or recent_paths()
  for i, p in ipairs(paths) do
    if not seen[p] then
      local exists = is_dir_mode and vim.fn.isdirectory(p) == 1 or vim.fn.filereadable(p) == 1
      if exists then
        seen[p] = true
        local label = vim.fn.fnamemodify(p, ':.')
        local item = {
          path = p,
          order = i,
          label = label,
          is_dir = is_dir_mode,
        }
        local group = lsc.group_for({ name = p, is_dir = is_dir_mode })
        if group then
          item.group = group
        end
        local sc = frecency.score(p)
        if sc then
          item.frecency = sc
          scored[#scored + 1] = item
        else
          rest[#rest + 1] = item
        end
        if #scored + #rest >= 150 then
          break
        end
      end
    end
  end
  table.sort(scored, function(a, b)
    if a.frecency == b.frecency then
      return a.order < b.order
    end
    return a.frecency > b.frecency
  end)
  local out = {}
  for _, it in ipairs(scored) do
    out[#out + 1] = it
  end
  for _, it in ipairs(rest) do
    out[#out + 1] = it
  end
  return out
end

local running = false

function M.run()
  if running then
    return
  end
  running = true
  local snap = snapshot_items()
  local title = mode == 'dirs' and 'Recent Dirs' or 'Recent Files'
  -- First query letter must prefix the label; ties broken by recency.
  local source = filter.source(function()
    return snap
  end, 'label', 'order')
  pick.pick({
    title = title,
    query = previous_input,
    source = source,
    multi = true,
    -- Directories are not markable: they cannot be opened in bulk.
    markable = function(it)
      return not it.is_dir
    end,
    -- Enter with marks opens every marked file: the first via edit, the rest
    -- as buffers (same semantics as the filesystem float).
    on_open_many = function(items, m)
      running = false
      local files = {}
      for _, it in ipairs(items) do
        if not it.is_dir then
          files[#files + 1] = it
        end
      end
      if #files == 0 then
        return
      end
      local cmd = m == 'enter' and 'edit'
        or m == 'tab' and 'tabedit'
        or m == 'split' and 'split'
        or 'vsplit'
      for i, it in ipairs(files) do
        frecency.record(it.path)
        if cmd == 'edit' and i > 1 then
          vim.cmd('silent badd ' .. vim.fn.fnameescape(it.path))
        else
          vim.cmd('silent ' .. cmd .. ' ' .. vim.fn.fnameescape(it.path))
        end
      end
    end,
    keys = {
      ['<C-r>'] = function(p2)
        -- Toggle the MRU source between files and dirs in place.
        mode = mode == 'dirs' and 'files' or 'dirs'
        previous_input = p2.query
        p2:close()
        vim.schedule(M.run)
      end,
    },
    on_open = function(item, m)
      running = false
      frecency.record(item.path)
      if item.is_dir then
        -- A visited directory: reopen the filesystem picker rooted there.
        vim.schedule(function()
          native.run(item.path)
        end)
      else
        open_path(item.path, m)
      end
    end,
    on_close = function(p2)
      running = false
      if p2 and p2.query then
        previous_input = p2.query
      end
    end,
  })
end

function M.is_running()
  return running
end

return M
