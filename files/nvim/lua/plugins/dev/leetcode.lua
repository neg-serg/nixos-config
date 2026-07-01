-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ kawre/leetcode.nvim                                                         │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'kawre/leetcode.nvim',
        build=function()
            pcall(function() require('nvim-treesitter.install').update({with_sync=true})('html') end)
        end,
        cmd='Leet',
        dependencies={
            'nvim-lua/plenary.nvim',
            'MunifTanjim/nui.nvim',
        },
        keys={
            {'<leader>Lq', '<Cmd>Leet list<CR>', desc='LeetCode: List questions'},
            {'<leader>Ll', '<Cmd>Leet<CR>', desc='LeetCode: View question'},
            {'<leader>Lt', '<Cmd>Leet run<CR>', desc='LeetCode: Test code'},
            {'<leader>Ls', '<Cmd>Leet submit<CR>', desc='LeetCode: Submit code'},
            {'<leader>Lr', '<Cmd>Leet reset<CR>', desc='LeetCode: Reset code'},
        },
        opts={
            lang='python3',
            picker='fzf-lua',
        }}
