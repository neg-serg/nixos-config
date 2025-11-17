{
  lib,
  xdg,
  ...
}: let
  dockerfileBashOverride = xdg.mkXdgText "bat/syntaxes/Dockerfile (with bash).sublime-syntax" ''
    %YAML 1.2
    ---
    name: Dockerfile (with bash)
    scope: source.dockerfile.bash
    contexts:
      main:
        - include: scope:source.dockerfile
  '';
  jsonStub = xdg.mkXdgText "bat/syntaxes/JSON.sublime-syntax" ''
    %YAML 1.2
    ---
    name: JSON
    scope: source.json
    contexts:
      main:
        - include: arrays
      arrays:
        - match: '\G\['
          push: arrays
        - match: ']'
          pop: true
        - match: '.'
          scope: constant.character
  '';
in
  {
    # Reduce activation noise: keep bat disabled by default (can be overridden)
    programs.bat.enable = lib.mkDefault false;
    programs.bat.config = {
      theme = lib.mkForce "ansi";
      italic-text = "always";
      paging = "never";
      decorations = "never";
    };
  }
  // dockerfileBashOverride
  // jsonStub
