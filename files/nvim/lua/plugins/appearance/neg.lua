-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ neg-serg/neg.nvim                                                            │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'neg-serg/neg.nvim', -- my pure-dark neovim colorscheme
    lazy = false,
    priority = 1000,
    config = function()
        vim.cmd.colorscheme("neg")

        -- Autocomplete (blink.cmp links its menu to Pmenu/PmenuSel): a
        -- "fog / lit" contrast in the neg palette - a dim bluish-grey list
        -- on a dark neutral panel (#15181f / #6c7e96) and a lit blue
        -- selection bar (#005faf) with light white-blue bold text
        -- (#d1e5ff). blink paints the selection as a background-only bar,
        -- so the light text rides on the fuzzy-match (BlinkCmpLabelMatch)
        -- and kind-icon groups above it.
        require('neg').setup({
            overrides = function(p)
                return {
                    -- fog: dark neutral panel, bluish-grey text
                    Pmenu      = { bg = p.dnorm, fg = p.pmen },
                    PmenuSbar  = { bg = p.dnorm, fg = 'NONE' },
                    PmenuThumb = { bg = p.ops3, fg = 'NONE' },
                    PmenuExtra = { fg = p.comm },
                    -- lit: blue selection bar; fg/bold for consumers that
                    -- render text with PmenuSel (nvim-cmp etc.)
                    PmenuSel      = { bg = p.ops3, fg = p.whit, bold = true },
                    PmenuMatch    = { fg = p.high, underline = true },
                    PmenuMatchSel = { fg = p.whit, bold = true },
                    -- blink: grey labels, light-blue bold fuzzy matches and
                    -- kind icons, dim captions
                    BlinkCmpLabel            = { fg = p.pmen },
                    BlinkCmpLabelMatch       = { fg = p.whit, bold = true },
                    BlinkCmpLabelDetail      = { fg = p.comm },
                    BlinkCmpLabelDescription = { fg = p.comm },
                    BlinkCmpSource           = { fg = p.comm },
                    BlinkCmpKind             = { fg = p.high },
                }
            end,
        })
    end
}
