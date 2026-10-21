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

/// Counters for `--stats`.
#[derive(Default, Debug, Clone, Copy)]
pub struct Stats {
    pub lines: u64,
    pub bytes: u64,
    pub spans: u64,
}

/// Colourise everything `reader` yields into `writer`, line by line.
///
/// Lines are forwarded as soon as they are complete, so `journalctl -f` and
/// other infinite sources stream instead of buffering.
pub fn process<R: Read, W: Write>(
    engine: &Engine,
    mut reader: R,
    mut writer: W,
) -> io::Result<Stats> {
    let mut stats = Stats::default();
    let mut inbuf = vec![0u8; 64 * 1024];
    let mut pending: Vec<u8> = Vec::new();
    let mut out: Vec<u8> = Vec::with_capacity(64 * 1024);
    let mut hits: Vec<Hit> = Vec::with_capacity(32);
    let mut sgr = SgrWriter::new();

    // Reusable line scratch: a line longer than the read buffer is assembled
    // here, everything else borrows straight from `inbuf`.
    loop {
        let read = match reader.read(&mut inbuf) {
            Ok(0) => break,
            Ok(n) => n,
            Err(err) if err.kind() == io::ErrorKind::Interrupted => continue,
            Err(err) => return Err(err),
        };
        stats.bytes += read as u64;
        let chunk = &inbuf[..read];
        let mut start = 0usize;
        while let Some(offset) = chunk[start..].iter().position(|b| *b == b'\n') {
            let end = start + offset;
            let mut line: &[u8] = &chunk[start..end];
            if !pending.is_empty() {
                pending.extend_from_slice(line);
                line = &pending;
            }
            stats.spans += render(engine, line, &mut hits, &mut sgr, &mut out) as u64;
            stats.lines += 1;
            out.push(b'\n');
            start = end + 1;
            if out.len() >= 60 * 1024 {
                writer.write_all(&out)?;
                out.clear();
            }
            pending.clear();
        }
        if start < chunk.len() {
            pending.extend_from_slice(&chunk[start..]);
        }
    }
    if !pending.is_empty() {
        let line = std::mem::take(&mut pending);
        stats.spans += render(engine, &line, &mut hits, &mut sgr, &mut out) as u64;
        stats.lines += 1;
    }
    if !out.is_empty() {
        writer.write_all(&out)?;
    }
    writer.flush()?;
    Ok(stats)
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

    #[test]
    fn stats_count_lines_and_bytes() {
        let engine = engine_for("generic");
        let mut out = Vec::new();
        let stats = process(&engine, "a\nb\nc\n".as_bytes(), &mut out).unwrap();
        assert_eq!(stats.lines, 3);
        assert_eq!(stats.bytes, 6);
    }
}
