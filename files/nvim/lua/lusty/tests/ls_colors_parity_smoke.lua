-- LS_COLORS parity: `lusty --color-map` must resolve the same rules as
-- lusty/ls_colors.lua for one controlled palette, so the Rust standalone and
-- the Lua float cannot drift. Runs headless:
--   nvim --clean --headless -l files/nvim/lua/lusty/tests/ls_colors_parity_smoke.lua
-- Requires the lusty binary on PATH; skips when it predates the dump flag.

local base = vim.fn.fnamemodify(arg[0], ':h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

local H = require('lusty.tests.harness')

if not H.require_lusty('ls_colors parity smoke') then return end

if not H.has_flag('--color-map') then
  return H.skip('ls_colors parity smoke', 'backend without the dump flag')
end

-- Controlled palette: types, an exec rule, a simple extension, a multi-dot
-- extension and a 256-colour rule.
local palette = 'di=01;34:ln=01;36:ex=01;32:*.md=00;33:*.tar.gz=01;35:*.rs=38;5;208:*.log=00;90'
vim.env.LS_COLORS = palette

local probes = {
  'd:src',
  'l:link',
  'f:run.sh:exec',
  'f:note.md',
  'f:archive.tar.gz',
  'f:main.rs',
  'f:server.log',
  'f:plain.txt',
}

local rust = {}
local cmd = { 'lusty', '--color-map' }
for _, spec in ipairs(probes) do
  cmd[#cmd + 1] = spec
end
for _, line in ipairs(vim.fn.systemlist(cmd)) do
  local spec, code = line:match('^([^\t]*)\t(.*)$')
  assert(spec, 'bad --color-map line: ' .. vim.inspect(line))
  rust[spec] = code
end

local lsc = require('lusty.ls_colors')
lsc.reset() -- re-read LS_COLORS after vim.env was set

local function lua_code(spec)
  local kind, name, flag = spec:match('^([^:]+):([^:]*)(.*)$')
  local entry = { name = name }
  if kind == 'd' then
    entry.is_dir = true
  elseif kind == 'l' then
    entry.is_link = true
  elseif kind == 's' then
    entry.is_socket = true
  elseif kind == 'p' then
    entry.is_pipe = true
  elseif kind == 'b' then
    entry.is_block = true
  elseif kind == 'c' then
    entry.is_char = true
  end
  if flag == ':exec' then
    entry.is_exec = true
  end
  return lsc.code_for(entry) or ''
end

for _, spec in ipairs(probes) do
  local want = lua_code(spec)
  assert(
    rust[spec] == want,
    spec .. ': rust=' .. vim.inspect(rust[spec]) .. ' lua=' .. vim.inspect(want)
  )
end

vim.env.LS_COLORS = nil
H.finish('PASS ls_colors parity smoke')
