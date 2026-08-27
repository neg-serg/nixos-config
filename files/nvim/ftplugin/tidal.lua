-- tidal.lua: evaluate TidalCycles patterns from .tidal buffers.
-- <C-CR> / <leader>ts: send current line to the Tidal ghci terminal.
-- <leader>tb: send whole buffer. ghci terminal auto-created (visible split).
local GHCI = "/nix/store/dblqzi4fyk94jgsvkw1zhn2khqrgs41k-ghc-9.10.3/lib/ghc-9.10.3/bin/ghc"
local GHCI_LIB = "/nix/store/8la161r2gjh44jcciyfsldzyn99crm27-ghc-9.10.3-with-packages/lib/ghc-9.10.3/lib"
local BOOT = vim.fn.expand("~/.config/tidal/BootTidal.hs")
local function find_ghci_job()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buftype == "terminal" then
      local job = vim.b[buf].terminal_job_id
      if job and vim.api.nvim_chan_is_valid(job) then return job end
    end
  end
  return nil
end
local function ensure_ghci()
  local job = find_ghci_job()
  if job then return job end
  vim.cmd("vsplit")
  vim.cmd("terminal " .. GHCI .. " -B" .. GHCI_LIB .. " --interactive -XOverloadedStrings -ghci-script=" .. BOOT .. " -v0")
  vim.wait(6000, function() return find_ghci_job() ~= nil end, 200)
  return find_ghci_job()
end
local function send_line()
  local spawned = find_ghci_job() == nil
  local job = ensure_ghci()
  if not job then vim.notify("tidal: ghci not found", vim.log.levels.ERROR) return end
  local line = vim.fn.getline(".")
  local deliver = function() vim.api.nvim_chan_send(job, line .. "\n") end
  if spawned then vim.defer_fn(deliver, 9000) else deliver() end
end
local function send_block()
  local spawned = find_ghci_job() == nil
  local job = ensure_ghci()
  if not job then return end
  local text = table.concat(vim.fn.getline(1, "$"), "\n") .. "\n"
  local deliver = function() vim.api.nvim_chan_send(job, text) end
  if spawned then vim.defer_fn(deliver, 9000) else deliver() end
end
vim.keymap.set("n", "<C-CR>", send_line, { buffer = true, desc = "Send line to Tidal ghci" })
vim.keymap.set("n", "<leader>ts", send_line, { buffer = true, desc = "Send line to Tidal ghci" })
vim.keymap.set("n", "<leader>tb", send_block, { buffer = true, desc = "Send whole buffer to Tidal ghci" })
