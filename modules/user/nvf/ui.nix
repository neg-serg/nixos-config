{...}: {
  programs.nvf.settings.vim = {
    # UI components provided by nvf.
    # We keep them minimal to avoid conflicts with handwritten Lua UI for now.
    telescope.enable = true;
    autocomplete.nvim-cmp.enable = true;

    # You can enable more nvf UI components here as you migrate
    # statusline.lualine.enable = true;
    # filetree.neo-tree.enable = true;
  };
}
