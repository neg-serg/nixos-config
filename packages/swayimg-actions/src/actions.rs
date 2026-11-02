//! Action dispatch and the action bodies, mirroring the shell's `case` block.

use std::fs;
use std::io::Write;
use std::time::Duration;

use crate::bytes::{join, os_owned, read_lines, zsh_echo};
use crate::env::{path, Paths};
use crate::picker;
use crate::range;
use crate::screen;
use crate::tools::{self, Call};

pub fn dispatch(paths: &Paths, action: &[u8], file: &[u8], dest: &[u8]) -> i32 {
    match action {
        b"rotate-left" => rotate(270, file),
        b"rotate-right" => rotate(90, file),
        b"rotate-180" => rotate(180, file),
        b"rotate-ccw" => rotate(-90, file),
        b"copyname" => {
            copy_name(paths, file);
            0
        }
        b"mv" => {
            move_or_copy(paths, "mv", file, dest);
            0
        }
        b"cp" => {
            move_or_copy(paths, "cp", file, dest);
            0
        }
        b"wall-mono" => {
            wall(paths, "mono", file);
            0
        }
        b"wall-fill" => {
            wall(paths, "fill", file);
            0
        }
        b"wall-full" => {
            wall(paths, "full", file);
            0
        }
        b"wall-tile" => {
            wall(paths, "tile", file);
            0
        }
        b"wall-center" => {
            wall(paths, "center", file);
            0
        }
        b"wall-cover" => {
            wall(paths, "cover", file);
            0
        }
        b"range-mark" => range_mark(paths, file),
        b"range-clear" => {
            range_clear(paths);
            0
        }
        b"range-trash" => range_trash(paths, file),
        b"range-cp" => range_copy(paths, file),
        b"range-mv" => range_move(paths, file),
        _ => {
            // echo "Unknown action: $action" >&2 — including echo's escapes.
            let echoed = zsh_echo(action);
            let mut message = b"Unknown action: ".to_vec();
            message.extend_from_slice(&echoed.data);
            if echoed.newline {
                message.push(b'\n');
            }
            stderr(&message);
            2
        }
    }
}

fn stderr(message: &[u8]) {
    let _ = std::io::stderr().write_all(message);
}

fn variable(name: &str) -> Option<Vec<u8>> {
    use std::os::unix::ffi::OsStringExt;
    std::env::var_os(name)
        .map(|value| value.into_vec())
        .filter(|value| !value.is_empty())
}

/// rotate-left/right/180/ccw: `printf '%s\n' "$file" | rotate <angle>`.
/// `mogrify` runs once per stdin line (the loop is line-based), and the script
/// exits with the last command's status — 127 when mogrify is not installed.
fn rotate(angle: i32, file: &[u8]) -> i32 {
    let mut input = file.to_vec();
    input.push(b'\n');
    let mut status = 0;
    for line in read_lines(&input) {
        let outcome = Call::new("mogrify")
            .argument("-rotate")
            .argument(angle.to_string())
            .argument(os_owned(&line))
            .run();
        status = outcome.code();
    }
    status
}

/// copyname: `realpath` into `wl-copy`, then the optional `pic-notify` toast.
/// The shell's last statement was `[ -x ... ] && ... || true`, so this action
/// always succeeds even when wl-copy is missing or fails.
fn copy_name(paths: &Paths, file: &[u8]) {
    let resolved = tools::realpath_or_empty(file);
    let mut clipboard = resolved;
    clipboard.push(b'\n');
    Call::new("wl-copy").input(clipboard).run();

    let notifier = join(&paths.home, b".local/bin/pic-notify");
    if tools::is_executable(&notifier) {
        Call::new(os_owned(&notifier))
            .argument(os_owned(file))
            .run();
    }
}

/// mv/cp with the remembered last destination (the shell's `proc`).
fn move_or_copy(paths: &Paths, command: &str, file: &[u8], requested_dest: &[u8]) {
    let mut tee = file.to_vec();
    tee.push(b'\n');
    let _ = fs::write(path(&paths.tmp_file), tee);

    let mut dest = requested_dest.to_vec();
    if dest.is_empty() {
        dest = picker::choose_dest(paths, command, file);
    }
    if dest.is_empty() {
        return;
    }

    // mkdir -p "$dest" 2>/dev/null || true
    let _ = fs::create_dir_all(path(&dest));
    if !path(&dest).is_dir() {
        return;
    }

    // "Avoid swayimg crash when current list ends after move: switch away first"
    if command == "mv" {
        crate::ipc::send(b"next_file");
    }

    let file_list = fs::read(path(&paths.tmp_file)).unwrap_or_default();
    for line in read_lines(&file_list) {
        // "$cmd" "$(realpath "$line")" "$dest"
        let resolved = tools::realpath_or_empty(&line);
        Call::new(command)
            .argument(os_owned(&resolved))
            .argument(os_owned(&dest))
            .run();
    }

    if tools::program_exists("zoxide") {
        Call::new("zoxide")
            .argument("add")
            .argument(os_owned(&dest))
            .run();
    }

    // printf '%s %s\n' "$cmd" "$dest" > "$last_file"
    let mut last = command.as_bytes().to_vec();
    last.push(b' ');
    last.extend_from_slice(&dest);
    last.push(b'\n');
    let _ = fs::write(path(&paths.last_file), last);
}

/// wall-*: ensure swww, render through convert, set the wallpaper, append the
/// source file to the wallpaper list. Always exits 0.
fn wall(paths: &Paths, mode: &str, file: &[u8]) {
    ensure_swww();
    if !render_for_mode(paths, mode, file) {
        return;
    }

    let target = variable("SWWW_IMAGE_OVERRIDE").unwrap_or_else(|| paths.tmp_wall.clone());
    let mut call = Call::new("swww")
        .argument("img")
        .argument(os_owned(&target))
        .quiet();
    // zsh does not word-split or glob an unquoted parameter expansion, so
    // ${SWWW_FLAGS:-} is either one argument (even with spaces) or none.
    if let Some(flags) = variable("SWWW_FLAGS") {
        call = call.argument(os_owned(&flags));
    }
    call.run();

    // echo "$file" >> .../wallpaper.list, with zsh echo's escape processing.
    let echoed = zsh_echo(file);
    let mut line = echoed.data;
    if echoed.newline {
        line.push(b'\n');
    }
    if let Ok(mut list) = fs::OpenOptions::new()
        .append(true)
        .create(true)
        .open(path(&paths.wallpaper_list))
    {
        let _ = list.write_all(&line);
    }
}

/// `ensure_swww`: start the daemon when `swww query` fails, then a 50 ms pause.
fn ensure_swww() {
    let query = Call::new("swww").argument("query").quiet().run();
    if query.success() {
        return;
    }
    Call::new("swww").argument("init").quiet().run();
    std::thread::sleep(Duration::from_millis(50));
}

/// `render_for_mode`: returns convert's success. Missing convert is the silent
/// "return 1" guard, which makes wall return 0 without touching the wallpaper.
fn render_for_mode(paths: &Paths, mode: &str, file: &[u8]) -> bool {
    if !tools::program_exists("convert") {
        return false;
    }
    let wh = screen::screen_size();
    let _ = fs::remove_file(path(&paths.tmp_wall));

    let mut geometry = wh.clone();
    geometry.push(b'^');

    let mut call = Call::new("convert");
    match mode {
        "center" => {
            call = call
                .argument(os_owned(file))
                .argument("-resize")
                .argument(os_owned(&wh))
                .argument("-gravity")
                .argument("center")
                .argument("-background")
                .argument("black")
                .argument("-extent")
                .argument(os_owned(&wh))
                .argument(os_owned(&paths.tmp_wall));
        }
        "tile" => {
            let mut tile = b"tile:".to_vec();
            tile.extend_from_slice(file);
            call = call
                .argument("-size")
                .argument(os_owned(&wh))
                .argument(os_owned(&tile))
                .argument(os_owned(&paths.tmp_wall));
        }
        "mono" | "retro" => {
            let colors = if mode == "mono" { "2" } else { "12" };
            call = call
                .argument(os_owned(file))
                .argument("-colors")
                .argument(colors)
                .argument(os_owned(&paths.tmp_wall));
        }
        // cover/full/fill and the default arm share the cover command.
        _ => {
            call = call
                .argument(os_owned(file))
                .argument("-resize")
                .argument(os_owned(&geometry))
                .argument("-gravity")
                .argument("center")
                .argument("-extent")
                .argument(os_owned(&wh))
                .argument(os_owned(&paths.tmp_wall));
        }
    }
    call.run().success()
}

// ---- range operations -----------------------------------------------------

fn range_mark(paths: &Paths, file: &[u8]) -> i32 {
    let regular = fs::metadata(path(file))
        .map(|metadata| metadata.is_file())
        .unwrap_or(false);
    let symlink = fs::symlink_metadata(path(file)).is_ok();
    if !regular && !symlink {
        let mut message = b"swayimg-actions: range-mark: file not found: ".to_vec();
        message.extend_from_slice(file);
        message.push(b'\n');
        stderr(&message);
        return 1;
    }

    // realpath "$1" > "$range_file" 2>/dev/null: the redirection truncates the
    // mark before realpath runs, so a failure leaves an empty file behind.
    let mut marker = match fs::File::create(path(&paths.range_file)) {
        Ok(marker) => marker,
        Err(_) => return range_mark_realpath_failed(file),
    };
    // `realpath "$1" > "$range_file" 2>/dev/null` wrote stdout verbatim,
    // including realpath's trailing newline (no command substitution here).
    let outcome = Call::new("realpath")
        .argument(os_owned(file))
        .capture_stdout()
        .quiet_stderr()
        .run();
    if outcome.success() {
        let _ = marker.write_all(&outcome.stdout);
        0
    } else {
        range_mark_realpath_failed(file)
    }
}

fn range_mark_realpath_failed(file: &[u8]) -> i32 {
    let mut message = b"swayimg-actions: range-mark: realpath failed for: ".to_vec();
    message.extend_from_slice(file);
    message.push(b'\n');
    stderr(&message);
    1
}

fn range_clear(paths: &Paths) {
    let _ = fs::remove_file(path(&paths.range_file));
}

fn stale_message(anchor: &[u8]) {
    let mut message = b"swayimg-actions: stale range mark cleared (".to_vec();
    message.extend_from_slice(anchor);
    message.extend_from_slice(b" no longer exists)\n");
    stderr(&message);
}

fn single_trash(paths: &Paths, file: &[u8]) {
    let _ = fs::create_dir_all(path(&paths.trash));
    crate::ipc::send(b"prev_file");
    Call::new("mv")
        .argument(os_owned(file))
        .argument(os_owned(&paths.trash))
        .run();
}

fn range_trash(paths: &Paths, file: &[u8]) -> i32 {
    let Some(anchor) = range::read_mark(&paths.range_file) else {
        single_trash(paths, file);
        return 0;
    };
    if range::is_stale(&anchor) {
        stale_message(&anchor);
        range_clear(paths);
        single_trash(paths, file);
        return 0;
    }
    let files = match range::range_slice(&anchor, file) {
        Ok(files) => files,
        Err(()) => return 1,
    };
    crate::ipc::send(b"prev_file");
    let _ = fs::create_dir_all(path(&paths.trash));
    apply_lines("mv", &files, &paths.trash);
    range_clear(paths);
    0
}

fn range_copy(paths: &Paths, file: &[u8]) -> i32 {
    let Some(anchor) = range::read_mark(&paths.range_file) else {
        return single_copy(paths, file);
    };
    if range::is_stale(&anchor) {
        stale_message(&anchor);
        range_clear(paths);
        return single_copy(paths, file);
    }
    let dest = picker::choose_dest(paths, "cp", file);
    if dest.is_empty() {
        return 0;
    }
    let files = match range::range_slice(&anchor, file) {
        Ok(files) => files,
        Err(()) => return 1,
    };
    // The regular range-cp branch is the only one without `mkdir -p "$dest"`;
    // kept as-is (the picker normally selects an existing directory).
    apply_lines("cp", &files, &dest);
    range_clear(paths);
    0
}

fn single_copy(paths: &Paths, file: &[u8]) -> i32 {
    let dest = picker::choose_dest(paths, "cp", file);
    if dest.is_empty() {
        return 0;
    }
    let _ = fs::create_dir_all(path(&dest));
    Call::new("cp")
        .argument(os_owned(file))
        .argument(os_owned(&dest))
        .run();
    0
}

fn range_move(paths: &Paths, file: &[u8]) -> i32 {
    let Some(anchor) = range::read_mark(&paths.range_file) else {
        return single_move(paths, file);
    };
    if range::is_stale(&anchor) {
        stale_message(&anchor);
        range_clear(paths);
        return single_move(paths, file);
    }
    let dest = picker::choose_dest(paths, "mv", file);
    if dest.is_empty() {
        return 0;
    }
    let files = match range::range_slice(&anchor, file) {
        Ok(files) => files,
        Err(()) => return 1,
    };
    crate::ipc::send(b"prev_file");
    let _ = fs::create_dir_all(path(&dest));
    apply_lines("mv", &files, &dest);
    range_clear(paths);
    0
}

fn single_move(paths: &Paths, file: &[u8]) -> i32 {
    let dest = picker::choose_dest(paths, "mv", file);
    if dest.is_empty() {
        return 0;
    }
    crate::ipc::send(b"prev_file");
    let _ = fs::create_dir_all(path(&dest));
    Call::new("mv")
        .argument(os_owned(file))
        .argument(os_owned(&dest))
        .run();
    0
}

/// `printf '%s\n' "$files" | while read -r f; do <cmd> "$f" "$dest"; done`.
/// An empty file list still runs one iteration with an empty path (the shell's
/// printf wrote a single newline), which is exactly how the c_line bug shows up
/// in stderr.
fn apply_lines(command: &str, files: &[u8], dest: &[u8]) {
    let mut input = files.to_vec();
    input.push(b'\n');
    for line in read_lines(&input) {
        Call::new(command)
            .argument(os_owned(&line))
            .argument(os_owned(dest))
            .run();
    }
}
