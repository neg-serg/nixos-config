{
  lib,
  pkgs,
  config,
  systemdUser ? import ./systemd-user.nix {inherit lib;},
  ...
}: let
  hmRepoPath = ../..;
  repoRoot = hmRepoPath + "/..";
  packagesRoot = repoRoot + "/packages";
in {
  # Project-specific helpers under lib.neg
  config.lib.neg = rec {
    # mkEnabledList flags groups -> concatenated list of groups
    # flags: { a = true; b = false; }
    # groups: { a = [pkg1]; b = [pkg2]; }
    # => [pkg1]
    mkEnabledList = flags: groups: let
      names = builtins.attrNames groups;
    in
      lib.concatLists (
        builtins.map (n: lib.optionals (flags.${n} or false) (groups.${n} or [])) names
      );

    # Alias
    mkPackagesFromGroups = flags: groups: (mkEnabledList flags groups);

    # Package list helpers
    pnameOf = pkg: (pkg.pname or (builtins.parseDrvName (pkg.name or "")).name);
    filterByNames = names: pkgsList:
      builtins.filter (p: !(builtins.elem (pnameOf p) names)) pkgsList;
    # Apply global excludePkgs filter to a list of packages by pname
    # Example: exclude tools like "dsniff" from curated groups without editing modules
    filterByExclude = pkgsList:
      builtins.filter (p: !(builtins.elem (pnameOf p) (config.features.excludePkgs or []))) pkgsList;

    # Shorthand: apply global excludePkgs filter to a list of packages
    # Usage (preferred explicit pkgs.* form):
    #   home.packages = config.lib.neg.pkgsList [ pkgs.foo pkgs.bar ];
    pkgsList = filterByExclude;

    # Emit a warning (non-fatal) when condition holds
    mkWarnIf = cond: msg: {
      warnings = lib.optional cond msg;
    };

    # Make an enable option with default value
    mkBool = desc: default:
      (lib.mkEnableOption desc) // {inherit default;};

    # Conditional sugar for readability in mkMerge blocks
    # Usage:
    #   lib.mkMerge [ (config.lib.neg.mkWhen cond { ... }) (config.lib.neg.mkUnless cond { ... }) ]
    mkWhen = cond: attrs: lib.mkIf cond attrs;
    mkUnless = cond: attrs: lib.mkIf (! cond) attrs;

    # mkDotfilesSymlink removed to avoid config.lib recursion in evaluation.

    # Browser addons helper: produce well-known addon lists given NUR addons set
    browserAddons = fa: {
      common = with fa; [
        augmented-steam
        cookie-quick-manager
        darkreader
        enhanced-github
        export-tabs-urls-and-titles
        lovely-forks
        search-by-image
        stylus
        tabliss
        to-google-translate
        tridactyl
      ];
    };

    # Systemd (user) helpers to avoid repeating arrays in many modules
    inherit systemdUser;

    # Web helpers defaults
    # Provide a safe fallback default browser so modules can refer to
    # config.lib.neg.web.defaultBrowser even when features.web.enable = false.
    web.defaultBrowser = lib.mkDefault {
      name = "xdg-open";
      pkg = pkgs.xdg-utils;
      bin = "${pkgs.xdg-utils}/bin/xdg-open";
      desktop = "xdg-open.desktop";
      newTabArg = "";
    };

    # Home activation DAG helpers to avoid repeating small shell snippets
    # Usage patterns:
    #   home.activation.fixZsh = config.lib.neg.mkRemoveIfSymlink "${config.xdg.configHome}/zsh";
    #   home.activation.fixGdbDir = config.lib.neg.mkEnsureRealDir "${config.xdg.configHome}/gdb";
    #   home.activation.fixTigFile = config.lib.neg.mkRemoveIfNotSymlink "${config.xdg.configHome}/tig/config";
    mkRemoveIfSymlink = path:
      lib.hm.dag.entryBefore ["linkGeneration"] ''
        set -eu
        if [ -L "${path}" ]; then
          rm -f "${path}"
        fi
      '';

    # Remove the path only if it is a broken symlink (preserve valid symlinks)
    mkRemoveIfBrokenSymlink = path:
      lib.hm.dag.entryBefore ["linkGeneration"] ''
        set -eu
        if [ -L "${path}" ] && [ ! -e "${path}" ]; then
          rm -f "${path}"
        fi
      '';

    mkEnsureRealDir = path:
      lib.hm.dag.entryBefore ["linkGeneration"] ''
        set -eu
        if [ -L "${path}" ]; then
          rm -f "${path}"
        fi
        mkdir -p "${path}"
      '';

    # Ensure multiple directories exist before linkGeneration and are real dirs (not symlinks)
    # For each path: if path is a symlink, remove it, then mkdir -p path
    mkEnsureRealDirsMany = paths: let
      quoted = lib.concatStringsSep " " (map (p: ''"'' + p + ''"'') paths);
    in
      lib.hm.dag.entryBefore ["linkGeneration"] ''
        set -eu
        for p in ${quoted}; do
          if [ -L "$p" ]; then
            rm -f "$p"
          fi
          mkdir -p "$p"
        done
      '';

    mkRemoveIfNotSymlink = path:
      lib.hm.dag.entryBefore ["linkGeneration"] ''
        set -eu
        if [ -e "${path}" ] && [ ! -L "${path}" ]; then
          rm -f "${path}"
        fi
      '';

    # Ensure directories exist after HM writes files
    # Useful for app runtime dirs that must be present before services start.
    mkEnsureDirsAfterWrite = paths: let
      quoted = lib.concatStringsSep " " (map (p: ''"'' + p + ''"'') paths);
    in
      lib.hm.dag.entryAfter ["writeBoundary"] ''
        set -eu
        mkdir -p ${quoted}
      '';

    # XDG aggregated fixups removed; prefer per-file force=true when needed.

    # Ensure a set of Maildir-style folders exist under a base path.
    # Example: mkEnsureMaildirs "$HOME/.local/mail/gmail" ["INBOX" "[Gmail]/Sent Mail" ...]
    mkEnsureMaildirs = base: boxes: let
      mkLine = b: ''mkdir -p "${base}/${b}/cur" "${base}/${b}/new" "${base}/${b}/tmp"'';
      body = lib.concatStringsSep "\n" (map mkLine boxes);
    in
      lib.hm.dag.entryAfter ["writeBoundary"] ''
        set -eu
        ${body}
      '';

    # Ensure a path is absent before HM links/writes files.
    # Removes regular files with rm -f and directories with rm -rf, ignores symlinks
    # (combine with mkRemoveIfSymlink if needed).
    mkEnsureAbsent = path:
      lib.hm.dag.entryBefore ["linkGeneration"] ''
        set -eu
        if [ -e "${path}" ] && [ ! -L "${path}" ]; then
          if [ -d "${path}" ]; then
            rm -rf "${path}"
          else
            rm -f "${path}"
          fi
        fi
      '';

    mkEnsureAbsentMany = paths: let
      scriptFor = p: ''
        if [ -e "${p}" ] && [ ! -L "${p}" ]; then
          if [ -d "${p}" ]; then rm -rf "${p}"; else rm -f "${p}"; fi
        fi
      '';
      body = lib.concatStringsSep "\n" (map scriptFor paths);
    in
      lib.hm.dag.entryBefore ["linkGeneration"] ''
        set -eu
        ${body}
      '';

    # Ensure the parent directory of a path is a real directory (not a symlink)
    # and exists. Uses dirname at runtime to avoid brittle string parsing in Nix.
    mkEnsureRealParent = path:
      lib.hm.dag.entryBefore ["linkGeneration"] ''
        set -eu
        parent_dir="$(dirname "${path}")"
        if [ -L "$parent_dir" ]; then
          rm -f "$parent_dir"
        fi
        mkdir -p "$parent_dir"
      '';

    # Create a local wrapper script under ~/.local/bin with activation-time guard.
    # See packages/lib/local-bin.nix for implementation details.
    mkLocalBin = import (packagesRoot + "/lib/local-bin.nix") {inherit lib;};

    # XDG file helpers were split into a dedicated pure helper module
    # to avoid config/lib coupling in regular modules. Prefer importing
    # modules/lib/xdg-helpers.nix locally where needed:
    #   let xdg = import ../../lib/xdg-helpers.nix { inherit lib; };
    #   in xdg.mkXdgText "path/in/config" "...contents..."
    # See STYLE.md ("XDG file helpers") for examples and guidance.
  };

  options.neg = {
    # Provide a typed option for dotfiles root
    hmConfigRoot = lib.mkOption {
      type = lib.types.path;
      default = hmRepoPath;
      description = "Absolute path to the Home Manager configuration tree (used for linking config assets).";
      example = "/etc/nixos/home";
    };

    # Optional integration points for modules under the 'neg' namespace
    quickshell = {
      wrapperPackage = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = "Wrapped quickshell package (provides 'qs') with required QT/QML env prefixes.";
        example = "pkgs.callPackage ./path/to/wrapper.nix {}";
      };
    };

    # Rofi package (single source of truth) used by wrapper and config
    rofi = {
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.rofi.override {
          plugins = [
            pkgs.rofi-file-browser # file browser mode for rofi
            pkgs.neg.rofi_games # custom games menu plugin
          ];
        };
        description = "Rofi build with required plugins (file-browser, rofi-games).";
      };
    };
  };
}
