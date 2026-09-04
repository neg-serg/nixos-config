-- Native recent-file explorer: LustyRecent rendered in the native bottom
-- float. Items come from nvim's oldfiles (v:oldfiles, most recent first),
-- restricted to files that still exist, deduped, capped at 150. Labels are
-- relative to the cwd when possible so the same basename from different
-- directories stays distinguishable.

local pick = require('lusty.native_pick')
local fuzzy = require('lusty.fuzzy')
local mercury = require('lusty.mercury')
local util = require('lusty.util')
local lsc = require('lusty.ls_colors')

local M = {}

-- Test seam / future source override; default reads v:oldfiles.
local recent_fn = nil
function M.set_recent_fn(fn)
  recent_fn = fn
end

local function recent_paths()
  if recent_fn then
    return recent_fn()
  end
  return vim.v.oldfiles or {}
end

local function open_path(path, mode)
  local cmd = mode == 'enter' and 'edit ' or mode == 'tab' and 'tabedit ' or mode == 'split' and 'split ' or 'vsplit '
  vim.cmd('silent ' .. cmd .. vim.fn.fnameescape(path))
end

local function snapshot_items()
  local seen = {}
  local out = {}
  for i, p in ipairs(recent_paths()) do
    if not seen[p] and vim.fn.filereadable(p) == 1 then
      seen[p] = true
      local label = vim.fn.fnamemodify(p, ':.')
      local item = {
        path = p,
        order = i,
        label = label,
      }
      local group = lsc.group_for({ name = p, is_dir = false })
      if group then
        item.group = group
      end
      out[#out + 1] = item
      if #out >= 150 then
        break
      end
    end
  end
  return out
end

-- Filtering mirrors the other explorers: first query letter must prefix the
-- basename; then fuzzy/mercury score on the label, ties by recency.
local function make_source(snap)
  return function(query)
    if query == '' then
      return snap
    end
    local use_mercury = tostring(vim.g.LustyExplorerFuzzyEngine or '') == 'mercury'
    local first = query:sub(1, 1):lower()
    local scored = {}
    for _, it in ipairs(snap) do
      local base_first = (util.basename(it.label) or ''):sub(1, 1):lower()
      if base_first == first then
        local score = use_mercury and mercury.score(it.label, query) or fuzzy.score(it.label, query)
        if score and score ~= 0.0 then
          scored[#scored + 1] = { it = it, score = score }
        end
      end
    end
    table.sort(scored, function(a, b)
      if a.score == b.score then
        return a.it.order < b.it.order
      end
      return a.score > b.score
    end)
    local res = {}
    for _, s in ipairs(scored) do
      res[#res + 1] = s.it
    end
    return res
  end
end

local running = false

function M.run()
  if running then
    return
  end
  running = true
  local snap = snapshot_items()
  pick.pick({
    title = 'Recent Files',
    source = make_source(snap),
    on_open = function(item, mode)
      running = false
      open_path(item.path, mode)
    end,
    on_close = function()
      running = false
    end,
  })
end

function M.is_running()
  return running
end

return M
