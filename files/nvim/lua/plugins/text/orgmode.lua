-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ nvim-orgmode/orgmode                                                         │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'nvim-orgmode/orgmode', config=function() -- orgmode support
    require'orgmode'.setup({
        org_agenda_files='~/orgfiles/**/*',
        org_default_notes_file='~/orgfiles/refile.org',
    })
    end,
    event={'VeryLazy'}}
