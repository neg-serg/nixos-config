{pkgs ? null, ...}: {
  mkXdgText = relPath: text: {
    # Declare the file; use force=true on the caller side if overwriting is needed.
    xdg.configFile."${relPath}".text = text;
  };

  mkXdgSource = relPath: attrs: {
    xdg.configFile."${relPath}" = attrs;
  };

  # Declare an XDG data file. Use `force = true` on the caller side if you need to overwrite conflicts.
  mkXdgDataText = relPath: text: {
    xdg.dataFile."${relPath}".text = text;
  };

  # Declare an XDG cache file. Use `force = true` if you need to overwrite conflicts.
  mkXdgCacheText = relPath: text: {
    xdg.cacheFile."${relPath}".text = text;
  };

  # Same as mkXdgSource but for XDG data files (link-only or attr-based)
  mkXdgDataSource = relPath: attrs: {
    xdg.dataFile."${relPath}" = attrs;
  };

  # Same as mkXdgSource but for XDG cache files (link-only or attr-based)
  mkXdgCacheSource = relPath: attrs: {
    xdg.cacheFile."${relPath}" = attrs;
  };

  # Convenience: write JSON to an XDG config file
  # Usage:
  #   (xdg.mkXdgConfigJson "myapp/config.json" { enable = true; paths = ["a" "b"]; })
  mkXdgConfigJson = relPath: attrs: {
    xdg.configFile."${relPath}".text = builtins.toJSON attrs;
  };

  # Convenience: write JSON to an XDG data file
  # Usage:
  #   (xdg.mkXdgDataJson "myapp/state.json" { version = 1; })
  mkXdgDataJson = relPath: attrs: {
    xdg.dataFile."${relPath}".text = builtins.toJSON attrs;
  };

  # Convenience: write TOML to an XDG config file using nixpkgs' TOML formatter.
  # Requires passing `pkgs` when importing this helper module:
  #   let xdg = import ../../lib/xdg-helpers.nix { inherit lib pkgs; };
  mkXdgConfigToml = relPath: attrs: {
    xdg.configFile."${relPath}".source = (pkgs.formats.toml {}).generate relPath attrs;
  };

  # Convenience: write TOML to an XDG data file using nixpkgs' TOML formatter.
  mkXdgDataToml = relPath: attrs: {
    xdg.dataFile."${relPath}".source = (pkgs.formats.toml {}).generate relPath attrs;
  };
}
