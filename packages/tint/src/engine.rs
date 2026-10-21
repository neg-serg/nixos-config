//! The per-line pipeline: classify, match, resolve styles, emit.
//!
//! The engine owns everything a run needs after the arguments have been parsed
//! (a scan configuration, a compiled rule list, a theme and the user's style
//! table), so rendering is immutable and lock-free: the streaming code can move
//! it behind a shared reference and read the same engine from several readers.

use std::io::{self, Read, Write};

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
        Streamer {
            engine,
            pending: Vec::new(),
            out: Vec::with_capacity(64 * 1024),
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
            let Some(offset) = chunk[start..].iter().position(|b| TERMINATOR[*b as usize]) else {
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
pub fn process<R: Read, W: Write>(
    engine: &Engine,
    mut reader: R,
    mut writer: W,
) -> io::Result<Stats> {
    let mut streamer = Streamer::new(engine);
    let mut inbuf = vec![0u8; 64 * 1024];
    loop {
        let read = match reader.read(&mut inbuf) {
            Ok(0) => break,
            Ok(n) => n,
            Err(err) if err.kind() == io::ErrorKind::Interrupted => continue,
            Err(err) => return Err(err),
        };
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
    fn stats_count_lines_and_bytes() {
        let engine = engine_for("generic");
        let mut out = Vec::new();
        let stats = process(&engine, "a\nb\nc\n".as_bytes(), &mut out).unwrap();
        assert_eq!(stats.lines, 3);
        assert_eq!(stats.bytes, 6);
    }
}
