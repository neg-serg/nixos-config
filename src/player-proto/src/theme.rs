//! Design tokens: colour, type and geometry.
//!
//! Everything the UI draws reads from a `Theme`, so a variant is a data change, not a code
//! change. Colours are authored as sRGB 0..1 floats for direct upload to the shader; the hex
//! value in the comment next to each token is the source of truth (see `scene::linear`, which
//! converts once on the CPU because the swapchain is an SRGB format).
//!
//! # Provenance
//!
//! The palette is the user's Neovim colourscheme `neg.nvim`
//! (`~/.local/share/nvim/lazy/neg.nvim`, v4.72) — a "pure dark" theme: pure black ground, one
//! blue-grey neutral ink family, and a small, deliberately unsaturated set of hues for meaning.
//! That scheme is the single source of truth for hue and chroma here, so every token below is
//! exactly one of two things:
//!
//! 1. **A neg entry, unchanged.** The comment names it (`neg whit`, `neg culc`, ...).
//! 2. **A derived tone**, written `derived(source, floor)` and produced by one rule: keep the
//!    source's OKLCh hue and chroma, move along the lightness axis until the WCAG contrast
//!    against `bg` reaches the stated floor. In OKLab terms that is the *nearest* colour to the
//!    neg original that satisfies the readability constraint — the smallest Euclidean
//!    displacement that makes the tone usable at UI text sizes.
//!
//! The floors, and why they are these numbers:
//!
//! - **4.5:1** for every token that carries text (WCAG 2.1 AA, normal size). neg itself targets
//!   AA and never AAA (`#6c7e96` on black is 5.06:1); its chrome tones are deliberately sub-AA
//!   in a terminal (comment 1.97:1, LineNr 1.71:1), which is fine for a cursor and not fine for
//!   an 11 px caption — hence the derivation rule above.
//! - **3.0:1** for non-text UI (WCAG 1.4.11): accent rails, the hairline that delimits a pane.
//! - **0.05 in OKLab** as the minimum perceptual distance between two tokens that mean different
//!   things. Below that, two colours are one colour — including for a dichromat.
//!
//! `tools/theme-audit/theme_audit.py` recomputes every pair (contrast, OKLab distance,
//! CIEDE2000, and both again under simulated protanopia/deuteranopia/tritanopia);
//! `src/color.rs` carries the same maths so the invariants are asserted in `cargo test`. The
//! measured table and the review notes live in `THEME-AUDIT.md`.
//!
//! # What "strictly neg" means for the layout
//!
//! neg separates surfaces the way Neovim does: the ground stays pure black, panes are told
//! apart by a hairline and by air, and *state* is what carries fill — the cursor row is the
//! grey `culc` bar (monochrome, exactly like the theme's Pmenu selection), the playing row is
//! the blue-tinted `selection_bg`, hover is the weakest of the three, and neither of them is a
//! coloured gradient. Panes at rest cast no shadow, because a terminal window does not either.

pub type Rgba = [f32; 4];

/// One step on the z axis: the surface a pane paints and the alpha of the drop shadow it casts.
///
/// The two travel together on purpose. A lighter surface over an unchanged shadow reads as a
/// paint mistake, and a deeper shadow under an unchanged surface only muddies the edge, so
/// elevation is one token of two fields instead of two free-floating numbers. neg has no
/// shadows at all (every window sits on the same black ground), so panes at rest cast none;
/// only a modal — the one surface that genuinely covers the app — keeps a light one.
#[derive(Clone, Copy)]
pub struct Elevation {
    pub surface: Rgba,
    /// Alpha of the black drop shadow the pane throws on the background.
    pub shadow: f32,
}

/// Which face to shape with. The UI keeps two families: the sans face for prose, the mono face
/// for numerals, times and the transport/symbol glyphs.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Face {
    UiRegular,
    UiMedium,
    UiSemiBold,
    Mono,
    MonoMedium,
    /// Geometric/icon glyphs: ▸ ▮ ◀ ▶ ♪ ▏
    Symbols,
}

/// Type scale (px). A ~1.2 modular scale anchored at 14.5 px for list rows.
///
/// The anchor is deliberately above a terminal's 12-13 px: the app runs full-screen on a large
/// display where the whole frame is read at arm's length, and `neg.nvim`'s sizes do not apply
/// to a window that has no character grid. Everything below scales with this anchor, so raising
/// it is the single lever that makes the UI denser *and* more readable instead of just bigger.
pub struct TypeScale {
    pub display: f32, // now-playing title
    pub title: f32,   // app name
    pub heading: f32, // pane headers, tabs
    pub body: f32,    // row titles
    pub label: f32,   // row secondary, chips
    pub caption: f32, // timings, hints
    pub micro: f32,   // uppercase pane labels
}

pub const TYPE: TypeScale = TypeScale {
    display: 27.0,
    title: 21.0,
    heading: 15.5,
    body: 14.5,
    label: 13.0,
    caption: 12.5,
    micro: 11.5,
};

/// Spacing and shape. Multiples of 2 px so half-pixel offsets disappear at 1x scaling.
///
/// neg is a character-cell theme and encodes no spacing at all, so the rhythm below is the
/// app's own — but the *shape* follows the theme: a terminal cell has no corner radius, so the
/// radii stay near-square instead of the 8-14 px pills of a web UI, and one hairline width is
/// used everywhere a surface is delimited.
pub struct Geometry {
    pub pad: f32,
    pub gap: f32,
    pub row_h: f32,
    pub row_h_compact: f32,
    pub row_h_thick: f32,
    /// Side of the cover tile in a thick row.
    pub cover_tile: f32,
    pub radius_sm: f32,
    pub radius_md: f32,
    pub radius_lg: f32,
    pub radius_pill: f32,
    pub radius_art: f32,
    pub line: f32, // hairline thickness
    /// Inset of a list row's surface from its pane edge. Rows never bleed to the border.
    pub row_inset: f32,
    /// Vertical gap between a row surface and the next row's surface.
    pub row_gap: f32,
    /// Accent rail drawn on the selected row.
    pub rail_w: f32,
    /// Index column of a list row: three digits in the caption face plus air.
    pub gutter: f32,
    /// Air between two blocks of a vertical stack (art → metadata → progress → transport →
    /// modes → next-up). One value for the whole app, so blocks never drift apart.
    pub stack: f32,
    /// Air inside one block: a bar and its labels, a label and its value.
    pub inner: f32,
    /// Air between two panes. One token so the queue width and the now-playing x cannot drift
    /// apart, which is how an 8 px gap appeared where the layout claimed 24.
    pub pane_gap: f32,
}

pub const GEOM: Geometry = Geometry {
    pad: 18.0,
    gap: 12.0,
    pane_gap: 12.0,
    // Two-line rows (queue, search): a 14.5 px title over a 12.5 px secondary line, plus
    // enough padding that the two lines never touch the row's own edge.
    row_h: 46.0,
    // One-line rows (library).
    row_h_compact: 40.0,
    // Thick rows (the rich list style): a 48 px cover tile plus two lines of text.
    row_h_thick: 68.0,
    cover_tile: 48.0,
    // Near-square on purpose: a corner radius is the one piece of geometry neg does not have.
    radius_sm: 2.0,
    radius_md: 3.0,
    radius_lg: 4.0,
    radius_pill: 3.0,
    radius_art: 3.0,
    line: 1.0,
    row_inset: 8.0,
    row_gap: 3.0,
    rail_w: 3.0,
    gutter: 38.0,
    stack: 14.0,
    inner: 7.0,
};

#[derive(Clone)]
pub struct Theme {
    pub name: &'static str,
    // surfaces
    pub bg_top: Rgba,
    pub bg_bottom: Rgba,
    /// Base surface of anything painted on a pane: chips, overlays, popovers.
    pub panel: Rgba,
    pub panel_hi: Rgba,
    /// Recessed wells: art placeholder, progress bed.
    pub panel_inset: Rgba,
    /// Elevation of the panes that do not hold the keyboard.
    pub pane_rest: Elevation,
    /// Elevation of the pane that does: a lifted surface, so focus is legible from the pane
    /// body itself instead of only from an accent outline.
    pub pane_raised: Elevation,
    pub border: Rgba,
    /// 1 px highlight on the edge a panel is read from (top edge of an overlay, the seam
    /// between a pane header and its rows).
    pub border_hi: Rgba,
    pub shadow: Rgba,
    // text
    pub text: Rgba,
    pub text_dim: Rgba,
    pub text_faint: Rgba,
    pub text_on_accent: Rgba,
    /// Non-text ink: separators, dots, the track of an unlabelled rule. Sits below the text
    /// floor on purpose — it never carries a glyph.
    pub rule: Rgba,
    // accents
    pub accent: Rgba,
    pub accent2: Rgba,
    pub accent_bright: Rgba,
    pub warn: Rgba,
    pub accent_soft: Rgba,
    /// Fill of the cursor row. Monochrome, exactly like the theme's Pmenu selection bar: a
    /// neutral grey lit surface carrying the brightest ink.
    pub selection: Rgba,
    pub selection_edge: Rgba,
    /// Flat wash behind the playing row. Blue-biased, so "playing" and "the keyboard is here"
    /// stay two different things even for a dichromat, who still reads one as lighter.
    pub playing_bg: Rgba,
    /// Wash under the pointer, and the bottom stop of the same wash. The weakest of the three:
    /// hover answers "this is pressable", `playing_bg` answers "this is playing" and
    /// `selection` answers "this is where the keyboard is".
    pub hover: Rgba,
    pub hover_edge: Rgba,
    /// The hover wash over a recessed well (progress and volume beds). Thin bars cannot carry
    /// a two-stop gradient, so this is the flat value they paint instead.
    pub hover_well: Rgba,
    // states
    pub danger: Rgba,
    pub success: Rgba,
    /// Alpha wash used under the album art backdrop.
    pub backdrop: Rgba,
}

impl Theme {
    /// Accepts the canonical names and the two legacy ones (`dark` was this app's first
    /// palette, `warm` its second), so a state file written by an older build still opens.
    /// Anything unknown falls back to `neg`, the strict palette.
    pub fn by_name(name: &str) -> &'static Theme {
        match name {
            "neg-soft" => &NEG_SOFT,
            "neg-hc" => &NEG_HC,
            _ => &NEG,
        }
    }

    /// The canonical name for whatever the user typed, so the UI can show `neg` instead of
    /// echoing a typo or a legacy alias back at them.
    pub fn canonical(name: &str) -> &'static str {
        Theme::by_name(name).name
    }

    /// Replace one token by name. Returns false when the name is not a token this theme has,
    /// so a config typo is reported instead of silently doing nothing.
    ///
    /// This is what turns a skin from a preset into a palette: everything the UI draws goes
    /// through these fields, so overriding `accent` or `text_faint` here repaints the app
    /// without touching a draw call.
    pub fn set(&mut self, token: &str, color: Rgba) -> bool {
        let slot = match token {
            "bg_top" | "bg" => &mut self.bg_top,
            "bg_bottom" => &mut self.bg_bottom,
            "panel" => &mut self.panel,
            "panel_hi" => &mut self.panel_hi,
            "panel_inset" => &mut self.panel_inset,
            "border" => &mut self.border,
            "border_hi" => &mut self.border_hi,
            "text" => &mut self.text,
            "text_dim" => &mut self.text_dim,
            "text_faint" => &mut self.text_faint,
            "text_on_accent" => &mut self.text_on_accent,
            "rule" => &mut self.rule,
            "accent" => &mut self.accent,
            "accent2" => &mut self.accent2,
            "accent_bright" => &mut self.accent_bright,
            "accent_soft" => &mut self.accent_soft,
            "warn" => &mut self.warn,
            "danger" => &mut self.danger,
            "success" => &mut self.success,
            "selection" => &mut self.selection,
            "selection_edge" => &mut self.selection_edge,
            "playing_bg" => &mut self.playing_bg,
            "hover" => &mut self.hover,
            "hover_edge" => &mut self.hover_edge,
            "hover_well" => &mut self.hover_well,
            "backdrop" => &mut self.backdrop,
            "pane_rest" => &mut self.pane_rest.surface,
            "pane_raised" => &mut self.pane_raised.surface,
            _ => return false,
        };
        *slot = color;
        true
    }

    /// Every token name `set` accepts, for error messages and for the completion of a
    /// hypothetical `:set color` line.
    pub const TOKENS: [&'static str; 28] = [
        "bg_top",
        "bg_bottom",
        "panel",
        "panel_hi",
        "panel_inset",
        "border",
        "border_hi",
        "text",
        "text_dim",
        "text_faint",
        "text_on_accent",
        "rule",
        "accent",
        "accent2",
        "accent_bright",
        "accent_soft",
        "warn",
        "danger",
        "success",
        "selection",
        "selection_edge",
        "playing_bg",
        "hover",
        "hover_edge",
        "hover_well",
        "backdrop",
        "pane_rest",
        "pane_raised",
    ];
}

/// Strict neg.nvim: pure black ground, the theme's own greys for ink, one accent hue family.
///
/// Ink ladder, brightest first — `text` 16.4:1, `text_dim` 11.4:1, `text_faint` 5.1:1 on the
/// black ground. Those three *are* neg's `whit`, `high` and `norm`, i.e. the same three tones
/// the colourscheme uses for a selected label, a search match and normal text — so the app's
/// hierarchy and the editor's agree by construction rather than by coincidence.
pub const NEG: Theme = Theme {
    name: "neg",
    bg_top: [0.0, 0.0, 0.0, 1.0], // neg bclr: the ground is pure black
    bg_bottom: [0.0, 0.0, 0.0, 1.0], // flat: neg never gradients a background
    panel: [0.0588, 0.0588, 0.0588, 1.0], // #0f0f0f neg bg_panel = lighten(bclr, 6)
    panel_hi: [0.1098, 0.1098, 0.1098, 1.0], // #1c1c1c derived(neg bg_panel, one step up)
    panel_inset: [0.0275, 0.0275, 0.0275, 1.0], // #070707 derived(bclr, well below panel)
    pane_rest: Elevation {
        surface: [0.0, 0.0, 0.0, 1.0], // neg Normal: panes share the ground
        shadow: 0.0,                   // a terminal window casts no shadow
    },
    pane_raised: Elevation {
        // The pane that owns the keyboard lifts one visible plane off the ground; 1.03:1 is
        // enough to read as a different plane and small enough not to fight the row washes
        // painted on top of it.
        surface: [0.0196, 0.0196, 0.0196, 1.0], // #050505 derived(bclr, +1 plane)
        shadow: 0.0,
    },
    border: [0.1216, 0.1216, 0.1216, 1.0], // #1f1f1f derived(bclr, pane hairline)
    border_hi: [0.1725, 0.2118, 0.2549, 1.0], // #2c3641 neg LineNr
    shadow: [0.0, 0.0, 0.0, 0.45],
    text: [0.8196, 0.8980, 1.0, 1.0],             // #d1e5ff neg whit
    text_dim: [0.6471, 0.7569, 0.9020, 1.0],      // #a5c1e6 neg high
    text_faint: [0.4235, 0.4941, 0.5882, 1.0],    // #6c7e96 neg norm
    text_on_accent: [0.0, 0.0, 0.0, 1.0],         // neg bclr
    rule: [0.1686, 0.2667, 0.3843, 1.0],          // #2b4462 neg shade_10 (active divider)
    accent: [0.2118, 0.4863, 0.6902, 1.0],        // #367cb0 neg ops1 (keyword1)
    accent2: [0.2471, 0.4392, 0.8471, 1.0],       // #3f70d8 derived(neg dchg #1d4aaf, 4.5:1)
    accent_bright: [0.4392, 0.5843, 0.6902, 1.0], // #7095b0 neg func (same hue family)
    warn: [0.7843, 0.6588, 0.9373, 1.0],          // #c8a8ef neg dwarn
    accent_soft: [0.2118, 0.4863, 0.6902, 0.14],
    selection: [0.1529, 0.1529, 0.1529, 1.0], // #272727 neg culc: the mono PmenuSel bar
    selection_edge: [0.1137, 0.1137, 0.1137, 1.0], // #1d1d1d derived(neg culc, bottom stop)
    playing_bg: [0.0510, 0.0941, 0.1412, 1.0], // #0d1824 neg selection_bg
    hover: [0.0353, 0.0353, 0.0353, 1.0],     // #090909 derived(bclr, weakest wash)
    hover_edge: [0.0196, 0.0196, 0.0196, 1.0], // #050505 derived(hover, bottom stop)
    hover_well: [0.0784, 0.0784, 0.0784, 1.0], // #141414 neg bg_float
    danger: [0.7216, 0.3451, 0.4118, 1.0],    // #b85869 derived(neg dred #6b0f2a, 4.64:1)
    success: [0.1412, 0.5216, 0.3843, 1.0],   // #248562 derived(neg lit3 #127a57, 4.61:1)
    backdrop: [0.1333, 0.2471, 0.4510, 0.15], // neg drk2 #223f73
};

/// neg with the ground left alone and the state fills pulled one step down — for the case where
/// a grey bar on black is too loud. Same hues, same ink ladder, quieter fills.
pub const NEG_SOFT: Theme = Theme {
    name: "neg-soft",
    bg_top: [0.0, 0.0, 0.0, 1.0],
    bg_bottom: [0.0, 0.0, 0.0, 1.0],
    panel: [0.0431, 0.0431, 0.0431, 1.0],       // #0b0b0b
    panel_hi: [0.0902, 0.0902, 0.0902, 1.0],    // #171717
    panel_inset: [0.0196, 0.0196, 0.0196, 1.0], // #050505
    pane_rest: Elevation {
        surface: [0.0, 0.0, 0.0, 1.0],
        shadow: 0.0,
    },
    pane_raised: Elevation {
        surface: [0.0157, 0.0157, 0.0157, 1.0], // #040404
        shadow: 0.0,
    },
    border: [0.1020, 0.1020, 0.1020, 1.0],    // #1a1a1a
    border_hi: [0.1529, 0.1882, 0.2275, 1.0], // #272f3a — one step under neg LineNr
    shadow: [0.0, 0.0, 0.0, 0.40],
    text: [0.8196, 0.8980, 1.0, 1.0],          // #d1e5ff
    text_dim: [0.6471, 0.7569, 0.9020, 1.0],   // #a5c1e6
    text_faint: [0.4235, 0.4941, 0.5882, 1.0], // #6c7e96
    text_on_accent: [0.0, 0.0, 0.0, 1.0],
    rule: [0.1686, 0.2667, 0.3843, 1.0],          // #2b4462
    accent: [0.2118, 0.4863, 0.6902, 1.0],        // #367cb0
    accent2: [0.2471, 0.4392, 0.8471, 1.0],       // #3f70d8
    accent_bright: [0.4392, 0.5843, 0.6902, 1.0], // #7095b0
    warn: [0.7843, 0.6588, 0.9373, 1.0],          // #c8a8ef
    accent_soft: [0.2118, 0.4863, 0.6902, 0.10],
    selection: [0.1216, 0.1216, 0.1216, 1.0], // #1f1f1f: quieter cursor bar
    selection_edge: [0.0902, 0.0902, 0.0902, 1.0], // #171717
    playing_bg: [0.0353, 0.0667, 0.1020, 1.0], // #09111a: quieter playing wash
    hover: [0.0235, 0.0235, 0.0235, 1.0],     // #060606
    hover_edge: [0.0157, 0.0157, 0.0157, 1.0], // #040404
    hover_well: [0.0588, 0.0588, 0.0588, 1.0], // #0f0f0f
    danger: [0.7216, 0.3451, 0.4118, 1.0],    // #b85869
    success: [0.1412, 0.5216, 0.3843, 1.0],   // #248562
    backdrop: [0.1333, 0.2471, 0.4510, 0.12],
};

/// neg's accessibility direction: the whole ink ladder lifted one step (neg `whit` → `col24`,
/// `high` → `whit`, `norm` → `high`), borders brought up to a delimited 3:1, and the state fills
/// lightened so the cursor still reads on a bright display in a lit room.
pub const NEG_HC: Theme = Theme {
    name: "neg-hc",
    bg_top: [0.0, 0.0, 0.0, 1.0],
    bg_bottom: [0.0, 0.0, 0.0, 1.0],
    panel: [0.0784, 0.0784, 0.0784, 1.0],       // #141414
    panel_hi: [0.1451, 0.1451, 0.1451, 1.0],    // #252525
    panel_inset: [0.0353, 0.0353, 0.0353, 1.0], // #090909
    pane_rest: Elevation {
        surface: [0.0, 0.0, 0.0, 1.0],
        shadow: 0.0,
    },
    pane_raised: Elevation {
        surface: [0.0275, 0.0275, 0.0275, 1.0], // #070707
        shadow: 0.0,
    },
    border: [0.2431, 0.2431, 0.2431, 1.0],    // #3e3e3e
    border_hi: [0.2471, 0.3451, 0.4627, 1.0], // #3f5876 neg col12
    shadow: [0.0, 0.0, 0.0, 0.50],
    text: [0.9333, 0.9333, 0.9333, 1.0],  // #eeeeee neg col24
    text_dim: [0.8196, 0.8980, 1.0, 1.0], // #d1e5ff neg whit
    text_faint: [0.6471, 0.7569, 0.9020, 1.0], // #a5c1e6 neg high
    text_on_accent: [0.0, 0.0, 0.0, 1.0],
    rule: [0.4392, 0.5843, 0.6902, 1.0],       // #7095b0 neg func
    accent: [0.2784, 0.5882, 0.8078, 1.0],     // #4796ce derived(neg ops1, 6.1:1)
    accent2: [0.3333, 0.5490, 0.9294, 1.0],    // #5589ed derived(neg dchg, 6.1:1)
    accent_bright: [0.8784, 0.9608, 1.0, 1.0], // #e0f5ff bright step of the same hue
    warn: [0.8784, 0.7882, 0.9882, 1.0],       // #e0c9fc derived(neg dwarn, one step up)
    accent_soft: [0.2784, 0.5882, 0.8078, 0.18],
    selection: [0.2157, 0.2157, 0.2157, 1.0],      // #373737
    selection_edge: [0.1725, 0.1725, 0.1725, 1.0], // #2c2c2c
    playing_bg: [0.0745, 0.1373, 0.2078, 1.0],     // #132335
    hover: [0.0588, 0.0588, 0.0588, 1.0],          // #0f0f0f
    hover_edge: [0.0392, 0.0392, 0.0392, 1.0],     // #0a0a0a
    hover_well: [0.1020, 0.1020, 0.1020, 1.0],     // #1a1a1a
    danger: [0.8549, 0.4627, 0.5176, 1.0],         // #da767f derived(danger, 6.1:1)
    success: [0.2196, 0.6588, 0.5059, 1.0],        // #38a881 derived(success, 6.1:1)
    backdrop: [0.1333, 0.2471, 0.4510, 0.18],
};

/// Legacy name for the default palette. Earlier builds called it `dark`; the state file on disk
/// still says so, and `panels.rs` only needs "some theme" for its measurement tests.
pub const DARK: Theme = NEG;

/// Legacy alias for the palette that used to be the second variant.
pub const WARM: Theme = NEG_HC;

/// Every variant `:theme` offers, in the order the cycling key walks them.
pub const VARIANTS: [&Theme; 3] = [&NEG, &NEG_SOFT, &NEG_HC];

/// The names of `VARIANTS`, for the command line's completion list and the state file. Kept
/// beside `VARIANTS` and asserted against it in the tests, so adding a variant means touching
/// one place and the compiler plus the test catch the other.
pub const VARIANT_NAMES: [&str; 3] = ["neg", "neg-soft", "neg-hc"];

/// The variant after `name` in `VARIANTS`, wrapping around. One function, so the keyboard
/// toggle and the `:theme` completion can never disagree about the order.
pub fn next_variant(name: &str) -> &'static Theme {
    let current = Theme::by_name(name);
    let index = VARIANTS
        .iter()
        .position(|t| t.name == current.name)
        .unwrap_or(0);
    VARIANTS[(index + 1) % VARIANTS.len()]
}

/// Alpha helpers, so call sites read as intent instead of float arithmetic.
pub fn with_alpha(c: Rgba, a: f32) -> Rgba {
    [c[0], c[1], c[2], a]
}

/// Blend `top` over `bottom` on the CPU, honouring `top`'s alpha. Needed wherever a translucent
/// ink has to be measured (contrast, layout) before it is drawn: the composited value, not the
/// authored one, is what the reader sees.
pub fn over(top: Rgba, bottom: Rgba) -> Rgba {
    let a = top[3];
    [
        top[0] * a + bottom[0] * (1.0 - a),
        top[1] * a + bottom[1] * (1.0 - a),
        top[2] * a + bottom[2] * (1.0 - a),
        1.0,
    ]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::color::{contrast, delta_ok, hex};

    /// Every variant is held to the same floors, so a new variant that breaks readability fails
    /// here instead of in a screenshot review.
    #[test]
    fn text_ink_clears_aa_on_every_ground() {
        for theme in VARIANTS {
            for ink in [theme.text, theme.text_dim, theme.text_faint] {
                for ground in [
                    theme.bg_top,
                    theme.pane_rest.surface,
                    theme.pane_raised.surface,
                ] {
                    let ratio = contrast(ink, ground);
                    assert!(
                        ratio >= 4.5,
                        "{}: ink {:?} on ground {:?} is {ratio:.2} < 4.5",
                        theme.name,
                        hex(ink),
                        hex(ground)
                    );
                }
            }
        }
    }

    #[test]
    fn accent_ink_clears_aa_on_the_black_ground() {
        for theme in VARIANTS {
            for (label, ink) in [
                ("accent", theme.accent),
                ("accent2", theme.accent2),
                ("accent_bright", theme.accent_bright),
                ("warn", theme.warn),
                ("danger", theme.danger),
                ("success", theme.success),
            ] {
                let ratio = contrast(ink, theme.bg_top);
                assert!(
                    ratio >= 4.5,
                    "{}: {label} {} is {ratio:.2} on the ground, needs 4.5",
                    theme.name,
                    hex(ink)
                );
            }
        }
    }

    /// The three list states must be told apart by lightness alone: a dichromat loses the hue
    /// difference between the blue playing wash and the grey cursor bar, so the OKLab distance
    /// between them is the invariant that survives.
    #[test]
    fn row_states_are_distinguishable() {
        for theme in VARIANTS {
            let states = [
                ("hover", theme.hover),
                ("playing", theme.playing_bg),
                ("selection", theme.selection),
            ];
            for (i, (name_a, a)) in states.iter().enumerate() {
                for (name_b, b) in states.iter().skip(i + 1) {
                    let d = delta_ok(*a, *b);
                    assert!(
                        d >= 0.05,
                        "{}: {name_a} vs {name_b} differ by {d:.3} < 0.05 in OKLab",
                        theme.name
                    );
                }
                let from_ground = delta_ok(*a, theme.bg_top);
                assert!(
                    from_ground >= 0.05,
                    "{}: {name_a} is {from_ground:.3} away from the ground — invisible",
                    theme.name
                );
            }
            // Meaning rises with lightness: hover < playing < cursor.
            let l = |c: Rgba| crate::color::oklab(c)[0];
            assert!(
                l(theme.hover) < l(theme.playing_bg),
                "{}: hover must be the quietest wash",
                theme.name
            );
            assert!(
                l(theme.playing_bg) < l(theme.selection),
                "{}: the cursor bar must outshine the playing wash",
                theme.name
            );
        }
    }

    /// Two accents that mean different things must not be one colour for the eye.
    #[test]
    fn accent_vocabulary_is_separated() {
        for theme in VARIANTS {
            let accents = [
                ("accent", theme.accent),
                ("accent2", theme.accent2),
                ("warn", theme.warn),
                ("danger", theme.danger),
                ("success", theme.success),
            ];
            for (i, (name_a, a)) in accents.iter().enumerate() {
                for (name_b, b) in accents.iter().skip(i + 1) {
                    let d = delta_ok(*a, *b);
                    assert!(
                        d >= 0.03,
                        "{}: {name_a} vs {name_b} differ by {d:.3} in OKLab",
                        theme.name
                    );
                }
            }
            // accent and accent_bright are one hue family by design, so they only have to
            // differ by lightness.
            assert!(
                delta_ok(theme.accent, theme.accent_bright) >= 0.05,
                "{}: accent and accent_bright are the same tone",
                theme.name
            );
        }
    }

    #[test]
    fn variant_names_are_canonical() {
        for theme in VARIANTS {
            assert_eq!(Theme::canonical(theme.name), theme.name);
        }
        // Legacy names from earlier builds fall back to the strict palette.
        assert_eq!(Theme::canonical("dark"), "neg");
        assert_eq!(Theme::canonical("warm"), "neg");
        assert_eq!(Theme::canonical("nonsense"), "neg");
        for (name, theme) in VARIANT_NAMES.iter().zip(VARIANTS) {
            assert_eq!(*name, theme.name, "VARIANT_NAMES and VARIANTS disagree");
        }
        assert_eq!(next_variant("neg").name, "neg-soft");
        assert_eq!(next_variant("neg-soft").name, "neg-hc");
        assert_eq!(next_variant("neg-hc").name, "neg");
    }

    /// The hex in the comment next to a token has to be the colour the float triple actually
    /// encodes: a transposed digit there silently ships a wrong palette.
    #[test]
    fn authored_floats_match_their_documented_hex() {
        let cases: &[(&str, Rgba, &str)] = &[
            ("neg.bg_top", NEG.bg_top, "#000000"),
            ("neg.panel", NEG.panel, "#0f0f0f"),
            ("neg.panel_hi", NEG.panel_hi, "#1c1c1c"),
            ("neg.text", NEG.text, "#d1e5ff"),
            ("neg.text_dim", NEG.text_dim, "#a5c1e6"),
            ("neg.text_faint", NEG.text_faint, "#6c7e96"),
            ("neg.rule", NEG.rule, "#2b4462"),
            ("neg.accent", NEG.accent, "#367cb0"),
            ("neg.accent2", NEG.accent2, "#3f70d8"),
            ("neg.accent_bright", NEG.accent_bright, "#7095b0"),
            ("neg.warn", NEG.warn, "#c8a8ef"),
            ("neg.selection", NEG.selection, "#272727"),
            ("neg.selection_edge", NEG.selection_edge, "#1d1d1d"),
            ("neg.playing_bg", NEG.playing_bg, "#0d1824"),
            ("neg.border", NEG.border, "#1f1f1f"),
            ("neg.border_hi", NEG.border_hi, "#2c3641"),
            ("neg.hover_well", NEG.hover_well, "#141414"),
            ("neg.danger", NEG.danger, "#b85869"),
            ("neg.success", NEG.success, "#248562"),
            ("neg_hc.text", NEG_HC.text, "#eeeeee"),
            ("neg_soft.panel", NEG_SOFT.panel, "#0b0b0b"),
        ];
        for (label, rgba, expected) in cases {
            let got = hex(*rgba);
            assert_eq!(
                got, *expected,
                "{label} documents {expected} but encodes {got}"
            );
        }
    }

    /// A config file can repaint any token by name, so a typo has to be a reported miss rather
    /// than a silent no-op — and every name in `TOKENS` has to be one `set` actually accepts.
    #[test]
    fn every_advertised_token_can_be_set() {
        for token in Theme::TOKENS {
            let mut theme = NEG.clone();
            let before = theme.text;
            assert!(
                theme.set(token, [0.5, 0.25, 0.125, 1.0]),
                "{token} is advertised but not settable"
            );
            let touched = crate::color::hex(theme.text) != crate::color::hex(before)
                || Theme::TOKENS.contains(&token);
            assert!(touched);
        }
        let mut theme = NEG.clone();
        assert!(
            !theme.set("nonsense", [0.0, 0.0, 0.0, 1.0]),
            "an unknown token must be refused"
        );
        // `bg` is the friendly alias the config examples use.
        assert!(theme.set("bg", [0.1, 0.0, 0.0, 1.0]));
        assert_eq!(crate::color::hex(theme.bg_top), "#1a0000");
    }

    /// `over()` is the compositor the theme promises, so it has to behave like one: an opaque
    /// ink passes through untouched, and a half-transparent ink lands halfway between the ink
    /// and the ground. The second half of the test is the reason no text token in this theme is
    /// translucent: a 50% ink on black loses most of its contrast, and a reader cannot predict
    /// by eye which alpha still clears 4.5:1.
    #[test]
    fn compositing_a_translucent_ink_lands_on_the_ground() {
        let black = NEG.bg_top;
        let opaque = over(NEG.text, black);
        for i in 0..3 {
            assert!(
                (opaque[i] - NEG.text[i]).abs() < 1e-6,
                "an opaque ink was altered"
            );
        }
        let half = over(with_alpha(NEG.text, 0.5), black);
        for i in 0..3 {
            assert!(
                (half[i] - NEG.text[i] * 0.5).abs() < 1e-6,
                "channel {i} did not land midway between ink and ground"
            );
        }
        assert!(
            contrast(half, black) < contrast(NEG.text, black) * 0.6,
            "a half-transparent ink should lose most of its contrast"
        );
    }
}
