-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ folke/snacks.nvim                                                            │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  "folke/snacks.nvim",
  priority = 1000,
  event = "VeryLazy",
  opts = function()
    local has_args = vim.fn.argc(-1) > 0

    return {
      bigfile = { enabled = true },
      dashboard = {
          enabled = not has_args,
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
          },
          sections = {
              { section = "header" },
              { section = "recent_files", limit = 8, padding = 1 },
              { section = "startup" },
          },
      },
      indent = {
        enabled = true,
        chunk = {
          enabled = true,
          char = '│',
          priority = 50,
          filter = function(buf)
            local ft = vim.bo[buf].filetype
            return ft ~= 'help' and ft ~= 'markdown' and ft ~= 'norg' and ft ~= 'org'
          end,
        },
        -- rainbow scope highlighting replaces rainbow-delimiters
        scope = {
          enabled = true,
          priority = 200,
          animate = { enabled = false },
          char = '│',
        },
      },
      input = { enabled = true },
      notifier = { enabled = true },
      quickfile = { enabled = has_args },
      scroll = { enabled = false },
      terminal = { enabled = true },
      statuscolumn = { enabled = true },
      zen = { enabled = true, zoom = { enabled = true } },
      words = { enabled = true },
    }
  end,
  keys = {
    { "<leader>ss", function() Snacks.scratch() end, desc = "Toggle Scratch Buffer" },
    { "<leader>S",  function() Snacks.scratch.select() end, desc = "Select Scratch Buffer" },
    { "<leader>n",  function() Snacks.notifier.show_history() end, desc = "Notification History" },
    { "<leader>bd", function() Snacks.bufdelete() end, desc = "Delete Buffer" },
    { "<leader>cR", function() Snacks.rename.rename_file() end, desc = "Rename File" },
    { "<leader>go", function() Snacks.gitbrowse() end, desc = "Git Browse (open)" },
    { "<leader>gb", function() Snacks.git.blame_line() end, desc = "Git Blame Line" },
    { "<leader>gf", function() Snacks.lazygit.log_file() end, desc = "Lazygit Current File History" },
    { "<leader>gg", function() Snacks.lazygit() end, desc = "Lazygit" },
    { "<leader>gl", function() Snacks.lazygit.log() end, desc = "Lazygit Log (cwd)" },
    { "<leader>un", function() Snacks.notifier.hide() end, desc = "Dismiss All Notifications" },
    { "ei", function() Snacks.terminal.toggle() end, desc = "Toggle terminal" },
    { "]]",         function() Snacks.words.jump(1, true) end, desc = "Next Reference", mode = { "n", "t" } },
    { "[[",         function() Snacks.words.jump(-1, true) end, desc = "Prev Reference", mode = { "n", "t" } },
  },
  init = function()
    vim.api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      callback = function()
        require("utils.frecency").setup()
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
