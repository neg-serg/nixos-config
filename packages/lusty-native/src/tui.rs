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

use crate::cache;
use crate::colors::{self, Colors};
use crate::listing::{Entry, FileKind, Options};
use crate::rank;

/// RU (йцукен) to EN characters, matching the Lua port's table. Physical
/// keys under the RU layout produce Cyrillic; map them back to the EN query
/// character (the '.' key produces 'ю' which maps to '.'; there is no '/'
/// row because it would override the dot).
pub fn ru_to_en(c: char) -> Option<char> {
    let en = match c {
        'й' => 'q',
        'ц' => 'w',
        'у' => 'e',
        'к' => 'r',
        'е' => 't',
        'н' => 'y',
        'г' => 'u',
        'ш' => 'i',
        'щ' => 'o',
        'з' => 'p',
        'х' => '[',
        'ъ' => ']',
        'ф' => 'a',
        'ы' => 's',
        'в' => 'd',
        'а' => 'f',
        'п' => 'g',
        'р' => 'h',
        'о' => 'j',
        'л' => 'k',
        'д' => 'l',
        'ж' => ';',
        'э' => '\'',
        'я' => 'z',
        'ч' => 'x',
        'с' => 'c',
        'м' => 'v',
        'и' => 'b',
        'т' => 'n',
        'ь' => 'm',
        'б' => ',',
        'ю' => '.',
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
    cursor_row: Option<usize>,
    box_w: usize,            // popup inner width (content columns between the borders)
    box_h: usize,            // popup outer height including the two border rows
    pop_top: usize,          // 0-based screen row of the popup top border
    ui_rows: Option<usize>,  // user popup height (outer rows incl borders)
    ui_width: Option<usize>, // user popup width (outer columns incl borders)
    long: bool,              // eza -l style: one entry per row with mode/size/date
    icons: bool,             // nerd-font icons per entry + dir icon before the prompt
    reverse: bool,           // eza --reverse per depth
    dirs_first: bool,        // eza --group-dirs-first
    sort_mode: u8,           // 0 name, 1 ext, 2 size, 3 time
    cols_mask: u8,           // long view fields: 1 perm, 2 user, 4 size, 8 time
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
            cursor_row: None,
            box_w: 78,
            box_h: OUTER_ROWS,
            pop_top: 0,
            ui_rows: None,
            ui_width: None,
            long: false,
            icons: std::env::var("LUSTY_ICONS")
                .map(|v| v == "1")
                .unwrap_or(false),
            reverse: false,
            dirs_first: false,
            sort_mode: 0,
            cols_mask: 15,
            palette,
        }
    }

    /// Override the popup size. CLI flags win over LUSTY_ROWS/LUSTY_WIDTH
    /// env vars; None keeps the default (14 outer rows, full terminal
    /// columns, i.e. 12 content rows and 100 content columns).
    /// Apply eza-style order tweaks to in-memory listings.
    pub fn set_sort(&mut self, reverse: bool, dirs_first: bool) {
        self.reverse = reverse;
        self.dirs_first = dirs_first;
    }

    pub fn set_sort_mode(&mut self, mode: u8) {
        self.sort_mode = mode;
    }

    /// Set the long-view columns from a comma list (perm,user,size,time).
    pub fn set_columns(&mut self, spec: &str) {
        let mut mask = 0u8;
        for tok in spec.split(',').map(|t| t.trim()).filter(|t| !t.is_empty()) {
            match tok {
                "perm" => mask |= 1,
                "user" => mask |= 2,
                "size" => mask |= 4,
                "time" => mask |= 8,
                _ => {}
            }
        }
        if mask != 0 {
            self.cols_mask = mask;
        }
    }

    /// Enable the long listing view (mode/size/date + name per row).
    pub fn set_long(&mut self, on: bool) {
        self.long = on;
    }

    pub fn set_ui(&mut self, rows: Option<usize>, width: Option<usize>) {
        let env_usize = |name: &str| {
            std::env::var(name)
                .ok()
                .and_then(|v| v.trim().parse::<usize>().ok())
        };
        self.ui_rows = rows.or_else(|| env_usize("LUSTY_ROWS"));
        self.ui_width = width.or_else(|| env_usize("LUSTY_WIDTH"));
    }

    fn show_dots(&self) -> bool {
        self.query.starts_with('.')
    }

    /// The listing backing the current view (hidden or dot-shown), listed on
    /// demand and cached per root.
    fn listing(&mut self) -> &Vec<Entry> {
        let dots = self.show_dots();
        let cache = if dots {
            &mut self.dots
        } else {
            &mut self.hidden
        };
        if cache.is_none() {
            let opts = Options {
                depth: self.opts.depth,
                skip_dirs: self.opts.skip_dirs.clone(),
                follow_mounts: self.opts.follow_mounts,
                show_dots: dots,
            };
            let mut listed = cache::cached_list(&self.root, &opts);
            match self.sort_mode {
                1 => crate::listing::sort_by_ext(&mut listed),
                2 => crate::listing::sort_by_meta(&self.root, &mut listed, false),
                3 => crate::listing::sort_by_meta(&self.root, &mut listed, true),
                _ => crate::listing::reorder(&mut listed, self.dirs_first, self.reverse),
            }
            *cache = Some(listed);
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

    /// '/' descends into a directory when the typed prefix uniquely names one
    /// (exact name or unique prefix among the immediate children), shell
    /// style; a lone '/' moves to the filesystem root, Lusty style. When the
    /// prefix is not unique, '/' is typed as an ordinary character.
    fn slash_enter(&mut self) {
        let q = self.query.clone();
        if q.is_empty() {
            let root = std::path::PathBuf::from("/");
            if self.root != root {
                self.re_root(root);
            }
            return;
        }
        let ql = q.to_lowercase();
        let entries = self.listing().clone();
        let mut cand: Option<String> = None;
        let mut dup = false;
        for e in entries.iter() {
            if e.kind != FileKind::Dir || e.depth != 1 {
                continue;
            }
            let nl = e.basename().to_lowercase();
            if nl == ql || nl.starts_with(&ql) {
                if cand.is_some() {
                    dup = true;
                } else {
                    cand = Some(e.basename().to_string());
                }
            }
        }
        if let (Some(n), false) = (cand, dup) {
            let path = if self.root == std::path::Path::new("/") {
                std::path::PathBuf::from("/").join(&n)
            } else {
                self.root.join(&n)
            };
            self.re_root(path);
            return;
        }
        // not a unique directory: let '/' be typed as an ordinary character
        self.query.push('/');
        self.needs_rank = true;
        self.selected = 0;
        self.offset = 0;
    }

    fn open(&mut self, action: &str) -> io::Result<()> {
        if self.ranked.is_empty() {
            return Ok(());
        }
        let entry = self.entry_at(self.selected);
        if entry.kind == FileKind::Dir {
            self.re_root(entry.path(&self.root));
            return Ok(());
        }
        // No alternate screen here: the picker usually runs inside a nvim
        // terminal buffer (possibly itself inside a web xterm), whose
        // alt-screen emulation is unreliable. The shim deletes the buffer on
        // exit anyway, so clear the frame and print the selection.
        // clear the panel first, then park the cursor at its first row (right
        // under the command line) so the selection prints like normal shell
        // output, not below a gap of erased panel rows
        self.clear_panel(&mut io::stdout())?;
        let esc = char::from_u32(0x1b).unwrap();
        write!(io::stdout(), "{esc}[{};1H", self.panel_top() + 1)?;
        terminal::disable_raw_mode()?;
        execute!(io::stdout(), cursor::Show)?;
        let mut so = io::stdout().lock();
        writeln!(so, "{}\t{}", action, entry.path(&self.root).display())?;
        so.flush()?;
        std::process::exit(0);
    }

    pub fn run(&mut self) -> io::Result<i32> {
        terminal::enable_raw_mode()?;
        let mut stdout = io::stdout();
        execute!(stdout, cursor::Hide)?;
        // Capture the prompt position first: the cursor sits on the
        // empty line right below the command line the picker was
        // launched from.
        self.cursor_row = probe_cursor_row();
        // The ioctl size can be stale when running inside a nvim
        // terminal buffer; ask the terminal emulator directly (DSR
        // cursor report after moving to a huge position) for the real
        // grid size.
        let probed = probe_size();
        if let Some((cols, rows)) = probed {
            self.size = (cols, rows);
        } else {
            let (c, r) = terminal::size().unwrap_or((80, 24));
            self.size = ((c as usize).max(40), (r as usize).max(10));
        }
        let h = self.size.1;
        self.compute_box();
        // Place the box directly under the command line; when it would
        // run past the bottom of the screen, scroll the content up first
        // (fzf --height behaviour). probe_size parked the cursor on the
        // bottom row, so plain newlines scroll.
        let esc = char::from_u32(0x1b).unwrap();
        let r0 = self
            .cursor_row
            .map(|r| r.min(h.saturating_sub(1)))
            .unwrap_or(h.saturating_sub(self.box_h));
        let scroll_by = (r0 + self.box_h).saturating_sub(h);
        if scroll_by > 0 && probed.is_some() {
            let mut s = String::with_capacity(scroll_by + 1);
            for _ in 0..scroll_by {
                s.push('\n');
            }
            write!(stdout, "{s}")?;
            stdout.flush()?;
            self.pop_top = r0 - scroll_by;
        } else if scroll_by > 0 {
            self.pop_top = h.saturating_sub(self.box_h);
        } else {
            self.pop_top = r0;
        }
        let result = self.loop_events(&mut stdout);
        // Clear first, then park the cursor at the top of the popup area
        // so the shell continues directly under the command line.
        self.clear_panel(&mut stdout)?;
        write!(stdout, "{esc}[{};1H", self.panel_top() + 1)?;
        terminal::disable_raw_mode()?;
        execute!(stdout, cursor::Show)?;
        result
    }
}

/// Ask the terminal for its real dimensions: move the cursor far away and
/// request its position (DSR). Every emulator answers ESC[<row>;<col>R.
fn probe_size() -> Option<(usize, usize)> {
    use std::time::{Duration, Instant};

    let esc = char::from_u32(0x1b).unwrap();
    let mut out = io::stdout();
    write!(out, "{esc}[9999;9999H{esc}[6n").ok()?;
    out.flush().ok()?;

    let deadline = Instant::now() + Duration::from_millis(400);
    let mut buf = Vec::new();
    let mut byte = [0u8; 1];
    loop {
        if Instant::now() >= deadline {
            return None;
        }
        let remaining = deadline.saturating_duration_since(Instant::now());
        let ms = remaining.as_millis().min(100) as i32;
        let mut fds = [libc::pollfd {
            fd: 0,
            events: libc::POLLIN,
            revents: 0,
        }];
        // SAFETY: fds is a valid array of pollfds for the stdin fd.
        let rc = unsafe { libc::poll(fds.as_mut_ptr(), 1, ms) };
        if rc <= 0 {
            continue; // timeout or poll error
        }
        // Read raw from fd 0; see probe_cursor_row for why not io::stdin.
        // SAFETY: byte is a valid 1-byte buffer for the stdin fd.
        let n = unsafe { libc::read(0, byte.as_mut_ptr().cast(), 1) };
        if n <= 0 {
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
/// Ask the terminal where the cursor is (DSR), so the panel can start right
/// below the command line. Returns the 0-based row.
fn probe_cursor_row() -> Option<usize> {
    use std::time::{Duration, Instant};

    let esc = char::from_u32(0x1b).unwrap();
    let mut out = io::stdout();
    write!(out, "{esc}[6n").ok()?;
    out.flush().ok()?;

    let deadline = Instant::now() + Duration::from_millis(200);
    let mut buf = Vec::new();
    let mut byte = [0u8; 1];
    loop {
        if Instant::now() >= deadline {
            return None;
        }
        let remaining = deadline.saturating_duration_since(Instant::now());
        let ms = remaining.as_millis().min(50) as i32;
        let mut fds = [libc::pollfd {
            fd: 0,
            events: libc::POLLIN,
            revents: 0,
        }];
        // SAFETY: valid pollfd array for the stdin fd.
        let rc = unsafe { libc::poll(fds.as_mut_ptr(), 1, ms) };
        if rc <= 0 {
            continue;
        }
        // Read raw from fd 0 (not io::stdin, whose BufReader would swallow
        // the rest of the DSR reply and strand it outside the kernel queue).
        // SAFETY: byte is a valid 1-byte buffer for the stdin fd.
        let n = unsafe { libc::read(0, byte.as_mut_ptr().cast(), 1) };
        if n <= 0 {
            return None;
        }
        buf.push(byte[0]);
        if byte[0] == b'R' {
            break;
        }
    }
    let s = String::from_utf8_lossy(&buf);
    let (row, _col) = parse_dsr(&s)?;
    Some(row.saturating_sub(1))
}

fn parse_dsr(s: &str) -> Option<(usize, usize)> {
    let inner = s.rsplit('[').next()?;
    let inner = inner.strip_suffix('R')?;
    let mut parts = inner.split(';');
    let row: usize = parts.next()?.trim().parse().ok()?;
    let col: usize = parts.next()?.trim().parse().ok()?;
    Some((row, col))
}

impl App {
    /// Recompute the popup box size from the current screen size and the
    /// user overrides (--rows/--width or LUSTY_ROWS/LUSTY_WIDTH). Both
    /// dimensions are clamped so the outer box never exceeds the terminal;
    /// defaults are OUTER_ROWS rows and the full terminal width.
    fn compute_box(&mut self) {
        let (w, h) = self.size;
        let outer_h = match self.ui_rows {
            Some(r) => r.clamp(5, 200).min(h),
            None => OUTER_ROWS.min(h),
        };
        self.box_h = outer_h.max(1);
        let outer_w = match self.ui_width {
            Some(uw) => uw.clamp(10, 400).min(w),
            None => w, // default: span the whole terminal width
        };
        self.box_w = outer_w.saturating_sub(2);
    }

    fn list_rows(&self) -> usize {
        // Content rows inside the borders minus the prompt line at the
        // bottom (box_h includes the two border rows).
        self.box_h.saturating_sub(3).max(1)
    }

    /// 0-based screen row of the popup top border, fixed at startup to
    /// sit directly under the command line the picker was launched from.
    fn panel_top(&self) -> usize {
        self.pop_top
    }

    /// Adaptive columns: as many as the content needs (ceil(total/rows)),
    /// no more than fit the popup width given the widest name (capped at 20).
    fn max_cols(&mut self) -> usize {
        let w = self.box_w;
        let rows = self.list_rows();
        let total = self.ranked.len().max(1);
        let needed = total.div_ceil(rows).max(1);
        let name_w = self.max_name_w().min(20).max(1);
        let byw = ((w + 2) / (name_w + 4)).max(1);
        needed.min(byw).min(8).max(1)
    }

    fn col_width(&mut self) -> usize {
        let cols = self.max_cols();
        let w = self.box_w;
        // pitch = col_w + 2 separator; ensure cols*col_w + 2*(cols-1) <= w
        let text_w = w.saturating_sub(2 * (cols - 1));
        (text_w / cols).max(6)
    }

    /// Widest label (in chars) over the full listing of the current root.
    fn max_name_w(&mut self) -> usize {
        let entries = self.listing();
        entries
            .iter()
            .map(|e| e.label.chars().count())
            .max()
            .unwrap_or(0)
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
                Event::Key(KeyEvent {
                    code, modifiers, ..
                }) => {
                    let ctrl = modifiers.contains(KeyModifiers::CONTROL);
                    match (code, ctrl) {
                        (KeyCode::Esc, _) => return Ok(1),
                        (KeyCode::Char('c' | 'g'), true) => return Ok(1),
                        (KeyCode::Enter | KeyCode::Tab, _) => self.open("edit")?,
                        (KeyCode::Char('t'), true) => self.open("tabedit")?,
                        (KeyCode::Char('o'), true) => self.open("split")?,
                        (KeyCode::Char('v'), true) => self.open("vsplit")?,
                        (KeyCode::Char('n'), true)
                        | (KeyCode::Char('j'), true)
                        | (KeyCode::Down, _) => {
                            self.move_sel(1);
                        }
                        (KeyCode::Char('p'), true)
                        | (KeyCode::Char('k'), true)
                        | (KeyCode::Up, _) => {
                            self.move_sel(-1);
                        }
                        (KeyCode::Char('f'), true) | (KeyCode::Right, _) => {
                            let rows = self.list_rows();
                            self.column_nav(1, rows);
                        }
                        (KeyCode::Char('b'), true) | (KeyCode::Left, _) => {
                            let rows = self.list_rows();
                            self.column_nav(-1, rows);
                        }
                        (KeyCode::Char('w'), true) => {
                            // First C-w clears the typed query (shell/vim
                            // word-delete feel); only a second C-w with an
                            // empty query moves up a directory.
                            if !self.query.is_empty() {
                                self.query.clear();
                                self.needs_rank = true;
                                self.selected = 0;
                                self.offset = 0;
                            } else if let Some(parent) = self.root.parent() {
                                if parent != self.root {
                                    self.re_root(parent.to_path_buf());
                                }
                            }
                        }
                        (KeyCode::Char('l'), true) => self.long = !self.long,
                        (KeyCode::Char('u'), true) => {
                            if !self.query.is_empty() {
                                self.query.clear();
                                self.needs_rank = true;
                                self.selected = 0;
                            }
                        }
                        // readline-ish: C-h = backspace, Home/End = first/last,
                        // PgUp/PgDn = one page of the grid
                        (KeyCode::Char('h'), true) => {
                            if self.query.pop().is_some() {
                                self.needs_rank = true;
                                self.selected = 0;
                            }
                        }
                        (KeyCode::Home, _) | (KeyCode::Char('a'), true) => {
                            if self.ranked_len() > 0 {
                                self.selected = 0;
                            }
                        }
                        (KeyCode::End, _) | (KeyCode::Char('e'), true) => {
                            let n = self.ranked_len();
                            if n > 0 {
                                self.selected = n - 1;
                            }
                        }
                        (KeyCode::PageUp, _) => {
                            let n = self.ranked_len();
                            let page = self.list_rows();
                            if n > 0 {
                                self.selected = self.selected.saturating_sub(page);
                            }
                        }
                        (KeyCode::PageDown, _) => {
                            let n = self.ranked_len();
                            let page = self.list_rows();
                            if n > 0 {
                                self.selected = (self.selected + page).min(n - 1);
                            }
                        }
                        (KeyCode::Backspace, _) => {
                            if self.query.pop().is_some() {
                                self.needs_rank = true;
                                self.selected = 0;
                            }
                        }
                        (KeyCode::Char('/'), false) => self.slash_enter(),
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
                Event::Resize(c, r) => {
                    // Keep the box inside the new grid: recompute dimensions
                    // from the fresh size and pull the box up if it no
                    // longer fits below its current top row.
                    self.size = (c as usize, r as usize);
                    self.compute_box();
                    let h = self.size.1;
                    if self.pop_top + self.box_h > h {
                        self.pop_top = h.saturating_sub(self.box_h);
                    }
                }
                _ => {}
            }
            self.clamp_offset(self.list_rows());
        }
    }

    fn draw(&mut self, out: &mut io::Stdout) -> io::Result<()> {
        self.ensure_ranked();
        let root_path = self.root.clone();
        let esc = char::from_u32(0x1b).unwrap();
        let w = self.box_w;
        let top = self.pop_top;
        let bh = self.box_h;
        let rows = self.list_rows();
        let mut cols = self.max_cols();
        let mut col_w = self.col_width();
        if self.long {
            cols = 1;
            col_w = self.box_w;
        }
        let bg = "48;2;0;0;0"; // opaque black popup background
        let border = "38;2;108;126;150"; // #6c7e96 border colour
        let revert = format!("{esc}[22;23;24;39;{bg}m"); // default fg on popup bg
        let mut frame = String::with_capacity((w + 64) * (bh + 2));

        // Top border: box-drawing frame around w content columns.
        frame.push_str(&format!("{esc}[{};1H", top + 1));
        frame.push_str(&format!("{esc}[{bg}m{esc}[{border}m"));
        frame.push('\u{250c}'); // \u250c
        for _ in 0..w {
            frame.push('\u{2500}'); // \u2500
        }
        frame.push('\u{2510}'); // \u2510
        frame.push_str(&format!("{esc}[0m{esc}[K"));
        // Content rows: entry grid on top, prompt as the bottom line.
        for r in 0..(bh.saturating_sub(2)) {
            frame.push_str(&format!("{esc}[{};1H", top + 2 + r));
            frame.push_str(&format!("{esc}[{bg}m{esc}[{border}m"));
            frame.push('\u{2502}'); // \u2502
            let mut line = String::new();
            if r < rows {
                for c in 0..cols {
                    let pos = self.offset + r * cols + c;
                    let mut cell = String::new();
                    if pos < self.ranked.len() {
                        let i = self.ranked[pos];
                        let e = self.listing()[i].clone();
                        if self.long {
                            if let Some(m) =
                                crate::listing::meta_line(&root_path.join(&e.label), self.cols_mask)
                            {
                                cell.push_str(&format!("{esc}[38;2;108;126;150m{m}"));
                                cell.push_str(&revert);
                                cell.push(' ');
                            }
                        }
                        if pos == self.selected {
                            cell.push_str(&format!("{esc}[1;48;2;0;95;175;38;2;209;229;255m"));
                        } else {
                            let exec =
                                e.kind == FileKind::File && is_exec(&root_path.join(&e.label));
                            if let Some(code) = self.palette.code_for(e.basename(), e.kind, exec) {
                                cell.push_str(&format!("{esc}[{code}m"));
                            }
                        }
                        if self.icons {
                            cell.push_str(icon_for(&e));
                            cell.push(' ');
                        }
                        cell.push_str(&e.label);
                        if e.kind == FileKind::Dir && !self.icons {
                            cell.push('/');
                        }
                        cell.push_str(&revert);
                    }
                    ansi_pad(&mut cell, col_w);
                    line.push_str(&cell);
                    if c + 1 < cols {
                        line.push_str("  ");
                    }
                }
            } else if r == rows {
                line = self.prompt_line();
            }
            ansi_pad(&mut line, w);
            frame.push_str(&line);
            frame.push_str(&format!("{esc}[{border}m"));
            frame.push('\u{2502}'); // \u2502
            frame.push_str(&format!("{esc}[0m{esc}[K"));
        }
        // Bottom border.
        frame.push_str(&format!("{esc}[{};1H", top + bh));
        frame.push_str(&format!("{esc}[{bg}m{esc}[{border}m"));
        frame.push('\u{2514}'); // \u2514
        for _ in 0..w {
            frame.push('\u{2500}'); // \u2500
        }
        frame.push('\u{2518}'); // \u2518
        frame.push_str(&format!("{esc}[0m{esc}[K"));
        write!(out, "{frame}")?;
        out.flush()
    }

    /// Erase the panel lines (used when the picker exits).
    fn clear_panel(&self, out: &mut io::Stdout) -> io::Result<()> {
        let bh = self.box_h;
        let top = self.pop_top;
        let esc = char::from_u32(0x1b).unwrap();
        let mut s = String::new();
        for r in 0..bh {
            s.push(esc);
            s.push_str(&format!("[{};1H", top + r + 1));
            s.push(esc);
            s.push_str("[K");
        }
        write!(out, "{s}")?;
        out.flush()
    }

    fn prompt_line(&self) -> String {
        let esc = char::from_u32(0x1b).unwrap();
        let mut out = String::new();
        if self.icons {
            out.push(esc);
            out.push_str("[38;2;108;126;150m");
            out.push_str(ICON_DIR);
            out.push(' ');
        }
        let push_painted = |text: &str, code: &str, out: &mut String| {
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
        out.push_str("[22;23;24;39m");
        out
    }
}

/// Outer popup height: two border rows plus up to 12 content rows.
const OUTER_ROWS: usize = 14;

const ICON_DIR: &str = "\u{f115}";
const ICON_FILE: &str = "\u{f15b}";

/// Nerd-font glyph for an entry; falls back to the generic file icon.
fn icon_for(e: &crate::listing::Entry) -> &'static str {
    match e.kind {
        crate::listing::FileKind::Dir => ICON_DIR,
        crate::listing::FileKind::Link => "\u{f481}",
        _ => {
            let low = e.basename().to_ascii_lowercase();
            if low.ends_with(".md") {
                "\u{f48a}"
            } else if low.ends_with(".rs") {
                "\u{e7a8}"
            } else if low.ends_with(".lua") || low.ends_with(".scd") || low.ends_with(".sc") {
                "\u{e620}"
            } else if low.ends_with(".jpg")
                || low.ends_with(".jpeg")
                || low.ends_with(".png")
                || low.ends_with(".webp")
                || low.ends_with(".gif")
            {
                "\u{f1c5}"
            } else if low.ends_with(".mp3") || low.ends_with(".flac") || low.ends_with(".wav") {
                "\u{f001}"
            } else if low.ends_with(".mp4") || low.ends_with(".mkv") || low.ends_with(".webm") {
                "\u{f03d}"
            } else if low.ends_with(".zip")
                || low.ends_with(".tar")
                || low.ends_with(".gz")
                || low.ends_with(".7z")
            {
                "\u{f410}"
            } else {
                ICON_FILE
            }
        }
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
    while vis < width {
        out.push(' ');
        vis += 1;
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
