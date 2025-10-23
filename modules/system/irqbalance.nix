{ lib, config, pkgs, ... }:
let
  inherit (lib) mkIf mkMerge types;
  cfg = config.profiles.performance.irqbalance;
in {
  options.profiles.performance.irqbalance.autoBannedFromIsolated = lib.mkOption {
    type = types.bool;
    default = true;
    description = ''
      Automatically set IRQBALANCE_BANNED_CPUS based on CPUs listed in
      kernel params nohz_full= and isolcpus=. This avoids stale masks when
      CPU isolation changes.
    '';
  };

  config = mkMerge [
    {
      # Balance hardware interrupts across CPU cores to reduce spikes on a single core
      services.irqbalance.enable = true;
    }
    (mkIf cfg.autoBannedFromIsolated {
      # Compute banned CPU mask at runtime from /proc/cmdline and expose via EnvironmentFile
      systemd.services.irqbalance = {
        preStart = ''
          set -euo pipefail
          CMDLINE=$(cat /proc/cmdline)
          get_param() {
            printf '%s' "$CMDLINE" | tr ' ' '\n' | sed -n "s/^$1=//p" | head -n1
          }
          NOHZ=$(get_param nohz_full || true)
          ISOL=$(get_param isolcpus || true)
          RAW=''${NOHZ}''${NOHZ:+,}''${ISOL}
          tmpdir=/run/irqbalance
          install -d -m 0755 "$tmpdir"
          # Expand CPU list (e.g., 14-15,30-31) to individual indices
          cpus=$(printf '%s' "$RAW" | tr ',' '\n' | while read -r tok; do
            [ -n "$tok" ] || continue
            if ! printf '%s' "$tok" | grep -Eq '^[0-9]+(-[0-9]+)?$'; then continue; fi
            if printf '%s' "$tok" | grep -q -- '-'; then
              a=''${tok%-*}; b=''${tok#*-}; seq "$a" "$b"
            else
              printf '%s\n' "$tok"
            fi
          done | sort -n | uniq)
          # Build hex mask using gawk bitwise ops
          mask=$(printf '%s\n' $cpus | awk 'NF{ for (i=1;i<=NF;i++) { cpu=$i; m = or(m, lshift(1, cpu)); } } END{ printf "0x%X\n", m+0 }')
          # Fallback to 0x0 if none parsed
          [ -n "$mask" ] || mask=0x0
          printf 'IRQBALANCE_BANNED_CPUS=%s\n' "$mask" > "$tmpdir/irqbalance.env"
        '';
        serviceConfig = {
          RuntimeDirectory = "irqbalance";
          EnvironmentFile = [ "/run/irqbalance/irqbalance.env" ];
        };
      };
    })
  ];
}
