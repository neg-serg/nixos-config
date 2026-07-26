-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ nvim-orgmode/orgmode                                                         │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'nvim-orgmode/orgmode',
    ft = 'org',
    cmd = { 'OrgAgenda', 'OrgCapture' },
    config=function()
        require'orgmode'.setup({
            org_agenda_files='~/orgfiles/**/*',
            org_default_notes_file='~/orgfiles/refile.org',
            org_todo_keywords = { 'TODO(t)', 'IN_PROGRESS(i)', 'WAIT(w)', '|', 'DONE(d)', 'CANCELLED(c)' },
            org_startup_folded = 'showeverything',
            org_startup_indented = true,
            org_edit_src_content_indentation = 0,
            org_capture_templates = {
                t = { description = 'Todo', template = '** TODO %?\n   %U\n   %a' },
                n = { description = 'Note', template = '** %?\n   %U\n   %a' },
            },
            win_split_mode = 'auto',
        })

        -- Org-mode keybindings
        local org_augroup = vim.api.nvim_create_augroup('NegOrgmode', { clear = true })
        vim.api.nvim_create_autocmd('FileType', {
            pattern = 'org',
            group = org_augroup,
            callback = function(args)
                local opts = { silent = true, buffer = args.buf }
                vim.keymap.set('n', '<leader>oa', '<Cmd>OrgAgenda<CR>', { desc = 'Org agenda', buffer = args.buf })
                vim.keymap.set('n', '<leader>oc', '<Cmd>OrgCapture<CR>', { desc = 'Org capture', buffer = args.buf })
                vim.keymap.set('n', '<leader>oh', '<Cmd>OrgHeadline<CR>', { desc = 'Org headline', buffer = args.buf })
                vim.keymap.set('n', '<leader>otd', '<Cmd>OrgTodo<CR>', { desc = 'Org todo', buffer = args.buf })
                vim.keymap.set('n', '<leader>ots', '<Cmd>OrgTimeStamp<CR>', { desc = 'Org timestamp', buffer = args.buf })
                vim.keymap.set('n', '<leader>op', '<Cmd>OrgPriority<CR>', { desc = 'Org priority', buffer = args.buf })
            end,
        })
    end,
}
