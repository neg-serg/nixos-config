//! Live-data models for the widgets that read named pipes: a non-blocking FIFO line reader and
//! the oscilloscope/VU history that a renderer turns into a trace.
//!
//! Nothing here draws. The panels in `panels.rs` are pure functions of `(theme, geometry, data)`,
//! and this module is the other half of that split: it owns the parts that can go wrong at
//! runtime — a producer that never appears, one that dies halfway through a line, one that
//! restarts every second — and it does so with plain Rust plus three `libc` calls, so every rule
//! below is unit-testable without a GPU, a window, or a real FIFO.
//!
//! Two invariants drive the design:
//!
//! - **A frame must never wait.** The UI polls at 60 Hz inside its render loop, so every read is
//!   `O_NONBLOCK` and every open is `O_NONBLOCK`; the worst case is "no data this frame", never a
//!   stall behind a silent producer.
//! - **A widget with no data is not an error.** A pipe that does not exist yet is the normal state
//!   before the first producer starts, so the model carries that state ([`FifoStatus::Missing`])
//!   instead of failing, and keeps looking so it comes alive by itself.

use std::collections::VecDeque;
use std::ffi::CString;
use std::os::fd::RawFd;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};

/// How many lines a [`Fifo`] keeps when the caller never says otherwise.
///
/// The UI only ever shows a screenful of history, and an unbounded queue behind a producer that
/// runs faster than the display is how a music player turns into a memory leak.
pub const DEFAULT_CAPACITY: usize = 256;

/// Largest look-back the UI may ask for; see [`Fifo::set_capacity`].
pub const MAX_CAPACITY: usize = 4096;

/// Largest line buffer a [`Scope`] may be asked to keep.
pub const MAX_SCOPE: usize = 1 << 16;

/// Bytes per `read(2)`. Small enough that one poll cannot monopolise the frame, large enough that
/// a fast producer drains in a handful of syscalls.
const READ_CHUNK: usize = 8 * 1024;

/// Bytes one [`Fifo::poll`] is allowed to consume. A producer that dumps megabytes must not turn
/// a 16 ms frame into a 200 ms one; the rest simply waits for the next poll.
const READ_BUDGET: usize = 64 * 1024;

/// Longest partial line kept in memory. A producer that writes without ever emitting a newline
/// would otherwise grow the buffer forever, so the fragment is published as a line at this size.
const MAX_PARTIAL: usize = 64 * 1024;

// ---------------------------------------------------------------- FIFO

/// What the far end of a [`Fifo`] looks like right now, for the label the UI prints next to the
/// widget. A named pipe has a lifecycle (created, producer attached, producer gone) and the user
/// needs to be told which part of it they are looking at; that is data, not an error.
#[derive(Clone, PartialEq, Eq, Debug)]
pub enum FifoStatus {
    /// The path does not exist (yet). Not an error: the producer simply has not started.
    Missing,
    /// A descriptor is held; the producer may still be silent this frame.
    Open,
    /// The far end closed. For a FIFO this is temporary — the next poll re-opens the path and
    /// picks up a producer that restarted.
    Closed,
    /// The path exists but cannot be used (permissions, a directory, a dead descriptor). Carries
    /// the operating system's own words so the UI can show them instead of inventing a reason.
    Error(String),
}

impl FifoStatus {
    /// A one-word label for the widget chrome. Deliberately short and lower case: it sits in a
    /// caption next to the widget title, and the detailed reason stays in the `Error` payload.
    pub fn label(&self) -> &str {
        match self {
            FifoStatus::Missing => "missing",
            FifoStatus::Open => "open",
            FifoStatus::Closed => "closed",
            FifoStatus::Error(_) => "error",
        }
    }
}

/// A line reader over a named pipe that can be polled from a render loop.
///
/// # Why non-blocking, and why re-open
///
/// Reading a FIFO looks like a loop over `read(2)`, but a naive loop loses data in the most
/// ordinary situation there is: a producer that is a `while` loop or a fresh process per update
/// closes the pipe after every write, and `read(2)` then returns 0 forever on that descriptor.
/// The next producer's bytes go into a *new* pipe instance, which the old descriptor can never
/// see. This type therefore treats EOF as "producer gone, not the end of the world": it flushes
/// what it has, closes the descriptor and lets the following [`Fifo::poll`] open the path again.
/// Because the open is `O_NONBLOCK` too, the re-open is free when the path is still empty, and a
/// writer that blocks in `open(2)` waiting for a reader is unblocked by exactly that call.
///
/// The same rule must *not* apply to a regular file: re-opening it would restart at offset 0 and
/// replay the whole file every frame, so a file keeps its descriptor and its offset and simply
/// picks up appended bytes — which is what makes a `tail -f`-style file usable for testing.
pub struct Fifo {
    path: PathBuf,
    /// Owned descriptor, or -1 when none is held (never opened, or closed after EOF).
    fd: RawFd,
    status: FifoStatus,
    /// Whether `poll` may (re-)open `path`. False for the synthetic constructor, whose contents
    /// were handed over directly and must never be replaced by whatever happens to sit on disk.
    reopenable: bool,
    /// Bytes of the line currently being assembled. Kept as bytes, not as `str`, because a read
    /// boundary can fall in the middle of a UTF-8 sequence.
    partial: Vec<u8>,
    lines: VecDeque<String>,
    capacity: usize,
}

impl Fifo {
    /// Open a path, or say plainly that there is nothing to read.
    ///
    /// Returns `None` when the path is absent — a widget that has never been fed is the normal
    /// state before a producer starts, not an error — and also when the path exists but cannot be
    /// opened, so callers that only care about "do I have data" need no error handling. Callers
    /// that want to *show* the reason (the UI prints the status) use [`Fifo::attach`], which keeps
    /// the model and its typed status instead of collapsing both cases into `None`.
    pub fn open(path: impl Into<PathBuf>) -> Option<Fifo> {
        let mut fifo = Fifo::attach(path);
        if matches!(fifo.status, FifoStatus::Open) {
            Some(fifo)
        } else {
            fifo.close();
            None
        }
    }

    /// Build the model even when the path is missing or unusable, carrying the reason in
    /// [`Fifo::status`].
    ///
    /// This is the constructor the widget uses: it must exist (and report "missing") before the
    /// producer does, and it must start working by itself the moment the producer creates the
    /// pipe, because there is no moment in the frame loop at which a restart would be convenient.
    pub fn attach(path: impl Into<PathBuf>) -> Fifo {
        let mut fifo = Fifo {
            path: path.into(),
            fd: -1,
            status: FifoStatus::Missing,
            reopenable: true,
            partial: Vec::new(),
            lines: VecDeque::new(),
            capacity: DEFAULT_CAPACITY,
        };
        fifo.try_open();
        fifo
    }

    /// A model seeded with known lines and no descriptor at all.
    ///
    /// Two uses: the UI's empty state (a widget with a title, a status and no producer), and the
    /// unit tests below, which must not create real FIFOs — a test that blocks on `open(2)` is a
    /// test that hangs the whole suite on one machine and passes on another.
    pub fn from_lines(path: impl Into<PathBuf>, lines: impl IntoIterator<Item = String>) -> Fifo {
        let mut fifo = Fifo {
            path: path.into(),
            fd: -1,
            status: FifoStatus::Closed,
            reopenable: false,
            partial: Vec::new(),
            lines: VecDeque::new(),
            capacity: DEFAULT_CAPACITY,
        };
        for line in lines {
            fifo.push_raw(line.into_bytes());
        }
        fifo
    }

    /// Drain everything the producer has written since the last call and return how many complete
    /// lines that added.
    ///
    /// Never blocks and never reads more than 64 KiB, so it is safe to call once per frame.
    /// Complete lines are those terminated by `\n`; a trailing fragment stays in the buffer
    /// until its newline arrives (or until the far end closes, which publishes it — see below).
    pub fn poll(&mut self) -> usize {
        if self.fd < 0 {
            if !self.reopenable || !self.try_open() {
                return 0;
            }
        }

        let mut added = 0usize;
        let mut consumed = 0usize;
        let mut buf = [0u8; READ_CHUNK];
        while consumed < READ_BUDGET {
            // SAFETY: `self.fd` is a descriptor this struct owns and keeps open for the whole
            // call; `buf` is a live, correctly sized array, so the kernel writes at most
            // `buf.len()` bytes into memory we own.
            let n = unsafe { libc::read(self.fd, buf.as_mut_ptr().cast(), buf.len()) };
            if n > 0 {
                let n = n as usize;
                consumed += n;
                added += self.feed_bytes(&buf[..n]);
                self.status = FifoStatus::Open;
            } else if n == 0 {
                added += self.on_eof();
                break;
            } else {
                let err = std::io::Error::last_os_error();
                let code = err.raw_os_error();
                // An empty non-blocking pipe reports EAGAIN rather than EOF: there is a producer,
                // it just has not written this frame.
                if code == Some(libc::EAGAIN) || code == Some(libc::EWOULDBLOCK) {
                    self.status = FifoStatus::Open;
                    break;
                }
                if code == Some(libc::EINTR) {
                    continue;
                }
                self.status = FifoStatus::Error(err.to_string());
                self.close();
                break;
            }
        }
        added
    }

    /// Push raw bytes through the same splitter `poll` uses, without any descriptor.
    ///
    /// Exists so the line-assembly rules (fragment across calls, `\r\n`, over-long lines) can be
    /// exercised deterministically in tests, and so an embedding can replay captured bytes into
    /// the widget. Returns the number of complete lines produced.
    pub fn feed_bytes(&mut self, bytes: &[u8]) -> usize {
        let mut added = 0;
        let mut rest = bytes;
        while let Some(pos) = rest.iter().position(|&b| b == b'\n') {
            self.partial.extend_from_slice(&rest[..pos]);
            let raw = std::mem::take(&mut self.partial);
            added += self.push_raw(raw);
            rest = &rest[pos + 1..];
        }
        if !rest.is_empty() {
            self.partial.extend_from_slice(rest);
            if self.partial.len() > MAX_PARTIAL {
                let raw = std::mem::take(&mut self.partial);
                added += self.push_raw(raw);
            }
        }
        added
    }

    /// The retained history, oldest first.
    pub fn lines(&self) -> impl Iterator<Item = &str> + '_ {
        self.lines.iter().map(|s| s.as_str())
    }

    /// The newest `n` lines, oldest first — the `n` a widget draws into its caption or list.
    pub fn last(&self, n: usize) -> Vec<&str> {
        let skip = self.lines.len().saturating_sub(n);
        self.lines.iter().skip(skip).map(|s| s.as_str()).collect()
    }

    /// How many lines are retained. Bounded by [`Fifo::capacity`], which is the point.
    pub fn len(&self) -> usize {
        self.lines.len()
    }

    /// Whether nothing has arrived yet.
    pub fn is_empty(&self) -> bool {
        self.lines.is_empty()
    }

    /// The path being read, for the "where does this widget get its data" line in the UI.
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Current lifecycle state, including the reason an open failed.
    pub fn status(&self) -> &FifoStatus {
        &self.status
    }

    /// The current history bound.
    pub fn capacity(&self) -> usize {
        self.capacity
    }

    /// Change the history bound, clamped to 1..=[`MAX_CAPACITY`].
    ///
    /// Clamped rather than rejected because the value comes from a resize or from a config file:
    /// a bound of zero would silently drop every line, and a huge one is a memory leak with extra
    /// steps. Shrinking drops the oldest lines immediately, so the invariant "len <= capacity"
    /// holds the moment the call returns.
    pub fn set_capacity(&mut self, n: usize) {
        self.capacity = n.clamp(1, MAX_CAPACITY);
        while self.lines.len() > self.capacity {
            self.lines.pop_front();
        }
    }

    /// Open the path with the three flags that make this type possible.
    fn try_open(&mut self) -> bool {
        if !self.reopenable {
            return false;
        }
        let cpath = match CString::new(self.path.as_os_str().as_bytes()) {
            Ok(c) => c,
            Err(_) => {
                self.status = FifoStatus::Error("path contains a NUL byte".to_string());
                return false;
            }
        };
        // SAFETY: `cpath` is a NUL-terminated C string that outlives this call, and the flags are
        // the read-only, non-blocking, close-on-exec combination; `open` returns either a fresh
        // descriptor we take ownership of or -1.
        let fd = unsafe {
            libc::open(
                cpath.as_ptr(),
                libc::O_RDONLY | libc::O_NONBLOCK | libc::O_CLOEXEC,
            )
        };
        if fd < 0 {
            let err = std::io::Error::last_os_error();
            let code = err.raw_os_error();
            self.status = match code {
                // The producer has not created the pipe yet (or its directory is gone): the one
                // case that is a normal state rather than a fault.
                Some(libc::ENOENT) | Some(libc::ENOTDIR) => FifoStatus::Missing,
                _ => FifoStatus::Error(err.to_string()),
            };
            return false;
        }
        self.fd = fd;
        self.status = FifoStatus::Open;
        true
    }

    /// Handle `read(2) == 0`: the far end is gone. Returns the number of lines the flush produced,
    /// so a fragment published here is counted like any other new line.
    fn on_eof(&mut self) -> usize {
        // A producer that exits without a final newline still said something complete; publish it
        // instead of dropping it, otherwise the last sample of every short-lived producer is lost.
        let mut added = 0;
        if !self.partial.is_empty() {
            let raw = std::mem::take(&mut self.partial);
            added += self.push_raw(raw);
        }
        self.status = FifoStatus::Closed;
        if self.is_pipe_like() {
            // Drop the descriptor so the next poll opens the path again and meets a producer that
            // restarted in the meantime. Without this, every second producer of a loop is invisible.
            self.close();
        }
        // A regular file keeps its descriptor and offset: re-opening it would replay the whole
        // file from byte zero on every frame once it has been read to the end.
        added
    }

    /// Whether the far end is something that can come and go (a FIFO, a socket, a device).
    fn is_pipe_like(&self) -> bool {
        match std::fs::metadata(&self.path) {
            Ok(meta) => !meta.is_file(),
            // The path vanished under us: treat it as a pipe so the next poll re-opens and reports
            // the new state instead of reading a dead descriptor forever.
            Err(_) => true,
        }
    }

    fn close(&mut self) {
        if self.fd >= 0 {
            // SAFETY: `self.fd` is a descriptor this struct owns and has not closed yet; the -1
            // sentinel is never passed to `close(2)`, and the field is cleared right after.
            unsafe { libc::close(self.fd) };
            self.fd = -1;
        }
    }

    /// Publish one complete line: strip a `\r` a text-mode producer may have left, decode
    /// lossily (a widget should show a mangled byte, not refuse the whole line) and evict the
    /// oldest line once the bound is exceeded.
    fn push_raw(&mut self, mut raw: Vec<u8>) -> usize {
        if raw.last() == Some(&b'\r') {
            raw.pop();
        }
        let line = String::from_utf8_lossy(&raw).into_owned();
        self.lines.push_back(line);
        while self.lines.len() > self.capacity {
            self.lines.pop_front();
        }
        1
    }
}

impl Drop for Fifo {
    fn drop(&mut self) {
        self.close();
    }
}

// ---------------------------------------------------------------- scope

/// A bounded history of normalised samples: the data behind an oscilloscope or VU widget.
///
/// The renderer wants a fixed number of points across whatever width the pane got, while the
/// producer sends whatever rate it likes, so the history is a ring of the newest samples and
/// [`Scope::resample`] is the bridge between the two.
pub struct Scope {
    samples: VecDeque<f32>,
    capacity: usize,
}

impl Scope {
    /// A history bounded to `capacity` samples (clamped to at least one, so a zero-sized pane
    /// cannot produce a scope that silently discards everything it is given).
    pub fn new(capacity: usize) -> Scope {
        let capacity = capacity.clamp(1, MAX_SCOPE);
        Scope {
            samples: VecDeque::with_capacity(capacity),
            capacity,
        }
    }

    /// Append one sample, clamped into -1..=1.
    ///
    /// The clamp is the contract with the shader: the trace is drawn against a fixed unit box, so
    /// an out-of-range producer would otherwise paint outside its pane. Infinities clamp; NaN is
    /// folded to zero because a single NaN would poison every statistic derived from the history.
    pub fn push(&mut self, v: f32) {
        let v = if v.is_nan() { 0.0 } else { v.clamp(-1.0, 1.0) };
        if self.samples.len() == self.capacity {
            self.samples.pop_front();
        }
        self.samples.push_back(v);
    }

    /// Parse one line of text into samples and report how many were taken.
    ///
    /// This is the shape a FIFO of numbers arrives in: either one value per line (`0.1`), or a
    /// whole frame on one line (`0.1 0.3 -0.2`, commas allowed). Tokens that are not numbers are
    /// ignored rather than failing the line, because providers of live data happily mix in
    /// headers, timestamps and `inf`-free junk, and a widget that goes blank because of one bad
    /// token is worse than one that shows the readings around it.
    pub fn push_text(&mut self, text: &str) -> usize {
        let mut taken = 0;
        for token in text.split(|c: char| c == ',' || c.is_whitespace()) {
            if token.is_empty() {
                continue;
            }
            if let Ok(v) = token.parse::<f32>() {
                self.push(v);
                taken += 1;
            }
        }
        taken
    }

    /// Number of samples currently held (never more than the capacity).
    pub fn len(&self) -> usize {
        self.samples.len()
    }

    /// Whether nothing has been pushed since the last clear.
    pub fn is_empty(&self) -> bool {
        self.samples.is_empty()
    }

    /// Forget the history, e.g. when the producer disconnects and the trace should not keep
    /// pretending it is live.
    pub fn clear(&mut self) {
        self.samples.clear();
    }

    /// The raw history, oldest first — for a renderer that draws samples as they are.
    pub fn samples(&self) -> impl Iterator<Item = f32> + '_ {
        self.samples.iter().copied()
    }

    /// Linear interpolation from the history to exactly `columns` points.
    ///
    /// Why this exists: the pane's width in device pixels is a layout decision made once, the
    /// sample count is whatever the producer sent, and the two never match. Nearest-neighbour
    /// picks would make a 900-point history look like a comb at 300 columns and a 40-point
    /// history look like a staircase; interpolating along the index axis keeps the *shape* of the
    /// trace independent of both, so a narrow pane is the same waveform as a wide one.
    ///
    /// An empty history yields zeros rather than nothing: a panel that is told to draw N points
    /// should get N points and paint its baseline, not have to special-case zero.
    pub fn resample(&self, columns: usize) -> Vec<f32> {
        if columns == 0 {
            return Vec::new();
        }
        let n = self.samples.len();
        if n == 0 {
            return vec![0.0; columns];
        }
        if n == 1 {
            return vec![self.samples[0]; columns];
        }
        if columns == 1 {
            return vec![self.samples[n - 1]];
        }
        let step = (n - 1) as f32 / (columns - 1) as f32;
        let mut out = Vec::with_capacity(columns);
        for i in 0..columns {
            let pos = i as f32 * step;
            let i0 = pos.floor() as usize;
            let i1 = (i0 + 1).min(n - 1);
            let frac = pos - i0 as f32;
            let a = self.samples[i0];
            let b = self.samples[i1];
            out.push(a + (b - a) * frac);
        }
        out
    }

    /// Largest absolute sample, i.e. the peak the VU meter shows. Zero for an empty history.
    pub fn peak(&self) -> f32 {
        self.samples.iter().fold(0.0f32, |m, v| m.max(v.abs()))
    }

    /// Root mean square of the history, the honest "loudness" number for a meter: unlike the peak
    /// it does not jump to full on a single click.
    pub fn rms(&self) -> f32 {
        if self.samples.is_empty() {
            return 0.0;
        }
        let sum: f32 = self.samples.iter().map(|v| v * v).sum();
        (sum / self.samples.len() as f32).sqrt()
    }

    /// The most recent sample, or zero when nothing has arrived.
    pub fn last(&self) -> f32 {
        self.samples.back().copied().unwrap_or(0.0)
    }

    /// Take whatever the FIFO collected since the last frame and push it as samples; returns the
    /// number of samples taken.
    ///
    /// This is the single call the UI makes per frame per scope widget: it combines the two
    /// lifecycles (pipe may be empty, may have restarted, may have delivered three lines) so the
    /// panel code only ever sees "n new samples".
    pub fn feed_from(&mut self, fifo: &mut Fifo) -> usize {
        let fresh = fifo.poll();
        if fresh == 0 {
            return 0;
        }
        // Only the lines this poll added are new; `last` clamps to what survived eviction, which
        // is the correct behaviour for a bounded history anyway.
        let mut taken = 0;
        for line in fifo.last(fresh) {
            taken += self.push_text(line);
        }
        taken
    }

    /// Fill the history with a calm, deterministic idle trace centred on `t` seconds.
    ///
    /// A widget with no producer has two honest options: show its status label and nothing else,
    /// or show that it is alive and waiting. The second reads better and is what this is for —
    /// two counter-phase sines ("breathing"), small amplitude so it never looks like real
    /// audio, and a pure function of `t` so frames never jitter and no RNG state exists to drift.
    pub fn idle_pattern(&mut self, t: f32) {
        const AMP_A: f32 = 0.09;
        const AMP_B: f32 = 0.05;
        // Seconds of trace one full window spans, i.e. how slowly it moves.
        const SPAN: f32 = 2.4;
        let n = self.capacity;
        self.samples.clear();
        let denom = (n.max(2) - 1) as f32;
        for i in 0..n {
            let u = i as f32 / denom;
            let ts = t - SPAN + u * SPAN;
            let a = (ts * std::f32::consts::TAU * 0.11).sin() * AMP_A;
            let b = (ts * std::f32::consts::TAU * 0.07 + std::f32::consts::PI).sin() * AMP_B;
            self.samples.push_back((a + b).clamp(-1.0, 1.0));
        }
    }
}

// ---------------------------------------------------------------- tests

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use std::sync::atomic::{AtomicU32, Ordering};

    static SEQ: AtomicU32 = AtomicU32::new(0);

    /// A unique path under the platform temp dir. Unique per process *and* per call so parallel
    /// test threads never share a file.
    fn temp_path(tag: &str) -> PathBuf {
        let n = SEQ.fetch_add(1, Ordering::Relaxed);
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        std::env::temp_dir().join(format!(
            "player-proto-widgets-{}-{}-{}-{}.txt",
            tag,
            std::process::id(),
            stamp,
            n
        ))
    }

    fn append(path: &Path, text: &str) {
        let file = std::fs::OpenOptions::new().append(true).open(path);
        match file {
            Ok(mut f) => assert!(f.write_all(text.as_bytes()).is_ok(), "append to temp file"),
            Err(e) => panic!("cannot reopen temp file {path:?}: {e}"),
        }
    }

    fn must_open(path: &Path) -> Fifo {
        match Fifo::open(path) {
            Some(f) => f,
            None => panic!("expected an open FIFO model for {path:?}"),
        }
    }

    fn cleanup(path: &Path) {
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn open_on_a_missing_path_returns_none_with_missing_status() {
        let path = temp_path("missing");
        let _ = std::fs::remove_file(&path);

        assert!(Fifo::open(&path).is_none(), "a missing path is not an open");

        // The same path through `attach`: the model exists and says why it has no data.
        let mut fifo = Fifo::attach(&path);
        assert!(matches!(fifo.status(), FifoStatus::Missing));
        assert_eq!(fifo.status().label(), "missing");
        assert_eq!(fifo.path(), path.as_path());
        assert_eq!(
            fifo.poll(),
            0,
            "polling a missing path must not block or add"
        );
        assert!(fifo.is_empty());
        assert!(matches!(fifo.status(), FifoStatus::Missing));
    }

    #[test]
    fn status_labels_are_short_words() {
        assert_eq!(FifoStatus::Open.label(), "open");
        assert_eq!(FifoStatus::Closed.label(), "closed");
        assert_eq!(FifoStatus::Error("nope".into()).label(), "error");
        assert_eq!(FifoStatus::Missing.label(), "missing");
    }

    #[test]
    fn a_regular_file_is_read_incrementally_with_complete_lines_only() {
        let path = temp_path("incremental");
        assert!(std::fs::write(&path, b"").is_ok(), "create temp file");

        let mut fifo = must_open(&path);
        assert!(matches!(fifo.status(), FifoStatus::Open));
        assert_eq!(fifo.poll(), 0, "an empty file yields nothing");

        append(&path, "alpha\nbeta\n");
        assert_eq!(fifo.poll(), 2);
        assert_eq!(fifo.lines().collect::<Vec<_>>(), vec!["alpha", "beta"]);

        append(&path, "gamma\n");
        assert_eq!(fifo.poll(), 1, "only the appended line is new");
        assert_eq!(fifo.last(2), vec!["beta", "gamma"]);
        assert_eq!(fifo.len(), 3);

        // Nothing appended: the file's offset is retained, so nothing is replayed.
        assert_eq!(fifo.poll(), 0);
        assert_eq!(fifo.len(), 3);

        cleanup(&path);
    }

    #[test]
    fn partial_lines_survive_across_polls() {
        // A regular file reaches EOF on every poll that catches up, and creating a real FIFO in a
        // portable unit test is not acceptable, so the splitter is driven through `feed_bytes` --
        // the same code path the read loop feeds.
        let mut fifo = Fifo::from_lines("scope", Vec::<String>::new());
        assert_eq!(fifo.feed_bytes(b"one\ntw"), 1);
        assert_eq!(fifo.lines().collect::<Vec<_>>(), vec!["one"]);

        assert_eq!(fifo.feed_bytes(b"o\nthr"), 1);
        assert_eq!(fifo.feed_bytes(b"ee-and-a-half\r\n"), 1);
        assert_eq!(
            fifo.lines().collect::<Vec<_>>(),
            vec!["one", "two", "three-and-a-half"],
            "the fragment is completed across calls and CRLF loses its carriage return"
        );
    }

    #[test]
    fn capacity_eviction_keeps_the_newest_lines() {
        let mut fifo = Fifo::from_lines("evict", (0..10).map(|i| format!("line{i}")));
        assert_eq!(fifo.len(), 10);
        assert_eq!(fifo.capacity(), DEFAULT_CAPACITY);

        fifo.set_capacity(3);
        assert_eq!(fifo.last(10), vec!["line7", "line8", "line9"]);

        assert_eq!(fifo.feed_bytes(b"ten\neleven\n"), 2);
        assert_eq!(fifo.last(10), vec!["line9", "ten", "eleven"]);

        // Clamped at both ends rather than trusted.
        fifo.set_capacity(0);
        assert_eq!(fifo.capacity(), 1);
        assert_eq!(fifo.last(10), vec!["eleven"]);
        fifo.set_capacity(usize::MAX);
        assert_eq!(fifo.capacity(), MAX_CAPACITY);
    }

    #[test]
    fn eof_flushes_the_trailing_partial_line() {
        let path = temp_path("eof");
        assert!(
            std::fs::write(&path, b"one\ntwo-without-newline").is_ok(),
            "create temp file"
        );

        let mut fifo = must_open(&path);
        assert_eq!(fifo.poll(), 2);
        assert_eq!(fifo.last(5), vec!["one", "two-without-newline"]);
        assert!(matches!(fifo.status(), FifoStatus::Closed));

        // Flushed exactly once: the fragment is empty afterwards.
        assert_eq!(fifo.poll(), 0);
        assert_eq!(fifo.len(), 2);

        cleanup(&path);
    }

    #[test]
    fn push_clamps_to_the_unit_range() {
        let mut scope = Scope::new(8);
        scope.push(2.5);
        scope.push(-9.0);
        scope.push(0.25);
        scope.push(f32::NAN);
        scope.push(f32::INFINITY);
        assert_eq!(scope.len(), 5);
        assert_eq!(
            scope.samples().collect::<Vec<_>>(),
            vec![1.0, -1.0, 0.25, 0.0, 1.0]
        );
        assert_eq!(scope.last(), 1.0);

        let mut tiny = Scope::new(0);
        tiny.push(0.1);
        tiny.push(0.2);
        assert_eq!(tiny.len(), 1, "a zero capacity is clamped up to one");
        assert_eq!(tiny.last(), 0.2);
    }

    #[test]
    fn push_text_parses_separators_and_ignores_junk() {
        let mut scope = Scope::new(32);
        assert_eq!(scope.push_text("0.1 0.3 -0.2"), 3);
        assert_eq!(scope.push_text("1,0.5,,junk,  2.0\n"), 3);
        assert_eq!(scope.push_text("  \t , "), 0);
        assert_eq!(scope.push_text("nope"), 0);
        assert_eq!(scope.push_text(""), 0);
        assert_eq!(scope.len(), 6);
        assert_eq!(
            scope.samples().collect::<Vec<_>>(),
            vec![0.1, 0.3, -0.2, 1.0, 0.5, 1.0],
            "the out-of-range value is clamped, the junk is dropped"
        );
    }

    #[test]
    fn resample_returns_exactly_the_requested_columns() {
        let mut scope = Scope::new(64);
        for i in 0..37 {
            scope.push(i as f32 / 18.0 - 1.0);
        }
        for columns in [0usize, 1, 2, 7, 37, 200] {
            assert_eq!(scope.resample(columns).len(), columns);
        }
        assert!(scope.resample(0).is_empty());

        // A single sample is a flat line, not a division by zero.
        let mut one = Scope::new(4);
        one.push(-0.5);
        let flat = one.resample(9);
        assert_eq!(flat.len(), 9);
        assert!(flat.iter().all(|v| (*v + 0.5).abs() < 1e-6));
    }

    #[test]
    fn resample_interpolates_between_two_known_samples() {
        let mut scope = Scope::new(8);
        scope.push(0.0);
        scope.push(1.0);
        let out = scope.resample(5);
        assert_eq!(out.len(), 5);
        for (got, want) in out.iter().zip([0.0, 0.25, 0.5, 0.75, 1.0]) {
            assert!((got - want).abs() < 1e-6, "got {got}, want {want}");
        }

        // A peak in the middle stays a peak: 0, 1, 0 sampled at five columns.
        let mut peaky = Scope::new(8);
        peaky.push(0.0);
        peaky.push(1.0);
        peaky.push(0.0);
        let out = peaky.resample(5);
        for (got, want) in out.iter().zip([0.0, 0.5, 1.0, 0.5, 0.0]) {
            assert!((got - want).abs() < 1e-6, "got {got}, want {want}");
        }
    }

    #[test]
    fn resample_of_an_empty_scope_is_zeros() {
        let scope = Scope::new(16);
        let out = scope.resample(12);
        assert_eq!(out.len(), 12);
        assert!(out.iter().all(|v| *v == 0.0));
        assert!(scope.is_empty());
        assert_eq!(scope.last(), 0.0);
        assert_eq!(scope.peak(), 0.0);
        assert_eq!(scope.rms(), 0.0);
    }

    #[test]
    fn peak_and_rms_match_a_known_sequence() {
        let mut scope = Scope::new(8);
        for v in [0.5, -0.5, 0.5, -0.5] {
            scope.push(v);
        }
        assert!((scope.peak() - 0.5).abs() < 1e-6);
        assert!((scope.rms() - 0.5).abs() < 1e-6);

        scope.clear();
        assert!(scope.is_empty());
        assert_eq!(scope.peak(), 0.0);
        assert_eq!(scope.rms(), 0.0);

        // sqrt((0.36 + 0 + 0 + 0.64) / 4) = 0.5, peak 0.8.
        for v in [0.6, 0.0, 0.0, 0.8] {
            scope.push(v);
        }
        assert!((scope.peak() - 0.8).abs() < 1e-6);
        assert!((scope.rms() - 0.5).abs() < 1e-6, "rms {}", scope.rms());
    }

    #[test]
    fn feed_from_only_takes_the_lines_that_arrived() {
        let path = temp_path("feed");
        assert!(
            std::fs::write(&path, b"0.0 1.0\n").is_ok(),
            "create temp file"
        );

        let mut fifo = must_open(&path);
        let mut scope = Scope::new(16);
        assert_eq!(scope.feed_from(&mut fifo), 2);
        assert_eq!(scope.samples().collect::<Vec<_>>(), vec![0.0, 1.0]);

        assert_eq!(scope.feed_from(&mut fifo), 0, "already consumed");
        assert_eq!(scope.len(), 2);

        append(&path, "0.25\n");
        assert_eq!(scope.feed_from(&mut fifo), 1);
        assert_eq!(scope.last(), 0.25);

        cleanup(&path);
    }

    #[test]
    fn idle_pattern_stays_inside_the_unit_range() {
        let mut scope = Scope::new(128);
        let mut t = -5.0f32;
        while t < 12.0 {
            scope.idle_pattern(t);
            assert_eq!(scope.len(), 128, "the pattern fills the window");
            for v in scope.samples() {
                assert!(v.is_finite(), "idle sample must be finite, got {v}");
                assert!(
                    v.abs() <= 1.0,
                    "idle sample {v} left the unit range at t={t}"
                );
            }
            t += 0.37;
        }

        // Deterministic in t: the same instant produces the same trace, so frames cannot jitter.
        let mut a = Scope::new(32);
        let mut b = Scope::new(32);
        a.idle_pattern(1.234);
        b.idle_pattern(1.234);
        assert_eq!(
            a.samples().collect::<Vec<_>>(),
            b.samples().collect::<Vec<_>>()
        );

        // Calm but not dead: the trace actually moves.
        let values: Vec<f32> = a.samples().collect();
        let min = values.iter().copied().fold(f32::INFINITY, f32::min);
        let max = values.iter().copied().fold(f32::NEG_INFINITY, f32::max);
        assert!(max - min > 0.01, "idle trace is flat: {min}..{max}");
    }
}
