//! Design tokens: colour, type and geometry.
//!
//! Everything the UI draws reads from a `Theme`, so a variant is a data change, not a code
//! change. Colours are linear-ish 0..1 float triples for direct upload to the shader; the hex
//! values in the comments are the sRGB source of truth.

pub type Rgba = [f32; 4];

/// One step on the z axis: the surface a pane paints and the alpha of the drop shadow it casts.
///
/// The two travel together on purpose. A lighter surface over an unchanged shadow reads as a
/// paint mistake, and a deeper shadow under an unchanged surface only muddies the edge, so
/// elevation is one token of two fields instead of two free-floating numbers. Two levels cover
/// this layout: the panes at rest and the single pane that owns the keyboard.
#[derive(Clone, Copy)]
pub struct Elevation {
    pub surface: Rgba,
    /// Alpha of the black drop shadow the pane throws on the background.
    pub shadow: f32,
}

/// Which face to shape with. The UI keeps two families: Inter for text, FiraCode Nerd Font
/// Mono for numerals, times and the transport/symbol glyphs.
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

/// Type scale (px). A ~1.2 modular scale anchored at 13 px for list rows.
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
    display: 20.0,
    title: 18.0,
    heading: 14.0,
    body: 13.0,
    label: 11.5,
    caption: 11.0,
    micro: 11.0,
};

/// Spacing and shape. Multiples of 2 px so half-pixel offsets disappear at 1x scaling.
pub struct Geometry {
    pub pad: f32,
    pub gap: f32,
    pub row_h: f32,
    pub row_h_compact: f32,
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
    pad: 20.0,
    gap: 12.0,
    pane_gap: 16.0,
    /// Two-line rows (queue, search): 14/18 title + 12/16 secondary + breathing room.
    row_h: 40.0,
    /// One-line rows (library).
    row_h_compact: 36.0,
    radius_sm: 3.0,
    radius_md: 8.0,
    radius_lg: 14.0,
    radius_pill: 12.0,
    radius_art: 18.0,
    line: 1.0,
    row_inset: 10.0,
    row_gap: 4.0,
    rail_w: 3.0,
    gutter: 34.0,
    stack: 16.0,
    inner: 8.0,
};

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
    /// Elevation of the pane that does: a lighter surface and a deeper shadow, so focus is
    /// legible from the pane body itself instead of only from an accent outline.
    pub pane_raised: Elevation,
    pub border: Rgba,
    /// 1 px top highlight; the only thing that separates panels on this palette
    /// (black shadows reach 1.08-1.12:1 against the background, i.e. nothing).
    pub border_hi: Rgba,
    pub shadow: Rgba,
    // text
    pub text: Rgba,
    pub text_dim: Rgba,
    pub text_faint: Rgba,
    pub text_on_accent: Rgba,
    // accents
    pub accent: Rgba,
    pub accent2: Rgba,
    pub accent_bright: Rgba,
    pub warn: Rgba,
    pub accent_soft: Rgba,
    /// Top of the selected-row wash; `selection_edge` is the bottom, so the cursor reads as a
    /// lit surface instead of a flat overlay.
    pub selection: Rgba,
    pub selection_edge: Rgba,
    /// Flat wash behind the playing row, always weaker than the cursor.
    pub playing_bg: Rgba,
    /// Wash under the pointer, and the bottom stop of the same wash so a hovered row is lit
    /// from the top like a selected one. Weaker than both washes above: hover answers "this is
    /// pressable", the playing wash answers "this is playing" and `selection` answers "this is
    /// where the keyboard is", so a mouse resting on a row can never outshine the cursor.
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

/// Cool blue-on-charcoal, the default. Contrast of every text/background pair was computed
/// with the WCAG 2.1 formula (see FONTS-AND-THEME.md section 6.3); text_faint alone is 6.3:1 on
/// `panel` and 5.9:1 on the raised pane, so 11 px labels pass AA on either surface.
pub const DARK: Theme = Theme {
    name: "dark",
    bg_top: [0.0588, 0.0784, 0.1059, 1.0],      // #0F141B
    bg_bottom: [0.0314, 0.0392, 0.0549, 1.0],   // #080A0E
    panel: [0.0784, 0.0980, 0.1333, 1.0],       // #141922
    panel_hi: [0.1059, 0.1333, 0.1765, 1.0],    // #1B222D
    panel_inset: [0.0510, 0.0667, 0.0902, 1.0], // #0D1117
    pane_rest: Elevation {
        surface: [0.0784, 0.0980, 0.1333, 1.0], // #141922
        shadow: 0.35,
    },
    pane_raised: Elevation {
        // One step below `panel_hi`, so chips and wells painted on a raised pane still read.
        surface: [0.0980, 0.1255, 0.1725, 1.0], // #19202C
        shadow: 0.55,
    },
    border: [1.0, 1.0, 1.0, 0.07],
    border_hi: [1.0, 1.0, 1.0, 0.14],
    shadow: [0.0, 0.0, 0.0, 0.45],
    text: [0.9098, 0.9294, 0.9608, 1.0],           // #E8EDF5
    text_dim: [0.7020, 0.7451, 0.8078, 1.0],       // #B3BECE
    text_faint: [0.5569, 0.6118, 0.6863, 1.0],     // #8E9CAF
    text_on_accent: [0.0314, 0.0392, 0.0549, 1.0], // #080A0E
    accent: [0.3725, 0.8196, 1.0, 1.0],            // #5FD1FF
    accent2: [0.5490, 0.6078, 1.0, 1.0],           // #8C9BFF
    accent_bright: [0.5608, 0.8784, 1.0, 1.0],     // #8FE0FF
    warn: [0.9647, 0.7765, 0.4039, 1.0],           // #F6C667
    accent_soft: [0.3725, 0.8196, 1.0, 0.16],
    selection: [0.3725, 0.8196, 1.0, 0.20],
    selection_edge: [0.5490, 0.6078, 1.0, 0.07],
    playing_bg: [0.3725, 0.8196, 1.0, 0.08],
    hover: [0.3725, 0.8196, 1.0, 0.055],
    hover_edge: [0.5490, 0.6078, 1.0, 0.020],
    hover_well: [0.3725, 0.8196, 1.0, 0.030],
    danger: [1.0, 0.4824, 0.4824, 1.0],     // #FF7B7B
    success: [0.3294, 0.8510, 0.5490, 1.0], // #54D98C
    backdrop: [0.25, 0.29, 0.40, 0.15],
};

/// Warm amber-on-ink alternative; same token names so the UI code is unaware.
pub const WARM: Theme = Theme {
    name: "warm",
    bg_top: [0.071, 0.055, 0.043, 1.0], // #12100b-ish
    bg_bottom: [0.039, 0.031, 0.024, 1.0],
    panel: [0.086, 0.071, 0.055, 1.0],
    panel_hi: [0.118, 0.098, 0.075, 1.0],
    panel_inset: [0.055, 0.043, 0.031, 1.0],
    pane_rest: Elevation {
        surface: [0.086, 0.071, 0.055, 1.0],
        shadow: 0.40,
    },
    pane_raised: Elevation {
        surface: [0.110, 0.090, 0.070, 1.0],
        shadow: 0.62,
    },
    border: [1.0, 0.94, 0.86, 0.07],
    border_hi: [1.0, 0.94, 0.86, 0.14],
    shadow: [0.0, 0.0, 0.0, 0.55],
    text: [0.965, 0.941, 0.902, 1.0], // #f6f0e6
    text_dim: [0.706, 0.647, 0.573, 1.0],
    text_faint: [0.451, 0.404, 0.349, 1.0],
    text_on_accent: [0.10, 0.06, 0.02, 1.0],
    accent: [1.0, 0.722, 0.361, 1.0],  // #ffb85c
    accent2: [1.0, 0.541, 0.404, 1.0], // #ff8a67
    accent_bright: [1.0, 0.812, 0.529, 1.0],
    warn: [0.9647, 0.7765, 0.4039, 1.0],
    accent_soft: [1.0, 0.722, 0.361, 0.16],
    selection: [1.0, 0.722, 0.361, 0.22],
    selection_edge: [1.0, 0.541, 0.404, 0.07],
    playing_bg: [1.0, 0.722, 0.361, 0.10],
    hover: [1.0, 0.722, 0.361, 0.06],
    hover_edge: [1.0, 0.541, 0.404, 0.020],
    hover_well: [1.0, 0.722, 0.361, 0.030],
    danger: [0.937, 0.400, 0.400, 1.0],
    success: [0.353, 0.890, 0.596, 1.0],
    backdrop: [0.40, 0.29, 0.20, 0.15],
};

impl Theme {
    pub fn by_name(name: &str) -> &'static Theme {
        match name {
            "warm" => &WARM,
            _ => &DARK,
        }
    }
}

/// Alpha helpers, so call sites read as intent instead of float arithmetic.
pub fn with_alpha(c: Rgba, a: f32) -> Rgba {
    [c[0], c[1], c[2], a]
}
