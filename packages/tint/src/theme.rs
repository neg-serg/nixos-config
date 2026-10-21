//! Semantic colour slots and the themes that fill them.
//!
//! Everything the engine can colour is addressed through a [`Kind`], never
//! through a raw escape code: rulesets and scanners say *what* a token is, the
//! theme says *how* it looks. That split is what makes `--theme`, `mono` and
//! `NO_COLOR` a table swap instead of a code path.

use crate::style::{Color, Style};

/// What a span of text is, semantically.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Kind {
    /// Errors, failures, fatal conditions.
    Err,
    /// Warnings and deprecations.
    Warn,
    /// Success, "active (running)", "OK".
    Ok,
    /// Informational markers, headers of streamed logs.
    Info,
    /// Notes, hints, "reached", "changed".
    Note,
    /// De-emphasised text: timestamps, separators, units.
    Dim,
    /// Plain numbers in tabular output.
    Num,
    /// Byte sizes and counts with a unit (`12G`, `1.5 GiB`).
    Size,
    /// Durations (`230ms`, `1.5s`, `2h13m`).
    Dur,
    /// Temperatures below the hot threshold.
    TempCool,
    /// Temperatures at or above the hot threshold.
    TempHot,
    /// Percentages below the caution threshold.
    PctLow,
    /// Percentages in the caution band.
    PctMid,
    /// Percentages in the danger band.
    PctHigh,
    /// Filesystem paths.
    Path,
    /// URLs.
    Url,
    /// IPv4/IPv6 addresses and CIDR prefixes.
    Ip,
    /// MAC addresses.
    Mac,
    /// Ports and numeric protocol identifiers.
    Port,
    /// Timestamps (ISO, syslog, `HH:MM:SS`).
    Time,
    /// Hashes: git object ids, checksums.
    Hash,
    /// Quoted strings.
    Str,
    /// Keys of `key=value` / `key: value` pairs.
    Key,
    /// Unit suffixes (`KiB`, `%`, `ms`).
    Unit,
    /// Table headers and emphasised lines.
    Hdr,
    /// Structural punctuation: `|`, `->`, `=>`, brackets.
    Sep,
    /// Added lines (diffs), "+".
    Add,
    /// Removed lines (diffs), "-".
    Del,
    /// Diff hunk headers and context.
    Ctx,
}

pub const KIND_COUNT: usize = 29;

impl Kind {
    /// Every kind, in the order used by [`Theme`]. Kept next to the enum so a
    /// new kind cannot be forgotten here.
    pub const ALL: [Kind; KIND_COUNT] = [
        Kind::Err,
        Kind::Warn,
        Kind::Ok,
        Kind::Info,
        Kind::Note,
        Kind::Dim,
        Kind::Num,
        Kind::Size,
        Kind::Dur,
        Kind::TempCool,
        Kind::TempHot,
        Kind::PctLow,
        Kind::PctMid,
        Kind::PctHigh,
        Kind::Path,
        Kind::Url,
        Kind::Ip,
        Kind::Mac,
        Kind::Port,
        Kind::Time,
        Kind::Hash,
        Kind::Str,
        Kind::Key,
        Kind::Unit,
        Kind::Hdr,
        Kind::Sep,
        Kind::Add,
        Kind::Del,
        Kind::Ctx,
    ];
}

impl Kind {
    /// The config/CLI name of this slot.
    pub fn name(self) -> &'static str {
        match self {
            Kind::Err => "err",
            Kind::Warn => "warn",
            Kind::Ok => "ok",
            Kind::Info => "info",
            Kind::Note => "note",
            Kind::Dim => "dim",
            Kind::Num => "num",
            Kind::Size => "size",
            Kind::Dur => "dur",
            Kind::TempCool => "tempcool",
            Kind::TempHot => "temphot",
            Kind::PctLow => "pctlow",
            Kind::PctMid => "pctmid",
            Kind::PctHigh => "pcthigh",
            Kind::Path => "path",
            Kind::Url => "url",
            Kind::Ip => "ip",
            Kind::Mac => "mac",
            Kind::Port => "port",
            Kind::Time => "time",
            Kind::Hash => "hash",
            Kind::Str => "str",
            Kind::Key => "key",
            Kind::Unit => "unit",
            Kind::Hdr => "hdr",
            Kind::Sep => "sep",
            Kind::Add => "add",
            Kind::Del => "del",
            Kind::Ctx => "ctx",
        }
    }

    /// Look a kind up by its config name (`err`, `pcthigh`, ...).
    pub fn by_name(name: &str) -> Option<Kind> {
        let kind = match name {
            "err" | "error" => Kind::Err,
            "warn" | "warning" => Kind::Warn,
            "ok" => Kind::Ok,
            "info" => Kind::Info,
            "note" => Kind::Note,
            "dim" => Kind::Dim,
            "num" | "number" => Kind::Num,
            "size" => Kind::Size,
            "dur" | "duration" => Kind::Dur,
            "tempcool" => Kind::TempCool,
            "temphot" => Kind::TempHot,
            "pctlow" => Kind::PctLow,
            "pctmid" => Kind::PctMid,
            "pcthigh" => Kind::PctHigh,
            "path" => Kind::Path,
            "url" => Kind::Url,
            "ip" => Kind::Ip,
            "mac" => Kind::Mac,
            "port" => Kind::Port,
            "time" => Kind::Time,
            "hash" => Kind::Hash,
            "str" | "string" => Kind::Str,
            "key" => Kind::Key,
            "unit" => Kind::Unit,
            "hdr" | "header" => Kind::Hdr,
            "sep" => Kind::Sep,
            "add" => Kind::Add,
            "del" => Kind::Del,
            "ctx" => Kind::Ctx,
            _ => return None,
        };
        Some(kind)
    }
}

/// A theme: one style per [`Kind`].
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Theme {
    styles: [Style; KIND_COUNT],
}

impl Theme {
    pub fn get(&self, kind: Kind) -> Style {
        self.styles[kind as usize]
    }

    pub fn set(&mut self, kind: Kind, style: Style) {
        self.styles[kind as usize] = style;
    }

    /// Build a theme from a per-kind style list, in [`Kind::ALL`] order.
    fn from_styles(styles: [Style; KIND_COUNT]) -> Theme {
        Theme { styles }
    }

    /// Default for dark terminals: classic 16 ANSI colours, so the result
    /// follows whatever palette the terminal theme uses.
    pub fn dark() -> Theme {
        Theme::from_styles([
            Style::fg(1).bold(),      // Err
            Style::fg(3).bold(),      // Warn
            Style::fg(2),             // Ok
            Style::fg(6),             // Info
            Style::fg(5),             // Note
            Style::fg(8),             // Dim
            Style::fg(8),             // Num
            Style::fg(6),             // Size
            Style::fg(5),             // Dur
            Style::fg(2),             // TempCool
            Style::fg(1).bold(),      // TempHot
            Style::fg(2),             // PctLow
            Style::fg(3),             // PctMid
            Style::fg(1).bold(),      // PctHigh
            Style::fg(4).underline(), // Path
            Style::fg(4).underline(), // Url
            Style::fg(6),             // Ip
            Style::fg(5),             // Mac
            Style::fg(6).dim(),       // Port
            Style::fg(8),             // Time
            Style::fg(3),             // Hash
            Style::fg(2),             // Str
            Style::fg(4).bold(),      // Key
            Style::fg(8),             // Unit
            Style::NONE.bold(),       // Hdr
            Style::fg(8),             // Sep
            Style::fg(2),             // Add
            Style::fg(1),             // Del
            Style::fg(6),             // Ctx
        ])
    }

    /// Variant that keeps contrast on a light background: no bright colours,
    /// darker blues and greens.
    pub fn light() -> Theme {
        let mut theme = Theme::dark();
        theme.set(Kind::Err, Style::fg(1).bold());
        theme.set(Kind::Warn, Style::fg(130));
        theme.set(Kind::Ok, Style::fg(28));
        theme.set(Kind::Info, Style::fg(30));
        theme.set(Kind::Note, Style::fg(90));
        theme.set(Kind::Dim, Style::fg(245));
        theme.set(Kind::Num, Style::fg(245));
        theme.set(Kind::Size, Style::fg(30));
        theme.set(Kind::Dur, Style::fg(90));
        theme.set(Kind::TempCool, Style::fg(28));
        theme.set(Kind::TempHot, Style::fg(124).bold());
        theme.set(Kind::PctLow, Style::fg(28));
        theme.set(Kind::PctMid, Style::fg(130));
        theme.set(Kind::PctHigh, Style::fg(124).bold());
        theme.set(Kind::Path, Style::fg(25).underline());
        theme.set(Kind::Url, Style::fg(25).underline());
        theme.set(Kind::Ip, Style::fg(30));
        theme.set(Kind::Mac, Style::fg(90));
        theme.set(Kind::Port, Style::fg(30));
        theme.set(Kind::Time, Style::fg(245));
        theme.set(Kind::Hash, Style::fg(130));
        theme.set(Kind::Str, Style::fg(28));
        theme.set(Kind::Key, Style::fg(25).bold());
        theme.set(Kind::Unit, Style::fg(245));
        theme.set(Kind::Sep, Style::fg(245));
        theme.set(Kind::Add, Style::fg(28));
        theme.set(Kind::Del, Style::fg(124));
        theme.set(Kind::Ctx, Style::fg(30));
        theme
    }

    /// 256-colour variant with the same semantics but calmer, more separated
    /// hues. Useful on truecolor terminals when 16 colours feel coarse.
    pub fn vivid() -> Theme {
        let mut theme = Theme::dark();
        theme.set(Kind::Err, Style::fg(203).bold());
        theme.set(Kind::Warn, Style::fg(214).bold());
        theme.set(Kind::Ok, Style::fg(41));
        theme.set(Kind::Info, Style::fg(45));
        theme.set(Kind::Note, Style::fg(170));
        theme.set(Kind::Dim, Style::fg(245));
        theme.set(Kind::Num, Style::fg(250));
        theme.set(Kind::Size, Style::fg(45));
        theme.set(Kind::Dur, Style::fg(170));
        theme.set(Kind::TempCool, Style::fg(41));
        theme.set(Kind::TempHot, Style::fg(203).bold());
        theme.set(Kind::PctLow, Style::fg(41));
        theme.set(Kind::PctMid, Style::fg(214));
        theme.set(Kind::PctHigh, Style::fg(203).bold());
        theme.set(
            Kind::Path,
            Style {
                fg: Some(Color::Idx(33)),
                underline: true,
                ..Style::NONE
            },
        );
        theme.set(
            Kind::Url,
            Style {
                fg: Some(Color::Idx(39)),
                underline: true,
                ..Style::NONE
            },
        );
        theme.set(Kind::Ip, Style::fg(45));
        theme.set(Kind::Mac, Style::fg(170));
        theme.set(Kind::Port, Style::fg(45).dim());
        theme.set(Kind::Time, Style::fg(245));
        theme.set(Kind::Hash, Style::fg(221));
        theme.set(Kind::Str, Style::fg(41));
        theme.set(Kind::Key, Style::fg(33).bold());
        theme.set(Kind::Unit, Style::fg(245));
        theme.set(Kind::Sep, Style::fg(240));
        theme.set(Kind::Add, Style::fg(41));
        theme.set(Kind::Del, Style::fg(203));
        theme.set(Kind::Ctx, Style::fg(45));
        theme
    }

    /// The `neg.nvim` palette, as truecolor.
    ///
    /// Colours are taken from the editor theme itself (palette.lua and
    /// groups/diagnostics.lua), not invented: errors are the diff-delete
    /// burgundy, warnings the lilac `dwarn`, success the diff-add spruce, hints
    /// the identifier blue, strings `lstr`, delimiters `dlim`, keywords `ops*`.
    /// Use it when the terminal background is the same near-black the editor
    /// uses (`#000000`); otherwise `dark` follows whatever ANSI palette the
    /// terminal has, which on this host is already the neg-tinted one.
    pub fn neg() -> Theme {
        let rgb = Style::fg_rgb;
        // One deliberate deviation: neg.nvim paints diagnostics with the
        // diff-delete burgundy #6b0f2a, which is 1.7:1 against the #000000
        // background — fine in the editor, where an undercurl and virtual text
        // carry the message, but unreadable for a one-line CLI error. The error
        // family therefore uses the bright red of the same terminal palette
        // (kitty color9 #cf4f88, 5.1:1). Override with
        // `theme.style.err = "#6b0f2a"` if the exact editor look is wanted.
        let red = rgb(0xcf, 0x4f, 0x88);
        Theme::from_styles([
            red.bold(),                        // Err        bright red of the palette
            rgb(0xc8, 0xa8, 0xef),             // Warn       dwarn
            rgb(0x00, 0x7a, 0x66),             // Ok         diff_add
            rgb(0x70, 0x95, 0xb0),             // Info       preproc_light
            rgb(0x62, 0x89, 0xb3),             // Note       identifier
            rgb(0x50, 0x6a, 0x7d),             // Dim        preproc_dark
            rgb(0x39, 0x55, 0x73),             // Num        ops4
            rgb(0x14, 0x87, 0x87),             // Size       literal2
            rgb(0x2b, 0x76, 0x94),             // Dur        ops2
            rgb(0x12, 0x7a, 0x57),             // TempCool   literal3
            red.bold(),                        // TempHot    bright red
            rgb(0x12, 0x7a, 0x57),             // PctLow     literal3
            rgb(0xc8, 0xa8, 0xef),             // PctMid     dwarn
            red.bold(),                        // PctHigh    bright red
            rgb(0x62, 0x89, 0xb3).underline(), // Path    identifier
            rgb(0x36, 0x7c, 0xb0).underline(), // Url     ops1
            rgb(0x14, 0x87, 0x87),             // Ip         literal2
            rgb(0x2b, 0x76, 0x94),             // Mac        ops2
            rgb(0x39, 0x55, 0x73),             // Port       ops4
            rgb(0x50, 0x6a, 0x7d),             // Time       preproc_dark
            rgb(0x36, 0x7c, 0xb0),             // Hash       ops1
            rgb(0x6e, 0x87, 0x9f),             // Str        lstr
            rgb(0x70, 0x95, 0xb0).bold(),      // Key        func
            rgb(0x50, 0x6a, 0x7d),             // Unit       preproc_dark
            rgb(0xa5, 0xc1, 0xe6).bold(),      // Hdr        high
            rgb(0x39, 0x55, 0x73),             // Sep        ops4
            rgb(0x00, 0x7a, 0x66),             // Add        diff_add
            red,                               // Del        bright red
            rgb(0x2b, 0x76, 0x94),             // Ctx        ops2
        ])
    }

    /// Attributes only — for colour-blind users, monochrome terminals and
    /// screenshots that must survive greyscale printing.
    pub fn mono() -> Theme {
        let mut theme = Theme::from_styles([Style::NONE; KIND_COUNT]);
        theme.set(Kind::Err, Style::NONE.bold());
        theme.set(Kind::Warn, Style::NONE.bold());
        theme.set(Kind::Ok, Style::NONE);
        theme.set(Kind::Info, Style::NONE.italic());
        theme.set(Kind::Note, Style::NONE.italic());
        theme.set(Kind::Dim, Style::NONE.dim());
        theme.set(Kind::Num, Style::NONE.dim());
        theme.set(Kind::Size, Style::NONE);
        theme.set(Kind::Dur, Style::NONE.dim());
        theme.set(Kind::TempCool, Style::NONE);
        theme.set(Kind::TempHot, Style::NONE.bold());
        theme.set(Kind::PctLow, Style::NONE);
        theme.set(Kind::PctMid, Style::NONE.bold());
        theme.set(Kind::PctHigh, Style::NONE.bold());
        theme.set(Kind::Path, Style::NONE.underline());
        theme.set(Kind::Url, Style::NONE.underline());
        theme.set(Kind::Ip, Style::NONE);
        theme.set(Kind::Mac, Style::NONE.dim());
        theme.set(Kind::Port, Style::NONE.dim());
        theme.set(Kind::Time, Style::NONE.dim());
        theme.set(Kind::Hash, Style::NONE);
        theme.set(Kind::Str, Style::NONE);
        theme.set(Kind::Key, Style::NONE.bold());
        theme.set(Kind::Unit, Style::NONE.dim());
        theme.set(Kind::Hdr, Style::NONE.bold());
        theme.set(Kind::Sep, Style::NONE.dim());
        theme.set(Kind::Add, Style::NONE.underline());
        theme.set(Kind::Del, Style::NONE.bold());
        theme.set(Kind::Ctx, Style::NONE);
        theme
    }

    /// Everything plain: used by `--color=never` on the render path.
    pub fn plain() -> Theme {
        Theme::from_styles([Style::NONE; KIND_COUNT])
    }

    /// Look a theme up by CLI/config name.
    pub fn by_name(name: &str) -> Option<Theme> {
        match name {
            "dark" | "auto" | "" => Some(Theme::dark()),
            "light" => Some(Theme::light()),
            "vivid" | "256" => Some(Theme::vivid()),
            "neg" | "neg.nvim" | "negnvim" => Some(Theme::neg()),
            "mono" => Some(Theme::mono()),
            "none" | "plain" => Some(Theme::plain()),
            _ => None,
        }
    }
}

impl Default for Theme {
    fn default() -> Theme {
        Theme::dark()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_kind_has_a_slot() {
        let theme = Theme::dark();
        for kind in Kind::ALL {
            // Indexing panics on an out-of-range kind; this asserts the table
            // covers every variant.
            let _ = theme.get(kind);
        }
    }

    #[test]
    fn mono_theme_carries_no_colour() {
        let theme = Theme::mono();
        for kind in Kind::ALL {
            let style = theme.get(kind);
            assert_eq!(style.fg, None, "{kind:?} has a foreground colour");
            assert_eq!(style.bg, None, "{kind:?} has a background colour");
        }
    }

    #[test]
    fn neg_theme_uses_the_editor_palette() {
        let theme = Theme::neg();
        assert_eq!(
            theme.get(Kind::Err).fg,
            Some(Color::Rgb(0xcf, 0x4f, 0x88)),
            "errors use the bright red of the same palette, not the 1.7:1 burgundy"
        );
        assert_eq!(
            theme.get(Kind::Warn).fg,
            Some(Color::Rgb(0xc8, 0xa8, 0xef)),
            "warnings take neg.nvim's dwarn lilac"
        );
        assert_eq!(
            Theme::by_name("neg").map(|t| t.get(Kind::Str)),
            Some(Theme::neg().get(Kind::Str))
        );
    }

    #[test]
    fn dark_and_light_differ() {
        assert_ne!(Theme::dark(), Theme::light());
        assert_ne!(Theme::dark(), Theme::vivid());
    }
}
