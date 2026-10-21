//! Pseudo-terminal mode.
//!
//! Some programs refuse to be interesting unless stdout is a terminal: `cargo`
//! and `nix` draw progress, `docker run -it` needs a tty for the container,
//! `python` wants a readline-capable stdin. Redirect their output through a pipe
//! and all of that silently disappears. `--pty` instead hands the child a
//! terminal of its own, relays the bytes here, and runs them through the same
//! colouriser.
//!
//! The relay is deliberately blunt about screen control: a chunk that carries an
//! ANSI escape is written through untouched, because it belongs to a full-screen
//! application (a pager, a TUI) that would be corrupted by inserting our own
//! sequences. Plain chunks are coloured as usual, and any partially buffered
//! line is spilled before the raw chunk so byte order survives the switch.
//!
//! Only libc is used — `posix_openpt`, `grantpt`, `unlockpt`, `ptsname_r`,
//! `setsid`, `ioctl`, `tcgetattr`/`tcsetattr`/`cfmakeraw`, `poll`, `read`,
//! `write`. That keeps the "no dependencies" property of the crate; the struct
//! layouts below are Linux's (this repo builds for Linux only) and their sizes
//! are asserted in the tests.

#![allow(unsafe_code)]

use std::ffi::c_void;
use std::fs::File;
use std::io::{self, Write};
use std::os::fd::{AsRawFd, FromRawFd, RawFd};
use std::os::unix::process::CommandExt;
use std::process::{Child, Command, Stdio};

use crate::engine::{Engine, Stats, Streamer};

const O_RDWR: i32 = 2;
const O_NOCTTY: i32 = 0o400;
const TIOCSCTTY: u64 = 0x540E;
const TIOCGWINSZ: u64 = 0x5413;
const TIOCSWINSZ: u64 = 0x5414;
const TCSANOW: i32 = 0;
const POLLIN: i16 = 0x001;
const POLLERR: i16 = 0x008;
const POLLHUP: i16 = 0x010;

/// `struct winsize` from `<termios.h>`.
#[repr(C)]
#[derive(Default, Clone, Copy, Debug)]
pub struct Winsize {
    pub rows: u16,
    pub cols: u16,
    pub xpixels: u16,
    pub ypixels: u16,
}

/// `struct termios` from `<asm-generic/termbits.h>`: four flag words, a line
/// discipline byte, 32 control characters, and the two speeds.
#[repr(C)]
#[derive(Clone, Copy)]
struct Termios {
    c_iflag: u32,
    c_oflag: u32,
    c_cflag: u32,
    c_lflag: u32,
    c_line: u8,
    c_cc: [u8; 32],
    c_ispeed: u32,
    c_ospeed: u32,
}

#[repr(C)]
struct PollFd {
    fd: i32,
    events: i16,
    revents: i16,
}

extern "C" {
    fn posix_openpt(flags: i32) -> i32;
    fn grantpt(fd: i32) -> i32;
    fn unlockpt(fd: i32) -> i32;
    fn ptsname_r(fd: i32, buf: *mut u8, len: usize) -> i32;
    fn setsid() -> i32;
    fn ioctl(fd: i32, request: u64, ...) -> i32;
    fn tcgetattr(fd: i32, termios: *mut Termios) -> i32;
    fn tcsetattr(fd: i32, action: i32, termios: *const Termios) -> i32;
    fn cfmakeraw(termios: *mut Termios);
    fn poll(fds: *mut PollFd, nfds: u64, timeout: i32) -> i32;
    fn read(fd: i32, buf: *mut c_void, count: usize) -> isize;
    fn write(fd: i32, buf: *const c_void, count: usize) -> isize;
}

/// A pty pair: the master side talks to us, the slave is the child's terminal.
pub struct Pty {
    master: File,
    slave: Option<File>,
    pub name: String,
}

impl Pty {
    /// `posix_openpt` + `grantpt` + `unlockpt` + `ptsname_r`, then open the slave.
    pub fn open() -> io::Result<Pty> {
        unsafe {
            let fd = posix_openpt(O_RDWR | O_NOCTTY);
            if fd < 0 {
                return Err(io::Error::last_os_error());
            }
            if grantpt(fd) != 0 || unlockpt(fd) != 0 {
                let err = io::Error::last_os_error();
                close_fd(fd);
                return Err(err);
            }
            let mut buf = [0u8; 128];
            if ptsname_r(fd, buf.as_mut_ptr(), buf.len()) != 0 {
                let err = io::Error::last_os_error();
                close_fd(fd);
                return Err(err);
            }
            let name = std::ffi::CStr::from_bytes_until_nul(&buf)
                .map(|c| c.to_string_lossy().into_owned())
                .unwrap_or_default();
            // Own the master before anything else can fail, so the descriptor is
            // closed on every error path from here on.
            let master = File::from_raw_fd(fd);
            let slave = File::options()
                .read(true)
                .write(true)
                .open(&name)
                .map_err(|err| io::Error::new(err.kind(), format!("{name}: {err}")))?;
            Ok(Pty {
                master,
                slave: Some(slave),
                name,
            })
        }
    }

    pub fn master_fd(&self) -> RawFd {
        self.master.as_raw_fd()
    }

    /// Drop the parent's copy of the slave: until every slave descriptor is
    /// closed the master never reports EOF.
    pub fn close_slave(&mut self) {
        self.slave = None;
    }

    /// Copy our terminal's size onto the pty, so the child (and its pager) know
    /// how big the screen is. Best effort: no tty, no size.
    pub fn copy_winsize(from: RawFd, to: RawFd) -> bool {
        if from < 0 || to < 0 {
            return false;
        }
        let mut size = Winsize::default();
        unsafe {
            if ioctl(from, TIOCGWINSZ, &mut size as *mut Winsize) < 0 {
                return false;
            }
            if size.rows == 0 && size.cols == 0 {
                return false;
            }
            ioctl(to, TIOCSWINSZ, &size as *const Winsize) >= 0
        }
    }

    /// Spawn `program` with the pty slave as its stdin, stdout and stderr, in a
    /// session of its own so the pty becomes its controlling terminal.
    pub fn spawn(&self, program: &str, args: &[String]) -> io::Result<Child> {
        let slave = self
            .slave
            .as_ref()
            .ok_or_else(|| io::Error::other("pty slave is already closed"))?;
        let slave_fd = slave.as_raw_fd();
        let mut command = Command::new(program);
        command.args(args);
        command.stdin(Stdio::from(slave.try_clone()?));
        command.stdout(Stdio::from(slave.try_clone()?));
        command.stderr(Stdio::from(slave.try_clone()?));
        unsafe {
            command.pre_exec(move || {
                if setsid() < 0 {
                    return Err(io::Error::last_os_error());
                }
                if ioctl(slave_fd, TIOCSCTTY, 0u64) < 0 {
                    return Err(io::Error::last_os_error());
                }
                Ok(())
            });
        }
        command.spawn()
    }
}

/// Restores the terminal attributes of our own stdin on drop.
pub struct RawMode {
    fd: RawFd,
    saved: Termios,
}

impl RawMode {
    /// Switch our stdin to raw so keystrokes reach the child unmodified and
    /// without the local echo that would fight the child's screen drawing.
    pub fn enable(fd: RawFd) -> Option<RawMode> {
        unsafe {
            let mut current: Termios = std::mem::zeroed();
            if tcgetattr(fd, &mut current) != 0 {
                return None;
            }
            let saved = current;
            let mut raw = current;
            cfmakeraw(&mut raw);
            if tcsetattr(fd, TCSANOW, &raw) != 0 {
                return None;
            }
            Some(RawMode { fd, saved })
        }
    }
}

impl Drop for RawMode {
    fn drop(&mut self) {
        unsafe {
            tcsetattr(self.fd, TCSANOW, &self.saved);
        }
    }
}

fn close_fd(fd: RawFd) {
    unsafe {
        // Wrap in a File so the drop closes exactly once.
        drop(File::from_raw_fd(fd));
    }
}

/// Relay bytes between our terminal and the pty.
///
/// * master → out: coloured, except chunks that carry ANSI escapes (screen
///   control belongs to the child, we do not paint over it);
/// * stdin → master: forwarded verbatim, so pagers and REPLs stay usable;
/// * on every poll timeout the window size is refreshed, which is how a resize
///   reaches the child's pager.
pub fn relay<W: Write>(
    engine: &Engine,
    master_fd: RawFd,
    stdin_fd: RawFd,
    out: &mut W,
) -> io::Result<Stats> {
    let mut streamer = Streamer::new(engine);
    let mut buf = vec![0u8; 64 * 1024];
    let mut stdin_open = true;
    loop {
        let mut fds = [
            PollFd {
                fd: master_fd,
                events: POLLIN,
                revents: 0,
            },
            PollFd {
                fd: if stdin_open { stdin_fd } else { -1 },
                events: POLLIN,
                revents: 0,
            },
        ];
        let ready = unsafe { poll(fds.as_mut_ptr(), fds.len() as u64, 200) };
        if ready < 0 {
            let err = io::Error::last_os_error();
            if err.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(err);
        }
        if ready == 0 {
            // Idle: pick up a terminal resize and keep the output flowing.
            Pty::copy_winsize(stdin_fd, master_fd);
            flush(out, &mut streamer)?;
            continue;
        }

        if stdin_open && fds[1].revents & (POLLIN | POLLHUP | POLLERR) != 0 {
            match read_fd(stdin_fd, &mut buf) {
                Ok(0) => {
                    stdin_open = false;
                    Pty::copy_winsize(stdin_fd, master_fd);
                }
                Ok(read) => {
                    write_all_fd(master_fd, &buf[..read])?;
                    Pty::copy_winsize(stdin_fd, master_fd);
                }
                Err(err) if err.kind() == io::ErrorKind::Interrupted => continue,
                Err(err) => return Err(err),
            }
        }

        let master_events = fds[0].revents;
        if master_events & (POLLIN | POLLHUP) != 0 {
            match read_fd(master_fd, &mut buf) {
                // EIO on the master is EOF: every slave is closed.
                Ok(0) => break,
                Ok(read) => {
                    let chunk = &buf[..read];
                    if chunk.contains(&0x1b) {
                        // Screen control: keep byte order, paint nothing.
                        streamer.spill_pending();
                        flush(out, &mut streamer)?;
                        out.write_all(chunk)?;
                        out.flush()?;
                    } else {
                        streamer.feed(chunk);
                        flush(out, &mut streamer)?;
                    }
                }
                Err(err) if err.kind() == io::ErrorKind::Interrupted => continue,
                Err(err) if err.raw_os_error() == Some(5) => break, // EIO
                Err(err) => return Err(err),
            }
        } else if master_events & POLLERR != 0 {
            break;
        }
    }
    streamer.finish();
    flush(out, &mut streamer)?;
    Ok(streamer.stats)
}

fn flush<W: Write>(out: &mut W, streamer: &mut Streamer<'_>) -> io::Result<()> {
    if streamer.out().is_empty() {
        return Ok(());
    }
    out.write_all(streamer.out())?;
    streamer.clear_out();
    out.flush()
}

fn read_fd(fd: RawFd, buf: &mut [u8]) -> io::Result<usize> {
    let read = unsafe { read(fd, buf.as_mut_ptr() as *mut c_void, buf.len()) };
    if read < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(read as usize)
}

fn write_all_fd(fd: RawFd, mut data: &[u8]) -> io::Result<()> {
    while !data.is_empty() {
        let written = unsafe { write(fd, data.as_ptr() as *const c_void, data.len()) };
        if written < 0 {
            let err = io::Error::last_os_error();
            if err.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(err);
        }
        data = &data[written as usize..];
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use crate::engine::AnsiPolicy;
    use crate::ruleset;
    use crate::theme::Theme;

    fn engine() -> Engine {
        let def = ruleset::find("generic").expect("ruleset");
        Engine::build(def, &Config::default(), Theme::dark(), AnsiPolicy::Skip)
    }

    #[test]
    fn structs_match_the_linux_abi() {
        assert_eq!(std::mem::size_of::<Winsize>(), 8);
        assert_eq!(std::mem::size_of::<Termios>(), 60);
    }

    #[test]
    fn open_reports_the_os_error_instead_of_panicking() {
        // In a sandbox /dev/ptmx may be denied; on a normal host this succeeds.
        match Pty::open() {
            Ok(pty) => assert!(pty.name.starts_with("/dev/pts/"), "{}", pty.name),
            Err(err) => assert!(!err.to_string().is_empty()),
        }
    }

    #[test]
    fn relay_colours_plain_chunks_and_forwards_stdin() {
        let engine = engine();
        // `io::pipe` returns (reader, writer).
        let (child_out_rx, mut child_out) = io::pipe().expect("pipe");
        let (user_rx, user_tx) = io::pipe().expect("pipe");
        let master = child_out_rx.as_raw_fd();
        let user_in = user_rx.as_raw_fd();

        child_out.write_all(b"error: one\n").unwrap();
        drop(child_out);
        drop(user_tx);

        let mut out: Vec<u8> = Vec::new();
        let stats = relay(&engine, master, user_in, &mut out).unwrap();
        assert_eq!(stats.lines, 1);
        let text = String::from_utf8(out).unwrap();
        assert!(text.contains("\x1b["), "expected colour: {text:?}");
        assert!(text.ends_with('\n'));
    }

    #[test]
    fn relay_forwards_keystrokes_to_the_child() {
        use std::io::Read;
        use std::net::Shutdown;
        use std::os::unix::net::UnixStream;

        // The master side must be bidirectional (a pty master is); a socket
        // pair stands in for it here.
        let (master_side, mut child_side) = UnixStream::pair().expect("socketpair");
        let (user_rx, mut user_tx) = io::pipe().expect("pipe");
        let master = master_side.as_raw_fd();
        let user_fd = user_rx.as_raw_fd();

        user_tx.write_all(b"q").unwrap();
        drop(user_tx);
        // EOF on the child side ends the relay once the keystroke is forwarded.
        child_side.shutdown(Shutdown::Write).unwrap();

        let engine = engine();
        let mut out: Vec<u8> = Vec::new();
        let _ = relay(&engine, master, user_fd, &mut out);
        // Close our end, otherwise the reading side below waits for ever.
        drop(master_side);

        let mut forwarded = Vec::new();
        child_side.read_to_end(&mut forwarded).unwrap();
        assert_eq!(forwarded, b"q");
    }

    #[test]
    fn escape_chunks_pass_through_untouched() {
        let engine = engine();
        let (child_out_rx, mut child_out) = io::pipe().expect("pipe");
        let (user_rx, user_tx) = io::pipe().expect("pipe");
        let master = child_out_rx.as_raw_fd();
        let user_in = user_rx.as_raw_fd();

        let screen = b"\x1b[2J\x1b[H\x1b[31mred\x1b[0m\n".to_vec();
        child_out.write_all(&screen).unwrap();
        drop(child_out);
        drop(user_tx);

        let mut out: Vec<u8> = Vec::new();
        relay(&engine, master, user_in, &mut out).unwrap();
        assert_eq!(out, screen);
    }
}
