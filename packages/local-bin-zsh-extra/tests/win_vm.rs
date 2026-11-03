//! Hermetic tests for the `win-vm` port.
//!
//! Every external tool is a fake first on an otherwise empty PATH: virsh,
//! virt-install, virt-xml, qemu-img, curl, sudo, mkdir, rm, systemctl, id and
//! the viewers. The config points at fixture files under the per-case tree, and
//! the Looking Glass path is redirected through
//! LOCAL_BIN_ZSH_EXTRA_LOOKING_GLASS, so no real libvirt domain, disk, nvram,
//! /dev/shm file or system service is ever touched.

mod support;

use std::fs;
use std::path::PathBuf;
use std::process::{Command, Output};

use support::{exited, expected_argv, stderr, stdout, tool_script, Case, MKDIR};

const BIN: &str = env!("CARGO_BIN_EXE_win-vm");
const USAGE: &str = include_str!("../src/win_vm_usage.txt");
const TEMPLATE: &str = include_str!("../src/win_vm_config_template.txt");

const VIRSH: &str = r#"#!/bin/sh
{ printf 'virsh\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/virsh.argv"
printf '%s\n' "$3" >> "$FAKE_LOG_DIR/virsh.calls"
case "$3" in
  dominfo) exit "${FAKE_VIRSH_DOMINFO_CODE:-1}" ;;
  domstate) printf '%s' "${FAKE_VIRSH_DOMSTATE:-shut off}"; exit "${FAKE_VIRSH_DOMSTATE_CODE:-0}" ;;
  net-info) printf '%s' "${FAKE_VIRSH_NETINFO:-Active: yes}"; exit 0 ;;
  domblklist) printf '%s' "${FAKE_VIRSH_DOMBLLIST-}"; exit "${FAKE_VIRSH_DOMBLLIST_CODE:-0}" ;;
  domdisplay) printf '%s' "${FAKE_VIRSH_DOMDISPLAY-}"; exit "${FAKE_VIRSH_DOMDISPLAY_CODE:-0}" ;;
  attach-device)
    if [ -n "${FAKE_VIRSH_DEVICE_COPY-}" ]; then
      while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line"; done < "$5" > "$FAKE_VIRSH_DEVICE_COPY"
    fi
    exit "${FAKE_VIRSH_ATTACH_CODE:-0}"
    ;;
  detach-device) exit "${FAKE_VIRSH_DETACH_CODE:-0}" ;;
  change-media) exit "${FAKE_VIRSH_CHANGE_CODE:-0}" ;;
  undefine)
    case " $* " in
      *--remove-all-storage*) exit "${FAKE_VIRSH_REMOVE_ALL_CODE:-0}" ;;
    esac
    exit "${FAKE_VIRSH_UNDEFINE_CODE:-0}"
    ;;
  *) exit "${FAKE_VIRSH_CODE:-0}" ;;
esac
"#;

const SUDO: &str = r#"#!/bin/sh
{ printf 'sudo\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/sudo.argv"
exec "$@"
"#;

const RM: &str = r#"#!/bin/sh
{ printf 'rm\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/rm.argv"
exec "${LOCAL_BIN_ZSH_EXTRA_TEST_RM:-/bin/rm}" "$@"
"#;

const QEMU_IMG: &str = r#"#!/bin/sh
{ printf 'qemu-img\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/qemu-img.argv"
previous=""
last=""
for a in "$@"; do previous="$last"; last="$a"; done
if [ -n "$previous" ]; then : > "$previous"; fi
exit "${FAKE_QEMU_IMG_CODE:-0}"
"#;

const CURL: &str = r#"#!/bin/sh
{ printf 'curl\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/curl.argv"
output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ -n "$output" ]; then : > "$output"; fi
exit "${FAKE_CURL_CODE:-0}"
"#;

const ID: &str = r#"#!/bin/sh
{ printf 'id\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/id.argv"
printf '%s\n' "${FAKE_ID_GROUPS:-neg libvirtd}"
exit "${FAKE_ID_CODE:-0}"
"#;

fn tool_fake(name: &str) -> String {
    let prefix = name.to_ascii_uppercase().replace('-', "_");
    tool_script(name, &prefix)
}

fn base_case(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("virsh", VIRSH);
    case.write_fake("mkdir", MKDIR);
    case.write_fake("rm", RM);
    case.write_fake("sudo", SUDO);
    case.write_fake("qemu-img", QEMU_IMG);
    case.write_fake("curl", CURL);
    case.write_fake("id", ID);
    for tool in [
        "virt-install",
        "virt-xml",
        "systemctl",
        "chown",
        "swtpm",
        "spicy",
        "remote-viewer",
        "virt-viewer",
        "looking-glass-client",
    ] {
        case.write_fake(tool, &tool_fake(tool));
    }
    case
}

struct Fixture {
    ovmf_code: String,
    ovmf_vars: String,
    windows: String,
    virtio: String,
    disk: String,
    config: PathBuf,
}

fn standard_config(case: &Case) -> Fixture {
    let fixtures = case.path("fixtures");
    fs::create_dir_all(&fixtures).expect("fixtures");
    for name in [
        "OVMF_CODE.fd",
        "OVMF_VARS.fd",
        "win.iso",
        "virtio.iso",
        "disk.qcow2",
    ] {
        fs::write(fixtures.join(name), b"fixture").expect("write fixture");
    }
    let fixture = Fixture {
        ovmf_code: fixtures.join("OVMF_CODE.fd").to_string_lossy().into_owned(),
        ovmf_vars: fixtures.join("OVMF_VARS.fd").to_string_lossy().into_owned(),
        windows: fixtures.join("win.iso").to_string_lossy().into_owned(),
        virtio: fixtures.join("virtio.iso").to_string_lossy().into_owned(),
        disk: fixtures.join("disk.qcow2").to_string_lossy().into_owned(),
        config: case.path("xdg/config/win-vm/config.sh"),
    };
    let text = format!(
        "VM_NAME=\"testvm\"\n\
         VM_OVMF_CODE=\"{code}\"\n\
         VM_OVMF_VARS_TEMPLATE=\"{vars}\"\n\
         VM_WINDOWS_ISO=\"{windows}\"\n\
         VM_VIRTIO_ISO=\"{virtio}\"\n\
         VM_VIRTIO_ISO_URL=\"https://example.invalid/virtio-win.iso\"\n\
         VM_DISK_PATH=\"{disk}\"\n",
        code = fixture.ovmf_code,
        vars = fixture.ovmf_vars,
        windows = fixture.windows,
        virtio = fixture.virtio,
        disk = fixture.disk,
    );
    case.write(&fixture.config, &text);
    fixture
}

fn append_config(case: &Case, lines: &str) {
    let path = case.path("xdg/config/win-vm/config.sh");
    let mut text = case.read_at(&path);
    text.push_str(lines);
    case.write(&path, &text);
}

fn run(case: &Case, arguments: &[&str], environment: &[(&str, &str)]) -> Output {
    let mut command = case.command();
    command.args(arguments);
    for (name, value) in environment {
        command.env(name, value);
    }
    command.output().expect("run win-vm")
}

fn run_in(case: &Case, directory: &std::path::Path, arguments: &[&str]) -> Output {
    case.command_in(directory)
        .args(arguments)
        .output()
        .expect("run win-vm")
}

fn full_command(case: &Case) -> Command {
    case.command()
}

#[test]
fn help_is_the_default_and_ignores_the_config() {
    let case = Case::new("win-help", BIN);
    for arguments in [&[][..], &["help"][..], &["-h"][..], &["--help"][..]] {
        let output = case.run(arguments);
        assert_eq!(exited(&output), 0, "{arguments:?}");
        assert_eq!(stdout(&output), USAGE, "{arguments:?}");
        let expected_error = if arguments.is_empty() {
            format!("{BIN}:shift:609: shift count must be <= $#\n")
        } else {
            String::new()
        };
        assert_eq!(stderr(&output), expected_error, "{arguments:?}");
    }
}

#[test]
fn an_unknown_command_prints_the_help_and_exits_one() {
    let case = Case::new("win-unknown", BIN);
    let output = case.run(&["bogus"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(stderr(&output), "unknown command: bogus\n");
    assert_eq!(stdout(&output), USAGE);
}

#[test]
fn init_writes_the_embedded_template_and_refuses_to_overwrite() {
    let case = base_case("win-init");
    let output = case.run(&["init"]);
    assert_eq!(exited(&output), 0);
    let config = case.path("xdg/config/win-vm/config.sh");
    assert_eq!(case.read_at(&config), TEMPLATE);
    assert_eq!(
        stdout(&output),
        format!(
            "==> created {}\n==> edit it, then run: win-vm check && win-vm define\n",
            config.display()
        )
    );
    assert_eq!(
        case.argv("mkdir"),
        expected_argv(
            "mkdir",
            &["-p", &case.path("xdg/config/win-vm").to_string_lossy()]
        )
    );

    let second = case.run(&["init"]);
    assert_eq!(exited(&second), 1);
    assert_eq!(
        stderr(&second),
        format!(
            "error: config already exists at {} (delete it to regenerate)\n",
            config.display()
        )
    );
}

#[test]
fn init_falls_back_to_home_config_without_xdg_config_home() {
    let case = base_case("win-init-home");
    let mut command = full_command(&case);
    command.env_remove("XDG_CONFIG_HOME");
    command.arg("init");
    let output = command.output().expect("run win-vm init");
    assert_eq!(exited(&output), 0);
    assert!(case.home.join(".config/win-vm/config.sh").exists());
}

#[test]
fn check_lists_the_missing_binaries() {
    let case = Case::new("win-check-missing-bin", BIN);
    standard_config(&case);
    case.write_fake("mkdir", MKDIR);
    let output = case.run(&["check"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(stdout(&output), "==> checking prerequisites...\n");
    assert_eq!(
        stderr(&output),
        "error: missing: virt-install, virt-xml, virsh, qemu-img, curl\n"
    );
}

#[test]
fn check_lists_missing_firmware_files() {
    let case = base_case("win-check-missing-ovmf");
    standard_config(&case);
    append_config(
        &case,
        "VM_OVMF_CODE=\"/no/such/CODE.fd\"\nVM_OVMF_VARS_TEMPLATE=\"/no/such/VARS.fd\"\n",
    );
    let output = case.run(&["check"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "error: missing: OVMF_CODE: /no/such/CODE.fd, OVMF_VARS: /no/such/VARS.fd\n"
    );
}

#[test]
fn check_warns_about_group_service_network_and_swtpm() {
    let case = base_case("win-check-warns");
    let fixture = standard_config(&case);
    case.remove_fake("swtpm");
    let output = run(
        &case,
        &["check"],
        &[
            ("FAKE_ID_GROUPS", "neg wheel"),
            ("FAKE_SYSTEMCTL_CODE", "3"),
            ("FAKE_VIRSH_NETINFO", "Active: no\n"),
            ("USER", "neg"),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        "==> checking prerequisites...\n==> checks passed\n"
    );
    assert_eq!(
        stderr(&output),
        "warn: user not in 'libvirtd' group; run: sudo usermod -aG libvirtd neg && relogin\n\
         warn: libvirtd.service not active; run: sudo systemctl enable --now libvirtd.service\n\
         warn: libvirt network 'default' is not active — will be started on 'define'\n\
         warn: swtpm not installed — Win11 TPM will fail\n"
    );
    assert!(case.argv("virsh").contains(&expected_argv(
        "virsh",
        &["--connect", "qemu:///system", "net-info", "default"]
    )));
    let _ = fixture;
}

#[test]
fn check_passes_quietly_when_everything_is_present() {
    let case = base_case("win-check-clean");
    standard_config(&case);
    let output = case.run(&["check"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        "==> checking prerequisites...\n==> checks passed\n"
    );
    assert_eq!(stderr(&output), "");
}

#[test]
fn prepare_starts_the_network_and_downloads_the_virtio_iso() {
    let case = base_case("win-prepare-download");
    let fixture = standard_config(&case);
    let virtio = case.path("new/virtio.iso");
    append_config(&case, &format!("VM_VIRTIO_ISO=\"{}\"\n", virtio.display()));
    let output = run(
        &case,
        &["prepare"],
        &[
            ("FAKE_VIRSH_NETINFO", "Active: no\n"),
            ("FAKE_VIRSH_NETSTART_CODE", "0"),
        ],
    );
    assert_eq!(exited(&output), 0, "{}", stderr(&output));
    assert!(virtio.exists());
    assert!(stdout(&output).contains("==> starting libvirt network 'default'\n"));
    assert!(stdout(&output).contains(&format!(
        "==> downloading virtio-win ISO → {}\n",
        virtio.display()
    )));
    let _ = fixture;
    let virsh = case.argv("virsh");
    assert!(
        virsh.contains(&expected_argv(
            "virsh",
            &["--connect", "qemu:///system", "net-start", "default"]
        )),
        "{virsh}"
    );
    assert!(
        virsh.contains(&expected_argv(
            "virsh",
            &["--connect", "qemu:///system", "net-autostart", "default"]
        )),
        "{virsh}"
    );
    assert!(case.argv("curl").contains("ARG --progress-bar\n"));
    assert!(case
        .argv("curl")
        .contains("ARG https://example.invalid/virtio-win.iso\n"));
    assert!(case
        .argv("curl")
        .contains(&format!("ARG {}\n", virtio.display())));
}

#[test]
fn prepare_creates_the_disk_image_and_ignores_chown_failure() {
    let case = base_case("win-prepare-disk");
    standard_config(&case);
    let disk = case.path("new/disk.qcow2");
    append_config(&case, &format!("VM_DISK_PATH=\"{}\"\n", disk.display()));
    let output = run(&case, &["prepare"], &[("FAKE_CHOWN_CODE", "1")]);
    assert_eq!(exited(&output), 0, "{}", stderr(&output));
    assert!(disk.exists());
    assert!(stdout(&output).contains(&format!(
        "==> creating disk image {} (80 GB)\n",
        disk.display()
    )));
    assert!(
        case.argv("qemu-img")
            .contains(&format!("ARG {}\nARG 80G\n", disk.display())),
        "{}",
        case.argv("qemu-img")
    );
    assert!(case.argv("sudo").contains(&format!(
        "ARG chown\nARG root:root\nARG {}\n",
        disk.display()
    )));
}

#[test]
fn prepare_reports_a_missing_windows_iso_with_the_original_text() {
    let case = base_case("win-prepare-no-windows");
    let fixture = standard_config(&case);
    let missing = case.path("missing/Win11.iso");
    append_config(
        &case,
        &format!("VM_WINDOWS_ISO=\"{}\"\n", missing.display()),
    );
    let output = case.run(&["prepare"]);
    assert_eq!(exited(&output), 1);
    let config = fixture.config.display();
    assert_eq!(
        stderr(&output),
        format!(
            "error: Windows ISO not found: {}\n    download it from https://www.microsoft.com/software-download/windows11\n    and set VM_WINDOWS_ISO in {config}\n",
            missing.display()
        )
    );
}

#[test]
fn define_builds_the_exact_virt_install_argv() {
    let case = base_case("win-define");
    let fixture = standard_config(&case);
    fs::write(case.home.join("win.iso"), b"home iso").expect("home iso");
    append_config(
        &case,
        "VM_NAME=\"vm1\"\n\
         VM_RAM_MB=8192\n\
         # a comment between assignments\n\
         VM_CPU_SOCKETS=1\n\
         VM_CPU_CORES=2\n\
         VM_CPU_THREADS=2\n\
         VM_GPU_PCI_BDF=\"0000:03:00.0\"\n\
         VM_GPU_AUDIO_BDF=\"0000:03:00.1\"\n\
         VM_CPU_PIN_SET=\"0 1 2 3\"\n\
         VM_HUGEPAGES=\"yes\"\n\
         VM_WINDOWS_ISO=\"${HOME}/win.iso\"\n\
         VM_OS_VARIANT='win11'\n",
    );
    let output = case.run(&["define"]);
    assert_eq!(exited(&output), 0, "{}", stderr(&output));
    let boot = format!(
        "loader={},loader.readonly=yes,loader.type=pflash,loader.secure=yes,nvram.template={}",
        fixture.ovmf_code, fixture.ovmf_vars
    );
    let disk = format!(
        "path={},bus=virtio,cache=writeback,discard=unmap",
        fixture.disk
    );
    let virtio = format!("path={},device=cdrom,bus=sata", fixture.virtio);
    let expected = expected_argv(
        "virt-install",
        &[
            "--connect",
            "qemu:///system",
            "--name",
            "vm1",
            "--memory",
            "8192",
            "--vcpus",
            "sockets=1,cores=2,threads=2",
            "--cpu",
            "host-passthrough",
            "--os-variant",
            "win11",
            "--machine",
            "q35",
            "--features",
            "smm.state=on",
            "--boot",
            &boot,
            "--tpm",
            "model=tpm-tis,backend.type=emulator,backend.version=2.0",
            "--sound",
            "ich9",
            "--disk",
            &disk,
            "--cdrom",
            &case.home.join("win.iso").to_string_lossy(),
            "--disk",
            &virtio,
            "--network",
            "network=default,model=virtio",
            "--noautoconsole",
            "--noreboot",
            "--wait",
            "0",
            "--graphics",
            "spice,listen=none",
            "--video",
            "virtio",
            "--memorybacking",
            "hugepages=yes",
        ],
    );
    assert_eq!(case.argv("virt-install"), expected);
    let output_text = stdout(&output);
    for line in [
        "==> defining VM 'vm1' via virt-install",
        "==> VM defined.",
        "==> Next steps:",
        "==>   win-vm start                 # boot the VM",
        "==> After Windows install completes:",
        "==>   win-vm eject-install         # remove install ISOs",
        "==>   win-vm gpu-add               # attach GPU",
        "==>   win-vm cpupin                # pin vCPUs",
    ] {
        assert!(
            output_text.contains(line),
            "missing {line:?} in {output_text}"
        );
    }
}

#[test]
fn define_refuses_a_defined_domain() {
    let case = base_case("win-define-existing");
    standard_config(&case);
    let output = run(&case, &["define"], &[("FAKE_VIRSH_DOMINFO_CODE", "0")]);
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "error: VM 'testvm' already defined — 'win-vm undefine' first, or 'win-vm edit' to modify\n"
    );
    assert_eq!(case.argv("virt-install"), "");
}

#[test]
fn define_rejects_an_unknown_graphics_mode() {
    let case = base_case("win-define-graphics");
    standard_config(&case);
    append_config(&case, "VM_GRAPHICS=\"vnc\"\n");
    let output = case.run(&["define"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "error: unknown VM_GRAPHICS: vnc (expected: spice | none)\n"
    );
    assert_eq!(case.argv("virt-install"), "");
}

#[test]
fn start_stop_kill_and_status_use_the_expected_verbs() {
    let case = base_case("win-lifecycle");
    standard_config(&case);
    let output = run(
        &case,
        &["start"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("FAKE_VIRSH_DOMSTATE", "shut off"),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert!(stdout(&output).contains("==> VM 'testvm' started\n"));
    assert!(case.argv("virsh").contains(&expected_argv(
        "virsh",
        &["--connect", "qemu:///system", "start", "testvm"]
    )));

    case.clear_logs();
    let output = run(
        &case,
        &["start"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("FAKE_VIRSH_DOMSTATE", "running"),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "==> VM 'testvm' is already running\n");
    assert!(!case.argv("virsh").contains("ARG start\n"));

    case.clear_logs();
    let output = run(
        &case,
        &["stop"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("FAKE_VIRSH_DOMSTATE", "running"),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        "==> ACPI shutdown sent; use 'win-vm kill' to force off\n"
    );
    assert!(case.argv("virsh").contains("ARG shutdown\n"));

    case.clear_logs();
    let output = run(
        &case,
        &["kill"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("FAKE_VIRSH_DOMSTATE", "running"),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "==> VM 'testvm' forced off\n");
    assert!(case.argv("virsh").contains("ARG destroy\n"));

    case.clear_logs();
    let output = run(&case, &["status"], &[("FAKE_VIRSH_DOMINFO_CODE", "1")]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "VM 'testvm': not defined\n");
}

#[test]
fn stop_and_kill_on_a_stopped_vm_are_no_ops() {
    let case = base_case("win-stopped");
    standard_config(&case);
    for command in ["stop", "kill"] {
        let output = run(
            &case,
            &[command],
            &[
                ("FAKE_VIRSH_DOMINFO_CODE", "0"),
                ("FAKE_VIRSH_DOMSTATE", "shut off"),
            ],
        );
        assert_eq!(exited(&output), 0);
        assert_eq!(
            stdout(&output),
            "==> VM 'testvm' is already stopped\n",
            "{command}"
        );
    }
}

#[test]
fn edit_runs_virsh_edit() {
    let case = base_case("win-edit");
    standard_config(&case);
    let output = run(&case, &["edit"], &[("FAKE_VIRSH_DOMINFO_CODE", "0")]);
    assert_eq!(exited(&output), 0);
    assert!(case.argv("virsh").contains(&expected_argv(
        "virsh",
        &["--connect", "qemu:///system", "edit", "testvm"]
    )));
}

#[test]
fn undefine_declines_without_a_terminal() {
    let case = base_case("win-undefine-no-tty");
    standard_config(&case);
    let output = run(
        &case,
        &["undefine"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("FAKE_VIRSH_DOMSTATE", "shut off"),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "\n");
    assert_eq!(stderr(&output), "not interactive and can't open terminal\n");
    assert!(!case.argv("virsh").contains("ARG undefine\n"));
}

#[test]
fn undefine_accepts_through_the_test_confirmation_file() {
    let case = base_case("win-undefine-yes");
    standard_config(&case);
    let answers = case.path("answers");
    fs::write(&answers, "y\n").expect("answers");
    let output = run(
        &case,
        &["undefine"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("FAKE_VIRSH_DOMSTATE", "shut off"),
            ("LOCAL_BIN_ZSH_EXTRA_ASK_FILE", &answers.to_string_lossy()),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "\n==> VM 'testvm' undefined\n");
    assert_eq!(
        stderr(&output),
        "Undefine VM 'testvm' (disk and nvram will be kept)? [y/N] "
    );
    assert!(case.argv("virsh").contains(&expected_argv(
        "virsh",
        &[
            "--connect",
            "qemu:///system",
            "undefine",
            "--nvram",
            "testvm"
        ]
    )));
}

#[test]
fn destroy_all_declines_without_a_terminal() {
    let case = base_case("win-destroy-cancel");
    let fixture = standard_config(&case);
    let output = run(
        &case,
        &["destroy-all"],
        &[("FAKE_VIRSH_DOMSTATE", "shut off")],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "\n");
    assert_eq!(
        stderr(&output),
        format!(
            "This will REMOVE the VM, its disk ({}), and its nvram.\nnot interactive and can't open terminal\n",
            fixture.disk
        )
    );
    assert_eq!(case.argv("sudo"), "");
}

#[test]
fn destroy_all_accepts_and_falls_back_from_remove_all_storage() {
    let case = base_case("win-destroy-yes");
    let fixture = standard_config(&case);
    let answers = case.path("answers");
    fs::write(&answers, "y\n").expect("answers");
    let output = run(
        &case,
        &["destroy-all"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("FAKE_VIRSH_DOMSTATE", "shut off"),
            ("FAKE_VIRSH_REMOVE_ALL_CODE", "1"),
            ("LOCAL_BIN_ZSH_EXTRA_ASK_FILE", &answers.to_string_lossy()),
        ],
    );
    assert_eq!(exited(&output), 0, "{}", stderr(&output));
    assert!(stdout(&output).ends_with("==> VM 'testvm' and its storage removed\n"));
    let virsh = case.argv("virsh");
    assert!(
        virsh.contains(&expected_argv(
            "virsh",
            &[
                "--connect",
                "qemu:///system",
                "undefine",
                "--nvram",
                "--remove-all-storage",
                "testvm"
            ]
        )),
        "{virsh}"
    );
    assert!(
        virsh.contains(&expected_argv(
            "virsh",
            &[
                "--connect",
                "qemu:///system",
                "undefine",
                "--nvram",
                "testvm"
            ]
        )),
        "{virsh}"
    );
    assert!(virsh.find("--remove-all-storage").unwrap() < virsh.rfind("undefine").unwrap());
    assert_eq!(
        case.argv("sudo"),
        expected_argv("sudo", &["rm", "-f", &fixture.disk])
    );
}

#[test]
fn eject_install_keeps_the_original_awk_filter() {
    // The shell checks $1 == "cdrom" on `domblklist --details`, but the first
    // column is the type (`file`), so real output matches nothing. The port
    // preserves that filter; this fixture is the real column layout.
    let case = base_case("win-eject-real-layout");
    let fixture = standard_config(&case);
    let domblklist = format!(
        " Type   Device   Target   Source\n\
         file   disk     vda      {}\n\
         file   cdrom    sda      {}\n\
         file   cdrom    sdb      {}\n",
        fixture.disk, fixture.windows, fixture.virtio
    );
    let output = run(
        &case,
        &["eject-install"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("FAKE_VIRSH_DOMBLLIST", domblklist.as_str()),
        ],
    );
    assert_eq!(exited(&output), 0, "{}", stderr(&output));
    assert!(stdout(&output).contains("==> ejecting install ISOs from VM 'testvm'\n"));
    assert!(!stdout(&output).contains("==>   ejecting "));
    assert!(!case.argv("virsh").contains("ARG change-media\n"));
}

#[test]
fn eject_install_uses_change_media_when_the_filter_matches() {
    let case = base_case("win-eject");
    let fixture = standard_config(&case);
    // A synthetic row whose first field is `cdrom`, which is what the shell's
    // awk filter actually asks for.
    let domblklist = format!(
        "cdrom cdrom sda {}\ncdrom cdrom sdb {}\n",
        fixture.windows, fixture.virtio
    );
    let output = run(
        &case,
        &["eject-install"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("FAKE_VIRSH_DOMBLLIST", domblklist.as_str()),
        ],
    );
    assert_eq!(exited(&output), 0, "{}", stderr(&output));
    assert!(stdout(&output).contains(&format!("==>   ejecting sda ({})\n", fixture.windows)));
    assert!(stdout(&output).contains(&format!("==>   ejecting sdb ({})\n", fixture.virtio)));
    let virsh = case.argv("virsh");
    assert!(
        virsh.contains(&expected_argv(
            "virsh",
            &[
                "--connect",
                "qemu:///system",
                "change-media",
                "testvm",
                "sda",
                "--eject",
                "--config"
            ]
        )),
        "{virsh}"
    );
    assert!(
        virsh.contains(&expected_argv(
            "virsh",
            &[
                "--connect",
                "qemu:///system",
                "change-media",
                "testvm",
                "sdb",
                "--eject",
                "--config"
            ]
        )),
        "{virsh}"
    );
}

#[test]
fn a_failing_eject_only_warns() {
    let case = base_case("win-eject-fail");
    let fixture = standard_config(&case);
    let domblklist = format!("cdrom cdrom sda {}\n", fixture.windows);
    let output = run(
        &case,
        &["eject-install"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("FAKE_VIRSH_DOMBLLIST", domblklist.as_str()),
            ("FAKE_VIRSH_CHANGE_CODE", "1"),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert!(stderr(&output).contains("warn:   failed to eject sda\n"));
}

#[test]
fn gpu_add_and_remove_convert_the_bdf() {
    let case = base_case("win-gpu");
    standard_config(&case);
    append_config(
        &case,
        "VM_GPU_PCI_BDF=\"0000:03:00.0\"\nVM_GPU_AUDIO_BDF=\"0000:03:00.1\"\n",
    );
    let output = run(&case, &["gpu-add"], &[("FAKE_VIRSH_DOMINFO_CODE", "0")]);
    assert_eq!(exited(&output), 0, "{}", stderr(&output));
    let mut expected = expected_argv(
        "virt-xml",
        &[
            "--connect",
            "qemu:///system",
            "testvm",
            "--add-device",
            "--hostdev",
            "pci_0000_03_00_0",
        ],
    );
    expected.push_str(&expected_argv(
        "virt-xml",
        &[
            "--connect",
            "qemu:///system",
            "testvm",
            "--add-device",
            "--hostdev",
            "pci_0000_03_00_1",
        ],
    ));
    assert_eq!(case.argv("virt-xml"), expected);
    assert!(stdout(&output).contains(
        "==> GPU added. Next: win-vm lg-enable (for Looking Glass) or set VM_GRAPHICS=none\n"
    ));

    case.clear_logs();
    let output = run(&case, &["gpu-remove"], &[("FAKE_VIRSH_DOMINFO_CODE", "0")]);
    assert_eq!(exited(&output), 0);
    assert!(case.argv("virt-xml").contains("ARG --remove-device\n"));
}

#[test]
fn gpu_commands_require_a_bdf() {
    let case = base_case("win-gpu-empty");
    standard_config(&case);
    let output = run(&case, &["gpu-add"], &[("FAKE_VIRSH_DOMINFO_CODE", "0")]);
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        format!(
            "error: VM_GPU_PCI_BDF is empty; set it in {}\n",
            case.path("xdg/config/win-vm/config.sh").display()
        )
    );
}

#[test]
fn lg_enable_writes_the_shmem_xml_and_warns_about_the_missing_device() {
    let case = base_case("win-lg");
    standard_config(&case);
    append_config(&case, "VM_LOOKING_GLASS_SIZE_MB=256\n");
    let copy = case.path("shmem-copy.xml");
    let output = run(
        &case,
        &["lg-enable"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("FAKE_VIRSH_DEVICE_COPY", &copy.to_string_lossy()),
            (
                "LOCAL_BIN_ZSH_EXTRA_LOOKING_GLASS",
                &case.path("no-looking-glass").to_string_lossy(),
            ),
        ],
    );
    assert_eq!(exited(&output), 0, "{}", stderr(&output));
    assert_eq!(
        case.read_at(&copy),
        "<shmem name='looking-glass'>\n  <model type='ivshmem-plain'/>\n  <size unit='M'>256</size>\n</shmem>\n"
    );
    assert!(stderr(&output)
        .contains("warn: /dev/shm/looking-glass missing — run: sudo systemd-tmpfiles --create\n"));
    assert!(stdout(&output).contains("==> adding IVSHMEM shmem device (256 MB)\n"));
    assert!(case.argv("rm").contains("ARG -f\n"));
    assert!(case.argv("virsh").contains("ARG --config\n"));
}

#[test]
fn cpupin_pins_every_vcpu_and_validates_the_count() {
    let case = base_case("win-cpupin");
    standard_config(&case);
    append_config(
        &case,
        "VM_CPU_SOCKETS=1\nVM_CPU_CORES=2\nVM_CPU_THREADS=2\nVM_CPU_PIN_SET=\"0 1 2 3\"\n",
    );
    let output = run(&case, &["cpupin"], &[("FAKE_VIRSH_DOMINFO_CODE", "0")]);
    assert_eq!(exited(&output), 0, "{}", stderr(&output));
    assert!(stdout(&output).contains("==> pinning 4 vCPUs to host cores: 0 1 2 3\n"));
    let virsh = case.argv("virsh");
    for (index, host) in ["0", "1", "2", "3"].iter().enumerate() {
        assert!(
            virsh.contains(&expected_argv(
                "virsh",
                &[
                    "--connect",
                    "qemu:///system",
                    "vcpupin",
                    "testvm",
                    &index.to_string(),
                    host,
                    "--config"
                ]
            )),
            "{virsh}"
        );
    }

    let case2 = base_case("win-cpupin-mismatch");
    standard_config(&case2);
    append_config(&case2, "VM_CPU_CORES=2\nVM_CPU_PIN_SET=\"0 1\"\n");
    let output = run(&case2, &["cpupin"], &[("FAKE_VIRSH_DOMINFO_CODE", "0")]);
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "error: VM_CPU_PIN_SET has 2 entries, expected 4 (sockets*cores*threads)\n"
    );
}

#[test]
fn hugepages_edits_the_domain_and_prints_the_host_hint() {
    let case = base_case("win-hugepages");
    standard_config(&case);
    append_config(&case, "VM_HUGEPAGES=\"yes\"\n");
    let output = run(&case, &["hugepages"], &[("FAKE_VIRSH_DOMINFO_CODE", "0")]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("virt-xml"),
        expected_argv(
            "virt-xml",
            &[
                "--connect",
                "qemu:///system",
                "testvm",
                "--edit",
                "--memorybacking",
                "hugepages=yes"
            ]
        )
    );
    assert!(stdout(&output).contains(
        "==> hugepages enabled. Pre-allocate on host: sudo sysctl vm.nr_hugepages=8192\n"
    ));
}

#[test]
fn usb_add_and_remove_use_config_or_live_according_to_the_state() {
    let case = base_case("win-usb");
    standard_config(&case);
    let copy = case.path("usb-copy.xml");
    let output = run(
        &case,
        &["usb-add", "0951:16ae"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("FAKE_VIRSH_DOMSTATE", "shut off"),
            ("FAKE_VIRSH_DEVICE_COPY", &copy.to_string_lossy()),
        ],
    );
    assert_eq!(exited(&output), 0, "{}", stderr(&output));
    assert_eq!(
        case.read_at(&copy),
        "<hostdev mode='subsystem' type='usb' managed='yes'>\n  <source>\n    <vendor id='0x0951'/>\n    <product id='0x16ae'/>\n  </source>\n</hostdev>\n"
    );
    assert!(case.argv("virsh").contains("ARG --config\n"));
    assert!(stdout(&output).contains("==> USB 0951:16ae attached to VM 'testvm'\n"));

    case.clear_logs();
    let output = run(
        &case,
        &["usb-add", "0951:16ae"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("FAKE_VIRSH_DOMSTATE", "running"),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert!(case.argv("virsh").contains("ARG --live\n"));

    case.clear_logs();
    let output = run(
        &case,
        &["usb-remove", "0951:16ae"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("FAKE_VIRSH_DOMSTATE", "shut off"),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert!(case.argv("virsh").contains("ARG detach-device\n"));
    assert_eq!(stdout(&output), "");
}

#[test]
fn usb_arguments_are_validated() {
    let case = base_case("win-usb-bad");
    standard_config(&case);
    let output = run(&case, &["usb-add"], &[("FAKE_VIRSH_DOMINFO_CODE", "0")]);
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "error: usage: win-vm usb-add VENDOR:PRODUCT (e.g. 0951:16ae)\n"
    );
    let output = run(
        &case,
        &["usb-add", "095116ae"],
        &[("FAKE_VIRSH_DOMINFO_CODE", "0")],
    );
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "error: bad format: expected VENDOR:PRODUCT\n"
    );
}

#[test]
fn console_uses_spicy_remote_viewer_or_virt_viewer() {
    let case = base_case("win-console");
    standard_config(&case);
    let output = run(
        &case,
        &["console"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("FAKE_VIRSH_DOMDISPLAY", "spice://127.0.0.1:5900\n"),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("spicy"),
        expected_argv("spicy", &["--uri", "spice://127.0.0.1:5900"])
    );

    case.remove_fake("spicy");
    case.clear_logs();
    let output = run(
        &case,
        &["console"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("FAKE_VIRSH_DOMDISPLAY", "spice://127.0.0.1:5900\n"),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("remote-viewer"),
        expected_argv("remote-viewer", &["spice://127.0.0.1:5900"])
    );

    case.remove_fake("remote-viewer");
    case.clear_logs();
    let output = run(
        &case,
        &["console"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("FAKE_VIRSH_DOMDISPLAY", "spice://127.0.0.1:5900\n"),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("virt-viewer"),
        expected_argv("virt-viewer", &["--connect", "qemu:///system", "testvm"])
    );

    case.clear_logs();
    let output = run(
        &case,
        &["console"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("FAKE_VIRSH_DOMDISPLAY_CODE", "1"),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("virt-viewer"),
        expected_argv("virt-viewer", &["--connect", "qemu:///system", "testvm"])
    );
}

#[test]
fn console_prefers_looking_glass_for_a_none_graphics_vm() {
    let case = base_case("win-console-lg");
    standard_config(&case);
    append_config(&case, "VM_GRAPHICS=\"none\"\n");
    let shm = case.path("looking-glass-fixture");
    fs::write(&shm, b"shm").expect("shm fixture");
    let output = run(
        &case,
        &["console"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("LOCAL_BIN_ZSH_EXTRA_LOOKING_GLASS", &shm.to_string_lossy()),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("looking-glass-client"),
        expected_argv(
            "looking-glass-client",
            &["-f", &shm.to_string_lossy(), "-F", "-s"]
        )
    );
}

#[test]
fn looking_glass_requires_the_shm_device_and_forwards_arguments() {
    let case = base_case("win-lg-cli");
    standard_config(&case);
    let missing = run(
        &case,
        &["looking-glass"],
        &[("FAKE_VIRSH_DOMINFO_CODE", "0")],
    );
    assert_eq!(exited(&missing), 1);
    assert_eq!(
        stderr(&missing),
        "error: /dev/shm/looking-glass missing; run 'win-vm lg-enable' first\n"
    );

    let shm = case.path("looking-glass-fixture");
    fs::write(&shm, b"shm").expect("shm fixture");
    let output = run(
        &case,
        &["looking-glass", "-m", "10"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("LOCAL_BIN_ZSH_EXTRA_LOOKING_GLASS", &shm.to_string_lossy()),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("looking-glass-client"),
        expected_argv(
            "looking-glass-client",
            &["-f", &shm.to_string_lossy(), "-F", "-s", "-m", "10"]
        )
    );
}

#[test]
fn failures_propagate_the_command_status() {
    let case = base_case("win-start-fail");
    standard_config(&case);
    let output = run(
        &case,
        &["start"],
        &[
            ("FAKE_VIRSH_DOMINFO_CODE", "0"),
            ("FAKE_VIRSH_DOMSTATE", "shut off"),
            ("FAKE_VIRSH_CODE", "3"),
        ],
    );
    assert_eq!(exited(&output), 3);
    assert!(!stdout(&output).contains("started"));
}

#[test]
fn a_run_in_another_directory_still_uses_the_config_home() {
    let case = base_case("win-cwd");
    standard_config(&case);
    let elsewhere = case.path("work/sub");
    fs::create_dir_all(&elsewhere).expect("elsewhere");
    let output = run_in(&case, &elsewhere, &["status"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "VM 'testvm': not defined\n");
}
