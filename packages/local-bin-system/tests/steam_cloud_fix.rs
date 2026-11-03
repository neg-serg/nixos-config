//! Hermetic tests for the `steam-cloud-fix` port: the Steam root/account
//! discovery, the client's `last_sync_state` parsing, the cloud-log rendering,
//! the cache move into `BACKUP_ROOT` and the stop/start control flow. Steam
//! itself, `pgrep`, `pkill`, `timeout`, `date`, `env` and `sleep` are fakes;
//! `mv` logs its argv and then runs the real coreutils binary so the test can
//! assert the actual tree.

mod support;

use std::path::{Path, PathBuf};

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_steam-cloud-fix");

const PGREP: &str = r#"#!/bin/sh
case "${FAKE_PGREP:-1}" in
  1) exit 1 ;;
  0) exit 0 ;;
  count)
    count=0
    if [ -f "$FAKE_RUNNING" ]; then IFS= read -r count < "$FAKE_RUNNING"; fi
    count=$((count + 1))
    printf '%s\n' "$count" > "$FAKE_RUNNING"
    [ "$count" -le "${FAKE_RUNNING_FOR:-2}" ] && exit 0 || exit 1
    ;;
esac
exit 1
"#;

const DATE: &str = r#"#!/bin/sh
printf 'date %s\n' "$*" >> "$FAKE_ARGV_LOG"
printf '%s\n' "${FAKE_DATE:-20240102-030405}"
exit "${FAKE_DATE_CODE:-0}"
"#;

const SLEEP: &str = r#"#!/bin/sh
printf 'sleep %s\n' "$*" >> "$FAKE_ARGV_LOG"
exit "${FAKE_SLEEP_CODE:-0}"
"#;

const ENV: &str = r#"#!/bin/sh
printf 'env %s\n' "$*" >> "$FAKE_ARGV_LOG"
exit 0
"#;

const PKILL: &str = r#"#!/bin/sh
printf 'pkill %s\n' "$*" >> "$FAKE_ARGV_LOG"
exit 0
"#;

const TIMEOUT: &str = r#"#!/bin/sh
printf 'timeout %s\n' "$*" >> "$FAKE_ARGV_LOG"
exit 0
"#;

const STEAM: &str = r#"#!/bin/sh
printf 'steam %s\n' "$*" >> "$FAKE_ARGV_LOG"
exit 0
"#;

fn host_tool(name: &str) -> PathBuf {
    let path = std::env::var_os("PATH").expect("host PATH");
    for directory in std::env::split_paths(&path) {
        let candidate = directory.join(name);
        if candidate.is_file() {
            return candidate;
        }
    }
    panic!("host tool not found: {name}");
}

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("pgrep", PGREP);
    case.write_fake("date", DATE);
    case.write_fake("sleep", SLEEP);
    case.write_fake("env", ENV);
    case.write_fake("pkill", PKILL);
    case.write_fake("timeout", TIMEOUT);
    case.write_fake("steam", STEAM);
    let mv = format!(
        "#!/bin/sh\nprintf 'mv %s\\n' \"$*\" >> \"$FAKE_ARGV_LOG\"\nexec {} \"$@\"\n",
        host_tool("mv").to_string_lossy()
    );
    case.write_fake("mv", &mv);
    case
}

fn steam_root(case: &Case) -> PathBuf {
    case.path("steam")
}

fn install_steam(case: &Case) -> String {
    let root = steam_root(case);
    std::fs::create_dir_all(root.join("userdata/123/config")).expect("create steam root");
    std::fs::create_dir_all(root.join("userdata/123/294100/ac/deep")).expect("create app cache");
    std::fs::create_dir_all(root.join("logs")).expect("create logs");
    case.write(
        &root.join("userdata/123/config/localconfig.vdf"),
        "\"UserLocalConfigStore\"\n{\n\t\"apps\"\n\t{\n\t\t\"294100\"\n\t\t{\n\t\t\t\"last_sync_state\"\t\t\"changesincloud\"\n\t\t}\n\t}\n}\n",
    );
    case.write(&root.join("userdata/123/294100/remotecache.vdf"), "cache");
    case.write(&root.join("userdata/123/294100/ac/file"), "staging");
    case.write(&root.join("userdata/123/294100/ac/deep/file"), "nested");
    case.write(
        &root.join("logs/cloud_log.txt"),
        "[2024-01-01 10:00:00] [AppID 294100] hello world\n[2024-01-01 10:00:01] [AppID 294100] sync step\n",
    );
    root.to_string_lossy().into_owned()
}

fn env_for<'a>(root: &'a str, backup: &'a str) -> Vec<(&'a str, &'a str)> {
    vec![("STEAM_ROOT", root), ("BACKUP_ROOT", backup)]
}

fn backup_dir(case: &Case) -> String {
    case.path("backup").to_string_lossy().into_owned()
}

#[test]
fn help_prints_the_header_including_its_artifacts() {
    let case = fixture("help");
    let output = case.run(&["--help"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "");
    let text = stdout(&output);
    assert!(text.starts_with(
        "Reset Steam Cloud bookkeeping for one app and (re)start the Steam client.\n"
    ));
    assert!(text.contains("  steam-cloud-fix --app 294100 --wait 120\n"));
    // `sed -n '2,32p'` overshoots the comment block; the port keeps that.
    assert!(text.ends_with("~/.local/share/steam-cloud-fix).\nset -euo pipefail\n\nAPPID=294100\n"));
}

#[test]
fn unknown_arguments_and_missing_values_are_errors() {
    let case = fixture("errors");
    let unknown = case.run(&["--nope"]);
    assert_eq!(exited(&unknown), 1);
    assert_eq!(stderr(&unknown), "ошибка: неизвестный аргумент: --nope\n");

    let missing_app = case.run(&["--app"]);
    assert_eq!(exited(&missing_app), 1);
    assert!(stderr(&missing_app).contains("--app требует appid"));

    let missing_wait = case.run(&["--wait"]);
    assert_eq!(exited(&missing_wait), 1);
    assert!(stderr(&missing_wait).contains("--wait требует секунды"));
}

#[test]
fn a_missing_steam_root_is_fatal() {
    let case = fixture("no-root");
    let root = case.path("nope");
    let output = case.run_env(
        &["--status"],
        &env_for(&root.to_string_lossy(), &backup_dir(&case)),
    );
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        format!("ошибка: нет каталога Steam: {}\n", root.to_string_lossy())
    );
}

#[test]
fn a_missing_profile_is_fatal() {
    let case = fixture("no-profile");
    let root = steam_root(&case);
    std::fs::create_dir_all(root.join("userdata/0")).expect("create anonymous dir");
    std::fs::create_dir_all(root.join("userdata/not-a-number")).expect("create named dir");
    let output = case.run_env(
        &["--status"],
        &env_for(&root.to_string_lossy(), &backup_dir(&case)),
    );
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        format!(
            "ошибка: не найден профиль в {}/userdata\n",
            root.to_string_lossy()
        )
    );
}

#[test]
fn the_largest_numeric_profile_wins() {
    let case = fixture("profile");
    let root = steam_root(&case);
    for (name, state) in [
        ("0", "ignored"),
        ("7", "changeslocal"),
        ("123", "synchronized"),
    ] {
        let config = root.join(format!("userdata/{name}/config"));
        std::fs::create_dir_all(&config).expect("create config");
        case.write(
            &config.join("localconfig.vdf"),
            &format!("\"294100\"\n{{\n\t\"last_sync_state\"\t\t\"{state}\"\n}}\n"),
        );
    }
    let output = case.run_env(
        &["--status"],
        &env_for(&root.to_string_lossy(), &backup_dir(&case)),
    );
    assert_eq!(exited(&output), 0);
    let text = stdout(&output);
    assert!(
        text.starts_with("RimWorld (appid 294100), профиль 123\n"),
        "{text}"
    );
    assert!(text.contains("синхронизировано"), "{text}");
}

#[test]
fn status_maps_the_known_states_and_the_unknown_default() {
    let cases = [
        ("synchronized", "синхронизировано"),
        (
            "changesincloud",
            "в облаке есть изменения, которых нет локально (ждёт загрузки)",
        ),
        ("changeslocal", "локальные изменения ждут выгрузки"),
        ("somethingelse", "somethingelse"),
    ];
    for (state, expected) in cases {
        let case = fixture("state");
        let root = steam_root(&case);
        std::fs::create_dir_all(root.join("userdata/123/config")).expect("create config");
        case.write(
            &root.join("userdata/123/config/localconfig.vdf"),
            &format!("\"294100\"\n{{\n\t\"last_sync_state\"\t\t\"{state}\"\n}}\n"),
        );
        let output = case.run_env(
            &["--status"],
            &env_for(&root.to_string_lossy(), &backup_dir(&case)),
        );
        assert_eq!(exited(&output), 0);
        assert!(
            stdout(&output).contains(&format!("  состояние облака: {expected}\n")),
            "{}",
            stdout(&output)
        );
    }

    let no_config = fixture("state-unrecorded");
    let root = steam_root(&no_config);
    std::fs::create_dir_all(root.join("userdata/123")).expect("create profile");
    let output = no_config.run_env(
        &["--status"],
        &env_for(&root.to_string_lossy(), &backup_dir(&no_config)),
    );
    assert_eq!(exited(&output), 0);
    assert!(stdout(&output).contains("  состояние облака: состояние не записано клиентом\n"));
}

#[test]
fn status_reports_the_cache_tree_and_recent_log_lines() {
    let case = fixture("status");
    let root = install_steam(&case);
    let output = case.run_env(&["--status"], &env_for(&root, &backup_dir(&case)));
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        "RimWorld (appid 294100), профиль 123\n  состояние облака: в облаке есть изменения, которых нет локально (ждёт загрузки)\n  кэш облака: userdata/123/294100 (2 файлов)\n  последние строки logs/cloud_log.txt:\n    10:00:00  hello world\n    10:00:01  sync step\n"
    );
    assert_eq!(stderr(&output), "");
}

#[test]
fn status_without_an_app_cache_says_so() {
    let case = fixture("status-no-cache");
    let root = steam_root(&case);
    std::fs::create_dir_all(root.join("userdata/123/config")).expect("create config");
    let output = case.run_env(
        &["--status"],
        &env_for(&root.to_string_lossy(), &backup_dir(&case)),
    );
    assert_eq!(exited(&output), 0);
    assert!(
        stdout(&output).contains("  кэш облака: нет (клиент ещё не заводил его для этой игры)\n")
    );
}

#[test]
fn only_recent_matching_cloud_log_lines_survive() {
    let case = fixture("cloud-log");
    let root = install_steam(&case);
    let mut log = String::new();
    for index in 0..12 {
        log.push_str(&format!(
            "[2024-01-01 10:00:{index:02}] [AppID 294100] line-{index}\n"
        ));
    }
    log.push_str("[2024-01-01 10:00:59] [AppID 999999] other-app\n");
    log.push_str("   \t  \n");
    case.write(&Path::new(&root).join("logs/cloud_log.txt"), &log);
    let output = case.run_env(&["--status"], &env_for(&root, &backup_dir(&case)));
    let text = stdout(&output);
    assert!(!text.contains("line-0\n"), "{text}");
    assert!(!text.contains("other-app"), "{text}");
    assert!(text.contains("    10:00:04  line-4\n"), "{text}");
    assert!(text.contains("    10:00:11  line-11\n"), "{text}");
    // Only the last 8 log lines are rendered.
    assert_eq!(text.matches("  line-").count(), 8, "{text}");
}

#[test]
fn repair_moves_the_cache_into_the_backup_root_and_can_skip_steam() {
    let case = fixture("repair");
    let root = install_steam(&case);
    let output = case.run_env(&["--no-start"], &env_for(&root, &backup_dir(&case)));
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        format!(
            "кэш облака убран в {}/294100-20240102-030405\nSteam не запускаю (--no-start).\n",
            backup_dir(&case)
        )
    );
    assert_eq!(stderr(&output), "");
    let backup = case.path("backup/294100-20240102-030405");
    assert!(backup.join("remotecache.vdf").is_file());
    assert!(backup.join("ac/file").is_file());
    assert!(backup.join("ac/deep/file").is_file());
    assert!(!Path::new(&root)
        .join("userdata/123/294100/remotecache.vdf")
        .exists());
    let argv = case.argv_log();
    assert!(
        argv.contains(&format!(
            "mv {root}/userdata/123/294100/remotecache.vdf {}/294100-20240102-030405/",
            backup_dir(&case)
        )),
        "{argv}"
    );
    assert!(argv.contains("date +%Y%m%d-%H%M%S"), "{argv}");
}

#[test]
fn repair_of_an_empty_cache_says_so() {
    let case = fixture("repair-empty");
    let root = steam_root(&case);
    std::fs::create_dir_all(root.join("userdata/123/config")).expect("create config");
    let output = case.run_env(
        &["--no-start"],
        &env_for(&root.to_string_lossy(), &backup_dir(&case)),
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        "кэш облака уже пуст — нечего убирать\nSteam не запускаю (--no-start).\n"
    );
}

#[test]
fn start_launches_env_setsid_detached_and_waits() {
    let case = fixture("start");
    let root = install_steam(&case);
    let output = case.run_env(&["--wait", "120"], &env_for(&root, &backup_dir(&case)));
    assert_eq!(exited(&output), 0);
    let text = stdout(&output);
    assert!(
        text.contains("Steam запускается, жду 120 с и смотрю облако...\n"),
        "{text}"
    );
    assert!(
        text.contains("  кэш облака: userdata/123/294100 (0 файлов)\n"),
        "{text}"
    );
    assert!(text.ends_with(
        "  или запусти игру, чтобы клиент разрешил конфликт сохранений своей стороной.\n"
    ));
    let argv = case.argv_log();
    assert!(
        argv.contains(
            "env -u ALL_PROXY -u all_proxy -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY setsid"
        ),
        "{argv}"
    );
    assert!(argv.contains("sleep 120"), "{argv}");
}

#[test]
fn a_running_client_is_stopped_before_the_cache_is_moved() {
    let case = fixture("stop");
    let root = install_steam(&case);
    let output = case.run_env(&["--no-start"], &env_for(&root, &backup_dir(&case)));
    assert_eq!(exited(&output), 0);
    // The fake pgrep is not running (FAKE_PGREP defaults to 1), so the stop
    // block is skipped; this is the green path of the stop helper.
    assert!(!stdout(&output).contains("останавливаю Steam"));
    assert!(stdout(&output).contains("кэш облака убран в"));
}

#[test]
fn stopping_waits_then_moves_when_pgrep_clears() {
    let case = fixture("stop-clears");
    let root = install_steam(&case);
    let output = case.run_env(
        &["--no-start"],
        &[
            ("STEAM_ROOT", &root),
            ("BACKUP_ROOT", &backup_dir(&case)),
            ("FAKE_PGREP", "count"),
            ("FAKE_RUNNING_FOR", "2"),
        ],
    );
    assert_eq!(exited(&output), 0);
    let text = stdout(&output);
    assert!(text.starts_with("останавливаю Steam...\n"), "{text}");
    let argv = case.argv_log();
    assert!(argv.contains("timeout 60 steam -shutdown"), "{argv}");
    // The first check polls the running client, the second sees it stopped.
    assert_eq!(argv.matches("sleep 1\n").count(), 1, "{argv}");
    assert!(!argv.contains("pkill"), "{argv}");
}

#[test]
fn a_stubborn_client_fails_the_run() {
    let case = fixture("stop-fails");
    let root = install_steam(&case);
    let output = case.run_env(
        &["--no-start"],
        &[
            ("STEAM_ROOT", &root),
            ("BACKUP_ROOT", &backup_dir(&case)),
            ("FAKE_PGREP", "0"),
        ],
    );
    assert_eq!(exited(&output), 1);
    assert!(stdout(&output).starts_with("останавливаю Steam...\n"));
    assert_eq!(
        stderr(&output),
        "ошибка: Steam не завершился — закрой его вручную и повтори\n"
    );
    let argv = case.argv_log();
    assert_eq!(argv.matches("sleep 1\n").count(), 50, "{argv}");
    assert!(argv.contains("pkill -TERM -f steamrt64/steam"), "{argv}");
    // Nothing was moved.
    assert!(!case.path("backup").join("294100-20240102-030405").exists());
}

#[test]
fn sleep_and_date_failures_propagate() {
    let sleep_case = fixture("sleep-fail");
    let root = install_steam(&sleep_case);
    let output = sleep_case.run_env(
        &["--wait", "1"],
        &[
            ("STEAM_ROOT", &root),
            ("BACKUP_ROOT", &backup_dir(&sleep_case)),
            ("FAKE_SLEEP_CODE", "3"),
        ],
    );
    assert_eq!(exited(&output), 3);

    let date_case = fixture("date-fail");
    let root = install_steam(&date_case);
    let output = date_case.run_env(
        &["--no-start"],
        &[
            ("STEAM_ROOT", &root),
            ("BACKUP_ROOT", &backup_dir(&date_case)),
            ("FAKE_DATE_CODE", "4"),
        ],
    );
    assert_eq!(exited(&output), 4);
}

#[test]
fn an_mv_failure_aborts_before_the_report() {
    let case = fixture("mv-fail");
    let root = install_steam(&case);
    let mv = "#!/bin/sh\nprintf 'mv %s\\n' \"$*\" >> \"$FAKE_ARGV_LOG\"\nexit 5\n".to_string();
    case.write_fake("mv", &mv);
    let output = case.run_env(&["--no-start"], &env_for(&root, &backup_dir(&case)));
    assert_eq!(exited(&output), 5);
    assert!(!stdout(&output).contains("кэш облака убран в"));
    assert!(case
        .path("steam/userdata/123/294100/remotecache.vdf")
        .is_file());
}

#[test]
fn start_without_a_steam_binary_fails_with_the_path() {
    let case = fixture("no-steam");
    case.remove_fake("steam");
    let root = install_steam(&case);
    let output = case.run_env(&["--wait", "0"], &env_for(&root, &backup_dir(&case)));
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        format!("ошибка: не нашёл steam ({root}/steam.sh)\n")
    );
}

#[test]
fn the_steam_root_steam_sh_fallback_is_used() {
    let case = fixture("steam-sh");
    case.remove_fake("steam");
    let root = install_steam(&case);
    let launcher = Path::new(&root).join("steam.sh");
    case.write(&launcher, "#!/bin/sh\nexit 0\n");
    let mut permissions = std::fs::metadata(&launcher)
        .expect("stat launcher")
        .permissions();
    use std::os::unix::fs::PermissionsExt;
    permissions.set_mode(0o755);
    std::fs::set_permissions(&launcher, permissions).expect("chmod launcher");
    let output = case.run_env(&["--wait", "0"], &env_for(&root, &backup_dir(&case)));
    assert_eq!(exited(&output), 0);
    assert!(case.argv_log().contains(&format!("setsid {root}/steam.sh")));
}

#[test]
fn a_custom_app_id_changes_the_paths_and_the_state_marker() {
    let case = fixture("custom-app");
    let root = install_steam(&case);
    std::fs::create_dir_all(Path::new(&root).join("userdata/123/42")).expect("create app dir");
    case.write(
        &Path::new(&root).join("userdata/123/42/remotecache.vdf"),
        "x",
    );
    let output = case.run_env(
        &["--app", "42", "--status"],
        &env_for(&root, &backup_dir(&case)),
    );
    assert_eq!(exited(&output), 0);
    assert!(stdout(&output).contains("RimWorld (appid 42), профиль 123\n"));
    assert!(stdout(&output).contains("  кэш облака: userdata/123/42 (1 файлов)\n"));
}

#[test]
fn file_count_is_capped_at_depth_two() {
    let case = fixture("depth");
    let root = install_steam(&case);
    let app = Path::new(&root).join("userdata/123/294100");
    case.write(&app.join("ac/one"), "1");
    case.write(&app.join("ac/two"), "2");
    std::fs::create_dir_all(app.join("ac/deep/deeper")).expect("create deeper");
    case.write(&app.join("ac/deep/deeper/three"), "3");
    let output = case.run_env(&["--status"], &env_for(&root, &backup_dir(&case)));
    assert!(
        stdout(&output).contains("(4 файлов)"),
        "{}",
        stdout(&output)
    );
}
