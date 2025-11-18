{
  config,
  xdg,
  ...
}:
# Link static configuration directory (config.jsonc + skull) from repo
xdg.mkXdgSource "fastfetch" {
  source = config.lib.file.mkOutOfStoreSymlink "${config.neg.hmConfigRoot}/modules/cli/fastfetch/conf";
  recursive = true;
}
