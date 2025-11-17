_: {
  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      # Yazi 0.3+: [manager] -> [mgr]
      mgr = {show_hidden = true;};
      opener.edit = [
        {
          run = ''nvim "$@"'';
          block = true;
        }
      ];
    };
    keymap = {
      # Yazi 0.3+: [keymap.manager] -> [keymap.mgr]
      mgr.prepend_keymap = [
        {
          run = "close";
          on = ["<Esc>"];
        }
        {
          run = "close";
          on = ["<C-q>"];
        }
        {
          run = "yank --cut";
          on = ["d"];
        }
        {
          run = "remove --force";
          on = ["D"];
        }
        {
          run = "remove --permanently";
          on = ["X"];
        }
        {
          on = ["f"];
          run = ''shell "$SHELL" --block'';
          desc = "Open $SHELL here";
        }
      ];
    };
  };
}
