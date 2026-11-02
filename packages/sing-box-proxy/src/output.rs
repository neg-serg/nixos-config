//! stderr helpers matching the shell script's `say`/`ok`/`warn`/`fail`/`step`
//! and the live progress lines of `validate_nodes`.
//!
//! Colours are emitted only when the shell script would have enabled them:
//! stderr is a terminal, `NO_COLOR` is unset, and `TERM` is usable. The shell
//! used `tput`; the port emits the equivalent ANSI SGR sequences directly, so
//! the escape bytes can differ from terminfo while the visible result matches.

use std::env;
use std::io::{self, IsTerminal, Write};

pub const RESET: &str = "\x1b[0m";
pub const BOLD: &str = "\x1b[1m";
pub const DIM: &str = "\x1b[2m";
pub const GREEN: &str = "\x1b[32m";
pub const YELLOW: &str = "\x1b[33m";
pub const RED: &str = "\x1b[31m";
pub const CYAN: &str = "\x1b[36m";

pub struct Ui<'a> {
    writer: &'a mut dyn Write,
    color: bool,
    tty: bool,
}

impl<'a> Ui<'a> {
    pub fn new(writer: &'a mut dyn Write, color: bool, tty: bool) -> Self {
        Self { writer, color, tty }
    }

    /// Ui for the real stderr, with colour/tty detection like the shell.
    pub fn stderr(writer: &'a mut io::Stderr) -> Self {
        let tty = writer.is_terminal();
        let color = tty && color_env_ok();
        Self::new(writer, color, tty)
    }

    pub fn color(&self) -> bool {
        self.color
    }

    fn green(&self) -> &'static str {
        if self.color {
            GREEN
        } else {
            ""
        }
    }

    fn yellow(&self) -> &'static str {
        if self.color {
            YELLOW
        } else {
            ""
        }
    }

    fn red(&self) -> &'static str {
        if self.color {
            RED
        } else {
            ""
        }
    }

    fn cyan(&self) -> &'static str {
        if self.color {
            CYAN
        } else {
            ""
        }
    }

    fn bold(&self) -> &'static str {
        if self.color {
            BOLD
        } else {
            ""
        }
    }

    fn dim(&self) -> &'static str {
        if self.color {
            DIM
        } else {
            ""
        }
    }

    fn reset(&self) -> &'static str {
        if self.color {
            RESET
        } else {
            ""
        }
    }

    /// `say`: dim `::` prefix.
    pub fn say(&mut self, msg: &str) {
        let _ = write!(self.writer, "{}::{} {}\n", self.dim(), self.reset(), msg);
    }

    /// `ok`: green check mark.
    pub fn ok(&mut self, msg: &str) {
        let _ = write!(self.writer, "{}✓{} {}\n", self.green(), self.reset(), msg);
    }

    /// `warn`: yellow bang.
    pub fn warn(&mut self, msg: &str) {
        let _ = write!(self.writer, "{}!{} {}\n", self.yellow(), self.reset(), msg);
    }

    /// `fail`: red cross.
    pub fn fail(&mut self, msg: &str) {
        let _ = write!(self.writer, "{}✗{} {}\n", self.red(), self.reset(), msg);
    }

    /// `step`: bold `== title ==`, title in cyan.
    pub fn step(&mut self, msg: &str) {
        let _ = write!(
            self.writer,
            "{}== {}{} =={}\n",
            self.bold(),
            self.cyan(),
            msg,
            self.reset()
        );
    }

    /// Plain stderr line (the embedded python `log()`).
    pub fn raw(&mut self, msg: impl AsRef<str>) {
        let _ = writeln!(self.writer, "{}", msg.as_ref());
    }

    /// `progress()` from `validate_nodes`: carriage-returned single line on a
    /// tty, plain lines otherwise.
    pub fn progress(&mut self, msg: &str, final_line: bool) {
        if self.tty {
            let prefix = if final_line { "\n" } else { "\r" };
            let _ = write!(self.writer, "{prefix}{msg}");
            let _ = self.writer.flush();
        } else if !msg.is_empty() {
            let _ = writeln!(self.writer, "{msg}");
            let _ = self.writer.flush();
        }
    }

    pub fn flush(&mut self) {
        let _ = self.writer.flush();
    }
}

/// Mirrors the shell's `[ -t 2 ] && [ -z "${NO_COLOR:-}" ]` plus the tput
/// failure modes (no TERM / TERM=dumb produce no escape sequences).
pub fn color_env_ok() -> bool {
    if env::var_os("NO_COLOR").is_some() {
        return false;
    }
    match env::var("TERM") {
        Ok(term) => !term.is_empty() && term != "dumb",
        Err(_) => false,
    }
}
