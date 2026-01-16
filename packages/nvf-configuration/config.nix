{ pkgs, nvimConfPath ? null }:
{
  vim = {
    package = pkgs.neovim-unwrapped;
    viAlias = true;
    vimAlias = true;
    lazy.enable = false;
    startPlugins = [
      pkgs.vimPlugins.lazy-nvim
      pkgs.fsread-nvim
      (pkgs.vimPlugins.nvim-treesitter.withPlugins (p: [
        p.bash
        p.caddy
        p.cmake
        p.css
        p.diff
        p.dockerfile
        p.gitcommit
        p.gitignore
        p.glsl
        p.go
        p.gomod
        p.gosum
        p.graphql
        p.html
        p.http
        p.ini
        p.javascript
        p.json
        p.just
        p.kconfig
        p.lua
        p.luadoc
        p.make
        p.markdown
        p.markdown_inline
        p.meson
        p.ninja
        p.nix
        p.php
        p.python
        p.query
        p.regex
        p.scss
        p.sql
        p.svelte
        p.toml
        p.vim
        p.vimdoc
        p.vue
        p.wgsl
        p.xml
        p.yaml
      ]))
    ];
    optPlugins = [ ];
    extraPlugins = { };
    pluginOverrides = { };
    
    # Minimal extra packages (LSPs/tools should be provided by devShells)
    extraPackages = [
      pkgs.ripgrep
      pkgs.fd
      pkgs.tree-sitter
    ];
    
    globals = { };
    options = {
      number = false;
      relativenumber = false;
    };
    keymaps = [ ];
    pluginRC = { };
    luaConfigPre = "";
    luaConfigRC = {
      userInit = if nvimConfPath != null then ''
        vim.opt.rtp:prepend("${nvimConfPath}")
        dofile("${nvimConfPath}/init.lua")
      '' else ''
        dofile(vim.fn.stdpath("config") .. "/init.lua")
      '';
    };
    luaConfigPost = "";
    additionalRuntimePaths = if nvimConfPath != null then [ nvimConfPath ] else [ "$HOME/.config/nvf" ];
    extraLuaFiles = [ ];
    withRuby = true;
    withNodeJs = false;
    luaPackages = [ ];
    withPython3 = true;
    python3Packages = [ ];
  };
}
