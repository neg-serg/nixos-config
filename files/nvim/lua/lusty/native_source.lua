-- Shared runner for the Lua-source list pickers (`lusty.native_buffers`,
-- `lusty.native_recent`, `lusty.native_buffer_grep`): one picker per module at
-- a time, the last query remembered between runs, the first-letter filter and
-- fuzzy ranking built from a snapshot function, and the running flag
-- maintained around the picker callbacks.
--
-- It sits next to `native_pick` instead of in `native_core`: the core is the
-- stateless float/method bag and stays below `native_pick` in the require
-- graph (native_pick requires native_core), while this runner closes the loop
-- by calling `native_pick.pick`.

local pick = require('lusty.native_pick')
local filter = require('lusty.filter')

local M = {}

--- Build a source-picker module table with `run` and `is_running`.
---
--- spec fields:
---   title         string, or function() -> string (recent: files/dirs mode)
---   snapshot      function() -> items, re-read for every query and after an
---                 on_delete (so a deleted buffer disappears immediately)
---   filter_key, filter_tie  filter fields: the first query letter must
---                 prefix item[filter_key]; ties are broken by filter_tie
---   source        optional function(items) -> function(query); replaces the
---                 filter source (the buffer grep builds its own)
---   multi, single_column, markable, keys, on_open, on_open_many, on_delete
---                 passed through to native_pick; `keys` may be a function of
---                 the session state
---
--- Callback order matches what the pickers used to inline: the running flag
--- drops before the caller's open callback runs (a scheduled follow-up run is
--- not swallowed) and on close, and the picker query is remembered on close.
--- `state.query` may be set by raw keymaps that want the next run to start
--- from a different query (the recent picker's files/dirs toggle).
function M.define(spec)
  local state = { running = false, query = '' }
  local items = {}

  local function run()
    if state.running then
      return
    end
    state.running = true
    items = spec.snapshot()
    local opts = {
      title = type(spec.title) == 'function' and spec.title() or spec.title,
      query = state.query,
      multi = spec.multi,
      single_column = spec.single_column,
      markable = spec.markable,
      keys = type(spec.keys) == 'function' and spec.keys(state) or spec.keys,
      source = spec.source and spec.source(items)
        or filter.source(function()
          return items
        end, spec.filter_key, spec.filter_tie),
      on_open = spec.on_open,
      on_open_many = spec.on_open_many,
      on_delete = spec.on_delete,
    }
    local open = opts.on_open
    if open then
      opts.on_open = function(item, mode)
        state.running = false
        open(item, mode)
      end
    end
    local open_many = opts.on_open_many
    if open_many then
      opts.on_open_many = function(list, mode)
        state.running = false
        open_many(list, mode)
      end
    end
    local delete = opts.on_delete
    if delete then
      opts.on_delete = function(item)
        delete(item)
        -- refresh the snapshot the source closure reads, so the picker's
        -- follow-up refresh shows the mutated list
        items = spec.snapshot()
      end
    end
    opts.on_close = function(picker)
      state.running = false
      if picker and picker.query then
        state.query = picker.query
      end
    end
    pick.pick(opts)
  end

  state.run = run
  return {
    run = run,
    is_running = function()
      return state.running
    end,
  }
end

return M
