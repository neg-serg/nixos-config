-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ folke/snacks.nvim                                                            │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    bigfile = { enabled = true },
    dashboard = {
        enabled = true,
        preset = {
            header = [[
                .d$$$$*$$$$$$bc
             .d$P"    d$$    "*$$.
           d$"      4$"$$      "$$.
         4$P        $F ^$F       "$c
        z$%        d$   3$        ^$L
       4$$$$$$$$$$$$$$$$$$$$$$$$$$$$$F
       $$$F"""""""$F""""""$F"""""C$$*$
      .$%"$$e    d$       3$   z$$"  $F
      4$    *$$.4$"        $$d$P"    $$
      4$      ^*$$.       .d$F       $$
      4$       d$"$$c   z$$"3$       $F
       $L     4$"  ^*$$$P"   $$     4$"
       3$     $F   .d$P$$e   ^$F    $P
        $$   d$  .$$"    "$$c 3$   d$
         *$.4$"z$$"        ^*$$$$ $$
          "$$$$P"             "$$$P
            *$b.             .d$P"
              "$$$ec.....ze$$$"
                  "**$$$**""
            ]]
        }
    },
    indent = { enabled = false },
    input = { enabled = true },
    notifier = { enabled = true },
    quickfile = { enabled = true },
    scroll = { enabled = false },
    statuscolumn = { enabled = true },
    words = { enabled = true },
  },
  keys = {
    { "<leader>ss", function() Snacks.scratch() end, desc = "Toggle Scratch Buffer" },
    { "<leader>S",  function() Snacks.scratch.select() end, desc = "Select Scratch Buffer" },
    { "<leader>n",  function() Snacks.notifier.show_history() end, desc = "Notification History" },
    { "<leader>bd", function() Snacks.bufdelete() end, desc = "Delete Buffer" },
    { "<leader>cR", function() Snacks.rename.rename_file() end, desc = "Rename File" },
    { "<leader>gB", function() Snacks.gitbrowse() end, desc = "Git Browse" },
    { "<leader>gb", function() Snacks.git.blame_line() end, desc = "Git Blame Line" },
    { "<leader>gf", function() Snacks.lazygit.log_file() end, desc = "Lazygit Current File History" },
    { "<leader>gg", function() Snacks.lazygit() end, desc = "Lazygit" },
    { "<leader>gl", function() Snacks.lazygit.log() end, desc = "Lazygit Log (cwd)" },
    { "<leader>un", function() Snacks.notifier.hide() end, desc = "Dismiss All Notifications" },
    { "<c-/>",      function() Snacks.terminal() end, desc = "Toggle Terminal" },
    { "<c-_>",      function() Snacks.terminal() end, desc = "which_key_ignore" },
    { "]]",         function() Snacks.words.jump(1, true) end, desc = "Next Reference", mode = { "n", "t" } },
    { "[[",         function() Snacks.words.jump(-1, true) end, desc = "Prev Reference", mode = { "n", "t" } },
  },
  init = function()
    vim.api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      callback = function()
        -- Setup some globals for debugging (lazy-loaded)
        _G.dd = function(...)
          Snacks.debug.inspect(...)
        end
        _G.bt = function()
          Snacks.debug.backtrace()
        end
        vim.print = _G.dd -- Override print to use snacks for better output
      end,
    })
  end,
}
