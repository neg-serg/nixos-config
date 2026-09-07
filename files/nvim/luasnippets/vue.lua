-- LuaSnip config and keymaps are in plugins/completion/luasnip.lua
local success, ls = pcall(require, "luasnip")
if not success then
  return
end
local s = ls.snippet
local sn = ls.snippet_node
local i = ls.insert_node
local t = ls.text_node
local f = ls.function_node
local c = ls.choice_node
local fmt = require("luasnip.extras.fmt").fmt

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
