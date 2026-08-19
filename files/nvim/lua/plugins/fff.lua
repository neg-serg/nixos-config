-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ dmtrKovalenko/fff — fastest file search for Neovim (Rust core)               │
-- │   Primary picker: frecency-ranked file finder + live grep.                         │
-- │   Pickers fff has no source for (buffers/commands/git/help/qf) live in snacks.    │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  "dmtrKovalenko/fff",
  cmd = { "Fff", "FffGrep" },
  keys = {
    -- find files (frecency-ranked)
    { "<leader>e",  function() require("fff").find_files() end, desc = "Find files (fff)" },
    { "<leader>ff", function() require("fff").find_files() end, desc = "Find files (fff)" },
    { "ee",         function() require("fff").find_files() end, desc = "Smart find files (fff frecency)" },
    { "<leader>.",  function() require("fff").find_files() end, desc = "Frecent files (fff frecency)" },
    -- scoped finds
    { "gz",         function() require("fff").find_files({ cwd = vim.fn.expand("%:p:h") }) end, desc = "Find in dir" },
    { "E",          function() require("fff").find_files({ cwd = require("utils.fzf").project_root() }) end, desc = "Project root find" },
    { "<leader>l",  function() require("fff").find_files({ cwd = vim.fn.expand("%:p:h") }) end, desc = "Files in current dir" },
    { "<leader>L",  function() require("fff").find_files({ cwd = require("utils.fzf").project_root() }) end, desc = "Files in project root" },
    -- grep
    { "<leader>fg", function() require("fff").live_grep() end, desc = "Live grep (fff)" },
    { "<leader>fG", function() require("fff").live_grep_under_cursor() end, desc = "Grep word (fff)" },
    { "<leader>sg", function() require("fff").live_grep_under_cursor() end, desc = "Grep word under cursor" },
    -- misc
    { "<leader>sr", function() require("fff").find_files({ resume = true }) end, desc = "Resume last fff picker" },
  },
  opts = {
    prompt = "❯ ",
    max_results = 120,
    layout = {
      width = 0.9,
      height = 0.6,
      prompt_position = "top",
      preview_position = "right",
      preview_size = 0.5,
      show_scrollbar = true,
      border = "rounded",
      path_shorten_strategy = "middle",
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
