-- LuaSnip config and keymaps are in plugins/completion/luasnip.lua
local P = require('luasnip_pre')
if not P.ls then
  return
end
local ls, s, sn, i, t, f, c, fmt = P.ls, P.s, P.sn, P.i, P.t, P.f, P.c, P.fmt

ls.add_snippets("vue", {
  s(
    "defineComponent",
    fmt(
      [[
defineComponent({{
	name: '{name}',
	{props}
	setup({props_arg}{ctx}) {{
		{body}
	}}
}})
    ]],
      {
        name = f(function(args, parent)
          local env = parent.snippet.env
          return env.TM_FILENAME:match "^(.+)%..+$"
        end, {}),
        props = c(1, { sn(nil, { t { "props: {", "" }, i(1), t { "", "}," } }), t "" }),
        props_arg = c(2, { t "props", t "" }),
        ctx = c(3, { t ", ctx", t "" }),
        body = i(0),
      }
    )
  ),
})
