//! Interactive file picker: raw-mode terminal UI with dual RU/EN layout,
//! dircolors coloring and the Lusty key bindings.
//!
//! Selection prints one line to stdout: ACTION<TAB>ABSOLUTE_PATH (action is
//! edit/tabedit/split/vsplit), then exits 0. Cancel exits 1 with no output.
//! Directory selection and C-w re-root the picker in place.

use std::io::{self, Write};
use std::path::PathBuf;

use crossterm::cursor;
use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyModifiers};
use crossterm::execute;
use crossterm::terminal::{self};

use crate::colors::{self, Colors};
use crate::listing::{self, Entry, FileKind, Options};
use crate::rank;

/// RU (йцукен) to EN characters, matching the Lua port's table. Physical
/// keys under the RU layout produce Cyrillic; map them back to the EN query
/// character (the '.' key produces 'ю' which maps to '.'; there is no '/'
/// row because it would override the dot).
pub fn ru_to_en(c: char) -> Option<char> {
    let en = match c {
        'й' => 'q', 'ц' => 'w', 'у' => 'e', 'к' => 'r', 'е' => 't',
        'н' => 'y', 'г' => 'u', 'ш' => 'i', 'щ' => 'o', 'з' => 'p',
        'х' => '[', 'ъ' => ']', 'ф' => 'a', 'ы' => 's', 'в' => 'd',
        'а' => 'f', 'п' => 'g', 'р' => 'h', 'о' => 'j', 'л' => 'k',
        'д' => 'l', 'ж' => ';', 'э' => '\'', 'я' => 'z', 'ч' => 'x',
        'с' => 'c', 'м' => 'v', 'и' => 'b', 'т' => 'n', 'ь' => 'm',
        'б' => ',', 'ю' => '.',
        _ => return None,
    };
    Some(en)
}

pub fn normalize_query_char(c: char) -> Option<char> {
    // Lowercase RU letters map to lowercase EN; uppercase RU letters (Shift)
    // map to uppercase EN so case-insensitive matching still sees the letter.
    let lower = c.to_lowercase().next().unwrap_or(c);
    let mapped = ru_to_en(lower).unwrap_or(lower);
    let out = if c.is_uppercase() {
        mapped.to_uppercase().next().unwrap_or(mapped)
    } else {
        mapped
    };
    // Accept printable ASCII (32..=126); punctuation is a regular query char.
    if out.is_ascii_graphic() || out == ' ' {
        Some(out)
    } else {
        None
    }
}

pub struct App {
    root: PathBuf,
    opts: Options,
    hidden: Option<Vec<Entry>>,
    dots: Option<Vec<Entry>>,
    query: String,
    ranked: Vec<usize>,
    needs_rank: bool,
    selected: usize,
    offset: usize,
    size: (usize, usize),
    palette: Colors,
}

impl App {
    pub fn new(root: PathBuf, opts: Options) -> App {
        let palette = colors::load();
        App {
            root,
            opts,
            hidden: None,
            dots: None,
            query: String::new(),
            ranked: Vec::new(),
            needs_rank: true,
            selected: 0,
            offset: 0,
            size: (80, 24),
            palette,
        }
    }

    fn show_dots(&self) -> bool {
        self.query.starts_with('.')
    }

    /// The listing backing the current view (hidden or dot-shown), listed on
    /// demand and cached per root.
    fn listing(&mut self) -> &Vec<Entry> {
        let dots = self.show_dots();
        let cache = if dots { &mut self.dots } else { &mut self.hidden };
        if cache.is_none() {
            let opts = Options {
                depth: self.opts.depth,
                skip_dirs: self.opts.skip_dirs.clone(),
                follow_mounts: self.opts.follow_mounts,
                show_dots: dots,
            };
            *cache = Some(listing::list(&self.root, &opts));
            self.needs_rank = true;
        }
        cache.as_ref().unwrap()
    }

    fn ranked_len(&mut self) -> usize {
        self.ensure_ranked();
        self.ranked.len()
    }

    fn ensure_ranked(&mut self) {
        if !self.needs_rank {
            return;
        }
        let query = self.query.clone();
        let entries = self.listing();
        self.ranked = rank::rank_indices(entries, &query);
        self.needs_rank = false;
        if self.selected >= self.ranked.len() && !self.ranked.is_empty() {
            self.selected = self.ranked.len() - 1;
        }
    }

    fn entry_at(&mut self, list_i: usize) -> Entry {
        self.ensure_ranked();
        let i = self.ranked[list_i];
        let entries = self.listing();
        entries[i].clone()
    }

    fn re_root(&mut self, dir: PathBuf) {
        self.root = dir;
        self.hidden = None;
        self.dots = None;
        self.query.clear();
        self.ranked = Vec::new();
        self.needs_rank = true;
        self.selected = 0;
        self.offset = 0;
    }

    fn move_sel(&mut self, delta: isize) {
        let n = self.ranked_len();
        if n == 0 {
            self.selected = 0;
            return;
        }
        self.selected = ((self.selected as isize + delta).rem_euclid(n as isize)) as usize;
    }

    fn column_nav(&mut self, delta: isize, row_count: usize) {
        let n = self.ranked_len();
        if n == 0 || row_count == 0 {
            self.selected = 0;
            return;
        }
        let columns = (n + row_count - 1) / row_count;
        let cur_col = self.selected / row_count;
        let cur_row = self.selected % row_count;
        let columns_i = columns as isize;
        let mut new_col = ((cur_col as isize) + delta).rem_euclid(columns_i);
        if (new_col + 1) * (row_count as isize + 1) > n as isize {
            new_col = if delta > 0 { 0 } else { (columns_i - 2).max(0) };
        }
        let mut s = new_col * row_count as isize + cur_row as isize;
        if s >= n as isize {
            s = n as isize - 1;
        }
        self.selected = s.max(0) as usize;
    }

    fn open(&mut self, action: &str) -> io::Result<()> {
        if self.ranked.is_empty() {
            return Ok(());
        }
        let entry = self.entry_at(self.selected);
        if entry.kind == FileKind::Dir {
            self.re_root(entry.path);
            return Ok(());
        }
        // No alternate screen here: the picker usually runs inside a nvim
        // terminal buffer (possibly itself inside a web xterm), whose
        // alt-screen emulation is unreliable. The shim deletes the buffer on
        // exit anyway, so clear the frame and print the selection.
        let esc = char::from_u32(0x1b).unwrap();
        write!(io::stdout(), "{esc}[2J{esc}[H")?;
        terminal::disable_raw_mode()?;
        execute!(io::stdout(), cursor::Show)?;
        let mut so = io::stdout().lock();
        writeln!(so, "{}\t{}", action, entry.path.display())?;
        so.flush()?;
        std::process::exit(0);
    }

    pub fn run(&mut self) -> io::Result<i32> {
        terminal::enable_raw_mode()?;
        let mut stdout = io::stdout();
        execute!(stdout, cursor::Hide)?;
        // The ioctl size can be stale when running inside a nvim terminal
        // buffer; ask the terminal emulator directly (DSR cursor report after
        // moving to a huge position) for the real grid size.
        if let Some((cols, rows)) = probe_size() {
            self.size = (cols, rows);
        } else {
            let (c, r) = terminal::size().unwrap_or((80, 24));
            self.size = ((c as usize).max(40), (r as usize).max(10));
        }
        let result = self.loop_events(&mut stdout);
        let esc = char::from_u32(0x1b).unwrap();
        write!(stdout, "{esc}[2J{esc}[H")?;
        terminal::disable_raw_mode()?;
        execute!(stdout, cursor::Show)?;
        result
    }
}

/// Ask the terminal for its real dimensions: move the cursor far away and
/// request its position (DSR). Every emulator answers ESC[<row>;<col>R.
fn probe_size() -> Option<(usize, usize)> {
    use std::io::Read;
    use std::os::unix::io::AsRawFd;
    use std::time::{Duration, Instant};

    let esc = char::from_u32(0x1b).unwrap();
    let mut out = io::stdout();
    write!(out, "{esc}[9999;9999H{esc}[6n").ok()?;
    out.flush().ok()?;

    let deadline = Instant::now() + Duration::from_millis(400);
    let mut stdin = io::stdin();
    let mut buf = Vec::new();
    let mut byte = [0u8; 1];
    loop {
        if Instant::now() >= deadline {
            return None;
        }
        let remaining = deadline.saturating_duration_since(Instant::now());
        let ms = remaining.as_millis().min(100) as i32;
        let mut fds = [libc::pollfd {
            fd: stdin.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        }];
        // SAFETY: fds is a valid array of pollfds for the stdin fd.
        let rc = unsafe { libc::poll(fds.as_mut_ptr(), 1, ms) };
        if rc <= 0 {
            continue; // timeout or poll error
        }
        if stdin.read(&mut byte).is_err() {
            return None;
        }
        buf.push(byte[0]);
        if byte[0] == b'R' {
            break;
        }
    }
    let s = String::from_utf8_lossy(&buf);
    let (row, col) = parse_dsr(&s)?;
    Some((col, row))
}

/// Parse ESC[<row>;<col>R.
fn parse_dsr(s: &str) -> Option<(usize, usize)> {
    let inner = s.rsplit('[').next()?;
    let inner = inner.strip_suffix('R')?;
    let mut parts = inner.split(';');
    let row: usize = parts.next()?.trim().parse().ok()?;
    let col: usize = parts.next()?.trim().parse().ok()?;
    Some((row, col))
}

impl App {
    fn list_rows(&self) -> usize {
        let h = self.size.1;
        h.saturating_sub(1).max(1)
    }

    /// Adaptive columns: as many as the content needs (ceil(total/rows)),
    /// no more than fit the width given the widest name (capped at 20).
    fn max_cols(&mut self) -> usize {
        let w = self.size.0;
        let rows = self.list_rows();
        let total = self.ranked.len().max(1);
        let needed = total.div_ceil(rows).max(1);
        let name_w = self.max_name_w().min(20).max(1);
        let byw = ((w + 2) / (name_w + 4)).max(1);
        needed.min(byw).min(8).max(1)
    }

    fn col_width(&mut self) -> usize {
        let cols = self.max_cols();
        let w = self.size.0;
        // pitch = col_w + 2 separator; ensure cols*col_w + 2*(cols-1) <= w
        let text_w = w.saturating_sub(2 * (cols - 1));
        (text_w / cols).max(6)
    }

    /// Widest label (in chars) over the full listing of the current root.
    fn max_name_w(&mut self) -> usize {
        let entries = self.listing();
        entries.iter().map(|e| e.label.chars().count()).max().unwrap_or(0)
    }

    fn clamp_offset(&mut self, rows: usize) {
        let n = self.ranked.len();
        if n == 0 {
            self.offset = 0;
            return;
        }
        if self.selected < self.offset {
            self.offset = self.selected;
        } else if self.selected >= self.offset + rows {
            self.offset = self.selected + 1 - rows;
        }
        if self.offset + rows > n && n >= rows {
            self.offset = n - rows;
        }
        if self.offset > self.selected {
            self.offset = self.selected;
        }
    }

    fn loop_events(&mut self, out: &mut io::Stdout) -> io::Result<i32> {
        loop {
            self.draw(out)?;
            let ev = event::read()?;
            match ev {
                Event::Key(KeyEvent { code, modifiers, .. }) => {
                    let ctrl = modifiers.contains(KeyModifiers::CONTROL);
                    match (code, ctrl) {
                        (KeyCode::Esc, _) => return Ok(1),
                        (KeyCode::Char('c' | 'g'), true) => return Ok(1),
                        (KeyCode::Enter | KeyCode::Tab, _) => self.open("edit")?,
                        (KeyCode::Char('t'), true) => self.open("tabedit")?,
                        (KeyCode::Char('o'), true) => self.open("split")?,
                        (KeyCode::Char('v'), true) => self.open("vsplit")?,
                        (KeyCode::Char('n'), true) | (KeyCode::Down, _) => self.move_sel(1),
                        (KeyCode::Char('p'), true) | (KeyCode::Up, _) => self.move_sel(-1),
                        (KeyCode::Char('f'), true) | (KeyCode::Right, _) => {
                            let rows = self.list_rows();
                            self.column_nav(1, rows);
                        }
                        (KeyCode::Char('b'), true) | (KeyCode::Left, _) => {
                            let rows = self.list_rows();
                            self.column_nav(-1, rows);
                        }
                        (KeyCode::Char('w'), true) => {
                            if let Some(parent) = self.root.parent() {
                                if parent != self.root {
                                    self.re_root(parent.to_path_buf());
                                }
                            }
                        }
                        (KeyCode::Char('u'), true) => {
                            if !self.query.is_empty() {
                                self.query.clear();
                                self.needs_rank = true;
                                self.selected = 0;
                            }
                        }
                        (KeyCode::Backspace, _) => {
                            if self.query.pop().is_some() {
                                self.needs_rank = true;
                                self.selected = 0;
                            }
                        }
                        (KeyCode::Char(c), false) => {
                            if let Some(c) = normalize_query_char(c) {
                                self.query.push(c);
                                self.needs_rank = true;
                                self.selected = 0;
                            }
                        }
                        _ => {}
                    }
                }
                Event::Resize(_, _) => {}
                _ => {}
            }
            self.clamp_offset(self.list_rows());
        }
    }

    fn draw(&mut self, out: &mut io::Stdout) -> io::Result<()> {
        self.ensure_ranked();
        let (w, h) = self.size;
        let rows = self.list_rows();
        let cols = self.max_cols();
        let col_w = self.col_width();
        let esc = char::from_u32(0x1b).unwrap();
        let mut frame = String::with_capacity((w + 64) * (rows + 2));

        frame.push(esc);
        frame.push_str("[2J");
        frame.push(esc);
        frame.push_str("[H");

        // row-major grid: fill a row left-to-right, then the next row down
        for r in 0..rows {
            let mut line = String::new();
            for c in 0..cols {
                let pos = self.offset + r * cols + c;
                let mut cell = String::new();
                let selected = pos == self.selected;
                if pos < self.ranked.len() {
                    let i = self.ranked[pos];
                    let e = self.listing()[i].clone();
                    if selected {
                        // neg.nvim PmenuSel style: lit blue bar + light text
                        cell.push(esc);
                        cell.push_str("[48;2;0;95;175;1;38;2;209;229;255m");
                    } else {
                        let exec = e.kind == FileKind::File && is_exec(&e.path);
                        if let Some(code) = self.palette.code_for(&e.name, e.kind, exec) {
                            cell.push(esc);
                            cell.push('[');
                            cell.push_str(code);
                            cell.push('m');
                        }
                    }
                    cell.push_str(&e.label);
                    if e.kind == FileKind::Dir {
                        cell.push('/');
                    }
                    cell.push(esc);
                    cell.push_str("[0m");
                }
                ansi_pad(&mut cell, col_w);
                line.push_str(&cell);
                if c + 1 < cols {
                    line.push_str("  ");
                }
            }
            ansi_pad(&mut line, w.saturating_sub(1).max(1));
            frame.push_str(&line);
            frame.push('\n');
        }

        let mut prompt = self.prompt_line();
        ansi_pad(&mut prompt, w.saturating_sub(1).max(1));
        frame.push_str(&prompt);
        if let Ok(db) = std::env::var("LUSTY_DUMP_FRAME") {
            let _ = std::fs::write(&db, &frame);
        }
        write!(out, "{frame}")?;
        out.flush()
    }

    fn prompt_line(&self) -> String {
        let esc = char::from_u32(0x1b).unwrap();
        let mut out = String::new();
        let mut push_painted = |text: &str, code: &str, out: &mut String| {
            if text.is_empty() {
                return;
            }
            out.push(esc);
            out.push('[');
            out.push_str(code);
            out.push('m');
            out.push_str(text);
        };
        let mut path = self.root.display().to_string();
        if let Ok(home) = std::env::var("HOME") {
            if path.starts_with(&home) {
                path = format!("~{}", &path[home.len()..]);
            }
        }
        if let Some(rest) = path.strip_prefix('~') {
            push_painted("~", "38;2;40;115;115", &mut out);
            path = rest.to_string();
        }
        let mut current = String::new();
        for ch in path.chars() {
            if ch == '/' {
                push_painted(&current, "38;2;149;167;188", &mut out);
                push_painted("/", "38;2;0;95;175", &mut out);
                current.clear();
            } else {
                current.push(ch);
            }
        }
        push_painted(&current, "38;2;149;167;188", &mut out);
        push_painted(" \u{f105} ", "38;2;0;95;175", &mut out);
        push_painted(&self.query, "1;38;2;255;255;255", &mut out);
        out.push(esc);
        out.push_str("[0m");
        out
    }
}

fn is_exec(path: &std::path::Path) -> bool {
    std::fs::metadata(path)
        .map(|m| std::os::unix::fs::PermissionsExt::mode(&m.permissions()) & 0o111 != 0)
        .unwrap_or(false)
}

fn ansi_pad(line: &mut String, width: usize) {
    let src: Vec<char> = line.chars().collect();
    let mut out = String::with_capacity(src.len() + width);
    let mut vis = 0usize;
    let mut in_esc = false;
    let mut had_sgr = false;
    for &c in &src {
        if in_esc {
            out.push(c);
            // '[' after ESC is the CSI introducer, not a final byte; the
            // escape ends at the first real final byte (0x40..=0x7e).
            if c == '[' {
                continue;
            }
            if (0x40..=0x7e).contains(&(c as u32)) {
                in_esc = false;
                if c == 'm' {
                    had_sgr = true;
                }
            }
            continue;
        }
        if c == '\x1b' {
            in_esc = true;
            out.push(c);
            continue;
        }
        if vis >= width {
            continue; // truncate visible content past the width
        }
        out.push(c);
        vis += 1;
    }
    if vis > width && had_sgr {
        out.push_str("\x1b[0m"); // ensure colors are closed after a cut
    }
    if vis < width {
        if had_sgr && !out.ends_with("\x1b[0m") {
            out.push_str("\x1b[0m");
        }
        while vis < width {
            out.push(' ');
            vis += 1;
        }
    }
    *line = out;
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ru_layout_maps_to_en() {
        assert_eq!(normalize_query_char('и'), Some('b'));
        assert_eq!(normalize_query_char('ю'), Some('.'));
        assert_eq!(normalize_query_char('б'), Some(','));
        assert_eq!(normalize_query_char('е'), Some('t'));
        // Uppercase RU (Shift) maps to uppercase EN.
        assert_eq!(normalize_query_char('И'), Some('B'));
        // EN letters pass through.
        assert_eq!(normalize_query_char('b'), Some('b'));
        assert_eq!(normalize_query_char('.'), Some('.'));
    }

    #[test]
    fn non_ascii_unmapped_is_dropped() {
        assert_eq!(normalize_query_char('ä'), None);
    }
}

#[cfg(test)]
mod apad_test {
    #[test]
    fn ansi_pad_keeps_escapes() {
        let esc = char::from_u32(0x1b).unwrap();
        let mut s = format!("{}[48;2;0;95;175;1;38;2;209;229;255mdoc/{}[0m", esc, esc);
        eprintln!("INPUT: {:?}", s);
        super::ansi_pad(&mut s, 22);
        eprintln!("OUT: {:?}", s);
        eprintln!("CHARS: {:?}", s.chars().collect::<Vec<_>>());
    }
}
