//! Rust port of `packages/local-bin/bin/win-vm`.
//!
//! The libvirt/QEMU Windows VM lifecycle manager. It keeps the original CLI,
//! help text, config file format, environment defaults, messages, prompts,
//! safety checks and all external argv (virsh, virt-install, virt-xml,
//! qemu-img, curl, sudo, mkdir, rm, systemctl, id, the viewers).
//!
//! `config.sh` is parsed, not sourced: assignments, quotes, escapes,
//! `$NAME`/`${NAME}` expansion and the `${NAME:-word}` family are understood;
//! the shipped template only needs `${HOME}`. This is the one place where the
//! port is intentionally narrower than zsh, and the parser is documented in
//! `win_vm_config.rs`.
//!
//! `read -q` on a non-TTY stdin fails in zsh with
//! `not interactive and can't open terminal` and the confirmation is declined;
//! the port does the same. On a TTY the port writes the same prompt to stderr
//! and reads a line (a terminal line discipline is required without unsafe
//! termios code, so Enter is needed where zsh read one character). The
//! LOCAL_BIN_ZSH_EXTRA_ASK_FILE hook lets the hermetic tests answer the prompt;
//! LOCAL_BIN_ZSH_EXTRA_LOOKING_GLASS points the Looking Glass existence checks
//! at a fixture instead of /dev/shm/looking-glass.

#![forbid(unsafe_code)]

use std::collections::BTreeMap;
use std::ffi::OsString;
use std::fs;
use std::io::{BufRead, IsTerminal, Write};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

use local_bin_zsh_extra::{
    capture_checked, err_line, err_str, out_line, out_str, raw_args, report_spawn_failure, run,
    run_ignored, split_shell_words, strip_trailing_newlines, which_str, Captured, StdioMode,
};

mod win_vm_config;

const USAGE: &str = include_str!("win_vm_usage.txt");
const CONFIG_TEMPLATE: &str = include_str!("win_vm_config_template.txt");
const DEFAULT_LOOKING_GLASS: &str = "/dev/shm/looking-glass";
const ASK_HOOK: &str = "LOCAL_BIN_ZSH_EXTRA_ASK_FILE";
const LOOKING_GLASS_HOOK: &str = "LOCAL_BIN_ZSH_EXTRA_LOOKING_GLASS";

fn main() {
    let mut arguments = raw_args();
    let no_arguments = arguments.is_empty();
    let command = arguments
        .first()
        .map(|argument| argument.to_string_lossy().into_owned())
        .unwrap_or_else(|| "help".to_string());
    if !arguments.is_empty() {
        arguments.remove(0);
    }

    let app = App::load();
    // `shift || true` still lets zsh print the diagnostic when no argument was
    // given. The line number is the original script's line 609.
    if no_arguments {
        let argv0 = std::env::args_os().next().unwrap_or_default();
        err_line(&format!(
            "{}:shift:609: shift count must be <= $#",
            argv0.to_string_lossy()
        ));
    }
    match command.as_str() {
        "init" => app.cmd_init(),
        "check" => app.cmd_check(),
        "prepare" => app.cmd_prepare(),
        "define" => app.cmd_define(),
        "start" => app.cmd_start(),
        "stop" => app.cmd_stop(),
        "kill" => app.cmd_kill(),
        "status" => app.cmd_status(),
        "edit" => app.cmd_edit(),
        "console" => app.cmd_console(),
        "undefine" => app.cmd_undefine(),
        "destroy-all" => app.cmd_destroy_all(),
        "eject-install" => app.cmd_eject_install(),
        "gpu-add" => app.cmd_gpu_add(),
        "gpu-remove" => app.cmd_gpu_remove(),
        "lg-enable" => app.cmd_lg_enable(),
        "cpupin" => app.cmd_cpupin(),
        "hugepages" => app.cmd_hugepages(),
        "usb-add" => app.cmd_usb_add(&arguments),
        "usb-remove" => app.cmd_usb_remove(&arguments),
        "looking-glass" => app.cmd_looking_glass(&arguments),
        "help" | "-h" | "--help" => out_str(USAGE),
        other => {
            err_line(&format!("unknown command: {other}"));
            out_str(USAGE);
            std::process::exit(1);
        }
    }
}

struct App {
    vars: BTreeMap<String, String>,
    config_dir: PathBuf,
    config_file: PathBuf,
    looking_glass: PathBuf,
}

impl App {
    fn load() -> Self {
        let mut vars = default_vars();
        let home = env_nonempty("HOME").map(PathBuf::from).unwrap_or_default();
        let config_root = env_nonempty("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".config"));
        let config_dir = config_root.join("win-vm");
        let config_file = config_dir.join("config.sh");
        if config_file.is_file() {
            match fs::read_to_string(&config_file) {
                Ok(text) => win_vm_config::parse_config(&text, &mut vars),
                Err(error) => {
                    err_line(&format!(
                        "error: cannot read {}: {error}",
                        config_file.display()
                    ));
                    std::process::exit(1);
                }
            }
        }
        let looking_glass = env_nonempty(LOOKING_GLASS_HOOK)
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(DEFAULT_LOOKING_GLASS));
        Self {
            vars,
            config_dir,
            config_file,
            looking_glass,
        }
    }

    fn get(&self, name: &str) -> String {
        self.vars.get(name).cloned().unwrap_or_default()
    }

    fn virsh_args(&self, rest: &[&str]) -> Vec<OsString> {
        let mut arguments = vec![
            OsString::from("--connect"),
            OsString::from(self.get("VM_URI")),
        ];
        arguments.extend(rest.iter().map(OsString::from));
        arguments
    }

    fn run_virsh(&self, rest: &[&str], stdout: StdioMode, stderr: StdioMode) -> i32 {
        run_program("virsh", "virsh", &self.virsh_args(rest), stdout, stderr)
    }

    fn capture_virsh(&self, rest: &[&str], stderr: StdioMode) -> Option<Captured> {
        capture_checked("virsh", "virsh", &self.virsh_args(rest), stderr)
    }

    fn vm_exists(&self) -> bool {
        self.run_virsh(
            &["dominfo", &self.get("VM_NAME")],
            StdioMode::Null,
            StdioMode::Null,
        ) == 0
    }

    fn vm_running(&self) -> bool {
        match self.capture_virsh(&["domstate", &self.get("VM_NAME")], StdioMode::Null) {
            Some(captured) => strip_trailing_newlines(captured.stdout) == b"running",
            None => false,
        }
    }

    fn require_defined(&self) {
        if !self.vm_exists() {
            die(&format!(
                "VM '{}' is not defined — run 'win-vm define' first",
                self.get("VM_NAME")
            ));
        }
    }

    fn require_stopped(&self) {
        if self.vm_running() {
            die(&format!(
                "VM '{}' is running — stop it first",
                self.get("VM_NAME")
            ));
        }
    }

    fn net_state(&self) -> String {
        let network = self.get("VM_NETWORK");
        let Some(captured) = self.capture_virsh(&["net-info", &network], StdioMode::Null) else {
            return String::new();
        };
        let text = String::from_utf8_lossy(&captured.stdout);
        let mut states = Vec::new();
        for line in text.split('\n') {
            if line.starts_with("Active:") {
                if let Some(field) = line.split_whitespace().nth(1) {
                    states.push(field.to_string());
                }
            }
        }
        states.join("\n")
    }

    fn confirm(&self, prompt: &str) -> bool {
        let line = format!("{prompt} [y/N] ");
        if let Some(file) = env_nonempty(ASK_HOOK) {
            let answer = fs::read_to_string(file)
                .ok()
                .and_then(|text| text.lines().next().map(str::to_string))
                .unwrap_or_default();
            err_str(&line);
            out_str("\n");
            return answer == "y";
        }
        if std::io::stdin().is_terminal() {
            err_str(&line);
            let _ = std::io::stderr().flush();
            let mut answer = String::new();
            let _ = std::io::stdin().lock().read_line(&mut answer);
            out_str("\n");
            // zsh's read -q stores the character verbatim and the script then
            // compares it with lowercase "y" only.
            return answer.strip_suffix('\n').unwrap_or(&answer) == "y";
        }
        err_line("not interactive and can't open terminal");
        out_str("\n");
        false
    }

    // ─── Subcommands ────────────────────────────────────────────────────────

    fn cmd_init(&self) {
        let status = run_program(
            "mkdir",
            "mkdir",
            &[
                OsString::from("-p"),
                self.config_dir.as_os_str().to_os_string(),
            ],
            StdioMode::Inherit,
            StdioMode::Inherit,
        );
        if status != 0 {
            std::process::exit(status);
        }
        if self.config_file.is_file() {
            die(&format!(
                "config already exists at {} (delete it to regenerate)",
                self.config_file.display()
            ));
        }
        if let Err(error) = fs::write(&self.config_file, CONFIG_TEMPLATE) {
            err_line(&format!(
                "error: cannot write {}: {error}",
                self.config_file.display()
            ));
            std::process::exit(1);
        }
        info(&format!("created {}", self.config_file.display()));
        info("edit it, then run: win-vm check && win-vm define");
    }

    fn cmd_check(&self) {
        info("checking prerequisites...");
        let mut missing = Vec::new();
        for binary in ["virt-install", "virt-xml", "virsh", "qemu-img", "curl"] {
            if which_str(binary).is_none() {
                missing.push(binary.to_string());
            }
        }
        let ovmf_code = self.get("VM_OVMF_CODE");
        if !Path::new(&ovmf_code).is_file() {
            missing.push(format!("OVMF_CODE: {ovmf_code}"));
        }
        let ovmf_vars = self.get("VM_OVMF_VARS_TEMPLATE");
        if !Path::new(&ovmf_vars).is_file() {
            missing.push(format!("OVMF_VARS: {ovmf_vars}"));
        }
        if !missing.is_empty() {
            die(&format!("missing: {}", missing.join(", ")));
        }

        let groups = capture_checked(
            "cmd_check",
            "id",
            &[OsString::from("-nG")],
            StdioMode::Inherit,
        )
        .map(|captured| String::from_utf8_lossy(&captured.stdout).into_owned())
        .unwrap_or_default();
        if !groups.split_whitespace().any(|group| group == "libvirtd") {
            let user = env_nonempty("USER").unwrap_or_default();
            warn(&format!(
                "user not in 'libvirtd' group; run: sudo usermod -aG libvirtd {user} && relogin"
            ));
        }

        if run_program(
            "cmd_check",
            "systemctl",
            &[
                OsString::from("is-active"),
                OsString::from("--quiet"),
                OsString::from("libvirtd.service"),
            ],
            StdioMode::Null,
            StdioMode::Null,
        ) != 0
        {
            warn("libvirtd.service not active; run: sudo systemctl enable --now libvirtd.service");
        }

        let network = self.get("VM_NETWORK");
        if self.net_state() != "yes" {
            warn(&format!(
                "libvirt network '{network}' is not active — will be started on 'define'"
            ));
        }

        if which_str("swtpm").is_none() {
            warn("swtpm not installed — Win11 TPM will fail");
        }

        info("checks passed");
    }

    fn cmd_prepare(&self) {
        self.cmd_check();

        let network = self.get("VM_NETWORK");
        if self.net_state() != "yes" {
            info(&format!("starting libvirt network '{network}'"));
            checked(
                "cmd_prepare",
                "virsh",
                &self.virsh_args(&["net-start", &network]),
                StdioMode::Inherit,
                StdioMode::Inherit,
            );
            let status = run_ignored(
                "cmd_prepare",
                "virsh",
                &self.virsh_args(&["net-autostart", &network]),
                StdioMode::Inherit,
            );
            let _ = status;
        }

        let virtio = self.get("VM_VIRTIO_ISO");
        if !Path::new(&virtio).is_file() {
            info(&format!("downloading virtio-win ISO → {virtio}"));
            let directory = head(&virtio);
            checked(
                "cmd_prepare",
                "sudo",
                &os_args(&["mkdir", "-p", &directory]),
                StdioMode::Inherit,
                StdioMode::Inherit,
            );
            checked(
                "cmd_prepare",
                "sudo",
                &os_args(&[
                    "curl",
                    "-fL",
                    "--progress-bar",
                    &self.get("VM_VIRTIO_ISO_URL"),
                    "-o",
                    &virtio,
                ]),
                StdioMode::Inherit,
                StdioMode::Inherit,
            );
        }

        let windows = self.get("VM_WINDOWS_ISO");
        if !Path::new(&windows).is_file() {
            die(&format!(
                "Windows ISO not found: {windows}\n    download it from https://www.microsoft.com/software-download/windows11\n    and set VM_WINDOWS_ISO in {}",
                self.config_file.display()
            ));
        }

        let disk = self.get("VM_DISK_PATH");
        if !Path::new(&disk).is_file() {
            let size = self.get("VM_DISK_SIZE_GB");
            info(&format!("creating disk image {disk} ({size} GB)"));
            let directory = head(&disk);
            checked(
                "cmd_prepare",
                "sudo",
                &os_args(&["mkdir", "-p", &directory]),
                StdioMode::Inherit,
                StdioMode::Inherit,
            );
            checked(
                "cmd_prepare",
                "sudo",
                &os_args(&[
                    "qemu-img",
                    "create",
                    "-f",
                    "qcow2",
                    "-o",
                    "preallocation=off",
                    &disk,
                    &format!("{size}G"),
                ]),
                StdioMode::Null,
                StdioMode::Inherit,
            );
            // 2>/dev/null || true
            let _ = run(
                "sudo",
                &os_args(&["chown", "root:root", &disk]),
                StdioMode::Inherit,
                StdioMode::Null,
            );
        }
    }

    fn cmd_define(&self) {
        self.cmd_prepare();

        if self.vm_exists() {
            die(&format!(
                "VM '{}' already defined — 'win-vm undefine' first, or 'win-vm edit' to modify",
                self.get("VM_NAME")
            ));
        }

        let name = self.get("VM_NAME");
        info(&format!("defining VM '{name}' via virt-install"));

        let mut arguments: Vec<OsString> = vec![
            OsString::from("--connect"),
            OsString::from(self.get("VM_URI")),
            OsString::from("--name"),
            OsString::from(&name),
            OsString::from("--memory"),
            OsString::from(self.get("VM_RAM_MB")),
            OsString::from("--vcpus"),
            OsString::from(format!(
                "sockets={},cores={},threads={}",
                self.get("VM_CPU_SOCKETS"),
                self.get("VM_CPU_CORES"),
                self.get("VM_CPU_THREADS")
            )),
            OsString::from("--cpu"),
            OsString::from(self.get("VM_CPU_MODEL")),
            OsString::from("--os-variant"),
            OsString::from(self.get("VM_OS_VARIANT")),
            OsString::from("--machine"),
            OsString::from("q35"),
            OsString::from("--features"),
            OsString::from("smm.state=on"),
            OsString::from("--boot"),
            OsString::from(format!(
                "loader={},loader.readonly=yes,loader.type=pflash,loader.secure=yes,nvram.template={}",
                self.get("VM_OVMF_CODE"),
                self.get("VM_OVMF_VARS_TEMPLATE")
            )),
            OsString::from("--tpm"),
            OsString::from("model=tpm-tis,backend.type=emulator,backend.version=2.0"),
            OsString::from("--sound"),
            OsString::from("ich9"),
            OsString::from("--disk"),
            OsString::from(format!(
                "path={},bus={},cache={},discard=unmap",
                self.get("VM_DISK_PATH"),
                self.get("VM_DISK_BUS"),
                self.get("VM_DISK_CACHE")
            )),
            OsString::from("--cdrom"),
            OsString::from(self.get("VM_WINDOWS_ISO")),
            OsString::from("--disk"),
            OsString::from(format!(
                "path={},device=cdrom,bus=sata",
                self.get("VM_VIRTIO_ISO")
            )),
            OsString::from("--network"),
            OsString::from(format!(
                "{}={},model=virtio",
                self.get("VM_NETWORK_TYPE"),
                self.get("VM_NETWORK")
            )),
            OsString::from("--noautoconsole"),
            OsString::from("--noreboot"),
            OsString::from("--wait"),
            OsString::from("0"),
        ];

        match self.get("VM_GRAPHICS").as_str() {
            "spice" => {
                arguments.push(OsString::from("--graphics"));
                arguments.push(OsString::from("spice,listen=none"));
                arguments.push(OsString::from("--video"));
                arguments.push(OsString::from("virtio"));
            }
            "none" => {
                arguments.push(OsString::from("--graphics"));
                arguments.push(OsString::from("none"));
            }
            other => die(&format!(
                "unknown VM_GRAPHICS: {other} (expected: spice | none)"
            )),
        }

        if self.get("VM_HUGEPAGES") == "yes" {
            arguments.push(OsString::from("--memorybacking"));
            arguments.push(OsString::from("hugepages=yes"));
        }

        checked(
            "cmd_define",
            "virt-install",
            &arguments,
            StdioMode::Inherit,
            StdioMode::Inherit,
        );

        info("VM defined.");
        info("");
        info("Next steps:");
        info("  win-vm start                 # boot the VM");
        info(&format!(
            "  virt-viewer -c {} {}   # view the console / run installer",
            self.get("VM_URI"),
            name
        ));
        info("");
        info("After Windows install completes:");
        info("  win-vm eject-install         # remove install ISOs");
        if !self.get("VM_GPU_PCI_BDF").is_empty() {
            info("  win-vm gpu-add               # attach GPU");
        }
        if !self.get("VM_CPU_PIN_SET").is_empty() {
            info("  win-vm cpupin                # pin vCPUs");
        }
    }

    fn cmd_start(&self) {
        self.require_defined();
        if self.vm_running() {
            info(&format!("VM '{}' is already running", self.get("VM_NAME")));
            return;
        }
        checked(
            "cmd_start",
            "virsh",
            &self.virsh_args(&["start", &self.get("VM_NAME")]),
            StdioMode::Inherit,
            StdioMode::Inherit,
        );
        info(&format!("VM '{}' started", self.get("VM_NAME")));
    }

    fn cmd_stop(&self) {
        self.require_defined();
        if !self.vm_running() {
            info(&format!("VM '{}' is already stopped", self.get("VM_NAME")));
            return;
        }
        checked(
            "cmd_stop",
            "virsh",
            &self.virsh_args(&["shutdown", &self.get("VM_NAME")]),
            StdioMode::Inherit,
            StdioMode::Inherit,
        );
        info("ACPI shutdown sent; use 'win-vm kill' to force off");
    }

    fn cmd_kill(&self) {
        self.require_defined();
        if !self.vm_running() {
            info(&format!("VM '{}' is already stopped", self.get("VM_NAME")));
            return;
        }
        checked(
            "cmd_kill",
            "virsh",
            &self.virsh_args(&["destroy", &self.get("VM_NAME")]),
            StdioMode::Inherit,
            StdioMode::Inherit,
        );
        info(&format!("VM '{}' forced off", self.get("VM_NAME")));
    }

    fn cmd_status(&self) {
        if !self.vm_exists() {
            out_line(&format!("VM '{}': not defined", self.get("VM_NAME")));
            return;
        }
        let status = self.run_virsh(
            &["dominfo", &self.get("VM_NAME")],
            StdioMode::Inherit,
            StdioMode::Inherit,
        );
        std::process::exit(status);
    }

    fn cmd_edit(&self) {
        self.require_defined();
        let status = self.run_virsh(
            &["edit", &self.get("VM_NAME")],
            StdioMode::Inherit,
            StdioMode::Inherit,
        );
        std::process::exit(status);
    }

    fn cmd_console(&self) {
        self.require_defined();
        if self.get("VM_GRAPHICS") == "none" && self.looking_glass.exists() {
            self.cmd_looking_glass(&[]);
        }
        let uri = match self.capture_virsh(&["domdisplay", &self.get("VM_NAME")], StdioMode::Null) {
            Some(captured) if captured.status == 0 => {
                String::from_utf8_lossy(&strip_trailing_newlines(captured.stdout)).into_owned()
            }
            _ => {
                exec_tool(
                    "cmd_console",
                    "virt-viewer",
                    &[
                        OsString::from("--connect"),
                        OsString::from(self.get("VM_URI")),
                        OsString::from(self.get("VM_NAME")),
                    ],
                );
            }
        };
        if which_str("spicy").is_some() {
            exec_tool(
                "cmd_console",
                "spicy",
                &[OsString::from("--uri"), OsString::from(uri)],
            );
        } else if which_str("remote-viewer").is_some() {
            exec_tool("cmd_console", "remote-viewer", &[OsString::from(uri)]);
        } else {
            exec_tool(
                "cmd_console",
                "virt-viewer",
                &[
                    OsString::from("--connect"),
                    OsString::from(self.get("VM_URI")),
                    OsString::from(self.get("VM_NAME")),
                ],
            );
        }
    }

    fn cmd_undefine(&self) {
        self.require_defined();
        self.require_stopped();
        if !self.confirm(&format!(
            "Undefine VM '{}' (disk and nvram will be kept)?",
            self.get("VM_NAME")
        )) {
            return;
        }
        checked(
            "cmd_undefine",
            "virsh",
            &self.virsh_args(&["undefine", "--nvram", &self.get("VM_NAME")]),
            StdioMode::Inherit,
            StdioMode::Inherit,
        );
        info(&format!("VM '{}' undefined", self.get("VM_NAME")));
    }

    fn cmd_destroy_all(&self) {
        self.require_stopped();
        err_line(&format!(
            "This will REMOVE the VM, its disk ({}), and its nvram.",
            self.get("VM_DISK_PATH")
        ));
        if !self.confirm("Are you absolutely sure?") {
            return;
        }
        if self.vm_exists() {
            let first = self.run_virsh(
                &[
                    "undefine",
                    "--nvram",
                    "--remove-all-storage",
                    &self.get("VM_NAME"),
                ],
                StdioMode::Inherit,
                StdioMode::Null,
            );
            if first != 0 {
                checked(
                    "cmd_destroy_all",
                    "virsh",
                    &self.virsh_args(&["undefine", "--nvram", &self.get("VM_NAME")]),
                    StdioMode::Inherit,
                    StdioMode::Inherit,
                );
            }
        }
        let disk = self.get("VM_DISK_PATH");
        if Path::new(&disk).is_file() {
            checked(
                "cmd_destroy_all",
                "sudo",
                &os_args(&["rm", "-f", &disk]),
                StdioMode::Inherit,
                StdioMode::Inherit,
            );
        }
        info(&format!(
            "VM '{}' and its storage removed",
            self.get("VM_NAME")
        ));
    }

    fn cmd_eject_install(&self) {
        self.require_defined();
        let name = self.get("VM_NAME");
        info(&format!("ejecting install ISOs from VM '{name}'"));
        for iso in [self.get("VM_WINDOWS_ISO"), self.get("VM_VIRTIO_ISO")] {
            let captured =
                match self.capture_virsh(&["domblklist", &name, "--details"], StdioMode::Inherit) {
                    Some(captured) => captured,
                    None => std::process::exit(127),
                };
            if captured.status != 0 {
                std::process::exit(captured.status);
            }
            let text = String::from_utf8_lossy(&captured.stdout);
            let mut targets = Vec::new();
            for line in text.split('\n') {
                let fields: Vec<&str> = line.split_whitespace().collect();
                if fields.len() >= 4 && fields[0] == "cdrom" && fields[3] == iso {
                    targets.push(fields[2].to_string());
                }
            }
            let target = targets.join("\n");
            if target.is_empty() {
                continue;
            }
            info(&format!("  ejecting {target} ({iso})"));
            let status = self.run_virsh(
                &["change-media", &name, &target, "--eject", "--config"],
                StdioMode::Inherit,
                StdioMode::Inherit,
            );
            if status != 0 {
                warn(&format!("  failed to eject {target}"));
            }
        }
    }

    fn cmd_gpu_add(&self) {
        self.require_defined();
        self.require_stopped();
        let bdf = self.get("VM_GPU_PCI_BDF");
        if bdf.is_empty() {
            die(&format!(
                "VM_GPU_PCI_BDF is empty; set it in {}",
                self.config_file.display()
            ));
        }
        info(&format!(
            "attaching GPU {bdf} to VM '{}'",
            self.get("VM_NAME")
        ));
        checked(
            "cmd_gpu_add",
            "virt-xml",
            &virt_xml_args(
                &self.get("VM_URI"),
                &self.get("VM_NAME"),
                "--add-device",
                &bdf_to_nodedev(&bdf),
            ),
            StdioMode::Inherit,
            StdioMode::Inherit,
        );

        let audio = self.get("VM_GPU_AUDIO_BDF");
        if !audio.is_empty() {
            info(&format!("attaching GPU audio function {audio}"));
            checked(
                "cmd_gpu_add",
                "virt-xml",
                &virt_xml_args(
                    &self.get("VM_URI"),
                    &self.get("VM_NAME"),
                    "--add-device",
                    &bdf_to_nodedev(&audio),
                ),
                StdioMode::Inherit,
                StdioMode::Inherit,
            );
        }
        info("GPU added. Next: win-vm lg-enable (for Looking Glass) or set VM_GRAPHICS=none");
    }

    fn cmd_gpu_remove(&self) {
        self.require_defined();
        self.require_stopped();
        let bdf = self.get("VM_GPU_PCI_BDF");
        if bdf.is_empty() {
            die("VM_GPU_PCI_BDF is empty");
        }
        info(&format!("detaching GPU from VM '{}'", self.get("VM_NAME")));
        let _ = run_ignored(
            "cmd_gpu_remove",
            "virt-xml",
            &virt_xml_args(
                &self.get("VM_URI"),
                &self.get("VM_NAME"),
                "--remove-device",
                &bdf_to_nodedev(&bdf),
            ),
            StdioMode::Inherit,
        );
        let audio = self.get("VM_GPU_AUDIO_BDF");
        if !audio.is_empty() {
            let _ = run_ignored(
                "cmd_gpu_remove",
                "virt-xml",
                &virt_xml_args(
                    &self.get("VM_URI"),
                    &self.get("VM_NAME"),
                    "--remove-device",
                    &bdf_to_nodedev(&audio),
                ),
                StdioMode::Inherit,
            );
        }
    }

    fn cmd_lg_enable(&self) {
        self.require_defined();
        self.require_stopped();
        let size = self.get("VM_LOOKING_GLASS_SIZE_MB");
        info(&format!("adding IVSHMEM shmem device ({size} MB)"));

        let shmem_xml = PathBuf::from(format!("/tmp/win-vm-shmem-{}.xml", std::process::id()));
        let xml = format!(
            "<shmem name='looking-glass'>\n  <model type='ivshmem-plain'/>\n  <size unit='M'>{size}</size>\n</shmem>\n"
        );
        if let Err(error) = fs::write(&shmem_xml, xml) {
            err_line(&format!(
                "error: cannot write {}: {error}",
                shmem_xml.display()
            ));
            std::process::exit(1);
        }
        checked(
            "cmd_lg_enable",
            "virsh",
            &self.virsh_args(&[
                "attach-device",
                &self.get("VM_NAME"),
                &shmem_xml.to_string_lossy(),
                "--config",
            ]),
            StdioMode::Inherit,
            StdioMode::Inherit,
        );
        checked(
            "cmd_lg_enable",
            "rm",
            &os_args(&["-f", &shmem_xml.to_string_lossy()]),
            StdioMode::Inherit,
            StdioMode::Inherit,
        );

        if !self.looking_glass.exists() {
            warn("/dev/shm/looking-glass missing — run: sudo systemd-tmpfiles --create");
        }

        info("IVSHMEM added. Install the Looking Glass host app inside Windows:");
        info("  https://looking-glass.io/downloads");
        info(&format!(
            "Then set VM_GRAPHICS=none in {} and run: win-vm looking-glass",
            self.config_file.display()
        ));
    }

    fn cmd_cpupin(&self) {
        self.require_defined();
        self.require_stopped();
        let pin = self.get("VM_CPU_PIN_SET");
        if pin.is_empty() {
            die(&format!(
                "VM_CPU_PIN_SET is empty; set it in {}",
                self.config_file.display()
            ));
        }
        let pin_set = split_shell_words(&pin);
        let total = zsh_int(&self.get("VM_CPU_SOCKETS"))
            * zsh_int(&self.get("VM_CPU_CORES"))
            * zsh_int(&self.get("VM_CPU_THREADS"));
        if pin_set.len() as i64 != total {
            die(&format!(
                "VM_CPU_PIN_SET has {} entries, expected {total} (sockets*cores*threads)",
                pin_set.len()
            ));
        }
        info(&format!(
            "pinning {total} vCPUs to host cores: {}",
            pin_set.join(" ")
        ));
        for index in 0..total.max(0) {
            checked(
                "cmd_cpupin",
                "virsh",
                &self.virsh_args(&[
                    "vcpupin",
                    &self.get("VM_NAME"),
                    &index.to_string(),
                    pin_set[index as usize],
                    "--config",
                ]),
                StdioMode::Inherit,
                StdioMode::Inherit,
            );
        }
    }

    fn cmd_hugepages(&self) {
        self.require_defined();
        self.require_stopped();
        checked(
            "cmd_hugepages",
            "virt-xml",
            &virt_xml_edit(&self.get("VM_URI"), &self.get("VM_NAME")),
            StdioMode::Inherit,
            StdioMode::Inherit,
        );
        let half = zsh_int(&self.get("VM_RAM_MB")) / 2;
        info(&format!(
            "hugepages enabled. Pre-allocate on host: sudo sysctl vm.nr_hugepages={half}"
        ));
    }

    fn cmd_usb_add(&self, arguments: &[OsString]) {
        self.require_defined();
        let id = arguments
            .first()
            .map(|argument| argument.to_string_lossy().into_owned())
            .unwrap_or_default();
        if id.is_empty() {
            die("usage: win-vm usb-add VENDOR:PRODUCT (e.g. 0951:16ae)");
        }
        if !id.contains(':') {
            die("bad format: expected VENDOR:PRODUCT");
        }
        let xml = usb_xml(&id);
        let path = PathBuf::from(format!("/tmp/win-vm-usb-{}.xml", std::process::id()));
        if let Err(error) = fs::write(&path, xml) {
            err_line(&format!("error: cannot write {}: {error}", path.display()));
            std::process::exit(1);
        }
        let running = self.vm_running();
        checked(
            "cmd_usb_add",
            "virsh",
            &self.virsh_args(&[
                "attach-device",
                &self.get("VM_NAME"),
                &path.to_string_lossy(),
                if running { "--live" } else { "--config" },
            ]),
            StdioMode::Inherit,
            StdioMode::Inherit,
        );
        checked(
            "cmd_usb_add",
            "rm",
            &os_args(&["-f", &path.to_string_lossy()]),
            StdioMode::Inherit,
            StdioMode::Inherit,
        );
        info(&format!(
            "USB {id} attached to VM '{}'",
            self.get("VM_NAME")
        ));
    }

    fn cmd_usb_remove(&self, arguments: &[OsString]) {
        self.require_defined();
        let id = arguments
            .first()
            .map(|argument| argument.to_string_lossy().into_owned())
            .unwrap_or_default();
        if id.is_empty() {
            die("usage: win-vm usb-remove VENDOR:PRODUCT");
        }
        let xml = usb_xml(&id);
        let path = PathBuf::from(format!("/tmp/win-vm-usb-{}.xml", std::process::id()));
        if let Err(error) = fs::write(&path, xml) {
            err_line(&format!("error: cannot write {}: {error}", path.display()));
            std::process::exit(1);
        }
        let running = self.vm_running();
        checked(
            "cmd_usb_remove",
            "virsh",
            &self.virsh_args(&[
                "detach-device",
                &self.get("VM_NAME"),
                &path.to_string_lossy(),
                if running { "--live" } else { "--config" },
            ]),
            StdioMode::Inherit,
            StdioMode::Inherit,
        );
        checked(
            "cmd_usb_remove",
            "rm",
            &os_args(&["-f", &path.to_string_lossy()]),
            StdioMode::Inherit,
            StdioMode::Inherit,
        );
    }

    fn cmd_looking_glass(&self, extra: &[OsString]) {
        self.require_defined();
        if !self.looking_glass.exists() {
            die("/dev/shm/looking-glass missing; run 'win-vm lg-enable' first");
        }
        let mut arguments = vec![
            OsString::from("-f"),
            self.looking_glass.as_os_str().to_os_string(),
            OsString::from("-F"),
            OsString::from("-s"),
        ];
        arguments.extend(extra.iter().cloned());
        exec_tool("cmd_looking_glass", "looking-glass-client", &arguments);
    }
}

fn default_vars() -> BTreeMap<String, String> {
    let mut vars = BTreeMap::new();
    win_vm_config::set_default(&mut vars, "VM_NAME", "win11");
    win_vm_config::set_default(&mut vars, "VM_OS_VARIANT", "win11");
    win_vm_config::set_default(&mut vars, "VM_RAM_MB", "16384");
    win_vm_config::set_default(&mut vars, "VM_CPU_SOCKETS", "1");
    win_vm_config::set_default(&mut vars, "VM_CPU_CORES", "4");
    win_vm_config::set_default(&mut vars, "VM_CPU_THREADS", "2");
    win_vm_config::set_default(&mut vars, "VM_CPU_MODEL", "host-passthrough");
    let name = vars.get("VM_NAME").cloned().unwrap_or_default();
    win_vm_config::set_default(
        &mut vars,
        "VM_DISK_PATH",
        &format!("/var/lib/libvirt/images/{name}.qcow2"),
    );
    win_vm_config::set_default(&mut vars, "VM_DISK_SIZE_GB", "80");
    win_vm_config::set_default(&mut vars, "VM_DISK_BUS", "virtio");
    win_vm_config::set_default(&mut vars, "VM_DISK_CACHE", "writeback");
    let home = env_nonempty("HOME").unwrap_or_default();
    win_vm_config::set_default(
        &mut vars,
        "VM_WINDOWS_ISO",
        &format!("{home}/Downloads/Win11.iso"),
    );
    win_vm_config::set_default(
        &mut vars,
        "VM_VIRTIO_ISO",
        "/var/lib/libvirt/images/virtio-win.iso",
    );
    win_vm_config::set_default(
        &mut vars,
        "VM_VIRTIO_ISO_URL",
        "https://github.com/virtio-win/virtio-win-pkg-scripts/releases/latest/download/virtio-win.iso",
    );
    win_vm_config::set_default(
        &mut vars,
        "VM_OVMF_CODE",
        "/run/libvirt/nix-ovmf/OVMF_CODE.secboot.fd",
    );
    win_vm_config::set_default(
        &mut vars,
        "VM_OVMF_VARS_TEMPLATE",
        "/run/libvirt/nix-ovmf/OVMF_VARS.fd",
    );
    win_vm_config::set_default(&mut vars, "VM_NETWORK", "default");
    win_vm_config::set_default(&mut vars, "VM_NETWORK_TYPE", "network");
    win_vm_config::set_default(&mut vars, "VM_GRAPHICS", "spice");
    win_vm_config::set_default(&mut vars, "VM_GPU_PCI_BDF", "");
    win_vm_config::set_default(&mut vars, "VM_GPU_AUDIO_BDF", "");
    win_vm_config::set_default(&mut vars, "VM_LOOKING_GLASS_SIZE_MB", "128");
    win_vm_config::set_default(&mut vars, "VM_CPU_PIN_SET", "");
    win_vm_config::set_default(&mut vars, "VM_HUGEPAGES", "no");
    win_vm_config::set_default(&mut vars, "VM_USB_DEVICES", "");
    win_vm_config::set_default(&mut vars, "VM_URI", "qemu:///system");
    vars
}

fn env_nonempty(name: &str) -> Option<String> {
    std::env::var_os(name)
        .filter(|value| !value.is_empty())
        .map(|value| value.to_string_lossy().into_owned())
}

fn os_args(arguments: &[&str]) -> Vec<OsString> {
    arguments.iter().map(OsString::from).collect()
}

fn virt_xml_args(uri: &str, name: &str, operation: &str, device: &str) -> Vec<OsString> {
    vec![
        OsString::from("--connect"),
        OsString::from(uri),
        OsString::from(name),
        OsString::from(operation),
        OsString::from("--hostdev"),
        OsString::from(device),
    ]
}

fn virt_xml_edit(uri: &str, name: &str) -> Vec<OsString> {
    vec![
        OsString::from("--connect"),
        OsString::from(uri),
        OsString::from(name),
        OsString::from("--edit"),
        OsString::from("--memorybacking"),
        OsString::from("hugepages=yes"),
    ]
}

/// `0000:03:00.0` -> `pci_0000_03_00_0`.
fn bdf_to_nodedev(bdf: &str) -> String {
    let replaced: String = bdf
        .chars()
        .map(|character| match character {
            ':' | '.' => '_',
            other => other,
        })
        .collect();
    format!("pci_{replaced}")
}

fn usb_xml(id: &str) -> String {
    let (vendor, product) = match id.rsplit_once(':') {
        Some((prefix, _)) => {
            let product = id.split_once(':').map(|(_, suffix)| suffix).unwrap_or("");
            (prefix, product)
        }
        None => (id, ""),
    };
    format!(
        "<hostdev mode='subsystem' type='usb' managed='yes'>\n  <source>\n    <vendor id='0x{vendor}'/>\n    <product id='0x{product}'/>\n  </source>\n</hostdev>\n"
    )
}

fn zsh_int(text: &str) -> i64 {
    text.trim().parse::<i64>().unwrap_or(0)
}

/// zsh `${path:h}`.
fn head(path: &str) -> String {
    match Path::new(path).parent() {
        Some(parent) if parent.as_os_str().is_empty() => ".".to_string(),
        Some(parent) => parent.to_string_lossy().into_owned(),
        None => "/".to_string(),
    }
}

fn info(message: &str) {
    out_line(&format!("==> {message}"));
}

fn warn(message: &str) {
    err_line(&format!("warn: {message}"));
}

fn die(message: &str) -> ! {
    err_line(&format!("error: {message}"));
    std::process::exit(1);
}

fn run_program(
    site: &str,
    tool: &str,
    arguments: &[OsString],
    stdout: StdioMode,
    stderr: StdioMode,
) -> i32 {
    match run(tool, arguments, stdout, stderr) {
        Ok(status) => status,
        Err(error) => report_spawn_failure(site, tool, &error, stderr),
    }
}

fn checked(site: &str, tool: &str, arguments: &[OsString], stdout: StdioMode, stderr: StdioMode) {
    let status = run_program(site, tool, arguments, stdout, stderr);
    if status != 0 {
        std::process::exit(status);
    }
}

fn exec_tool(site: &str, tool: &str, arguments: &[OsString]) -> ! {
    let error = Command::new(tool).args(arguments).exec();
    let status = report_spawn_failure(site, tool, &error, StdioMode::Inherit);
    std::process::exit(status)
}
