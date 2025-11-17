{
  lib,
  config,
  ...
}:
with lib;
  mkIf config.features.fun.enable {
    xdg = {
      dataFile = {
        # hack-art files
        "hack-art/bonsai" = {
          text = builtins.readFile ./fun-art/bonsai.sh;
          executable = true;
        };
        "hack-art/chess" = {
          text = builtins.readFile ./fun-art/chess.sh;
          executable = true;
        };
        "hack-art/nvim-logo" = {
          text = builtins.readFile ./fun-art/nvim-logo.sh;
          executable = true;
        };
        "hack-art/rain" = {
          text = builtins.readFile ./fun-art/rain.sh;
          executable = true;
        };
        "hack-art/skull" = {
          text = builtins.readFile ./fun-art/skull.sh;
          executable = true;
        };
        "hack-art/skullmono.sh" = {
          text = builtins.readFile ./fun-art/skullmono.sh;
          executable = true;
        };
        "hack-art/skulls" = {
          text = builtins.readFile ./fun-art/skulls.sh;
          executable = true;
        };
        "hack-art/skull.txt" = {
          text = builtins.readFile ./fun-art/skull.txt;
        };
        "hack-art/zalgo" = {
          text = builtins.readFile ./fun-art/zalgo.py;
          executable = true;
        };

        # fantasy-art files
        "fantasy-art/gandalf.txt" = {
          text = builtins.readFile ./fun-art/gandalf.txt;
        };
        "fantasy-art/helmet.txt" = {
          text = builtins.readFile ./fun-art/helmet.txt;
        };
        "fantasy-art/hydra.txt" = {
          text = builtins.readFile ./fun-art/hydra.txt;
        };
        "fantasy-art/skeleton_hood.txt" = {
          text = builtins.readFile ./fun-art/skeleton_hood.txt;
        };
      };
    };
  }
