-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ HiPhish/rainbow-delimiters.nvim                                              │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
    'HiPhish/rainbow-delimiters.nvim', -- rainbow parenthesis
    event = { "BufReadPost", "BufNewFile" },
    -- Skip git submodules (plugin's tests use a submodule like test/bin)
    -- which may fail to fetch in restricted environments.
    submodules = false,
    -- Prefer latest tagged release to reduce breakage on sync
    version = '*',
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    config=function()
        local rainbow_delimiters=require'rainbow-delimiters'
        vim.g.rainbow_delimiters={
            strategy={
                ['']=rainbow_delimiters.strategy['global'],
                vim=rainbow_delimiters.strategy['local'],
            },
            query={
                ['']='rainbow-delimiters',
                -- Fallback to default query if rainbow-blocks is not available
                lua = (function()
                    local ok, q = pcall(function()
                        -- Use the available treesitter API to test for query
                        local has
                        if vim.treesitter.query and vim.treesitter.query.get then
                            has = pcall(vim.treesitter.query.get, 'lua', 'rainbow-blocks')
                        elseif vim.treesitter.get_query then
                            has = pcall(vim.treesitter.get_query, 'lua', 'rainbow-blocks')
                        end
                        return has and 'rainbow-blocks' or 'rainbow-delimiters'
                    end)
                    return ok and q or 'rainbow-delimiters'
                end)(),
            },
            highlight={
                'RainbowDelimiterRed',
                'RainbowDelimiterYellow',
                'RainbowDelimiterBlue',
                'RainbowDelimiterOrange',
                'RainbowDelimiterGreen',
                'RainbowDelimiterViolet',
                'RainbowDelimiterCyan',
            },
        }
    end
}
