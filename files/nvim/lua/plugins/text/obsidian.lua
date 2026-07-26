-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ obsidian-nvim/obsidian.nvim                                                 │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'obsidian-nvim/obsidian.nvim', version='*', ft='markdown',
        dependencies={
            'nvim-lua/plenary.nvim',
            'ibhagwan/fzf-lua', -- picker backend for Obsidian commands
        },
        config=function()
            local obsidian = require('obsidian')

            obsidian.setup({
                legacy_commands=false,
                workspaces={
                    {name='notes', path='~/notes'},
                },
                picker={name='fzf-lua'},
                open_notes_in='vsplit',

                note_id_func=function(title)
                    if title ~= nil then
                        return title:gsub(' ', '-'):gsub('[^A-Za-z0-9-]', ''):lower()
                    else
                        return tostring(os.date('%Y%m%d%H%M'))
                    end
                end,

                note_frontmatter_func = function(note)
                    local out = { id = note.id, aliases = note.aliases, tags = note.tags }
                    if note.metadata ~= nil and not vim.tbl_isempty(note.metadata) then
                        for k, v in pairs(note.metadata) do
                            out[k] = v
                        end
                    end
                    return out
                end,

                link={style='wiki', prepend_note_path=true},
                attachments={folder=''},
                ui={enable=false}, -- render-markdown.nvim handles rendering
                daily_notes={
                    folder='',
                    date_format='%Y-%m-%d',
                    alias_format='%B %-d, %Y',
                },
                templates={folder=''},
                search={sort_by='path', sort_reversed=false},
                completion={nvim_cmp=false}, -- blink.cmp handles completion
                follow_url_func=function(url)
                    vim.fn.jobstart({'xdg-open', url}, {detach=true})
                end,
            })

            local function yank_notelink()
                local fname = vim.fn.expand('%:t:r')
                local link = '[[' .. fname .. ']]'
                vim.fn.setreg('+', link)
                vim.notify('Yanked: ' .. link)
            end

            local function browse_media()
                require('fzf-lua').files({
                    cwd=vim.fn.expand('~/notes'),
                    fd_opts='--type f -e png -e jpg -e jpeg -e gif -e svg -e webp -e mp4 -e webm -e pdf',
                })
            end

            local function set_obsidian_keys(buf)
                local opts={silent=true, noremap=true, buffer=buf}
                -- Existing
                vim.keymap.set('i', '<leader>[', '<Cmd>Obsidian link<CR>', opts)
                vim.keymap.set('n', '<C-S-i>', '<Cmd>Obsidian paste_img<CR>', opts)
                vim.keymap.set('n', '<C-a>', '<Cmd>Obsidian tags<CR>', opts)
                vim.keymap.set('n', '<S-m>', browse_media, opts)
                vim.keymap.set('n', '<C-t>', '<Cmd>Obsidian toggle_checkbox<CR>', opts)
                vim.keymap.set('n', '<C-y>', yank_notelink, opts)
                vim.keymap.set('n', '<leader>b', '<Cmd>Obsidian backlinks<CR>', opts)
                -- New
                vim.keymap.set('n', '<leader>on', '<Cmd>ObsidianNew<CR>', {desc='New note', buffer=buf})
                vim.keymap.set('n', '<leader>oq', '<Cmd>ObsidianQuickSwitch<CR>', {desc='Quick switch note', buffer=buf})
                vim.keymap.set('n', '<leader>ot', '<Cmd>ObsidianToday<CR>', {desc='Today daily note', buffer=buf})
                vim.keymap.set('n', '<leader>os', '<Cmd>ObsidianSearch<CR>', {desc='Search vault', buffer=buf})
                vim.keymap.set('n', '<leader>oT', '<Cmd>ObsidianTemplate<CR>', {desc='Insert template', buffer=buf})
            end

            local notes_dir = vim.fn.expand('~/notes')
            vim.api.nvim_create_autocmd({'BufNewFile','BufRead'}, {
                pattern='*.md',
                group=vim.api.nvim_create_augroup('obsidian_only_keymap', {clear=true}),
                callback=function(ev)
                    local path = vim.api.nvim_buf_get_name(ev.buf)
                    if path:find(notes_dir, 1, true) then
                        set_obsidian_keys(ev.buf)
                    end
                end,
            })

            if vim.bo.filetype == 'markdown' and vim.fn.expand('%:p'):find(notes_dir, 1, true) then
                set_obsidian_keys(0)
            end
        end}
