return function()
  vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = function()
      vim.schedule(function()
        local api, fn = vim.api, vim.fn

        -- Hygiene + double init guard
        local AUG = api.nvim_create_augroup('HeirlineConfig', { clear = true })
        if vim.g._heirline_config_loaded then return end
        vim.g._heirline_config_loaded = true

        -- Deps (defensive)
        local ok_heir, heir = pcall(require, 'heirline'); if not ok_heir then return end
        local ok_cond, c     = pcall(require, 'heirline.conditions')
        local ok_utils, utils= pcall(require, 'heirline.utils')
        if not ok_cond or not ok_utils then return end
        local ok_devicons, devicons = pcall(require, 'nvim-web-devicons')

        -- Debug helpers
        local uv = vim.uv or vim.loop
        local DEBUG = (vim.env.HEIRLINE_DEBUG == '1') or (vim.g.heirline_debug == true)
        local DBG_TITLE, DBG_MAX = 'HeirlineDBG', 600
        local dbg_log = {}
        local function dbg_push(line)
          if not DEBUG then return end
          local msg = string.format('[%s] %s', os.date('%H:%M:%S'), line)
          if #dbg_log >= DBG_MAX then table.remove(dbg_log, 1) end
          table.insert(dbg_log, msg)
        end
        local function dbg_notify(line, lvl)
          if not DEBUG then return end
          dbg_push(line)
          if vim.notify then vim.notify(line, lvl or vim.log.levels.DEBUG, { title = DBG_TITLE }) end
        end
        local function prof(name, f, thr)
          if not DEBUG or type(f) ~= 'function' then return f end
          local T = thr or 5.0
          return function(...)
            local t0 = uv.hrtime()
            local ok, res = xpcall(f, debug.traceback, ...)
            local dt = (uv.hrtime() - t0) / 1e6
            if dt > T then dbg_push(string.format('slow %-18s %.2f ms', name, dt)) end
            if not ok then dbg_push(string.format('err  %-18s %s', name, tostring(res))); return '' end
            return res
          end
        end

        -- User commands (debug)
        pcall(api.nvim_del_user_command, 'HeirlineDebugToggle')
        api.nvim_create_user_command('HeirlineDebugToggle', function()
          DEBUG = not DEBUG; vim.g.heirline_debug = DEBUG
          dbg_notify('debug mode: ' .. (DEBUG and 'ON' or 'OFF'))
        end, {})
        pcall(api.nvim_del_user_command, 'HeirlineDebugDump')
        api.nvim_create_user_command('HeirlineDebugDump', function()
          local b = api.nvim_create_buf(false, true)
          api.nvim_buf_set_lines(b, 0, -1, false, dbg_log)
          api.nvim_buf_set_option(b, 'bufhidden', 'wipe')
          api.nvim_buf_set_option(b, 'filetype', 'log')
          api.nvim_set_current_buf(b)
        end, {})
        pcall(api.nvim_del_user_command, 'HeirlineDebugClear')
        api.nvim_create_user_command('HeirlineDebugClear', function()
          dbg_log = {}; dbg_notify('log cleared')
        end, {})
        if DEBUG then
          api.nvim_create_autocmd({ 'LspAttach','LspDetach','DiagnosticChanged','WinResized' }, {
            group = AUG,
            callback = function(ev) dbg_push('event: ' .. ev.event) end,
          })
        end

        -- Flags (persisted globals) + notify helper
        vim.g.heirline_use_icons = vim.g.heirline_use_icons
        vim.g.heirline_use_theme_colors = vim.g.heirline_use_theme_colors
        vim.g.heirline_lock_theme = vim.g.heirline_lock_theme or false
        local function notify(msg, lvl)
          if vim.notify then vim.notify(msg, lvl or vim.log.levels.INFO, { title = 'Heirline' }) end
        end

        local USE_ICONS = vim.g.heirline_use_icons
        if USE_ICONS == nil then
          USE_ICONS = not (vim.env.NERD_FONT == '0') and (vim.g.have_nerd_font == true or true)
        end
        local SHOW_ENV = vim.g.heirline_env_indicator == true
        local USE_THEME = vim.g.heirline_use_theme_colors
        if USE_THEME == nil then USE_THEME = true end
        local LOCK_THEME = vim.g.heirline_lock_theme

        -- Persistence (remember toggles across sessions)
        local STATE_FILE = fn.stdpath('state') .. '/heirline_state.json'
        local function save_state()
          local obj = { use_theme = USE_THEME, lock_theme = LOCK_THEME, use_icons = USE_ICONS }
          pcall(fn.mkdir, fn.stdpath('state'), 'p')
          pcall(fn.writefile, { vim.json.encode(obj) }, STATE_FILE)
        end
        local function load_state()
          local ok, data = pcall(fn.readfile, STATE_FILE)
          if not ok or not data or #data == 0 then return end
          local ok2, obj = pcall(vim.json.decode, table.concat(data, '\n'))
          if not ok2 or type(obj) ~= 'table' then return end
          if obj.use_theme  ~= nil then USE_THEME  = obj.use_theme;  vim.g.heirline_use_theme_colors = USE_THEME end
          if obj.lock_theme ~= nil then LOCK_THEME = obj.lock_theme; vim.g.heirline_lock_theme       = LOCK_THEME end
          if obj.use_icons  ~= nil then USE_ICONS  = obj.use_icons;  vim.g.heirline_use_icons        = USE_ICONS end
        end
        load_state()
        api.nvim_create_autocmd('VimLeavePre', { group = AUG, callback = function() pcall(save_state) end })

        -- Symbols
        local function I(icons, ascii) return USE_ICONS and icons or ascii end
        local S = setmetatable({
          folder='', sep='¦', modified=I('','*'), lock=I('🔒','RO'),
          search=I('','/'), rec=I('','REC'), gear=I('','[LSP]'),
          branch=I('󰘵','[git]'), close=I('','[x]'),
          err=I('','E:'), warn=I('','W:'), utf8=I('','utf8'),
          latin=I('','enc'), linux=I('','unix'), mac=I('','mac'), win=I('','dos'),
          pilcrow=I('¶','¶'), wrap=I('⤶','↩'), doc=I('','[buf]'),
          plus=I('','+'), tilde=I('','~'), minus=I('','-'),
        }, { __index = function(_, k) return '[' .. tostring(k) .. ']' end })

        -- Theme helpers
        local _hl_cache = {}
        local function hl_get(name)
          if _hl_cache[name] then return _hl_cache[name] end
          local ok, h
          if vim.api.nvim_get_hl then
            ok, h = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
            if ok and h then _hl_cache[name] = h; return h end
          end
          ok, h = pcall(vim.api.nvim_get_hl_by_name, name, true)
          if ok and h then
            local r = { fg = h.foreground, bg = h.background }
            _hl_cache[name] = r; return r
          end
          return {}
        end
        local function tohex(n) if not n then return nil end; return string.format('#%06x', n) end
        local function hex_to_rgb(hex)
          if type(hex) ~= 'string' then return 255, 255, 255 end
          local clean = hex:gsub('#', '')
          if #clean ~= 6 then return 255, 255, 255 end
          return tonumber(clean:sub(1, 2), 16),
            tonumber(clean:sub(3, 4), 16),
            tonumber(clean:sub(5, 6), 16)
        end
        local function rgb_to_hex(r, g, b)
          local function clamp(x)
            x = math.floor(x + 0.5)
            if x < 0 then return 0 elseif x > 255 then return 255 else return x end
          end
          return string.format('#%02x%02x%02x', clamp(r), clamp(g), clamp(b))
        end
        local function mix_hex(a, b, ratio)
          ratio = math.min(math.max(ratio or 0.5, 0.0), 1.0)
          local ar, ag, ab = hex_to_rgb(a)
          local br, bg, bb = hex_to_rgb(b)
          local nr = ar * (1 - ratio) + br * ratio
          local ng = ag * (1 - ratio) + bg * ratio
          local nb = ab * (1 - ratio) + bb * ratio
          return rgb_to_hex(nr, ng, nb)
        end
        local function lighten_hex(hex, ratio)
          if type(hex) ~= 'string' then return hex end
          if hex == 'NONE' then return hex end
          if not hex:match('^#%x%x%x%x%x%x$') then return hex end
          return mix_hex(hex, '#ffffff', ratio or 0.12)
        end
        -- Nudged ~14% toward white to brighten the statusline background versus kitty base.
        local PANEL_LIGHTEN_RATIO = 0.14
        local function themed_colors(fallback)
          if LOCK_THEME and type(initial_colors) == 'table' then return vim.deepcopy(initial_colors) end
          if not USE_THEME then return vim.deepcopy(fallback) end
          local sl   = hl_get('StatusLine')
          local slnc = hl_get('StatusLineNC')
          local dfe  = hl_get('DiagnosticError')
          local dfw  = hl_get('DiagnosticWarn')
          local dir  = hl_get('Directory')
          local id   = hl_get('Identifier')
          local str  = hl_get('String')
          local dadd = hl_get('DiffAdd')
          local dchg = hl_get('DiffChange')
          local ddel = hl_get('DiffDelete')

          -- Helper to get color with fallback chain
          local function get_fg(hl, fb) return tohex(hl.fg) or fb end
          local function get_bg(hl, fb) return tohex(hl.bg) or fb end

          local t = {
            black       = fallback.black,
            white       = get_fg(sl, fallback.white),
            white_dim   = get_fg(slnc, fallback.white_dim) or fallback.white_dim,
            red         = get_fg(dfe, fallback.red),
            yellow      = get_fg(dfw, fallback.yellow),
            blue        = get_fg(dir, fallback.blue),
            cyan        = get_fg(id, fallback.cyan),
            green       = get_fg(str, fallback.green),
            diff_add    = get_fg(dadd, fallback.green),
            diff_change = get_fg(dchg, '#a0b1c5'),
            diff_del    = get_fg(ddel, fallback.red),
            blue_light  = fallback.blue_light,
            line_zero   = fallback.line_zero,
            dir_mid     = fallback.dir_mid,
            mode_ins_bg = get_bg(hl_get('DiffAdd'), 'NONE'),
            mode_vis_bg = get_bg(hl_get('Visual'), 'NONE'),
            mode_rep_bg = get_bg(hl_get('DiffDelete'), 'NONE'),
            base_bg     = get_bg(sl, fallback.black),
            nc_bg       = get_bg(slnc, fallback.black) or get_bg(sl, fallback.black),
          }
          if vim.g.colors_name == 'neg' then
            -- Force Color 25 (#005faf) as the main accent for neg theme
            local c25 = '#005faf'
            t.blue = c25
            t.cyan = c25
            t.dir_mid = '#005faf' -- make path segments match strict blue
            t.green = '#287373' -- use vibrant green for accents like tilde
            -- Also ensure white_dim has a sensible value for neg
            if not t.white_dim or t.white_dim == fallback.white_dim then
              t.white_dim = '#4a6078'
            end
          end
          return t
        end
        local function colors_assign(dst, src) for k, v in pairs(src) do dst[k] = v end end
        local function adjust_diff_change_shade(palette)
          if type(palette) ~= 'table' then return end
          local base = palette.white or '#d6dde6'
          -- 30% blend softens DiffChange to avoid clashing with kitty purples.
          palette.diff_change = mix_hex(base, '#ffffff', 0.3)
        end
        local function apply_palette_adjustments(palette)
          if type(palette) ~= 'table' then return end
          if palette._adjusted then return end
          adjust_diff_change_shade(palette)
          if palette.base_bg then palette.base_bg = lighten_hex(palette.base_bg, PANEL_LIGHTEN_RATIO) end
          palette._adjusted = true
        end

        -- Hardcoded shades mirror kitty theme entries (see kitty.conf colors 247/248/243).
        -- Update here if the kitty palette changes to keep the statusline consistent.
        local colors_fallback = {
          black = 'NONE',
          white = '#6d839e',   -- kitty color247 (statusline foreground)
          red = '#970d4f',     -- kitty accent for diagnostics
          green = '#007a51',   -- kitty green used across widgets
          blue = '#005faf',    -- kitty directory / separator blue
          yellow = '#c678dd',  -- kitty magenta-ish accent (warnings/LSP)
          cyan = '#6587b3',
          blue_light = '#517f8d',
          white_dim = '#3f5063',
          line_zero = '#3f5876', -- kitty color243, used for padded zeros in position
          dir_mid = '#7c90a8',   -- kitty color248, applied on cwd mid segments
        }
        local colors = themed_colors(colors_fallback)
        apply_palette_adjustments(colors)
        local initial_colors = vim.deepcopy(colors)
        local function hl(fg, bg) return { fg = fg, bg = bg } end
        local align = { provider = '%=' }

        local function apply_statusline_highlights()
          api.nvim_set_hl(0, 'StatusLine',   { fg = colors.white,     bg = colors.base_bg })
          api.nvim_set_hl(0, 'StatusLineNC', { fg = colors.white_dim, bg = colors.nc_bg })
          api.nvim_set_hl(0, 'HeirlineDiffAddIcon',    { fg = colors.diff_add    or colors.green,  bg = colors.base_bg, italic = true })
          api.nvim_set_hl(0, 'HeirlineDiffChangeIcon', { fg = colors.diff_change or colors.yellow, bg = colors.base_bg, italic = true })
          api.nvim_set_hl(0, 'HeirlineDiffDelIcon',    { fg = colors.diff_del    or colors.red,    bg = colors.base_bg, italic = true })
          api.nvim_set_hl(0, 'HeirlinePanelDivider',   { fg = colors.white_dim,  bg = colors.base_bg })
          api.nvim_set_hl(0, 'HeirlineVisualSel',      { fg = colors.yellow,     bg = colors.base_bg, italic = true })
          api.nvim_set_hl(0, 'HeirlineSizeIcon',       { fg = colors.blue,       bg = colors.base_bg })
          api.nvim_set_hl(0, 'HeirlinePositionIcon',   { fg = colors.green,      bg = colors.base_bg })
        end

        -- Helpers
        local function buf_valid(b) return type(b)=='number' and b>0 and api.nvim_buf_is_valid(b) end
        local function safe_buffer_matches(spec, bufnr)
          if bufnr ~= nil and not buf_valid(bufnr) then return false end
          return c.buffer_matches(spec, bufnr)
        end

        local function statusline_win()
          local win = vim.g.statusline_winid
          if win and api.nvim_win_is_valid(win) then return win end
          local ok, cur = pcall(api.nvim_get_current_win)
          if ok and cur and api.nvim_win_is_valid(cur) then return cur end
          return nil
        end
        local function statusline_buf()
          local win = statusline_win()
          if win then
            local ok, buf = pcall(api.nvim_win_get_buf, win)
            if ok and buf_valid(buf) then return buf end
          end
          local ok, buf = pcall(api.nvim_get_current_buf)
          if ok and buf_valid(buf) then return buf end
          return nil
        end
        local function buf_name_from(buf)
          if not buf_valid(buf) then return '' end
          local name = api.nvim_buf_get_name(buf)
          if not name or name == '' then return '' end
          return fn.fnamemodify(name, ':t')
        end
        local function buf_path_from(buf)
          if not buf_valid(buf) then return '' end
          return api.nvim_buf_get_name(buf)
        end
        local function window_cwd(win)
          if win and api.nvim_win_is_valid(win) then
            local ok, cwd = pcall(fn.getcwd, -1, win)
            if ok and type(cwd) == 'string' and cwd ~= '' then return cwd end
          end
          local buf = statusline_buf()
          if buf and api.nvim_buf_is_valid(buf) then
            local name = api.nvim_buf_get_name(buf)
            if name and name ~= '' then
              local dir = fn.fnamemodify(name, ':p:h')
              if dir and dir ~= '' then return dir end
            end
          end
          return fn.getcwd()
        end
        local function win_w()
          local win = statusline_win()
          if win and api.nvim_win_is_valid(win) then
            local ok, width = pcall(api.nvim_win_get_width, win)
            if ok and type(width) == 'number' and width > 0 then return width end
          end
          local ok_cur, width_cur = pcall(api.nvim_win_get_width, 0)
          if ok_cur and type(width_cur) == 'number' and width_cur > 0 then return width_cur end
          local columns = tonumber(vim.o.columns) or 0
          return (columns > 0) and columns or 120
        end
        local function is_narrow() return win_w() < 80 end
        local function is_tiny() return win_w() < 60 end
        local function is_empty()
          local buf = statusline_buf()
          return buf == nil or buf_name_from(buf) == ''
        end

        local _has = {}
        local function has_mod(name)
          local v = _has[name]; if v ~= nil then return v end
          local ok = pcall(require, name); _has[name] = ok; return ok
        end

        local function open_file_browser_cwd()
          local cwd = window_cwd(statusline_win())
          if has_mod('oil') then vim.cmd('Oil ' .. fn.fnameescape(cwd)); return end
          if has_mod('telescope') then
            local ok_ext = pcall(function()
              require('telescope').extensions.file_browser.file_browser({ cwd = cwd, respect_gitignore = true })
            end)
            if ok_ext then return end
            local ok_builtin = pcall(function()
              require('telescope.builtin').find_files({ cwd = cwd, hidden = true })
            end)
            if ok_builtin then return end
          end
          vim.cmd('Ex ' .. fn.fnameescape(cwd))
        end
        local function open_git_ui()
          if has_mod('telescope') then
            local ok = pcall(function() require('telescope.builtin').git_branches() end)
            if ok then return end
          end
          if has_mod('neogit') then return require('neogit').open() end
          if fn.exists(':Git') == 2 then return vim.cmd('Git') end
          notify('No git UI found (telescope/neogit/fugitive not available)', vim.log.levels.WARN)
          dbg_push('git click: no UI')
        end
        local function open_diagnostics_list()
          if has_mod('trouble') then
            local ok = pcall(require('trouble').toggle, { mode = 'document_diagnostics' })
            if not ok then pcall(require('trouble').toggle, { mode = 'workspace_diagnostics' }) end
          else
            pcall(vim.diagnostic.setqflist); vim.cmd('copen')
          end
        end

        -- Toggles (remember state)
        pcall(api.nvim_del_user_command, 'HeirlineIconsToggle')
        api.nvim_create_user_command('HeirlineIconsToggle', function()
          USE_ICONS = not USE_ICONS
          vim.g.heirline_use_icons = USE_ICONS
          save_state()
          notify('Heirline: icons ' .. (USE_ICONS and 'ON' or 'OFF'))
          vim.cmd('redrawstatus')
        end, {})

        pcall(api.nvim_del_user_command, 'HeirlineThemeToggle')
        api.nvim_create_user_command('HeirlineThemeToggle', function()
          USE_THEME = not USE_THEME
          vim.g.heirline_use_theme_colors = USE_THEME
          local fresh = themed_colors(colors_fallback)
          apply_palette_adjustments(fresh)
          colors_assign(colors, fresh)
          apply_statusline_highlights()
          save_state()
          notify('Heirline: theme-colors ' .. (USE_THEME and 'ON' or 'OFF'))
          vim.cmd('redrawstatus')
        end, {})

        pcall(api.nvim_del_user_command, 'HeirlineThemeLockToggle')
        api.nvim_create_user_command('HeirlineThemeLockToggle', function()
          LOCK_THEME = not LOCK_THEME
          vim.g.heirline_lock_theme = LOCK_THEME
          local src = LOCK_THEME and initial_colors or themed_colors(colors_fallback)
          if src ~= initial_colors then apply_palette_adjustments(src) end
          colors_assign(colors, src)
          apply_statusline_highlights()
          save_state()
          notify('Heirline: theme lock ' .. (LOCK_THEME and 'ENABLED' or 'DISABLED'))
          vim.cmd('redrawstatus')
        end, {})

        pcall(api.nvim_del_user_command, 'HeirlineThemeUseOriginal')
        api.nvim_create_user_command('HeirlineThemeUseOriginal', function()
          USE_THEME = true; vim.g.heirline_use_theme_colors = true
          LOCK_THEME = true; vim.g.heirline_lock_theme = true
          colors_assign(colors, initial_colors)
          apply_statusline_highlights()
          save_state()
          notify('Heirline: using ORIGINAL theme (locked)')
          vim.cmd('redrawstatus')
        end, {})

        -- Components
        local ok_parts, parts_ctor = pcall(require, 'plugins.panel.heirline.components')
        if not ok_parts or type(parts_ctor) ~= 'function' then
          dbg_notify('components module missing or invalid', vim.log.levels.ERROR)
          return
        end
        local parts = parts_ctor({
          api = api, fn = fn, c = c, utils = utils,
          colors = colors, S = S, prof = prof,
          dbg_push = dbg_push, ok_devicons = ok_devicons, devicons = devicons,
          USE_ICONS = USE_ICONS, SHOW_ENV = SHOW_ENV,
          is_empty = is_empty, is_narrow = is_narrow, is_tiny = is_tiny,
          statusline_win = statusline_win,
          statusline_buf = statusline_buf,
          buf_name = buf_name_from,
          buf_path = buf_path_from,
          window_cwd = window_cwd,
          open_file_browser_cwd = open_file_browser_cwd,
          open_git_ui = open_git_ui,
          open_diagnostics_list = open_diagnostics_list,
          safe_buffer_matches = safe_buffer_matches,
          notify = notify,
          hl = hl,
          align = align,
        })
        if type(parts) ~= 'table' or not parts.statusline then
          dbg_notify('components did not return a proper parts table', vim.log.levels.ERROR)
          return
        end
        local statusline = parts.statusline
        local SPECIAL_FT = parts.SPECIAL_FT

        -- Setup
        heir.setup({
          statusline = statusline,
          opts = {},
        })

        -- Sync HL + autos
        apply_statusline_highlights()

        api.nvim_create_autocmd('ColorScheme', {
          group = AUG,
          callback = function()
            -- Defer to let the colorscheme fully apply before reading highlight groups
            vim.defer_fn(function()
              _hl_cache = {}
              if LOCK_THEME then
                colors_assign(colors, initial_colors)
              else
                local fresh = themed_colors(colors_fallback)
                apply_palette_adjustments(fresh)
                colors_assign(colors, fresh)
              end
              apply_statusline_highlights()
              vim.cmd('redrawstatus')
              if DEBUG then dbg_notify(LOCK_THEME and 'colors reapplied (locked to original)' or 'colors refreshed from theme') end
            end, 50)
          end,
        })

        if DEBUG then dbg_notify('initialized (debug ON)') end
      end)
    end,
  })
end
