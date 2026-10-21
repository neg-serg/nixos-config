//! Built-in rulesets and the command → ruleset map.
//!
//! A ruleset is a *delta* on top of the generic classifiers: the handful of
//! words and line prefixes that only make sense for one program. Everything
//! else (sizes, addresses, paths, status words) the scanners already cover, so
//! adding a tool here is a two-line change and never a regex zoo.

use crate::theme::Kind;

/// Per-ruleset scanner switches beyond the generic defaults.
#[derive(Clone, Copy, Debug)]
pub struct ScanFlags {
    /// Colour bare numbers (table-like output).
    pub numbers: bool,
    /// Treat an alphabetic line with several column gaps as a table header.
    pub headers: bool,
    /// Colour `host:port` numbers as ports.
    pub ports: bool,
    /// Treat `key:` / `key=` pairs as keys. Off for output where a colon is
    /// prose (tracebacks, diffs).
    pub keyval: bool,
}

const NO_FLAGS: ScanFlags = ScanFlags {
    numbers: false,
    headers: false,
    ports: false,
    keyval: true,
};

const NUMBERS: ScanFlags = ScanFlags {
    numbers: true,
    headers: false,
    ports: false,
    keyval: true,
};

/// Prose output: colons are punctuation, not keys.
const PROSE: ScanFlags = ScanFlags {
    numbers: false,
    headers: false,
    ports: false,
    keyval: false,
};

const TABLE: ScanFlags = ScanFlags {
    numbers: true,
    headers: true,
    ports: false,
    // No key/value colouring: `ps` prints `--flag=value` in its COMMAND column
    // and the rest of the table has no keys at all.
    keyval: false,
};

/// Network tools: numbers, ports, no header heuristic (their headers carry
/// colons and would be mistaken for key/value pairs).
const NET: ScanFlags = ScanFlags {
    numbers: true,
    headers: false,
    ports: true,
    keyval: false,
};

/// One ruleset: an identity, its scanner switches and its own matchers.
pub struct RulesetDef {
    pub name: &'static str,
    pub about: &'static str,
    pub flags: ScanFlags,
    /// Case-sensitive words, matched on word boundaries.
    pub words: &'static [(&'static str, Kind)],
    /// Matched at the beginning of a line.
    pub lines: &'static [(&'static str, Kind)],
    /// Matched anywhere in the line, substrings included (`ValueError`).
    pub parts: &'static [(&'static str, Kind)],
}

/// Every ruleset, sorted by name for the `--list` output.
pub const RULESETS: &[RulesetDef] = &[
    RulesetDef {
        name: "cargo",
        about: "cargo build/test/clippy output",
        flags: NUMBERS,
        words: &[
            ("Compiling", Kind::Info),
            ("Finished", Kind::Ok),
            ("Running", Kind::Info),
            ("FAILED", Kind::Err),
            ("failed", Kind::Err),
            ("panicked", Kind::Err),
            ("test result", Kind::Hdr),
        ],
        lines: &[
            ("error:", Kind::Err),
            ("warning:", Kind::Warn),
            ("note:", Kind::Note),
            ("help:", Kind::Note),
            ("failures:", Kind::Err),
            ("test result:", Kind::Hdr),
        ],
        parts: &[],
    },
    RulesetDef {
        name: "curl",
        about: "curl -v / --trace transcripts",
        flags: NET,
        words: &[],
        lines: &[
            ("> ", Kind::Info),
            ("< ", Kind::Note),
            ("* ", Kind::Dim),
            ("} ", Kind::Dim),
            ("{ ", Kind::Dim),
            ("** ", Kind::Dim),
        ],
        parts: &[],
    },
    RulesetDef {
        name: "dmesg",
        about: "kernel log lines",
        flags: NO_FLAGS,
        words: &[
            ("WARNING", Kind::Warn),
            ("BUG", Kind::Err),
            ("Oops", Kind::Err),
            ("tainted", Kind::Warn),
            ("Call", Kind::Err),
            ("Trace", Kind::Err),
        ],
        lines: &[
            ("Call Trace:", Kind::Err),
            ("---[ end trace", Kind::Dim),
            ("segfault", Kind::Err),
        ],
        parts: &[],
    },
    RulesetDef {
        name: "docker",
        about: "docker/podman ps, images, logs",
        flags: NUMBERS,
        words: &[
            ("Up", Kind::Ok),
            ("Exited", Kind::Err),
            ("Restarting", Kind::Warn),
            ("Paused", Kind::Warn),
            ("Created", Kind::Info),
            ("healthy", Kind::Ok),
            ("unhealthy", Kind::Err),
            ("starting", Kind::Info),
        ],
        lines: &[],
        parts: &[],
    },
    RulesetDef {
        name: "df",
        about: "df/duf disk usage tables",
        flags: TABLE,
        words: &[("tmpfs", Kind::Dim), ("overlay", Kind::Dim)],
        lines: &[],
        parts: &[],
    },
    RulesetDef {
        name: "dig",
        about: "dig/host/nslookup answers",
        flags: NUMBERS,
        words: &[
            ("NOERROR", Kind::Ok),
            ("NXDOMAIN", Kind::Err),
            ("SERVFAIL", Kind::Err),
            ("REFUSED", Kind::Err),
            ("ANSWER", Kind::Ok),
        ],
        lines: &[
            (";; ->>HEADER<<-", Kind::Hdr),
            (";; flags:", Kind::Info),
            (";; QUESTION SECTION:", Kind::Dim),
            (";; ANSWER SECTION:", Kind::Hdr),
            (";; AUTHORITY SECTION:", Kind::Dim),
            (";; ADDITIONAL SECTION:", Kind::Dim),
            (";; SERVER:", Kind::Info),
            (";; WHEN:", Kind::Dim),
            (";; MSG SIZE", Kind::Dim),
            (";; Got answer:", Kind::Ok),
            (";; Query time:", Kind::Dim),
        ],
        parts: &[],
    },
    RulesetDef {
        name: "diff",
        about: "unified diffs without delta",
        flags: PROSE,
        words: &[],
        lines: &[
            ("+++", Kind::Add),
            ("---", Kind::Del),
            ("@@", Kind::Ctx),
            ("+", Kind::Add),
            ("-", Kind::Del),
            ("Only in", Kind::Note),
            ("diff ", Kind::Hdr),
        ],
        parts: &[],
    },
    RulesetDef {
        name: "du",
        about: "du/dust directory sizes",
        flags: NUMBERS,
        words: &[],
        lines: &[],
        parts: &[],
    },
    RulesetDef {
        name: "env",
        about: "env/printenv variable dumps",
        flags: NO_FLAGS,
        words: &[],
        lines: &[],
        parts: &[],
    },
    RulesetDef {
        name: "find",
        about: "find listings",
        flags: NO_FLAGS,
        words: &[],
        lines: &[],
        parts: &[],
    },
    RulesetDef {
        name: "free",
        about: "free memory tables",
        flags: TABLE,
        words: &[],
        lines: &[],
        parts: &[],
    },
    RulesetDef {
        name: "generic",
        about: "tool-agnostic classification, the default",
        flags: NO_FLAGS,
        words: &[],
        lines: &[],
        parts: &[],
    },
    RulesetDef {
        name: "git",
        about: "git log/diff/status piped through tint",
        flags: PROSE,
        words: &[
            ("modified", Kind::Note),
            ("deleted", Kind::Err),
            ("renamed", Kind::Note),
            ("copied", Kind::Note),
            ("Untracked", Kind::Warn),
            ("insertions", Kind::Ok),
            ("deletions", Kind::Err),
            ("Fast-forward", Kind::Ok),
            ("Merge", Kind::Info),
            ("Author", Kind::Key),
            ("Date", Kind::Key),
            ("HEAD", Kind::Info),
        ],
        lines: &[
            ("commit ", Kind::Hdr),
            ("Author:", Kind::Key),
            ("Date:", Kind::Key),
            ("Merge:", Kind::Info),
            ("diff --git", Kind::Hdr),
            ("index ", Kind::Dim),
            ("new file mode", Kind::Dim),
            ("deleted file mode", Kind::Dim),
            ("+++", Kind::Add),
            ("---", Kind::Del),
            ("@@", Kind::Ctx),
            ("+", Kind::Add),
            ("-", Kind::Del),
            ("Changes not staged for commit:", Kind::Hdr),
            ("Changes to be committed:", Kind::Hdr),
            ("Untracked files:", Kind::Hdr),
            ("modified:   ", Kind::Note),
            ("new file:   ", Kind::Add),
            ("deleted:    ", Kind::Del),
            ("renamed:    ", Kind::Note),
            ("On branch ", Kind::Info),
            ("Your branch is up to date", Kind::Ok),
            ("nothing to commit", Kind::Ok),
        ],
        parts: &[],
    },
    RulesetDef {
        name: "iptables",
        about: "iptables/nft rule dumps",
        flags: NUMBERS,
        words: &[
            ("ACCEPT", Kind::Ok),
            ("DROP", Kind::Err),
            ("REJECT", Kind::Err),
            ("MASQUERADE", Kind::Info),
            ("RETURN", Kind::Dim),
        ],
        lines: &[("Chain ", Kind::Hdr), ("table ", Kind::Hdr)],
        parts: &[],
    },
    RulesetDef {
        name: "ip",
        about: "ip addr/route/link dumps",
        flags: NET,
        words: &[
            ("UP", Kind::Ok),
            ("LOWER_UP", Kind::Ok),
            ("DOWN", Kind::Warn),
            ("NO-CARRIER", Kind::Warn),
            ("UNKNOWN", Kind::Warn),
            ("inet", Kind::Info),
            ("inet6", Kind::Info),
            ("forever", Kind::Ok),
            ("mtu", Kind::Dim),
            ("qdisc", Kind::Dim),
            ("state", Kind::Dim),
            ("permaddr", Kind::Dim),
            ("valid_lft", Kind::Dim),
            ("deprecated", Kind::Warn),
            ("tentative", Kind::Warn),
        ],
        lines: &[
            ("link/ether", Kind::Dim),
            ("link/loopback", Kind::Dim),
            ("link/none", Kind::Dim),
            ("default via", Kind::Info),
            ("broadcast", Kind::Note),
            ("local ", Kind::Note),
            ("2:", Kind::Hdr),
            ("3:", Kind::Hdr),
            ("4:", Kind::Hdr),
        ],
        parts: &[],
    },
    RulesetDef {
        name: "journalctl",
        about: "journalctl output (piped, no pager)",
        flags: NUMBERS,
        words: &[
            ("emerg", Kind::Err),
            ("alert", Kind::Err),
            ("crit", Kind::Err),
            ("err", Kind::Err),
            ("warning", Kind::Warn),
            ("notice", Kind::Info),
            ("info", Kind::Info),
        ],
        lines: &[("-- Journal begins", Kind::Dim), ("-- Boot ", Kind::Info)],
        parts: &[],
    },
    RulesetDef {
        name: "kubectl",
        about: "kubectl get/describe output",
        flags: NUMBERS,
        words: &[
            ("Running", Kind::Ok),
            ("Pending", Kind::Warn),
            ("ContainerCreating", Kind::Info),
            ("Terminating", Kind::Warn),
            ("Completed", Kind::Ok),
            ("CrashLoopBackOff", Kind::Err),
            ("ImagePullBackOff", Kind::Err),
            ("ErrImagePull", Kind::Err),
            ("OOMKilled", Kind::Err),
            ("Evicted", Kind::Err),
            ("Ready", Kind::Ok),
            ("True", Kind::Ok),
            ("False", Kind::Warn),
        ],
        lines: &[("NAME ", Kind::Hdr), ("Events:", Kind::Hdr)],
        parts: &[],
    },
    RulesetDef {
        name: "lsof",
        about: "lsof tables",
        flags: TABLE,
        words: &[],
        lines: &[],
        parts: &[],
    },
    RulesetDef {
        name: "lspci",
        about: "lspci/lsusb device listings",
        flags: NUMBERS,
        words: &[("Subsystem", Kind::Note), ("Capabilities", Kind::Note)],
        lines: &[
            ("\tKernel driver in use:", Kind::Key),
            ("\tKernel modules:", Kind::Key),
            ("\tSubsystem:", Kind::Key),
            ("\tCapabilities:", Kind::Note),
        ],
        parts: &[],
    },
    RulesetDef {
        name: "lsblk",
        about: "lsblk block device tree",
        flags: TABLE,
        words: &[
            ("disk", Kind::Info),
            ("part", Kind::Note),
            ("rom", Kind::Dim),
            ("loop", Kind::Dim),
            ("lvm", Kind::Dim),
            ("crypt", Kind::Warn),
        ],
        lines: &[],
        parts: &[],
    },
    RulesetDef {
        name: "make",
        about: "make/cmake/ninja/gcc builds",
        flags: NUMBERS,
        words: &[
            ("Error", Kind::Err),
            ("error", Kind::Err),
            ("warning", Kind::Warn),
            ("note", Kind::Note),
            ("Leaving", Kind::Dim),
            ("Entering", Kind::Dim),
        ],
        lines: &[
            ("make:", Kind::Info),
            ("make[", Kind::Dim),
            ("gcc:", Kind::Err),
            ("ld:", Kind::Err),
            ("cc ", Kind::Info),
            ("gcc ", Kind::Info),
            ("ninja:", Kind::Err),
            ("[", Kind::Dim),
        ],
        parts: &[],
    },
    RulesetDef {
        name: "mount",
        about: "mount/findmnt listings",
        flags: NUMBERS,
        words: &[("rw", Kind::Ok), ("ro", Kind::Warn), ("nosuid", Kind::Dim)],
        lines: &[],
        parts: &[],
    },
    RulesetDef {
        name: "nix",
        about: "nix/nixos-rebuild/nh build output",
        flags: NUMBERS,
        words: &[
            ("error", Kind::Err),
            ("warning", Kind::Warn),
            ("evaluating", Kind::Info),
            ("building", Kind::Info),
            ("copying", Kind::Info),
            ("fetching", Kind::Info),
            ("unpacking", Kind::Info),
            ("patching", Kind::Note),
            ("checking", Kind::Dim),
            ("installing", Kind::Ok),
            ("these", Kind::Info),
            ("derivations", Kind::Info),
            ("will", Kind::Dim),
            ("be", Kind::Dim),
            ("succeeded", Kind::Ok),
            ("failed", Kind::Err),
        ],
        lines: &[
            ("error:", Kind::Err),
            ("warning:", Kind::Warn),
            ("note:", Kind::Note),
            ("trace:", Kind::Dim),
            ("       > ", Kind::Err),
        ],
        parts: &[],
    },
    RulesetDef {
        name: "nmap",
        about: "nmap scan results",
        flags: NUMBERS,
        words: &[
            ("open", Kind::Ok),
            ("closed", Kind::Err),
            ("filtered", Kind::Warn),
            ("unfiltered", Kind::Ok),
        ],
        lines: &[
            ("Nmap scan report for", Kind::Hdr),
            ("PORT", Kind::Hdr),
            ("Host is up", Kind::Ok),
            ("Nmap done", Kind::Info),
        ],
        parts: &[],
    },
    RulesetDef {
        name: "openssl",
        about: "openssl s_client/verify output",
        flags: NUMBERS,
        words: &[("verify", Kind::Info), ("error", Kind::Err)],
        lines: &[
            ("depth=", Kind::Dim),
            ("verify return", Kind::Info),
            ("Verify return code: 0 (ok)", Kind::Ok),
            ("Verify return code", Kind::Err),
        ],
        parts: &[],
    },
    RulesetDef {
        name: "ping",
        about: "ping statistics",
        flags: NUMBERS,
        words: &[
            ("ttl", Kind::Dim),
            ("time", Kind::Dim),
            ("timeout", Kind::Err),
            ("unreachable", Kind::Err),
        ],
        lines: &[
            ("--- ", Kind::Hdr),
            ("PING ", Kind::Hdr),
            ("rtt ", Kind::Info),
        ],
        parts: &[],
    },
    RulesetDef {
        name: "ps",
        about: "ps/procs process tables",
        flags: TABLE,
        words: &[],
        lines: &[],
        parts: &[],
    },
    RulesetDef {
        name: "python",
        about: "python tracebacks and pytest runs",
        flags: PROSE,
        words: &[
            ("Error", Kind::Err),
            ("Exception", Kind::Err),
            ("Traceback", Kind::Err),
            ("Warning", Kind::Warn),
            ("FAILED", Kind::Err),
            ("PASSED", Kind::Ok),
            ("passed", Kind::Ok),
            ("failed", Kind::Err),
            ("skipped", Kind::Note),
        ],
        lines: &[
            ("Traceback (most recent call last):", Kind::Err),
            ("  File \"", Kind::Key),
            ("=====", Kind::Hdr),
            ("--- ", Kind::Hdr),
            ("during handling of the above exception", Kind::Warn),
        ],
        parts: &[
            ("Error", Kind::Err),
            ("Exception", Kind::Err),
            ("Warning", Kind::Warn),
        ],
    },
    RulesetDef {
        name: "rsync",
        about: "rsync --progress transfers",
        flags: NUMBERS,
        words: &[
            ("sent", Kind::Ok),
            ("received", Kind::Ok),
            ("total", Kind::Info),
            ("deleting", Kind::Warn),
            ("skipping", Kind::Dim),
            ("up-to-date", Kind::Note),
        ],
        lines: &[
            ("building file list", Kind::Info),
            ("Number of files:", Kind::Hdr),
        ],
        parts: &[],
    },
    RulesetDef {
        name: "sensors",
        about: "lm-sensors readings",
        flags: NUMBERS,
        words: &[("crit", Kind::Err), ("max", Kind::Dim), ("min", Kind::Dim)],
        lines: &[("Adapter:", Kind::Dim)],
        parts: &[],
    },
    RulesetDef {
        name: "smartctl",
        about: "smartctl/nvme drive health",
        flags: NUMBERS,
        words: &[
            ("PASSED", Kind::Ok),
            ("FAILED!", Kind::Err),
            ("Old_age", Kind::Dim),
            ("Pre-fail", Kind::Warn),
        ],
        lines: &[("SMART overall-health", Kind::Hdr)],
        parts: &[],
    },
    RulesetDef {
        name: "ss",
        about: "ss/netstat socket tables",
        flags: NET,
        words: &[
            ("ESTAB", Kind::Ok),
            ("LISTEN", Kind::Info),
            ("SYN-SENT", Kind::Warn),
            ("SYN-RECV", Kind::Warn),
            ("TIME-WAIT", Kind::Dim),
            ("CLOSE-WAIT", Kind::Warn),
            ("FIN-WAIT-1", Kind::Dim),
            ("FIN-WAIT-2", Kind::Dim),
            ("LAST-ACK", Kind::Warn),
            ("CLOSING", Kind::Warn),
            ("UNCONN", Kind::Dim),
        ],
        lines: &[
            ("State ", Kind::Hdr),
            ("Netid ", Kind::Hdr),
            ("Recv-Q", Kind::Hdr),
        ],
        parts: &[],
    },
    RulesetDef {
        name: "systemctl",
        about: "systemctl status (piped)",
        flags: NUMBERS,
        words: &[
            ("active", Kind::Ok),
            ("activating", Kind::Info),
            ("reloading", Kind::Info),
            ("deactivating", Kind::Warn),
            ("inactive", Kind::Warn),
            ("failed", Kind::Err),
            ("enabled", Kind::Ok),
            ("disabled", Kind::Warn),
            ("static", Kind::Dim),
            ("masked", Kind::Warn),
            ("exited", Kind::Dim),
        ],
        lines: &[
            ("●", Kind::Info),
            ("Loaded:", Kind::Key),
            ("Active:", Kind::Key),
            ("Main PID:", Kind::Key),
            ("Process:", Kind::Key),
            ("Tasks:", Kind::Key),
            ("Memory:", Kind::Key),
            ("CPU:", Kind::Key),
            ("CGroup:", Kind::Key),
            ("TriggeredBy:", Kind::Key),
            ("Drop-In:", Kind::Key),
        ],
        parts: &[],
    },
    RulesetDef {
        name: "systemd-analyze",
        about: "systemd-analyze blame/critical-chain",
        flags: NUMBERS,
        words: &[],
        lines: &[("Startup finished in", Kind::Info)],
        parts: &[],
    },
    RulesetDef {
        name: "tar",
        about: "tar/archive listings",
        flags: NUMBERS,
        words: &[],
        lines: &[("tar: ", Kind::Err)],
        parts: &[],
    },
    RulesetDef {
        name: "traceroute",
        about: "traceroute hops",
        flags: NUMBERS,
        words: &[("ms", Kind::Dim)],
        lines: &[("traceroute to", Kind::Hdr)],
        parts: &[],
    },
    RulesetDef {
        name: "uptime",
        about: "uptime/w/last sessions",
        flags: TABLE,
        words: &[("load average:", Kind::Key), ("up", Kind::Ok)],
        lines: &[],
        parts: &[],
    },
];

/// Command → ruleset map. Everything here is also inferred for `tint CMD ...`;
/// the shell integration wraps only the entries that are not in
/// [`EXPLICIT_ONLY`], unless the config asks for them.
///
/// Only commands that cannot be interactive and do not depend on a terminal for
/// progress are listed. A wrapped command sees a pipe instead of a tty, so
/// wrapping `docker` (`-it`), `kubectl` (`exec -it`), `python` (REPL),
/// `cargo`/`nix` (build progress) or `git` (pager) would quietly degrade them.
/// Those keep their ruleset and are used explicitly: `cmd | tint -r git`.
pub const WRAPPERS: &[(&str, &[&str])] = &[
    // `duf` and `dust` colour their own output and are already aliased in the
    // shell; piping them would throw their theme away.
    ("cargo", &["cargo", "rustc"]),
    ("df", &["df"]),
    ("diff", &["diff"]),
    ("dig", &["dig", "host", "nslookup"]),
    ("dmesg", &["dmesg"]),
    ("du", &["du"]),
    ("env", &["printenv"]),
    ("find", &["find"]),
    ("free", &["free"]),
    ("ip", &["ip"]),
    ("iptables", &["iptables", "nft", "ufw"]),
    ("journalctl", &["journalctl"]),
    ("lsof", &["lsof"]),
    ("lspci", &["lspci", "lsusb"]),
    ("lsblk", &["lsblk"]),
    ("mount", &["mount", "findmnt"]),
    (
        "nix",
        &["nix", "nix-build", "nixos-rebuild", "nh", "nix-store"],
    ),
    ("nmap", &["nmap"]),
    ("ping", &["ping"]),
    ("ps", &["ps"]),
    ("rsync", &["rsync"]),
    ("sensors", &["sensors"]),
    ("smartctl", &["smartctl", "nvme"]),
    ("ss", &["ss", "netstat"]),
    ("systemctl", &["systemctl"]),
    ("systemd-analyze", &["systemd-analyze"]),
    ("tar", &["tar"]),
    ("traceroute", &["traceroute"]),
    ("uptime", &["uptime", "w", "last"]),
];

/// Commands wrapped with `--pty` by default: none.
///
/// The relay hands the child a real terminal, which is what progress bars,
/// `-it` and REPLs need, but a relay bug inside a build command costs more than
/// missing colour. Opt in per command in the config:
///
///     pty = "cargo rustc nix nh nixos-rebuild rsync python3"
///
/// `PTY_WRAPPED` stays as the list of commands the shell integration *knows how*
/// to wrap this way; the config lists add to it.
pub const PTY_WRAPPED: &[&str] = &[];

/// Commands wrapped with `--pager` by default: `systemctl` only, because a
/// status fits one screen and `less -FRX` prints it and quits. Add more with
/// `pager = "journalctl"` in the config — but not follow modes (`journalctl -f`),
/// which a pager would swallow.
pub const PAGER_WRAPPED: &[&str] = &["systemctl"];

/// Rulesets that must be asked for explicitly (`cmd | tint -r NAME`) because
/// wrapping the command would hide a pager, an editor or an interactive prompt.
pub const EXPLICIT_ONLY: &[&str] = &[
    "cargo",
    "curl",
    "docker",
    "git",
    "journalctl",
    "kubectl",
    "make",
    "nix",
    "openssl",
    "python",
    "rsync",
];

/// Look a ruleset up by name.
pub fn find(name: &str) -> Option<&'static RulesetDef> {
    RULESETS.iter().find(|r| r.name == name)
}

/// The ruleset a command line should use when none was given explicitly.
pub fn for_command(command: &str) -> &'static str {
    let base = command.rsplit('/').next().unwrap_or(command);
    for (ruleset, commands) in WRAPPERS {
        if commands.contains(&base) {
            return ruleset;
        }
    }
    "generic"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_ruleset_name_is_unique() {
        let mut names: Vec<&str> = RULESETS.iter().map(|r| r.name).collect();
        names.sort_unstable();
        let count = names.len();
        names.dedup();
        assert_eq!(names.len(), count, "duplicate ruleset name");
    }

    #[test]
    fn wrapper_targets_exist() {
        for (ruleset, _) in WRAPPERS {
            assert!(find(ruleset).is_some(), "unknown ruleset {ruleset}");
        }
    }

    #[test]
    fn explicit_only_rulesets_exist() {
        for name in EXPLICIT_ONLY {
            assert!(find(name).is_some(), "unknown ruleset {name}");
        }
    }

    #[test]
    fn commands_map_to_themselves() {
        assert_eq!(for_command("df"), "df");
        assert_eq!(for_command("/usr/bin/df"), "df");
        assert_eq!(for_command("lsblk"), "lsblk");
        assert_eq!(for_command("no-such-tool"), "generic");
    }
}
