{
  imports = [
    # system/user modules already structured under modules/
    # Modules are now imported via modules/flat.nix in init.nix
    # ../modules/cli
    # ../modules/dev
    # ... (removed for flat structure)
  ];

  features.games.launchers.lutris.enable = false;
  features.apps.libreoffice.enable = false;
}
