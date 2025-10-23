{ lib, config, ... }:
let
  inherit (lib) mkIf mkMerge types;
  s = lib.strings;
  l = lib.lists;

  cfg = config.profiles.performance.irqbalance;

  # Extract a comma-joined value of a kernel parameter (may appear multiple times)
  getKParam = name:
    lib.concatStringsSep ","
      (lib.concatMap (p: if s.hasPrefix ("${name}=") p then [ (s.removePrefix ("${name}=") p) ] else [ ])
        (config.boot.kernelParams or [ ]));

  # Parse CPU set expressions like "1,2,4-7" ignoring non-numeric tokens
  parseCpuSet = (txt:
    let
      toks = lib.splitString "," txt;
      isInt = t: builtins.match "^[0-9]+$" t != null;
      isRange = t: builtins.match "^[0-9]+-[0-9]+$" t != null;
      toInt = t: builtins.fromJSON t;
      parseTok = t:
        let tt = s.trim t; in
        if tt == "" then [ ]
        else if isRange tt then
          let parts = lib.splitString "-" tt;
              a = toInt (builtins.elemAt parts 0);
              b = toInt (builtins.elemAt parts 1);
          in lib.range a b
        else if isInt tt then [ toInt tt ]
        else [ ];
    in lib.concatMap parseTok toks);

  # Collect isolated CPUs from nohz_full and isolcpus arguments
  isolatedCpus =
    let
      nohz = parseCpuSet (getKParam "nohz_full");
      isol = parseCpuSet (getKParam "isolcpus");
      all = nohz ++ isol;
    in lib.unique (lib.sort (a: b: a < b) all);

  # Convert a list of CPU indices to an uppercase hexadecimal mask string (e.g. 0xC000C000)
  toHexMask = (cpus:
    let
      has = i: lib.elem i cpus;
      maxCpu = if cpus == [ ] then 0 else builtins.elemAt cpus ((builtins.length cpus) - 1);
      lastNib = builtins.floor (maxCpu / 4);
      hexDigit = n: builtins.elemAt [
        "0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "A" "B" "C" "D" "E" "F"
      ] n;
      # Build nibbles from most-significant to least-significant
      nibbles = l.reverseList (builtins.genList (i:
        let base = i * 4; in
        (if has (base + 0) then 1 else 0)
        + (if has (base + 1) then 2 else 0)
        + (if has (base + 2) then 4 else 0)
        + (if has (base + 3) then 8 else 0)
      ) (lastNib + 1));
      hexStr = lib.concatStringsSep "" (map hexDigit nibbles);
      # Trim leading zeros; leave single zero if empty
      trimmed =
        let m = builtins.match "0*([0-9A-F]+)" hexStr; in
        if m == null then "0" else builtins.elemAt m 0;
    in "0x" + trimmed);
in
{
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
    (mkIf (cfg.autoBannedFromIsolated && isolatedCpus != [ ]) {
      # Allow hosts to override with a concrete mask via mkForce if desired
      systemd.services.irqbalance.environment.IRQBALANCE_BANNED_CPUS = lib.mkDefault (toHexMask isolatedCpus);
    })
  ];
}

