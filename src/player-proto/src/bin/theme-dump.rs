//! Dump one theme variant as a flat JSON token map.
//!
//! The audit tool (`tools/theme-audit/theme_audit.py`) needs the palette as data, and the
//! palette must have exactly one source of truth — `src/theme.rs`. So this binary is the only
//! bridge between them: it prints the tokens in the shape the auditor reads, which means the
//! report always describes the colours the app actually paints.
//!
//! ```sh
//! cargo run --release --quiet --bin theme-dump -- neg > /tmp/neg.json
//! python3 tools/theme-audit/theme_audit.py /tmp/neg.json --hues accent,accent2,warn,danger,success
//! ```
//!
//! Translucent tokens are printed as `#rrggbbaa`; the auditor composites them over the `bg`
//! token, so a wash is measured where it actually lands.

use player_proto::color::hex;
use player_proto::theme::{self, Rgba, Theme};

/// `#rrggbb`, or `#rrggbbaa` when the token is translucent.
fn render(c: Rgba) -> String {
    let base = hex(c);
    if c[3] >= 1.0 {
        return base;
    }
    format!(
        "{base}{:02x}",
        (c[3].clamp(0.0, 1.0) * 255.0).round() as u32
    )
}

fn tokens(t: &Theme) -> Vec<(&'static str, String)> {
    vec![
        ("bg", render(t.bg_top)),
        ("bg_bottom", render(t.bg_bottom)),
        ("panel", render(t.panel)),
        ("panel_hi", render(t.panel_hi)),
        ("panel_inset", render(t.panel_inset)),
        ("pane_rest", render(t.pane_rest.surface)),
        ("pane_raised", render(t.pane_raised.surface)),
        ("border", render(t.border)),
        ("border_hi", render(t.border_hi)),
        ("text", render(t.text)),
        ("text_dim", render(t.text_dim)),
        ("text_faint", render(t.text_faint)),
        ("text_on_accent", render(t.text_on_accent)),
        ("rule", render(t.rule)),
        ("accent", render(t.accent)),
        ("accent2", render(t.accent2)),
        ("accent_bright", render(t.accent_bright)),
        ("accent_soft", render(t.accent_soft)),
        ("warn", render(t.warn)),
        ("danger", render(t.danger)),
        ("success", render(t.success)),
        ("selection", render(t.selection)),
        ("selection_edge", render(t.selection_edge)),
        ("playing_bg", render(t.playing_bg)),
        ("hover", render(t.hover)),
        ("hover_edge", render(t.hover_edge)),
        ("hover_well", render(t.hover_well)),
        ("backdrop", render(t.backdrop)),
    ]
}

fn main() {
    let name = std::env::args()
        .nth(1)
        .unwrap_or_else(|| theme::NEG.name.to_string());
    let theme = theme::Theme::by_name(&name);
    let body: Vec<String> = tokens(theme)
        .into_iter()
        .map(|(key, value)| format!("\"{key}\":\"{value}\""))
        .collect();
    println!("{{{}}}", body.join(","));
}
