{ lib, neg, ... }: {
  config = lib.mkMerge [
    {
      # Packages
      environment.systemPackages = [
      ];
    }
    (neg.mkHomeFiles {
      # Handlr Config
      ".config/handlr/handlr.toml".text = ''
        enable_selector = false
        selector = "vicinae dmenu -p 'Open With: ❯>'"
      '';
    })
  ];
}
