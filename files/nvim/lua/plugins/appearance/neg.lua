-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ neg-serg/neg.nvim                                                            │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'neg-serg/neg.nvim', -- my pure-dark neovim colorscheme
    lazy = false,
    priority = 1000,
    config = function()
        -- Pmenu (native, blink.cmp, nvim-cmp) is monochrome and owned by
        -- the theme itself since 4.72: pure-black ground, neutral grey text,
        -- grey selection bar and white underlined matches. No Pmenu
        -- overrides here — keep the theme the single source of truth.
        vim.cmd.colorscheme("neg")
    end
}
