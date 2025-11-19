{
  lib,
  config,
  ...
}:
lib.mkIf (config.features.text.manipulate.enable or false) {
  programs.jqp.enable = true; # interactive jq
}
