-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ dmtrKovalenko/fff — fastest file search for Neovim                          │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  "dmtrKovalenko/fff",
  cmd = { "Fff", "FffGrep" },
  keys = {
    { "<leader>ff", function() require("fff").find_files() end, desc = "Find files (fff)" },
    { "<leader>fg", function() require("fff").live_grep() end, desc = "Live grep (fff)" },
    { "<leader>fG", function() require("fff").live_grep_under_cursor() end, desc = "Grep word (fff)" },
  },
  opts = {
    prompt = "🪿 ",
    max_results = 120,
    layout = {
      width = 0.85,
      height = 0.85,
      preview_position = "right",
      preview_size = 0.55,
    },
    preview = {
      line_numbers = true,
      wrap_lines = false,
    },
    keymaps = {
      select_split = "<C-s>",
      select_vsplit = "<C-v>",
      select_tab = "<C-t>",
    },
  },
}
