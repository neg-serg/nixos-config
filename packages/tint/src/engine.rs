//! The per-line pipeline: classify, match, resolve styles, emit.
//!
//! The engine owns everything a run needs after the arguments have been parsed
//! (a scan configuration, a compiled rule list, a theme and the user's style
//! table), so rendering is immutable and lock-free: the streaming code can move
//! it behind a shared reference and read the same engine from several readers.

use std::io::{self, Read, Write};
use std::time::Instant;

use crate::config::{Config, StyleTable};
use crate::hit::{normalize, Hit};
use crate::rule::{Matcher, Rule, RuleSet};
use crate::ruleset::RulesetDef;
use crate::scan::{scan, ScanCfg};
use crate::style::SgrWriter;
use crate::theme::Theme;

/// What a run does with lines that already contain ANSI escapes.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum AnsiPolicy {
    /// Pass such lines through untouched: the program coloured them itself and
    /// re-colouring would fight it. This is the default and the reason wrapping
    /// `git` or `journalctl` does not produce garbage.
    Skip,
    /// Colour anyway, keeping the embedded escapes.
    Extend,
}

impl AnsiPolicy {
    pub fn by_name(name: &str) -> Option<AnsiPolicy> {
        match name {
            "skip" | "auto" => Some(AnsiPolicy::Skip),
            "extend" | "force" => Some(AnsiPolicy::Extend),
            _ => None,
        }
    }
}

/// A ready-to-run colouriser.
pub struct Engine {
    scan: ScanCfg,
    rules: RuleSet,
    theme: Theme,
    styles: StyleTable,
    ansi: AnsiPolicy,
}

impl Engine {
    /// Combine a ruleset, the user config and a theme into an engine.
    pub fn build(def: &RulesetDef, config: &Config, mut theme: Theme, ansi: AnsiPolicy) -> Engine {
        let mut scan = ScanCfg::default();
        scan.numbers = def.flags.numbers;
        scan.headers = def.flags.headers;
        scan.ports = def.flags.ports;
        scan.keyval = def.flags.keyval;

        let mut rules: Vec<Rule> =
            Vec::with_capacity(def.words.len() + def.lines.len() + def.parts.len());
        for (word, kind) in def.words {
            rules.push(Rule::new(Matcher::Word(word.as_bytes().to_vec()), *kind));
        }
        for (prefix, kind) in def.lines {
            rules.push(Rule::new(
                Matcher::Prefix(prefix.as_bytes().to_vec()),
                *kind,
            ));
        }
        for (part, kind) in def.parts {
            rules.push(Rule::new(Matcher::Literal(part.as_bytes().to_vec()), *kind));
        }
        rules.extend(config.rules.iter().cloned());

        for (kind, style) in &config.kind_styles {
            theme.set(*kind, *style);
        }

        Engine {
            scan,
            rules: RuleSet::new(rules),
            theme,
            styles: config.styles.clone(),
            ansi,
        }
    }

    /// Ruleset name is not needed at render time, but tests and `--show` want to
    /// look at the compiled rule count.
    pub fn rule_count(&self) -> usize {
        self.rules.count()
    }

    /// Colourise one line (without its terminator) into `out`.
    ///
    /// `hits` and `sgr` are caller-owned scratch state; reusing them across
    /// lines is what keeps the hot path allocation-free.
    pub fn render_line(
        &self,
        line: &[u8],
        hits: &mut Vec<Hit>,
        sgr: &mut SgrWriter,
        out: &mut Vec<u8>,
    ) -> usize {
        if line.is_empty() {
            return 0;
        }
        // Never paint over data that is not text: a line with a NUL byte is
        // binary (or close enough), and ANSI escapes mean someone already
        // coloured this line unless the caller asked for `--ansi=extend`.
        let untouched = line.iter().any(|b| *b == 0x00)
            || (self.ansi == AnsiPolicy::Skip && line.iter().any(|b| *b == 0x1b));
        if untouched {
            out.extend_from_slice(line);
            return 0;
        }
        hits.clear();
        scan(line, &self.scan, hits);
        self.rules.matches(line, hits);
        normalize(hits);
        let mut cursor = 0usize;
        for hit in hits.iter() {
            let (start, end) = (hit.start as usize, hit.end as usize);
            if start > cursor {
                sgr.reset(out);
                out.extend_from_slice(&line[cursor..start]);
            }
            let style = self.styles.resolve(hit.style, self.theme.get(hit.kind));
            sgr.set(out, style);
            out.extend_from_slice(&line[start..end]);
            cursor = end;
        }
        if cursor < line.len() {
            sgr.reset(out);
            out.extend_from_slice(&line[cursor..]);
        }
        sgr.reset(out);
        hits.len()
    }
}

/// Line terminators. `\r` counts because progress meters redraw in place.
static TERMINATOR: [bool; 256] = {
    let mut table = [false; 256];
    table[b'\n' as usize] = true;
    table[b'\r' as usize] = true;
    table
};

/// Counters for `--stats`.
#[derive(Default, Debug, Clone, Copy)]
pub struct Stats {
    pub lines: u64,
    pub bytes: u64,
    pub spans: u64,
}

/// Incremental colouring state: feed it whatever the reader produced, take the
/// rendered bytes out.
///
/// A line is emitted as soon as its terminator arrives, so a live source keeps
/// its latency; `\r` counts as a terminator because progress meters redraw in
/// place; a `\r\n` pair stays intact even when its two bytes land in different
/// reads. The struct owns every buffer the hot path needs, so feeding costs no
/// allocations.
pub struct Streamer<'a> {
    engine: &'a Engine,
    pending: Vec<u8>,
    out: Vec<u8>,
    hits: Vec<Hit>,
    sgr: SgrWriter,
    /// A CR ended the previous chunk: it may be the first half of a CRLF pair.
    carry_cr: bool,
    pub stats: Stats,
}

impl<'a> Streamer<'a> {
    pub fn new(engine: &'a Engine) -> Streamer<'a> {
        Streamer::with_capacity(engine, 64 * 1024)
    }

    /// Same, with the output buffer sized up front: the parallel path knows how
    /// much text it is about to colour and would rather not reallocate.
    pub fn with_capacity(engine: &'a Engine, capacity: usize) -> Streamer<'a> {
        Streamer {
            engine,
            pending: Vec::new(),
            out: Vec::with_capacity(capacity),
            hits: Vec::with_capacity(32),
            sgr: SgrWriter::new(),
            carry_cr: false,
            stats: Stats::default(),
        }
    }

    /// Rendered bytes waiting to be written out.
    pub fn out(&self) -> &[u8] {
        &self.out
    }

    /// Call after the bytes from [`Streamer::out`] have been written.
    pub fn clear_out(&mut self) {
        self.out.clear();
    }

    /// Colour one chunk of input.
    pub fn feed(&mut self, chunk: &[u8]) {
        if chunk.is_empty() {
            return;
        }
        self.stats.bytes += chunk.len() as u64;
        let mut start = 0usize;
        if self.carry_cr {
            if chunk[0] == b'\n' {
                self.out.extend_from_slice(b"\r\n");
                start = 1;
            } else {
                self.out.push(b'\r');
            }
            self.carry_cr = false;
        }
        while start < chunk.len() {
            let Some(offset) = crate::fast::find2(b'\n', b'\r', &chunk[start..]) else {
                self.pending.extend_from_slice(&chunk[start..]);
                break;
            };
            let end = start + offset;
            let term = chunk[end];
            let line: &[u8] = if self.pending.is_empty() {
                &chunk[start..end]
            } else {
                self.pending.extend_from_slice(&chunk[start..end]);
                &self.pending
            };
            self.stats.spans += render(
                self.engine,
                line,
                &mut self.hits,
                &mut self.sgr,
                &mut self.out,
            ) as u64;
            self.stats.lines += 1;
            self.pending.clear();
            match term {
                b'\n' => {
                    self.out.push(b'\n');
                    start = end + 1;
                }
                _ => match chunk.get(end + 1) {
                    Some(b'\n') => {
                        self.out.extend_from_slice(b"\r\n");
                        start = end + 2;
                    }
                    Some(_) => {
                        self.out.push(b'\r');
                        start = end + 1;
                    }
                    None => {
                        // CRLF split across reads: decide on the next read.
                        self.carry_cr = true;
                        start = end + 1;
                    }
                },
            }
        }
    }

    /// Hand a buffered partial line back untouched.
    ///
    /// The pty relay uses this when the stream switches to raw screen control:
    /// the fragment must keep its position in the byte stream, even though it
    /// cannot be coloured as a line.
    pub fn spill_pending(&mut self) {
        if self.carry_cr {
            self.out.push(b'\r');
            self.carry_cr = false;
        }
        if !self.pending.is_empty() {
            let pending = std::mem::take(&mut self.pending);
            self.out.extend_from_slice(&pending);
        }
    }

    /// Finish and hand the rendered bytes over, for callers that write whole
    /// blocks at once (the parallel bulk path).
    pub fn into_output(mut self) -> (Vec<u8>, Stats) {
        self.finish();
        (self.out, self.stats)
    }

    /// Hand the buffered partial line over (the live path promotes to the bulk
    /// path when the source turns out to be a dump, not a follow).
    pub fn take_pending(&mut self) -> Vec<u8> {
        if self.carry_cr {
            self.pending.push(b'\r');
            self.carry_cr = false;
        }
        std::mem::take(&mut self.pending)
    }

    /// Flush a trailing partial line (no terminator was seen).
    pub fn finish(&mut self) {
        if self.carry_cr {
            self.out.push(b'\r');
            self.carry_cr = false;
        }
        if !self.pending.is_empty() {
            let line = std::mem::take(&mut self.pending);
            self.stats.spans += render(
                self.engine,
                &line,
                &mut self.hits,
                &mut self.sgr,
                &mut self.out,
            ) as u64;
            self.stats.lines += 1;
        }
    }
}

/// Colourise everything `reader` yields into `writer`.
///
/// Two paths. A source that fills the first read buffer is treated as *bulk*
/// (a file, a big log dump, `nix log | tint`): the input is taken in batches and
/// the batches are coloured by one thread per core, then written in order. A
/// source that hands over less than the buffer is a *live* stream (`tail -f`,
/// `journalctl -f`, a slow pipe) and stays on the single-threaded path, where a
/// line is written out as soon as its terminator arrives.
pub fn process<R: Read, W: Write>(
    engine: &Engine,
    mut reader: R,
    mut writer: W,
) -> io::Result<Stats> {
    let mut first = vec![0u8; 64 * 1024];
    let read = match reader.read(&mut first) {
        Ok(n) => n,
        Err(err) if err.kind() == io::ErrorKind::Interrupted => 0,
        Err(err) => return Err(err),
    };
    if read == first.len() {
        first.truncate(read);
        return process_bulk(engine, reader, writer, first);
    }
    let first_len = read as u64;
    first.truncate(read);
    let mut streamer = Streamer::new(engine);
    streamer.feed(&first);
    if !streamer.out().is_empty() {
        writer.write_all(streamer.out())?;
        streamer.clear_out();
        writer.flush()?;
    }
    let started = Instant::now();
    let mut seen = first_len;
    let mut inbuf = vec![0u8; 64 * 1024];
    loop {
        let read = match reader.read(&mut inbuf) {
            Ok(0) => break,
            Ok(n) => n,
            Err(err) if err.kind() == io::ErrorKind::Interrupted => continue,
            Err(err) => return Err(err),
        };
        seen += read as u64;
        // A source that hands over a lot of data quickly is a dump that arrived
        // through a pipe, not a live stream: promote it to the parallel path
        // instead of colouring the rest one thread at a time. Short and slow is
        // what `tail -f` looks like, and stays live.
        if seen >= PROMOTE_BYTES && started.elapsed() < PROMOTE_WINDOW {
            streamer.feed(b"");
            if !streamer.out().is_empty() {
                writer.write_all(streamer.out())?;
                streamer.clear_out();
            }
            let carry = streamer.take_pending();
            let head = streamer.stats;
            let mut rest = process_bulk(engine, reader, writer, carry)?;
            rest.bytes += head.bytes;
            rest.lines += head.lines;
            rest.spans += head.spans;
            return Ok(rest);
        }
        streamer.feed(&inbuf[..read]);
        // A short read means the source has nothing more ready: push what we
        // have so a live stream keeps its latency instead of sitting on it
        // until 60 KiB pile up.
        if streamer.out().len() >= 60 * 1024 || read < inbuf.len() {
            if !streamer.out().is_empty() {
                writer.write_all(streamer.out())?;
                streamer.clear_out();
                writer.flush()?;
            }
        }
    }
    streamer.finish();
    if !streamer.out().is_empty() {
        writer.write_all(streamer.out())?;
    }
    writer.flush()?;
    Ok(streamer.stats)
}

/// Promotion thresholds for a piped dump: this much data this fast is a bulk
/// source that arrived through a pipe.
const PROMOTE_BYTES: u64 = 1024 * 1024;
const PROMOTE_WINDOW: std::time::Duration = std::time::Duration::from_millis(50);

/// Per-thread slice of a batch. Batches are `threads x this`, capped so a run
/// never holds more than ~64 MiB of input: the barrier between batches costs far
/// more than the copy it saves, so the slice is generous.
const SLICE: usize = 2 * 1024 * 1024;
const MAX_BATCH: usize = 64 * 1024 * 1024;
/// One thread per core, but not more than this (the writer is a bottleneck too).
const MAX_THREADS: usize = 16;

fn process_bulk<R: Read, W: Write>(
    engine: &Engine,
    mut reader: R,
    mut writer: W,
    first: Vec<u8>,
) -> io::Result<Stats> {
    // `TINT_THREADS` pins the worker count (tests and benchmarks); otherwise one
    // worker per core, capped.
    let threads = std::env::var("TINT_THREADS")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .filter(|value| *value > 0)
        .unwrap_or_else(|| {
            std::thread::available_parallelism()
                .map(|n| n.get())
                .unwrap_or(1)
        })
        .min(MAX_THREADS);
    if threads < 2 {
        return process_sequential(engine, reader, writer, first);
    }
    let batch_limit = (threads * SLICE).min(MAX_BATCH);
    let mut stats = Stats::default();
    let mut batch = first;
    batch.reserve(batch_limit);
    let mut chunk = vec![0u8; 64 * 1024];
    loop {
        let mut eof = false;
        while batch.len() < batch_limit {
            let read = match reader.read(&mut chunk) {
                Ok(0) => {
                    eof = true;
                    break;
                }
                Ok(n) => n,
                Err(err) if err.kind() == io::ErrorKind::Interrupted => continue,
                Err(err) => return Err(err),
            };
            batch.extend_from_slice(&chunk[..read]);
        }
        // Split at the last full line: everything after it belongs to the next
        // batch, so no line is ever processed by two threads.
        let cut = match batch.iter().rposition(|b| *b == b'\n') {
            Some(index) => index + 1,
            None => 0,
        };
        if cut > 0 {
            let (head, tail) = batch.split_at(cut);
            process_batch(engine, head, threads, &mut writer, &mut stats)?;
            batch = tail.to_vec();
        }
        if eof {
            if !batch.is_empty() {
                // Trailing partial line (no terminator).
                let mut streamer = Streamer::new(engine);
                streamer.feed(&batch);
                let (out, piece) = streamer.into_output();
                writer.write_all(&out)?;
                stats.lines += piece.lines;
                stats.bytes += piece.bytes;
                stats.spans += piece.spans;
            }
            break;
        }
    }
    writer.flush()?;
    Ok(stats)
}

/// Colour one batch on `threads` threads, writing the pieces in input order.
fn process_batch<W: Write>(
    engine: &Engine,
    data: &[u8],
    threads: usize,
    writer: &mut W,
    stats: &mut Stats,
) -> io::Result<()> {
    let mut bounds = Vec::with_capacity(threads + 1);
    bounds.push(0usize);
    for piece in 1..threads {
        let target = data.len() * piece / threads;
        if target <= *bounds.last().expect("non-empty") {
            continue;
        }
        // Advance to the next line boundary so a line stays in one piece.
        let end = match data[target..].iter().position(|b| *b == b'\n') {
            Some(offset) => target + offset + 1,
            None => continue,
        };
        if end > *bounds.last().expect("non-empty") && end < data.len() {
            bounds.push(end);
        }
    }
    bounds.push(data.len());

    let results: Vec<(Vec<u8>, Stats)> = std::thread::scope(|scope| {
        let mut handles = Vec::with_capacity(bounds.len());
        for pair in bounds.windows(2) {
            let slice = &data[pair[0]..pair[1]];
            handles.push(scope.spawn(move || {
                let mut streamer = Streamer::with_capacity(engine, slice.len() * 3 / 2 + 4096);
                streamer.feed(slice);
                streamer.into_output()
            }));
        }
        handles
            .into_iter()
            .map(|handle| handle.join().expect("colouriser thread panicked"))
            .collect()
    });
    for (out, piece) in results {
        writer.write_all(&out)?;
        stats.lines += piece.lines;
        stats.bytes += piece.bytes;
        stats.spans += piece.spans;
    }
    Ok(())
}

/// The single-threaded path, re-entered when only one core is available.
fn process_sequential<R: Read, W: Write>(
    engine: &Engine,
    mut reader: R,
    mut writer: W,
    first: Vec<u8>,
) -> io::Result<Stats> {
    let mut streamer = Streamer::new(engine);
    streamer.feed(&first);
    let mut inbuf = vec![0u8; 64 * 1024];
    loop {
        let read = match reader.read(&mut inbuf) {
            Ok(0) => break,
            Ok(n) => n,
            Err(err) if err.kind() == io::ErrorKind::Interrupted => continue,
            Err(err) => return Err(err),
        };
        streamer.feed(&inbuf[..read]);
        if !streamer.out().is_empty() {
            writer.write_all(streamer.out())?;
            streamer.clear_out();
            writer.flush()?;
        }
    }
    streamer.finish();
    if !streamer.out().is_empty() {
        writer.write_all(streamer.out())?;
    }
    writer.flush()?;
    Ok(streamer.stats)
}

fn render(
    engine: &Engine,
    line: &[u8],
    hits: &mut Vec<Hit>,
    sgr: &mut SgrWriter,
    out: &mut Vec<u8>,
) -> usize {
    // Trailing CR of a CRLF pair stays with the terminator, not with the text.
    let (text, cr) = match line.split_last() {
        Some((b'\r', rest)) => (rest, true),
        _ => (line, false),
    };
    let spans = engine.render_line(text, hits, sgr, out);
    if cr {
        out.push(b'\r');
    }
    spans
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ruleset;

    fn engine_for(name: &str) -> Engine {
        let def = ruleset::find(name).expect("ruleset exists");
        Engine::build(def, &Config::default(), Theme::dark(), AnsiPolicy::Skip)
    }

    fn render_all(engine: &Engine, input: &str) -> String {
        let mut out = Vec::new();
        process(engine, input.as_bytes(), &mut out).unwrap();
        String::from_utf8(out).unwrap()
    }

    fn strip(input: &str) -> String {
        let bytes = input.as_bytes();
        let mut out = Vec::with_capacity(bytes.len());
        let mut i = 0;
        while i < bytes.len() {
            if bytes[i] == 0x1b {
                i += 1;
                while i < bytes.len() && !bytes[i].is_ascii_alphabetic() {
                    i += 1;
                }
                i += 1;
            } else {
                out.push(bytes[i]);
                i += 1;
            }
        }
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn text_survives_colouring() {
        let engine = engine_for("df");
        let input = "Filesystem      Size  Used Avail Use% Mounted on\n\
                     /dev/nvme0n1p2  1.8T  1.2T  512G  71% /\n";
        let output = render_all(&engine, input);
        assert_eq!(strip(&output), input);
    }

    #[test]
    fn coloured_output_actually_has_escapes() {
        let engine = engine_for("df");
        let output = render_all(&engine, "/dev/nvme0n1p2  1.8T  1.2T  512G  71% /\n");
        assert!(
            output.contains("\x1b["),
            "expected ANSI escapes in {output:?}"
        );
    }

    #[test]
    fn lines_are_coloured_independently() {
        let engine = engine_for("generic");
        let output = render_all(&engine, "error\nok\n");
        assert!(strip(&output).ends_with("error\nok\n"));
        // Each line ends with a reset, so styling cannot leak across lines.
        assert_eq!(output.matches("\x1b[0m").count(), 2);
    }

    #[test]
    fn existing_ansi_lines_pass_through() {
        let engine = engine_for("generic");
        let input = "\x1b[31merror\x1b[0m already coloured\n";
        assert_eq!(render_all(&engine, input), input);
    }

    #[test]
    fn binary_lines_are_never_painted() {
        let engine = engine_for("generic");
        let input = b"tar\x00error\x00\n";
        let mut out = Vec::new();
        process(&engine, &input[..], &mut out).unwrap();
        assert_eq!(out, input);
    }

    #[test]
    fn ansi_extend_policy_recolours() {
        let def = ruleset::find("generic").unwrap();
        let engine = Engine::build(def, &Config::default(), Theme::dark(), AnsiPolicy::Extend);
        let input = "\x1b[31merror\x1b[0m already coloured\n";
        let output = render_all(&engine, input);
        assert!(strip(&output).contains("error"), "{output:?}");
        assert!(output.len() > input.len());
    }

    #[test]
    fn crlf_and_missing_final_newline_are_preserved() {
        let engine = engine_for("generic");
        let input = "error one\r\nerror two";
        assert_eq!(strip(&render_all(&engine, input)), input);
    }

    #[test]
    fn long_lines_crossing_the_buffer_boundary_are_whole() {
        let engine = engine_for("generic");
        let long = "x".repeat(70_000);
        let input = format!("error {long}\n");
        assert_eq!(strip(&render_all(&engine, &input)), input);
    }

    /// Reader that hands out one chunk per read and can check what the writer
    /// has already seen; Writer that records everything it is given.
    struct ProbeReader {
        chunks: Vec<Vec<u8>>,
        index: usize,
        written: std::sync::Arc<std::sync::Mutex<Vec<u8>>>,
    }

    impl Read for ProbeReader {
        fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
            if self.index > 0 && self.index < self.chunks.len() {
                let seen = self.written.lock().unwrap();
                assert!(
                    !seen.is_empty(),
                    "chunk {} was read before chunk {} was written out",
                    self.index + 1,
                    self.index
                );
            }
            let Some(chunk) = self.chunks.get(self.index) else {
                return Ok(0);
            };
            self.index += 1;
            buf[..chunk.len()].copy_from_slice(chunk);
            Ok(chunk.len())
        }
    }

    struct ProbeWriter(std::sync::Arc<std::sync::Mutex<Vec<u8>>>);

    impl Write for ProbeWriter {
        fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
            self.0.lock().unwrap().extend_from_slice(buf);
            Ok(buf.len())
        }
        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }

    #[test]
    fn live_stream_is_flushed_before_the_next_chunk_arrives() {
        let engine = engine_for("generic");
        let written = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let reader = ProbeReader {
            chunks: vec![b"error one\n".to_vec(), b"error two\n".to_vec()],
            index: 0,
            written: written.clone(),
        };
        let stats = process(&engine, reader, ProbeWriter(written.clone())).unwrap();
        assert_eq!(stats.lines, 2);
        let out = String::from_utf8(written.lock().unwrap().clone()).unwrap();
        assert!(strip(&out).contains("error one\nerror two\n"));
    }

    #[test]
    fn carriage_return_progress_updates_are_kept_and_rendered() {
        let engine = engine_for("generic");
        let output = render_all(&engine, "step 1\rstep 2\rdone\n");
        assert_eq!(strip(&output), "step 1\rstep 2\rdone\n");
        assert!(
            output.contains("\x1b["),
            "progress segments are coloured too"
        );
    }

    #[test]
    fn crlf_split_across_reads_is_not_turned_into_an_extra_line() {
        let engine = engine_for("generic");
        let written = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let reader = ProbeReader {
            chunks: vec![b"error one\r".to_vec(), b"\nerror two\r\n".to_vec()],
            index: 0,
            written: written.clone(),
        };
        let stats = process(&engine, reader, ProbeWriter(written.clone())).unwrap();
        assert_eq!(stats.lines, 2);
        let out = String::from_utf8(written.lock().unwrap().clone()).unwrap();
        assert_eq!(strip(&out), "error one\r\nerror two\r\n");
    }

    #[test]
    fn bulk_path_matches_the_sequential_renderer() {
        let engine = engine_for("journalctl");
        // Enough lines to take several batches? One batch is 8 MiB; this test
        // only needs the bulk path to be taken, and parity to hold across many
        // piece boundaries.
        let mut input = String::new();
        for i in 0..4000 {
            input.push_str(&format!(
                "Oct 21 22:00:{:02} trantor svc[{}]: error {} 192.168.1.{} /nix/store/x-{}.drv\n",
                i % 60,
                i,
                i % 7,
                i % 250,
                i
            ));
        }
        let mut reference = Streamer::new(&engine);
        reference.feed(input.as_bytes());
        let (expected, expected_stats) = reference.into_output();

        let mut got: Vec<u8> = Vec::new();
        let stats = process(&engine, std::io::Cursor::new(input.as_bytes()), &mut got).unwrap();

        assert_eq!(got.len(), expected.len(), "different output length");
        assert!(got == expected, "parallel output differs from sequential");
        assert_eq!(stats.lines, expected_stats.lines);
        assert_eq!(stats.spans, expected_stats.spans);
    }

    #[test]
    fn streaming_sources_take_the_live_path() {
        // A source that hands over small chunks must not wait for a batch.
        let engine = engine_for("generic");
        let written = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let reader = ProbeReader {
            chunks: vec![b"error one\n".to_vec(), b"error two\n".to_vec()],
            index: 0,
            written: written.clone(),
        };
        let stats = process(&engine, reader, ProbeWriter(written.clone())).unwrap();
        assert_eq!(stats.lines, 2);
    }

    #[test]
    fn stats_count_lines_and_bytes() {
        let engine = engine_for("generic");
        let mut out = Vec::new();
        let stats = process(&engine, "a\nb\nc\n".as_bytes(), &mut out).unwrap();
        assert_eq!(stats.lines, 3);
        assert_eq!(stats.bytes, 6);
    }
}
