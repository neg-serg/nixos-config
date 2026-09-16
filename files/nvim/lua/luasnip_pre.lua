-- Shared preamble for the LuaSnip collections in `luasnippets/`. LuaSnip's
-- from_lua loader executes every .lua file inside that directory, so this
-- helper has to live under `lua/` (outside the scanned tree) to stay a plain
-- module.
--
-- Collections are loaded lazily, so LuaSnip may not be available yet: in that
-- case only `ls` stays nil and a caller that wants the old resilient behaviour
-- returns early. Fields mirror the usual constructor short names.

local M = { ls = nil }

local ok, ls = pcall(require, 'luasnip')
if ok then
  local extras = require('luasnip.extras')
  local fmt = require('luasnip.extras.fmt')
  M.ls = ls
  M.s = ls.snippet
  M.sn = ls.snippet_node
  M.t = ls.text_node
  M.i = ls.insert_node
  M.f = ls.function_node
  M.c = ls.choice_node
  M.d = ls.dynamic_node
  M.r = ls.restore_node
  M.isn = ls.indent_snippet_node
  M.rep = extras.rep
  M.fmt = fmt.fmt
  M.fmta = fmt.fmta
end

return M
