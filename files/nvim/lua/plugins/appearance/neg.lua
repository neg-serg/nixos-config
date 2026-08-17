-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ neg-serg/neg.nvim                                                            │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'neg-serg/neg.nvim', -- my pure-dark neovim colorscheme
    lazy = false,
    priority = 1000,
    config = function()
        vim.cmd.colorscheme("neg")

        -- Автокомплит (blink.cmp линкует меню на Pmenu/PmenuSel): контраст
        -- «туман / подсветка» в палитре neg — приглушённый голубовато-серый
        -- список на тёмно-сером фоне (#15181f / #6c7e96) и «зажжённая»
        -- синяя строка выбора (#005faf) со светло-бело-голубым жирным
        -- текстом (#d1e5ff). blink рисует выделение только фоном, поэтому
        -- светлый текст выбора дают fuzzy-совпадения (BlinkCmpLabelMatch)
        -- и иконка kind поверх синей плашки.
        require('neg').setup({
            overrides = function(p)
                return {
                    -- туман: тёмный нейтральный фон, голубовато-серый текст
                    Pmenu      = { bg = p.dnorm, fg = p.pmen },
                    PmenuSbar  = { bg = p.dnorm, fg = 'NONE' },
                    PmenuThumb = { bg = p.ops3, fg = 'NONE' },
                    PmenuExtra = { fg = p.comm },
                    -- подсветка: синяя плашка; fg/bold на случай рендера
                    -- текста через PmenuSel (nvim-cmp и т.п.)
                    PmenuSel      = { bg = p.ops3, fg = p.whit, bold = true },
                    PmenuMatch    = { fg = p.high, underline = true },
                    PmenuMatchSel = { fg = p.whit, bold = true },
                    -- blink: серые метки, светло-голубые жирные совпадения
                    -- и иконки kind, тусклые подписи
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
