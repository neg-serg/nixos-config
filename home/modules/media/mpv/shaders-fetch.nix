{
  lib,
  config,
  negLib,
  ...
}:
with lib; let
  cfg = config.features.media.aiUpscale or {};
  mkLocalBin = negLib.mkLocalBin;
  script = mkLocalBin "mpv-shaders-fetch" ''    #!/usr/bin/env bash
        set -euo pipefail

        force=0
        quiet=0
        while [[ $# -gt 0 ]]; do
          case "$1" in
            -f|--force) force=1; shift;;
            -q|--quiet) quiet=1; shift;;
            -h|--help)
              cat <<'USAGE'
    Usage: mpv-shaders-fetch [-f|--force] [-q|--quiet]

    Fetch common GLSL shaders for mpv into $XDG_CONFIG_HOME/mpv/shaders.
    Skips files that already exist unless --force is provided.

    Shaders:
      - FSRCNNX_x2_8-0-4-1.glsl
      - KrigBilateral.glsl
      - Anime4K_Upscale_CNN_x2_S.glsl
      - SSimSuperRes.glsl (tries multiple mirrors)
    USAGE
              exit 0
              ;;
            *) echo "Unknown option: $1" >&2; exit 2;;
          esac
        done

        cfg_home=''${XDG_CONFIG_HOME:-"$HOME/.config"}
        dir="$cfg_home/mpv/shaders"
        mkdir -p "$dir"

        fetch() {
          url="$1"; out="$2"
          dest="$dir/$out"
          if [[ -s "$dest" && $force -eq 0 ]]; then
            [[ $quiet -eq 1 ]] || echo "skip  $out (exists)"
            return 0
          fi
          tmp="$dest.tmp.$$"
          if command -v curl >/dev/null 2>&1; then
            if curl -fsSL "$url" -o "$tmp"; then
              mv -f "$tmp" "$dest"
              [[ $quiet -eq 1 ]] || echo "ok    $out"
              return 0
            fi
          elif command -v wget >/dev/null 2>&1; then
            if wget -qO "$tmp" "$url"; then
              mv -f "$tmp" "$dest"
              [[ $quiet -eq 1 ]] || echo "ok    $out"
              return 0
            fi
          else
            echo "Neither curl nor wget found in PATH" >&2
            return 1
          fi
          rm -f "$tmp" 2>/dev/null || true
          [[ $quiet -eq 1 ]] || echo "fail  $out ($url)" >&2
          return 1
        }

        # Common shaders (best-effort; failures are non-fatal)
        rc=0
        fetch "https://raw.githubusercontent.com/bjin/mpv-prescalers/master/FSRCNNX_x2_8-0-4-1.glsl" "FSRCNNX_x2_8-0-4-1.glsl" || rc=1
        fetch "https://raw.githubusercontent.com/bjin/mpv-prescalers/master/KrigBilateral.glsl" "KrigBilateral.glsl" || rc=1
        fetch "https://raw.githubusercontent.com/bloc97/Anime4K/master/glsl/Anime4K_Upscale_CNN_x2_S.glsl" "Anime4K_Upscale_CNN_x2_S.glsl" || rc=1
        # SSimSuperRes: try multiple mirrors
        if ! fetch "https://raw.githubusercontent.com/haasn/mpv-conf/master/shaders/SSimSuperRes.glsl" "SSimSuperRes.glsl"; then
          fetch "https://raw.githubusercontent.com/bjin/mpv-prescalers/master/SSimSuperRes.glsl" "SSimSuperRes.glsl" || rc=1
        fi

        exit $rc
  '';
in
  mkIf (config.features.gui.enable or false) (
    mkMerge [
      # Provide manual fetcher only when AI upscaling feature is enabled
      (mkIf (cfg.enable or false) script)
    ]
  )
