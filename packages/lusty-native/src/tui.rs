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
use crossterm::terminal::{self, EnterAlternateScreen, LeaveAlternateScreen};

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
    last_w: usize,
    last_h: usize,
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
            last_w: 0,
            last_h: 0,
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
        terminal::disable_raw_mode()?;
        execute!(io::stdout(), LeaveAlternateScreen, cursor::Show)?;
        let mut so = io::stdout().lock();
        writeln!(so, "{}\t{}", action, entry.path.display())?;
        so.flush()?;
        std::process::exit(0);
    }

    pub fn run(&mut self) -> io::Result<i32> {
        terminal::enable_raw_mode()?;
        let mut stdout = io::stdout();
        execute!(stdout, EnterAlternateScreen, cursor::Hide)?;
        let result = self.loop_events(&mut stdout);
        terminal::disable_raw_mode()?;
        execute!(stdout, LeaveAlternateScreen, cursor::Show)?;
        result
    }
}

impl App {
    fn list_rows(&self) -> usize {
        let (_, h) = terminal::size().unwrap_or((80, 24));
        (h as usize).saturating_sub(2).max(1)
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
        let (w, h) = terminal::size().unwrap_or((80, 24));
        let w = w as usize;
        let rows = (h as usize).saturating_sub(2).max(1);
        let esc = char::from_u32(0x1b).unwrap();
        let mut frame = String::with_capacity((w + 48) * (rows + 2));

        // Full clear only on geometry change: every frame redraws all rows
        // padded to the exact width, so stale wrap artifacts cannot survive.
        if self.last_w != w || self.last_h != h as usize {
            frame.push(esc);
            frame.push_str("[2J");
            self.last_w = w;
            self.last_h = h as usize;
        }
        frame.push(esc);
        frame.push_str("[H");

        // Status line: root + query + counts.
        let mut status = String::new();
        status.push(esc);
        status.push_str("[2m");
        status.push_str(&self.root.display().to_string());
        if !self.query.is_empty() {
            status.push_str("  q=");
            status.push_str(&self.query);
        }
        status.push_str(&format!("  ({} of {})", self.ranked.len(), self.listing().len()));
        status.push(esc);
        status.push_str("[0m");
        ansi_pad(&mut status, w);
        frame.push_str(&status);
        frame.push('\n');

        // Result rows.
        for r in 0..rows {
            let list_i = self.offset + r;
            let mut line = String::new();
            if list_i < self.ranked.len() {
                let e = self.entry_at(list_i);
                if list_i == self.selected {
                    line.push(esc);
                    line.push_str("[48;5;237m");
                }
                let exec = e.kind == FileKind::File && is_exec(&e.path);
                if let Some(code) = self.palette.code_for(&e.name, e.kind, exec) {
                    line.push(esc);
                    line.push('[');
                    line.push_str(code);
                    line.push('m');
                }
                line.push_str(&e.label);
                if e.kind == FileKind::Dir {
                    line.push('/');
                }
                line.push(esc);
                line.push_str("[0m");
            } else if self.ranked.is_empty() && list_i == 0 {
                line.push_str("(no matches)");
            }
            ansi_pad(&mut line, w);
            frame.push_str(&line);
            frame.push('\n');
        }

        // Prompt line at the bottom.
        frame.push_str(">> ");
        frame.push_str(&self.query);
        ansi_pad(&mut frame, w);
        write!(out, "{frame}")?;
        out.flush()
    }
}

fn is_exec(path: &std::path::Path) -> bool {
    std::fs::metadata(path)
        .map(|m| std::os::unix::fs::PermissionsExt::mode(&m.permissions()) & 0o111 != 0)
        .unwrap_or(false)
}

/// Pad or truncate a possibly-ANSI-colored line to the given number of
/// visible columns. Escape sequences count as zero width and are always
/// preserved, so a truncated colored label still closes its SGR codes.
fn ansi_pad(line: &mut String, width: usize) {
    let src: Vec<char> = line.chars().collect();
    let mut out = String::with_capacity(src.len() + width);
    let mut vis = 0usize;
    let mut in_esc = false;
    let mut had_sgr = false;
    for &c in &src {
        if in_esc {
            out.push(c);
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
