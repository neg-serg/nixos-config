-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ haya14busa/vim-asterisk                                                      │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'haya14busa/vim-asterisk', -- smartcase star
    keys = {
        { "*", "<Plug>(asterisk-#)", mode = "n" },
        { "#", "<Plug>(asterisk-*)", mode = "n" },
        { "g*", "<Plug>(asterisk-g#)", mode = "n" },
        { "g#", "<Plug>(asterisk-g*)", mode = "n" },
        { "z*", "<Plug>(asterisk-z#)", mode = "n" },
        { "gz*", "<Plug>(asterisk-gz#)", mode = "n" },
        { "z#", "<Plug>(asterisk-z*)", mode = "n" },
        { "gz#", "<Plug>(asterisk-gz*)", mode = "n" },
    },
    config=function() 
    end
}
