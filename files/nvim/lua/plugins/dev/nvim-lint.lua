-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ mfussenegger/nvim-lint                                                       │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
    'mfussenegger/nvim-lint',
    event = { "BufReadPost", "BufNewFile", "BufWritePost" },
    config=function()
        require('lint').linters_by_ft = {
          sh = {'shellcheck'},
          bash = {'shellcheck'},
          zsh = {'shellcheck'},
          yaml = {'yamllint'},
        }
        vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost', 'InsertLeave' }, {
          group = vim.api.nvim_create_augroup('NegNvimLint', { clear = true }),
          callback = function()
            require('lint').try_lint()
          end,
        })
    end
}
