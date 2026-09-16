-- Shared picker filter used by the native explorers: the first query letter
-- must prefix the basename of `item[key]`, then entries are scored (mercury or
-- the fuzzy engine) on that same field, zero scores are dropped, and results
-- are sorted by descending score with ties broken by `item[tie]` ascending.

local fuzzy = require('lusty.fuzzy')
local mercury = require('lusty.mercury')
local util = require('lusty.util')

local M = {}

-- get_items() is re-read on every query so a picker can rebuild its list
-- (e.g. the buffer explorer) without recreating the source.
function M.source(get_items, key, tie)
  return function(query)
    local items = get_items()
    if query == '' then
      return items
    end
    local use_mercury = tostring(vim.g.LustyExplorerFuzzyEngine or '') == 'mercury'
    local first = query:sub(1, 1):lower()
    local scored = {}
    for _, it in ipairs(items) do
      local base_first = (util.basename(it[key]) or ''):sub(1, 1):lower()
      if base_first == first then
        local score = use_mercury and mercury.score(it[key], query) or fuzzy.score(it[key], query)
        if score and score ~= 0.0 then
          scored[#scored + 1] = { it = it, score = score }
        end
      end
    end
    table.sort(scored, function(a, b)
      if a.score == b.score then
        return a.it[tie] < b.it[tie]
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

return M
