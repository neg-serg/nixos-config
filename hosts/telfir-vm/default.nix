{...}: {
  imports = [
    ./vm/hw.nix
    ./vm/network.nix
    ./vm/qa.nix
  ];

  # Keep VM lightweight but usable as a workstation
  roles.workstation.enable = true;
  profiles.vm.enable = true;

  services = {
    # Avoid pulling heavy/ROCm stack in the VM; fix build by disabling Ollama here
    ollama.enable = false;

    # Usability tweak in VM (optional)
    keyd = {
      enable = true;
      keyboards = {
        default = {
          ids = ["*"];
          settings = {
            main = {
              capslock = "layer(capslock)";
            };
            "capslock:C" = {
              "0" = "M-0";
              "a" = "home";
              "e" = "end";
              "j" = "down";
              "k" = "up";
              "1" = "up";
              "2" = "down";
              "q" = "escape";
              "`" = "asciitilde";
              "-" = "backspace";
              "h" = "backspace";
            };
          };
        };
      };
    };
  };
}
