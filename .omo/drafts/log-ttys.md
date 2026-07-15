# Draft: log-ttys

## Metadata
- **intent**: clear
- **review_required**: true (high-accuracy dual review)
- **slug**: log-ttys
- **created**: 2026-07-10
- **status**: approved (high-accuracy review passed)

## High-Accuracy Review Receipts

### Round 1
- **Momus**: OKAY (3 issues: tty9 conflict, feature flag placement, auth filter)
- **Oracle**: NEEDS_FIX (4 issues: tty9, _PID=1, empty networkUnits, concatStringsSep quoting)

### Round 2 (fixes applied)
- **Momus**: OKAY
- **Oracle**: NEEDS_FIX (1 critical: _PID=1 AND logic + quote bug)

### Round 3 (fix applied)
- **Momus**: OKAY
- **Oracle**: OKAY

### Final verdict: APPROVED by both reviewers.

## Decisions (final)
1. **Classification**: Combined — priority-based (tty8, tty10-11) + subsystem-based (tty12-16)
2. **TTY range**: tty8, tty10-tty16 — tty9 reserved for debug-shell
3. **Implementation**: systemd services with `StandardOutput=tty`, zero new packages
4. **Feature flags**: Self-contained in `modules/features/system.nix`
5. **systemd filter**: `_PID=1 + -u systemd-*.service` (OR via `+` operator)

## TTY Mapping (final)
| TTY | Key | journalctl filter |
|-----|-----|-------------------|
| tty8 | CRIT | `-p 2` |
| tty9 | — | debug-shell (untouched) |
| tty10 | ERR | `-p 3` |
| tty11 | WARN | `-p 4` |
| tty12 | KERN | `_TRANSPORT=kernel` |
| tty13 | AUTH | `SYSLOG_FACILITY=4 SYSLOG_FACILITY=10` |
| tty14 | SYSD | `_PID=1 + -u systemd-*.service` |
| tty15 | NET | `-u <unit1> -u <unit2> ...` |
| tty16 | FULL | `-p 7` |
