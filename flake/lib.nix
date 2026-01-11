{
  inputs,
  nixpkgs,
  ...
}:
let
  inherit (nixpkgs) lib;

  hyprlandOverlay =
    system:
    (
      _: prev:
      let
        hyprlandBase = inputs.hyprland.packages.${system}.hyprland.override { wrapRuntimeDeps = false; };
        hyprland = hyprlandBase;
      in
      {
        inherit hyprland;
        inherit (inputs.xdg-desktop-portal-hyprland.packages.${system}) xdg-desktop-portal-hyprland;
        hyprlandPlugins = prev.hyprlandPlugins // {
          # "borders-plus-plus" = inputs.hyprland-plugins.packages.${system}."borders-plus-plus";
          # dynamic-cursors removed
          hy3 = inputs.hy3.packages.${system}.hy3;
          hyprexpo = prev.hyprlandPlugins.hyprexpo.overrideAttrs (old: {
            buildInputs = [ hyprland ] ++ (lib.filter (i: i.pname or "" != "hyprland") old.buildInputs);
          });
        };
      }
    );

  mkPkgs =
    system:
    import nixpkgs {
      inherit system;
      overlays = [
        ((import ../packages/overlay.nix) inputs)
        (hyprlandOverlay system)
      ];
      config = {
        allowAliases = false;
        permittedInsecurePackages = [
          "yandex-browser-stable-25.10.1.1173-1"
        ];
        allowUnfreePredicate =
          pkg:
          let
            name = pkg.pname or (builtins.parseDrvName (pkg.name or "")).name;
            allowed = [
              "google-antigravity"
              "antigravity-fhs"
              "google-chrome"
              "yandex-browser-stable"
              "vivaldi"
              "beatprints"
              "richcolors"
              "steam-unwrapped"
              "steam"
              "steam-run"
            ];
          in
          builtins.elem name allowed;
      };
    };

  mkCustomPkgs = pkgs: import ../packages/flake/custom-packages.nix { inherit pkgs; };
  mkIosevkaNeg = system: inputs."iosevka-neg".packages.${system};
in
{
  inherit mkPkgs mkCustomPkgs mkIosevkaNeg;
}
