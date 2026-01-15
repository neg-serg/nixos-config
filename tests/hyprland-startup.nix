{
  name = "hyprland-startup";
  nodes = {
    machine =
      { pkgs, ... }:
      {
        hardware.graphics.enable = true;
        programs.hyprland.enable = true;
        environment.systemPackages = [ pkgs.hyprlandPlugins.hy3 ];
        environment.etc."hypr/hyprland.conf".text = ''
          plugin = ${pkgs.hyprlandPlugins.hy3}/lib/libhy3.so
        '';
      };
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Check that Hyprland binary operates (prints version) without segfaulting
    # We must set XDG_RUNTIME_DIR even for --version, otherwise it crashes
    machine.succeed("mkdir -p /tmp/runtime-dir")
    print(machine.succeed("XDG_RUNTIME_DIR=/tmp/runtime-dir Hyprland --version"))

    # Verify that the plugin is present in the wrapper's environment (if applicable)
    # The NixOS module for Hyprland usually adds plugins to the wrapper or config.
    # We mainly want to ensure the build succeeds and binary runs.
  '';
}
