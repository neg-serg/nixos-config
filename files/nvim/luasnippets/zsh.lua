-- Zsh snippets (ft=zsh: .zshrc, .zshenv, zsh scripts).
-- LuaSnip config and keymaps are in plugins/completion/luasnip.lua
local P = require('luasnip_pre')
local ls, s, i, t, rep = P.ls, P.s, P.i, P.t, P.rep

ls.add_snippets("zsh", {
  -- header / location
  s("shebang", { t { "#!/usr/bin/env zsh", "" }, i(0) }),
  s("scd", { t { 'cd "$(dirname "$0")"', "" }, i(0) }),

  -- split a file variable into basename / dir / stem / extension
  -- (zsh-native ${var:t/h/r/e} expansions, no external processes)
  s("parts", {
    t "local ", i(1, "file"), t '="$1"', t { "", "" },
    t "name=${", rep(1), t { ":t}  # basename", "" },
    t "dir=${", rep(1), t { ":h}   # parent dir", "" },
    t "stem=${", rep(1), t { ":r}   # name without extension", "" },
    t "ext=${", rep(1), t { ":e}   # extension (no dot)", "" },
    t { "", "" },
    i(0),
  }),

  -- control flow
  s("ifx", {
    t "if ", i(1, "cond"), t { "; then", "" },
    t "\t", i(0),
    t { "", "fi", "" },
  }),
  s("ifex", {
    t "if ", i(1, "cond"), t { "; then", "" },
    t "\t", i(2),
    t { "", "else", "" },
    t "\t", i(0),
    t { "", "fi", "" },
  }),
  s("forx", {
    t "for ", i(1, "item"), t " in ", i(2, "list"), t { "; do", "" },
    t "\t", i(0),
    t { "", "done", "" },
  }),
  s("args", {
    t { 'for arg in "$@"; do', "" },
    t "\t", i(0),
    t { "", "done", "" },
  }),

  -- guards
  s("has", {
    t { "if (( $+commands[" },
    i(1, "cmd"),
    t { "] )); then", "" },
    t "\t", i(0),
    t { "", "fi", "" },
  }),
  s("pgrp", {
    t { 'if pgrep -x "' },
    i(1, "proc"),
    t { '" > /dev/null; then', "" },
    t "\t", i(0),
    t { "", "fi", "" },
  }),
  s("req", {
    t "command -v ", i(1, "cmd"),
    t { " >/dev/null 2>&1 || {", "" },
    t "\techo \"", rep(1), t { ' is required" >&2; exit 1;', "" },
    t { "}", "" },
    i(0),
  }),

  -- pipes / redirection
  s("2e", t "2>&1 "),
  s("null", t "&> /dev/null "),
  s("sedp", { t "| sed 's/", i(1, "pat"), t "/", i(2, "repl"), t "/g'", i(0) }),

  -- processes
  s("bg", {
    t "nohup ", i(1, "cmd"), t { " >/dev/null 2>&1 &", "" }, i(0),
  }),
  s("killn", { t "pkill -x ", i(1, "proc"), i(0) }),
})
