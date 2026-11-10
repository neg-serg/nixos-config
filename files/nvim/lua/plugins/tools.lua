-- Tool plugins: log-highlight, neopyter
return {
  -- │ █▓▒░ fei6409/log-highlight.nvim                                               │
  {
    "fei6409/log-highlight.nvim",
    event = "BufRead *.log",
    opts = {},
  },

  -- │ █▓▒░ SUSTech-data/neopyter                                                   │
  {
    "SUSTech-data/neopyter",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "AbaoFromCUG/websocket.nvim",
    },
    ft = { "python", "markdown" },
    -- neopyter's async layer calls the private `vim._async` module shipped in
    -- Neovim 0.12. 0.13 replaced it with the public `vim.async` (different
    -- scheduling) and deleted the old module, so the plugin fails to load on
    -- the nightly (SUSTech-data/neopyter#62). Map the two calls it makes onto
    -- the public API until upstream supports 0.13; inert on 0.12.
    init = function()
      if not vim.async or pcall(require, "vim._async") then
        return
      end

      package.preload["vim._async"] = function()
        local async = vim.async
        return {
          -- `vim._async.run(fn, on_finish)`: completion moved to the task.
          run = function(func, on_finish)
            local task = async.run(func)
            if on_finish then
              task:on_complete(on_finish)
            end
          end,
          -- Same `(argc, func, ...)` call shape and unchanged callback results.
          await = async.await,
        }
      end
    end,
    opts = {
      mode = "direct",
      remote_address = "127.0.0.1:9001",
      file_pattern = { "*.ju.*", "*.ipynb" },
      on_attach = function(bufnr)
        local function map(mode, lhs, rhs, desc)
          vim.keymap.set(mode, lhs, rhs, { desc = desc, buffer = bufnr })
        end
        map("n", "<C-Enter>", "<cmd>Neopyter execute notebook:run-cell<cr>", "Run cell")
        map("n", "<S-Enter>", "<cmd>Neopyter execute notebook:run-cell-and-select-next<cr>", "Run cell and select next")
        map("n", "<space>X", "<cmd>Neopyter execute notebook:run-all-above<cr>", "Run all above")
      end,
    },
  },
}
