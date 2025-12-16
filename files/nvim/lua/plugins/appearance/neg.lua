-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ neg-serg/neg.nvim                                                            │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'neg-serg/neg.nvim', -- my pure-dark neovim colorscheme
    lazy = false,
    priority = 1000,
    config = function()
        vim.cmd.colorscheme("neg")
    end
}
