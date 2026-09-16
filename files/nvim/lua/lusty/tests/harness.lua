-- Shared scaffolding for the lusty headless smoke suites.
--
-- The suites run as `nvim --clean --headless -l <suite>.lua` from the repo
-- root (scripts/dev/check-lusty-smoke.sh). Every suite keeps its two-line
-- package.path preamble so `require('lusty.tests.harness')` resolves; the
-- boilerplate that used to be copied into each suite lives here.

local M = {}

--- Print the final PASS line and quit headless nvim.
function M.finish(message)
  print(message)
  vim.cmd('qa!')
end

--- Skip when the deployed `lusty` binary is not on PATH. Callers must
--- `return` when this returns false.
function M.require_lusty(name)
  if vim.fn.executable('lusty') ~= 1 then
    print('SKIP ' .. name .. ': lusty not on PATH')
    vim.cmd('qa!')
    return false
  end
  return true
end

--- Skip with a suite-specific reason (older backend, missing capability).
function M.skip(name, reason)
  print('SKIP ' .. name .. ': ' .. reason)
  vim.cmd('qa!')
  return false
end

--- Does `lusty --help` advertise a dump flag? Older binaries lack them.
function M.has_flag(flag)
  local help = table.concat(vim.fn.systemlist({ 'lusty', '--help' }), '\n')
  return help:find(flag, 1, true) ~= nil
end

--- Deterministic equality assertion (same message the suites used before).
function M.assert_eq(got, want, msg)
  if got ~= want then
    error((msg or 'assert') .. ': got ' .. tostring(got) .. ' want ' .. tostring(want))
  end
end

--- Wait until cond() is true, or fail after `ms` (default 5s).
function M.wait_until(cond, what, ms)
  ms = ms or 5000
  local t0 = vim.loop.hrtime()
  while not cond() do
    if (vim.loop.hrtime() - t0) / 1e6 > ms then
      error('timeout waiting for ' .. what)
    end
    vim.wait(10)
  end
end

--- Point the frecency journal at a suite-local file and clear it, so a stale
--- real journal cannot reorder the listing. Returns the frecency module for
--- suites that also pin the clock.
function M.isolate_frecency(path)
  local frec = require('lusty.frecency')
  frec.set_state_file(path)
  pcall(vim.fn.delete, path)
  return frec
end

return M
