-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ mikavilpas/yazi.nvim                                                         │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  "mikavilpas/yazi.nvim",
  event = "VeryLazy",
  keys = {
    -- 👇 in this section, choose your own keymappings!
    {
      "<leader>-",
      function()
        require("yazi").yazi()
      end,
      desc = "Open yazi at the current file",
    },
    {
      -- Open in the current working directory
      "<leader>cw",
      function()
        require("yazi").yazi(nil, vim.fn.getcwd())
      end,
      desc = "Open yazi in cwd"
    },
  },
  init = function()
    -- must be early, so nothing перехватит директории
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1
  end,
  opts = {
    open_for_directories = true,
    -- “fullscreen-like” float
    floating_window_scaling_factor = 1.0,
    yazi_floating_window_border = "none",
    keymaps = {
      open_file_in_vertical_split = "<c-v>",
      open_file_in_horizontal_split = "<c-x>",
      open_file_in_tab = "<c-t>",
      grep_in_directory = "<c-f>",
      replace_in_directory = "<c-g>",
      cycle_open_buffers = "<NOP>",
      copy_relative_path_to_selected_files = "<c-y>",
      send_to_quickfix_list = "<c-q>",
      change_working_directory = "<tab>",
    },
  },
}
