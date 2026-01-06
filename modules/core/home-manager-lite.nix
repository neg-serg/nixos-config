{ config, lib, pkgs, ... }:

let
  cfg = config.users.users;

  # Define the submodule for a single file entry
  fileType = lib.types.submodule ({ name, ... }: {
    options = {
      source = lib.mkOption {
        type = lib.types.path;
        description = "Path to the source file.";
      };
      text = lib.mkOption {
        type = lib.types.nullOr lib.types.lines;
        default = null;
        description = "Text content of the file.";
      };
      target = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "Relative path of the target file (defaults to attribute name).";
      };
      executable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether the file should be executable.";
      };
    };
  });

in
{
  options.users.users = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options.homeFiles = lib.mkOption {
        type = lib.types.attrsOf fileType;
        default = { };
        description = "Set of files to be managed in the user's home directory.";
      };
    });
  };

  config.system.activationScripts = lib.mkMerge (
    lib.mapAttrsToList (user: userConfig:
      let
        files = userConfig.homeFiles;
        homeDir = userConfig.home; # NixOS defines this string option
        scriptName = "home-manager-lite-${user}";
      in
      lib.mkIf (files != { }) {
        "${scriptName}" = lib.stringAfter [ "users" ] ''
          echo "Setting up home files for ${user}..."
          
          # Run as the user to ensure correct permissions
          ${pkgs.util-linux}/bin/runuser -u ${user} -- ${pkgs.bash}/bin/bash -c '
            set -eu
            
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: file:
              let
                 # If text is provided, write it to the store and use that as source
                 src = if file.text != null 
                       then (if file.executable then pkgs.writeScript else pkgs.writeText) (builtins.baseNameOf name) file.text 
                       else file.source;
                 targetPath = "${homeDir}/${file.target}";
                 targetDir = builtins.dirOf targetPath;
              in
              ''
                mkdir -p "${targetDir}"
                
                # Atomically update symlink: creating new -> renaming over old
                ln -sfn "${src}" "${targetPath}"
              ''
            ) files)}
          '
        '';
      }
    ) cfg
  );
}
