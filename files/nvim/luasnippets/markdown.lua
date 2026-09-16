local P = require('luasnip_pre')
local ls, s, i, t, c, fmt = P.ls, P.s, P.i, P.t, P.c, P.fmt
-- local rep = P.rep

ls.add_snippets("markdown", {
  s("t", fmt("- [{}] {}", { c(2, { t " ", t "-", t "x" }), i(1, "task") })),
})

