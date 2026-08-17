-- Smart TidalCycles actions for keymaps.
--
-- The plain tidal.nvim commands are silent when they cannot work (GHCi
-- without SuperDirt connects to nothing; sending without a session is
-- ignored). These wrappers check the real state and tell the user what to do
-- instead of quietly doing nothing useful.

local M = {}

local state = require('tidal.core.state')

--- Is SuperDirt listening on UDP 57120? (fast /proc scan via ss)
function M.engine_up()
  vim.fn.system('ss -uln 2>/dev/null | grep -q ":57120"')
  return vim.v.shell_error == 0
end

--- Launch Tidal only if the engine is up; otherwise point to `tidalctl start`.
function M.launch()
  if not M.engine_up() then
    vim.notify(
      'SuperDirt не запущен — сначала `tidalctl start`',
      vim.log.levels.WARN,
      { title = 'TidalCycles' }
    )
    return
  end
  vim.cmd 'TidalLaunch'
end

--- Send the current line; warn if the Tidal session is not running.
function M.send()
  if not state.ghci then
    vim.notify(
      'Tidal не запущен — <leader>tl или Ctrl+Enter',
      vim.log.levels.WARN,
      { title = 'TidalCycles' }
    )
    return
  end
  require('tidal').api.send_line()
end

--- Send each non-empty selected line as its own command.
function M.send_lines()
  local api = require('tidal').api
  local first = vim.fn.line "'<"
  local last = vim.fn.line "'>"
  for l = first, last do
    local text = vim.fn.getline(l):gsub('^%s+', ''):gsub('%s+$', '')
    if text ~= '' then
      api.send(text)
    end
  end
end

--- Hush everything; warn if no session.
function M.hush()
  if not state.ghci then
    vim.notify('Tidal не запущен — нечего глушить', vim.log.levels.WARN, { title = 'TidalCycles' })
    return
  end
  require('tidal.core.message').tidal.send_line('hush')
end

return M
