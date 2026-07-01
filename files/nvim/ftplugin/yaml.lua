-- gf for YAML: follow $ref, include:, extends:, and local uses:.
-- Anchor navigation via JSON Pointer paths (#/components/schemas/User).

local nav = require('utils.nav')

-- Jump to a JSON Pointer key path like #/components/schemas/User.
-- Tracks minimum indentation so each successive key must be nested deeper.
local function goto_yaml_keypath(anchor)
  local path = anchor:gsub('^#?/', '')
  if path == '' then return end
  local keys = vim.split(path, '/', { plain = true })
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local key_idx  = 1
  local min_indent = 0
  for lnum, line in ipairs(lines) do
    if line:match('^%s*$') or line:match('^%s*#') then goto continue end
    local indent = #(line:match('^(%s*)') or '')
    -- Match plain, single-quoted, or double-quoted YAML keys
    local key = line:match([[^%s*["']?([%w_%-%.]+)["']?%s*:]])
    if key == keys[key_idx] and indent >= min_indent then
      if key_idx == #keys then
        vim.api.nvim_win_set_cursor(0, { lnum, indent })
        return true
      end
      min_indent = indent + 1   -- next component must be indented further
      key_idx = key_idx + 1
    end
    ::continue::
  end
end

local function ref_at_cursor()
  local line = vim.api.nvim_get_current_line()
  local ref = line:match([[$ref%s*:%s*['"]?([^'"%s,}]+)['"]?]])
           or line:match([[include%s*:%s*['"]?([^'"%s,}]+)['"]?]])
           or line:match([[extends%s*:%s*['"]?([^'"%s,}]+)['"]?]])
            -- only local actions start with ./
           or line:match([[uses%s*:%s*['"]?(%.%/[^'"%s,}]+)['"]?]])
  if not ref then return nil end

  if ref:match('^https?://') then return { type = 'url', ref = ref } end
  if ref:sub(1, 1) == '#'   then return { type = 'anchor', anchor = ref } end

  local anchor
  local hash = ref:find('#', 1, true)
  if hash then anchor = ref:sub(hash + 1); ref = ref:sub(1, hash - 1) end
  if ref == '' then return { type = 'anchor', anchor = anchor } end
  return { type = 'file', path = ref, anchor = anchor }
end

local function follow_ref()
  local r = ref_at_cursor()
  if not r then return vim.cmd('normal! gf') end

  if r.type == 'url' then
    nav.open_url(r.ref)
  elseif r.type == 'anchor' then
    goto_yaml_keypath(r.anchor)
  elseif r.type == 'file' then
    local resolved = nav.resolve_path(r.path, { extensions = { '.yaml', '.yml', '.json' } })
    if resolved then
      nav.open_file(resolved, { anchor = r.anchor, anchor_fn = goto_yaml_keypath })
    end
  end
end

vim.keymap.set('n', 'gf', follow_ref, { buffer = true, desc = 'Follow $ref / include / extends / uses' })
vim.keymap.set('n', '<CR>', follow_ref, { buffer = true, desc = 'Follow $ref / include / extends / uses' })
