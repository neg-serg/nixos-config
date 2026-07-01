local ls = require "luasnip"
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local d = ls.dynamic_node
local r = ls.restore_node
local extras = require "luasnip.extras"
local rep = extras.rep
local fmt = require("luasnip.extras.fmt").fmt

return {
  c = {
    s("INCLUDE", {
      d(1, function(args, snip)
        local headers_to_load_into_choice_node = {}

        local extension = vim.fn.expand "%:e"
        local is_main = vim.fn.expand("%"):match "main%.cp?p?" ~= nil
        if (extension == "c" or extension == "cpp") and not is_main then
          local matching_h_file = vim.fn.expand("%:t"):gsub("%.c", ".h")
          local companion_header_file = string.format('#include "%s"', matching_h_file)
          table.insert(headers_to_load_into_choice_node, t(companion_header_file))
        end

        local current_file_directory = vim.fn.expand "%:h"
        local local_header_files = require("plenary.scandir").scan_dir(
          current_file_directory,
          { respect_gitignore = true, search_pattern = ".*%.h$" }
        )

        for _, local_header_name in ipairs(local_header_files) do
          local shortened_header_path = local_header_name:gsub(current_file_directory, "")
          shortened_header_path = shortened_header_path:gsub([[\+]], "/")
          shortened_header_path = shortened_header_path:gsub("^/", "")
          local new_header = t(string.format('#include "%s"', shortened_header_path))
          table.insert(headers_to_load_into_choice_node, new_header)
        end

        local custom_insert_nodes = {
          sn(
            nil,
            fmt(
              [[
                         #include "{}"
                         ]],
              {
                i(1, "custom_insert.h"),
              }
            )
          ),
          sn(
            nil,
            fmt(
              [[
                         #include <{}>
                         ]],
              {
                i(1, "custom_system_insert.h"),
              }
            )
          ),
        }
        for _, custom_insert_node in ipairs(custom_insert_nodes) do
          table.insert(headers_to_load_into_choice_node, custom_insert_node)
        end

        local system_headers = {
          t "#include <assert.h>",
          t "#include <complex.h>",
          t "#include <ctype.h>",
          t "#include <errno.h>",
          t "#include <fenv.h>",
          t "#include <float.h>",
          t "#include <inttypes.h>",
          t "#include <iso646.h>",
          t "#include <limits.h>",
          t "#include <locale.h>",
          t "#include <math.h>",
          t "#include <setjmp.h>",
          t "#include <signal.h>",
          t "#include <stdalign.h>",
          t "#include <stdarg.h>",
          t "#include <stdatomic.h>",
          t "#include <stdbit.h>",
          t "#include <stdbool.h>",
          t "#include <stdckdint.h>",
          t "#include <stddef.h>",
          t "#include <stdint.h>",
          t "#include <stdio.h>",
          t "#include <stdlib.h>",
          t "#include <stdnoreturn.h>",
          t "#include <string.h>",
          t "#include <tgmath.h>",
          t "#include <threads.h>",
          t "#include <time.h>",
          t "#include <uchar.h>",
          t "#include <wchar.h>",
          t "#include <wctype.h>",
        }
        for _, header_snippet in ipairs(system_headers) do
          table.insert(headers_to_load_into_choice_node, header_snippet)
        end

        return sn(1, c(1, headers_to_load_into_choice_node))
      end, {}),
    }),

    s("class", {
      c(1, {
        t "public ",
        t "private ",
      }),
      t "class ",
      i(2),
      t " ",
      c(3, {
        t "{",
        sn(nil, {
          t "extends ",
          i(1),
          t " {",
        }),
        sn(nil, {
          t "implements ",
          i(1),
          t " {",
        }),
      }),
      t { "", "\t" },
      i(0),
      t { "", "}" },
    }),

    s("#if", {
      t "#if ",
      i(1, "1"),
      t { "", "" },
      i(0),
      t { "", "#endif // " },
      f(function(args)
        return args[1]
      end, 1),
    }),
  },
}
