//! zalgo — read from stdin, print it back with combining marks.
//!
//! Port of `files/art/fun-art/zalgo.py` (originally by MetroWind): every
//! character gets a randomised number of combining marks above, on and below
//! it, which is exactly the "cursed text" effect. Flags mirror the Python
//! `optparse` interface so existing invocations keep working.
//!
//! The mark sets are copied verbatim from the original; the choice of marks is
//! random, so output is not byte-comparable with the Python version — the tests
//! pin the invariants instead (which marks, how many, and what stays untouched).

use std::io::{Read, Write};

const CHAR_UP: [char; 50] = [
    '\u{030d}', '\u{030e}', '\u{0304}', '\u{0305}', '\u{033f}', '\u{0311}', '\u{0306}', '\u{0310}',
    '\u{0352}', '\u{0357}', '\u{0351}', '\u{0307}', '\u{0308}', '\u{030a}', '\u{0342}', '\u{0343}',
    '\u{0344}', '\u{034a}', '\u{034b}', '\u{034c}', '\u{0303}', '\u{0302}', '\u{030c}', '\u{0350}',
    '\u{0300}', '\u{0301}', '\u{030b}', '\u{030f}', '\u{0312}', '\u{0313}', '\u{0314}', '\u{033d}',
    '\u{0309}', '\u{0363}', '\u{0364}', '\u{0365}', '\u{0366}', '\u{0367}', '\u{0368}', '\u{0369}',
    '\u{036a}', '\u{036b}', '\u{036c}', '\u{036d}', '\u{036e}', '\u{036f}', '\u{033e}', '\u{035b}',
    '\u{0346}', '\u{031a}',
];

const CHAR_MID: [char; 23] = [
    '\u{0315}', '\u{031b}', '\u{0340}', '\u{0341}', '\u{0358}', '\u{0321}', '\u{0322}', '\u{0327}',
    '\u{0328}', '\u{0334}', '\u{0335}', '\u{0336}', '\u{034f}', '\u{035c}', '\u{035d}', '\u{035e}',
    '\u{035f}', '\u{0360}', '\u{0362}', '\u{0338}', '\u{0337}', '\u{0361}', '\u{0489}',
];

const CHAR_DOWN: [char; 40] = [
    '\u{0316}', '\u{0317}', '\u{0318}', '\u{0319}', '\u{031c}', '\u{031d}', '\u{031e}', '\u{031f}',
    '\u{0320}', '\u{0324}', '\u{0325}', '\u{0326}', '\u{0329}', '\u{032a}', '\u{032b}', '\u{032c}',
    '\u{032d}', '\u{032e}', '\u{032f}', '\u{0330}', '\u{0331}', '\u{0332}', '\u{0333}', '\u{0339}',
    '\u{033a}', '\u{033b}', '\u{033c}', '\u{0345}', '\u{0347}', '\u{0348}', '\u{0349}', '\u{034d}',
    '\u{034e}', '\u{0353}', '\u{0354}', '\u{0355}', '\u{0356}', '\u{0359}', '\u{035a}', '\u{0323}',
];

const ZALGO_POS: [&str; 3] = ["up", "mid", "down"];

/// Small xorshift generator: the effect only needs plausible randomness, and
/// pulling in a crate for it would break the "no dependencies" rule.
pub struct Rng(u64);

impl Rng {
    pub fn new() -> Rng {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|delta| delta.as_nanos() as u64)
            .unwrap_or(0x9e3779b97f4a7c15);
        Rng(nanos | 1)
    }

    fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.0 = x;
        x
    }

    /// `random.randint(0, max)` — inclusive on both ends.
    fn randint(&mut self, max: usize) -> usize {
        if max == 0 {
            return 0;
        }
        (self.next() % (max as u64 + 1)) as usize
    }

    fn choice(&mut self, set: &[char]) -> char {
        set[(self.next() % set.len() as u64) as usize]
    }

    /// `random.sample` + `shuffle`: a random subset without repeats.
    fn sample(&mut self, set: &[char], count: usize) -> Vec<char> {
        let count = count.min(set.len());
        let mut pool: Vec<char> = set.to_vec();
        for index in 0..count {
            let swap = index + (self.next() as usize % (pool.len() - index));
            pool.swap(index, swap);
        }
        pool.truncate(count);
        pool
    }
}

fn charset(position: &str) -> &'static [char] {
    match position {
        "up" => &CHAR_UP,
        "mid" => &CHAR_MID,
        _ => &CHAR_DOWN,
    }
}

/// Add the marks for one character.
pub fn zalgo_char(ch: char, intensities: &[usize; 3], randomise: bool, rng: &mut Rng) -> String {
    let mut out = String::new();
    out.push(ch);
    for (index, position) in ZALGO_POS.iter().enumerate() {
        let count = if randomise {
            rng.randint(intensities[index])
        } else {
            intensities[index]
        };
        for mark in rng.sample(charset(position), count) {
            out.push(mark);
        }
    }
    out
}

/// Zalgo-ify one line; characters in `excludes` are left alone.
pub fn zalgo(
    text: &str,
    intensities: &[usize; 3],
    excludes: &[char],
    randomise: bool,
    rng: &mut Rng,
) -> String {
    let mut out = String::new();
    for ch in text.chars() {
        if excludes.contains(&ch) {
            out.push(ch);
        } else {
            out.push_str(&zalgo_char(ch, intensities, randomise, rng));
        }
    }
    out
}

struct Options {
    up: usize,
    mid: usize,
    down: usize,
    randomise: bool,
    excludes: Vec<char>,
}

fn parse_args() -> Result<Options, String> {
    let mut options = Options {
        up: 2,
        mid: 1,
        down: 5,
        randomise: true,
        excludes: vec![' '],
    };
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        let (flag, inline) = match arg.split_once('=') {
            Some((flag, value)) => (flag.to_string(), Some(value.to_string())),
            None => (arg.clone(), None),
        };
        let mut value = |name: &str| -> Result<String, String> {
            inline
                .clone()
                .or_else(|| args.next())
                .ok_or_else(|| format!("{name} expects a value"))
        };
        match flag.as_str() {
            "-u" | "--up-intensity" => {
                options.up = value("--up-intensity")?
                    .parse()
                    .map_err(|_| "bad number".to_string())?;
            }
            "-m" | "--mid-intensity" => {
                options.mid = value("--mid-intensity")?
                    .parse()
                    .map_err(|_| "bad number".to_string())?;
            }
            "-d" | "--down-intensity" => {
                options.down = value("--down-intensity")?
                    .parse()
                    .map_err(|_| "bad number".to_string())?;
            }
            "-f" | "--fix-intensity" => options.randomise = false,
            "-e" | "--excludes" => {
                options.excludes = value("--excludes")?.chars().collect();
            }
            "-h" | "--help" => {
                print!("{USAGE}");
                std::process::exit(0);
            }
            other => return Err(format!("unknown option {other}")),
        }
    }
    Ok(options)
}

const USAGE: &str = "\
Usage: zalgo [options]

  -u NUM, --up-intensity=NUM    marks above the character (default 2)
  -m NUM, --mid-intensity=NUM   marks on the character (default 1)
  -d NUM, --down-intensity=NUM  marks below the character (default 5)
  -f, --fix-intensity           do not randomise the intensity
  -e STR, --excludes=STR        characters left alone (default \" \")
";

fn main() -> std::process::ExitCode {
    let options = match parse_args() {
        Ok(options) => options,
        Err(exc) => {
            eprintln!("zalgo: {exc}");
            return std::process::ExitCode::from(2);
        }
    };
    let mut input = String::new();
    if std::io::stdin().read_to_string(&mut input).is_err() {
        eprintln!("zalgo: cannot read stdin");
        return std::process::ExitCode::from(1);
    }
    let intensities = [options.up, options.mid, options.down];
    let mut rng = Rng::new();
    let mut stdout = std::io::stdout();
    for line in input.lines() {
        let rendered = zalgo(
            line,
            &intensities,
            &options.excludes,
            options.randomise,
            &mut rng,
        );
        let _ = writeln!(stdout, "{rendered}");
    }
    let _ = stdout.flush();
    std::process::ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;

    fn seeded() -> Rng {
        Rng(0x1234_5678)
    }

    #[test]
    fn fixed_intensity_adds_exactly_that_many_marks() {
        let mut rng = seeded();
        let rendered = zalgo_char('a', &[2, 1, 5], false, &mut rng);
        let marks: Vec<char> = rendered.chars().skip(1).collect();
        assert_eq!(marks.len(), 8, "{rendered:?}");
        assert!(marks[..2].iter().all(|mark| CHAR_UP.contains(mark)));
        assert!(marks[2..3].iter().all(|mark| CHAR_MID.contains(mark)));
        assert!(marks[3..].iter().all(|mark| CHAR_DOWN.contains(mark)));
    }

    #[test]
    fn marks_never_repeat_within_one_character() {
        // `random.sample` semantics: 50 distinct up-marks at most.
        let mut rng = seeded();
        let rendered = zalgo_char('x', &[50, 0, 0], false, &mut rng);
        let marks: Vec<char> = rendered.chars().skip(1).collect();
        let mut unique = marks.clone();
        unique.sort();
        unique.dedup();
        assert_eq!(marks.len(), unique.len());
    }

    #[test]
    fn excluded_characters_are_left_alone() {
        let mut rng = seeded();
        let rendered = zalgo("a b", &[1, 1, 1], &[' '], false, &mut rng);
        assert!(rendered.contains(' '), "{rendered:?}");
        // The space itself is untouched: exactly one character between the marks.
        let segments: Vec<&str> = rendered.split(' ').collect();
        assert_eq!(segments.len(), 2);
    }

    #[test]
    fn randomised_intensity_stays_within_bounds() {
        let mut rng = seeded();
        for _ in 0..200 {
            let rendered = zalgo_char('z', &[3, 2, 4], true, &mut rng);
            let count = rendered.chars().count() - 1;
            assert!(count <= 3 + 2 + 4, "too many marks: {count}");
        }
    }
}
