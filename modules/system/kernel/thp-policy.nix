##
# Module: system/kernel/thp-policy
# Purpose: apply the transparent-hugepage policy from sysfs at activation, so the
# 2 MiB-page policy is testable with one switch instead of a reboot.
#
# Why not a kernel parameter: `transparent_hugepage=` is parsed by the kernel only
# at boot (`profiles.performance.thpMode` -> `boot.kernelParams`, modules/system/kernel/params.nix),
# so any experiment with it costs a reboot. `/sys/kernel/mm/transparent_hugepage/*`
# is writable at runtime; this oneshot writes it during activation and the policy
# then applies to every process until the next boot.
#
# Scope: nothing but those two sysfs files, no option, no other unit. The module
# exists to answer one measured question (does 2 MiB paging help a ~3 GiB bdwgc
# heap?); to remove it, delete this file and switch — the running host keeps the
# written policy until it reboots, and the kernel default returns on that boot.
#
# Portability: a kernel built without CONFIG_TRANSPARENT_HUGEPAGE has no such
# directory; `ConditionPathExists` turns the unit into a clean no-op there instead
# of failing the activation.
let
  thpSysfs = "/sys/kernel/mm/transparent_hugepage";
  enabledPolicy = "always";
  # `defer+madvise` lets hugepage allocation use kcompactd asynchronously instead
  # of synchronous compaction inside page faults, which would stall every process
  # on the host and not just the one being measured.
  defragPolicy = "defer+madvise";
  # Measured 2026-11-03 against `always` (20 evaluator runs per arm, A-B-A-B over
  # three switches, /tmp/gcsweep/results-defrag.jsonl): the toplevel eval's minor
  # faults and instructions are unchanged (49.9k vs 49.8k in 39 of 40 runs; 82.40G
  # in both arms), wall clock differs by -0.8 % with a load-confounded SEM of
  # 0.7 %, and no `always` block reproduced its own first-block low. `always` did
  # add direct compaction: 197 `compact_stall` events in 1 of its 20 runs, the same
  # run where minor faults jumped +62 % and AnonHugePages fell 4 % -- the
  # synchronous-compaction stall this comment warns about, on a host-wide knob.
in
{
  systemd.services.thp-policy = {
    description = "Set transparent hugepage policy (enabled=${enabledPolicy}, defrag=${defragPolicy})";
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "${thpSysfs}/enabled";
    # Host state, not process state: once written it stays written, so the unit
    # is a oneshot that remains "active" and never re-runs on later rebuilds.
    # After a reboot multi-user.target starts it again.
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # Shell builtins only: no PATH entries, no runtime inputs to keep in sync.
    script = ''
      set -eu
      printf '%s\n' '${enabledPolicy}' > ${thpSysfs}/enabled
      printf '%s\n' '${defragPolicy}' > ${thpSysfs}/defrag
      echo "thp: enabled=$(<${thpSysfs}/enabled) defrag=$(<${thpSysfs}/defrag)"
    '';
  };
}
