-- Frecency journal for the native pickers (frequency + recency).
--
-- Each file opened from a Lusty picker is recorded with an open count and
-- a last-open timestamp. The score decays with age so recently opened files
-- beat old bulk history:
--   score = count * 0.5 ^ (days_since_last_open / 2)
-- i.e. every two days of inactivity halves the weight of the count.
--
-- Persisted as JSON in stdpath('state') .. '/lusty/frecency.json'.

local M = {}

local state_file = nil
local journal = nil -- path -> { c = count, l = last-ts }
local dirty = false

-- Test seam: override the wall clock.
local now_fn = os.time
function M.set_now(fn)
  now_fn = fn
end

-- Test seam: override where the journal is stored.
function M.set_state_file(p)
  state_file = p
  journal = nil
end

local function ensure_path()
  if state_file then
    return state_file
  end
  state_file = vim.fn.stdpath('state') .. '/lusty/frecency.json'
  return state_file
end

local function load()
  if journal then
    return journal
  end
  journal = {}
  local ok, data = pcall(vim.fn.readfile, ensure_path())
  if ok and data and #data > 0 then
    local okd, decoded = pcall(vim.fn.json_decode, table.concat(data, '\n'))
    if okd and type(decoded) == 'table' then
      journal = decoded
    end
  end
  return journal
end

local function save()
  local ok = pcall(vim.fn.mkdir, vim.fn.fnamemodify(ensure_path(), ':h'), 'p')
  if not ok then
    return
  end
  local okd, encoded = pcall(vim.fn.json_encode, journal)
  if okd and encoded then
    pcall(vim.fn.writefile, { encoded }, ensure_path())
  end
  dirty = false
end

--- Record an open of `path` (called from the picker on_open).
function M.record(path)
  local j = load()
  local e = j[path] or { c = 0, l = 0 }
  e.c = e.c + 1
  e.l = now_fn()
  j[path] = e
  dirty = true
  save()
end

--- Journal paths (the keys), for merging into MRU/recent sources.
function M.paths()
  local out = {}
  for p in pairs(load()) do
    out[#out + 1] = p
  end
  return out
end

--- Frecency score for a path, or nil when never opened via a picker.
function M.score(path)
  local e = load()[path]
  if not e then
    return nil
  end
  local days = (now_fn() - e.l) / 86400
  if days < 0 then
    days = 0
  end
  return e.c * (0.5 ^ (days / 2))
end

function M.scores(paths)
  local out = {}
  for _, p in ipairs(paths) do
    out[p] = M.score(p)
  end
  return out
end

function M.__reset()
  journal = nil
  dirty = false
end

return M
