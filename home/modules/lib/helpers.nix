{
  lib,
  pkgs,
  systemdUser,
  packagesRoot,
}: let
  mkLocalBin = import (packagesRoot + "/lib/local-bin.nix") {inherit lib;};
in rec {
  inherit mkLocalBin systemdUser;

  mkEnabledList = flags: groups: let
    names = builtins.attrNames groups;
  in
    lib.concatLists (
      builtins.map (n: lib.optionals (flags.${n} or false) (groups.${n} or [])) names
    );

  mkPackagesFromGroups = mkEnabledList;

  pnameOf = pkg: (pkg.pname or (builtins.parseDrvName (pkg.name or "")).name);
  filterByNames = names: pkgsList:
    builtins.filter (p: !(builtins.elem (pnameOf p) names)) pkgsList;

  mkWarnIf = cond: msg: {
    warnings = lib.optional cond msg;
  };

  mkBool = desc: default:
    (lib.mkEnableOption desc) // {inherit default;};

  mkWhen = cond: attrs: lib.mkIf cond attrs;
  mkUnless = cond: attrs: lib.mkIf (! cond) attrs;

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

  web.defaultBrowser = lib.mkDefault {
    name = "xdg-open";
    pkg = pkgs.xdg-utils;
    bin = "${pkgs.xdg-utils}/bin/xdg-open";
    desktop = "xdg-open.desktop";
    newTabArg = "";
  };

  mkRemoveIfSymlink = path:
    lib.hm.dag.entryBefore ["linkGeneration"] ''
      set -eu
      if [ -L "${path}" ]; then
        rm -f "${path}"
      fi
    '';

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

  mkEnsureDirsAfterWrite = paths: let
    quoted = lib.concatStringsSep " " (map (p: ''"'' + p + ''"'') paths);
  in
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      set -eu
      mkdir -p ${quoted}
    '';

  mkEnsureMaildirs = base: boxes: let
    mkLine = b: ''mkdir -p "${base}/${b}/cur" "${base}/${b}/new" "${base}/${b}/tmp"'';
    body = lib.concatStringsSep "\n" (map mkLine boxes);
  in
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      set -eu
      ${body}
    '';

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

  mkEnsureRealParent = path:
    lib.hm.dag.entryBefore ["linkGeneration"] ''
      set -eu
      parent_dir="$(dirname "${path}")"
      if [ -L "$parent_dir" ]; then
        rm -f "$parent_dir"
      fi
      mkdir -p "$parent_dir"
    '';

  mkEnsureRealParentMany = paths: let
    scriptFor = p: ''
      parent="$(dirname "${p}")"
      if [ -L "$parent" ]; then rm -f "$parent"; fi
      mkdir -p "$parent"
    '';
    body = lib.concatStringsSep "\n" (map scriptFor paths);
  in
    lib.hm.dag.entryBefore ["linkGeneration"] ''
      set -eu
      ${body}
    '';

  mkEnsureRealLinks = pairs: lib.hm.dag.entryAfter ["writeBoundary"] ''
    set -eu
    while [ $# -gt 0 ]; do
      link="$1"; target="$2"; shift 2
      if [ -L "$link" ] || [ -e "$link" ]; then rm -rf "$link"; fi
      ln -s "$target" "$link"
    done
  '';
}
