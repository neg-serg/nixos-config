local M = {}
local uv = vim.uv

local HALF_LIFE = 30 * 24 * 3600 -- 30 days in seconds
local LAMBDA = math.log(2) / HALF_LIFE
local store_path = vim.fn.stdpath("data") .. "/neg-frecency.json"

M._data = nil

function M._load()
  if M._data then return M._data end
  local fd = io.open(store_path, "r")
  if fd then
    local raw = fd:read("*a")
    fd:close()
    local ok, decoded = pcall(vim.json.decode, raw)
    M._data = ok and type(decoded) == "table" and decoded or {}
  else
    M._data = {}
  end
  return M._data
end

function M._save()
  if not M._data then return end
  local fd = io.open(store_path, "w")
  if fd then
    fd:write(vim.json.encode(M._data))
    fd:close()
  end
end

function M._score(deadline)
  return math.exp(LAMBDA * (deadline - os.time()))
end

function M._deadline(score)
  return os.time() + (math.log(score) / LAMBDA)
end

function M.visit(path)
  local data = M._load()
  local old_score = 0
  if data[path] then
    old_score = M._score(data[path])
  end
  data[path] = M._deadline(old_score + 1)
end

function M.get_ranked()
  local data = M._load()
  local entries = {}
  for path, deadline in pairs(data) do
    local score = M._score(deadline)
    if score > 0.001 then
      table.insert(entries, { path = path, score = score })
    end
  end
  table.sort(entries, function(a, b) return a.score > b.score end)
  -- Fallback to oldfiles when store is empty
  if #entries == 0 then
    for _, f in ipairs(vim.v.oldfiles) do
      if uv.fs_stat(f) then
        table.insert(entries, { path = f, score = 0 })
      end
      if #entries >= 50 then break end
    end
  end
  return entries
end

function M.setup()
  local group = vim.api.nvim_create_augroup("neg_frecency", { clear = true })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(ev)
      if vim.api.nvim_win_get_config(0).relative ~= "" then return end
      local buf = ev.buf
      if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then return end
      local file = vim.api.nvim_buf_get_name(buf)
      if file == "" or not uv.fs_stat(file) then return end
      M.visit(file)
    end,
  })
  vim.api.nvim_create_autocmd("ExitPre", {
    group = group,
    callback = function() M._save() end,
  })
end

return M
