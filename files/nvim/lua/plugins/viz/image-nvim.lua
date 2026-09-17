-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ 3rd/image.nvim                                                               │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'3rd/image.nvim',
  build=false,

  ft = { "markdown", "typst" },
  -- Molten renders plots through this plugin, so the provider has to be loaded
  -- by the time a kernel is initialized (molten-nvim.lua is the consumer side).
  event = { "User MoltenInitPost" },
  config=function()
    require"image".setup({
    backend = "kitty",
    processor = "magick_cli",
    integrations = {
      markdown = {
        enabled = true,
        clear_in_insert_mode = false,
        download_remote_images = true,
        only_render_image_at_cursor = false,
        floating_windows = false, -- if true, images will be rendered in floating markdown windows
        filetypes = { "markdown", "vimwiki" }, -- markdown extensions (ie. quarto) can go here
      },
      typst = {
        enabled = true,
        filetypes = { "typst" },
      },
      html = {
        enabled = false,
      },
      css = {
        enabled = false,
      },
    },
    max_width = nil,
    max_height = nil,
    -- Molten sizes its output window from the raw image size (image_size() in
    -- molten's load_image_nvim.lua ignores these caps) and image.nvim clamps the
    -- render to the window percentage afterwards — anything below 100 leaves a
    -- gap in the output window. 100 also bounds huge images by the window size,
    -- so max_width/max_height can stay nil (upstream suggests 100/12 instead).
    max_width_window_percentage = 100,
    max_height_window_percentage = 100,
    window_overlap_clear_enabled = false, -- toggles images when windows are overlapped
    window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "snacks_notif", "scrollview", "scrollview_sign" },
    editor_only_render_when_focused = false, -- auto show/hide images when the editor gains/looses focus
    tmux_show_only_in_active_window = false, -- auto show/hide images in the correct Tmux window (needs visual-activity off)
    hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif" }, -- render image files as images when opened
  })
  end
}
