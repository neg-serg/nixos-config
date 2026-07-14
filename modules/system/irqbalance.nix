{ lib, config, pkgs, ... }:

let
  inherit (lib) mkIf types;
  cfg = config.profiles.performance.irqbalance;

  gawkBin = lib.getExe' pkgs.gawk "awk";
  fixScript = pkgs.writeText "irq-affinity-fix.sh" ''
    #!/usr/bin/env bash
    set -euo pipefail
    ISOLATED=$(cat /sys/devices/system/cpu/isolated 2>/dev/null || echo "")
    HOUSECPUS=$(cat /proc/cmdline | tr ' ' '\n' | sed -n 's/^irqaffinity=//p' | head -n1)
    [ -n "$HOUSECPUS" ] || HOUSECPUS="4-15,20-31"
    echo "IRQ affinity fix: isolated=$ISOLATED house=$HOUSECPUS"

    MASK=$(echo "$HOUSECPUS" | tr ',' '\n' | while IFS=- read -r a b; do
      if [ -n "$b" ]; then seq "$a" "$b"; else echo "$a"; fi
    done | sort -n | uniq | ${gawkBin} '{for(i=1;i<=NF;i++) m=or(m,lshift(1,$i))} END{printf "0x%X\n",m}')

    echo "$MASK" > /proc/irq/default_smp_affinity 2>/dev/null \
      && echo "default_smp_affinity set to $MASK" \
      || echo "default_smp_affinity: FAILED"

    for f in /proc/irq/*/smp_affinity_list; do
      echo "$HOUSECPUS" > "$f" 2>/dev/null || true
    done
    echo "IRQ affinity fix done"
  '';

  # Custom package containing only the systemd unit (no drop-ins generated)
  fixUnit = pkgs.runCommandLocal "irq-affinity-unit" { } ''
    mkdir -p $out/lib/systemd/system
    cat > $out/lib/systemd/system/irq-affinity-fix.service << UNIT
[Unit]
Description=Move IRQs off isolated CPUs
After=systemd-udevd.service

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=${lib.getExe pkgs.bash} ${fixScript}
Environment=PATH=/run/wrappers/bin:/nix/store/sr26flm2nkfa12dkrwj2630kqsfakky4-coreutils-9.11/bin:/nix/store/w8xlvapzxcz23ba312q119p57bnc7200-gnugrep-3.12/bin:/nix/store/0hamsiy8hsyfw1hmizbc3bf93ad7fa1v-gnused-4.9/bin:/nix/store/arcwm5lynrra8yjn5wvbj5mr3rikmb30-systemd-260.2/bin:${pkgs.gawk}/bin

[Install]
WantedBy=multi-user.target
UNIT
  '';
in
{
  options.profiles.performance.irqbalance.autoBannedFromIsolated = lib.mkOption {
    type = types.bool;
    default = true;
    description = ''
      Set up IRQ affinity at boot to keep interrupts off isolated CPUs.
      Replaces irqbalance which is broken on systemd 260.2 (CapBnd=0 bug).
    '';
  };

  config = mkIf cfg.autoBannedFromIsolated {
    # Install the custom unit via systemd.packages — no systemd.services
    # definitions, so NixOS generates NO drop-ins, avoiding CapBnd=0 bug.
    systemd.packages = [ fixUnit ];
    systemd.targets.multi-user.wants = [ "irq-affinity-fix.service" ];
  };
}
