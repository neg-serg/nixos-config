//! Skins: palette + wallpaper + surface treatment, in one switchable unit.
//!
//! The palette (`theme.rs`) answers "what colour is a caption"; a skin answers the bigger
//! question "what does this app look like" — whether panes are opaque black slabs or frosted
//! glass, whether the frame sits on a still ground or on a moving one, and how loud the
//! background is allowed to be. Keeping them apart means a skin is a handful of numbers, not a
//! branch in every draw function: the draw code asks the skin, and the skin is data.
//!
//! The set is deliberately short and each entry is a *look*, not a toggle soup:
//!
//! - `neg` — the strict one. Flat black ground, opaque panes, no effects, nothing animated.
//! - `neg-glass` — the same palette, but the cover is stretched behind the frame and panes are
//!   frosted slabs that refract it.
//! - `neg-vinyl` — the cover fills the frame behind opaque panes: a record sleeve on a shelf.
//! - `neg-tunnel` — a raymarched tunnel recedes behind frosted panes.
//! - `neg-plasma` — slow interference fields, the Windows-Media-Player kind of loud.
//! - `neg-spectrum` — a mirrored spectrum across the bottom, Winamp-style.
//!
//! Every one of them keeps the *ink* rules of the palette: text is only ever drawn in a theme
//! token, so a loud wallpaper can never make a title unreadable — the panes carry their own
//! opacity for that reason.

use crate::config::SkinSpec;
use crate::theme::{Rgba, Theme, NEG, NEG_HC, NEG_SOFT};

/// What sits behind the frame's panes.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Backdrop {
    /// Nothing: the ground is the palette's own background colour.
    None,
    /// The album cover, stretched across the frame and dimmed to wallpaper strength.
    Art,
    /// A procedural full-screen effect; the value is the mode in `shaders/bg.frag`
    /// (1 tunnel, 2 plasma, 3 spectrum).
    Effect(u8),
}

/// A frosted-glass surface.
#[derive(Clone, Copy)]
pub struct Glass {
    /// Colour of the slab. Its alpha is how much of the backdrop survives the frost: 0.35 is
    /// nearly clear, 0.75 is almost a pane of its own.
    pub tint: Rgba,
    /// How far the edge bends the backdrop, in *screen units* (fractions of the frame width):
    /// `shaders/glass.frag` expects 0..0.03 and clamps above that. 0 is a plain frosted blur,
    /// 0.004-0.01 reads as a bevel of liquid glass, and past ~0.02 the edge turns into a bubble.
    pub refraction: f32,
}

pub struct Skin {
    pub name: &'static str,
    /// The palette this skin paints with.
    pub theme: &'static Theme,
    /// One line for the command line's completion list.
    pub note: &'static str,
    pub backdrop: Backdrop,
    /// Background intensity, 0..1. Scaled again by the shader, and clamped there so a
    /// background can never outshine the ink drawn over it.
    pub backdrop_strength: f32,
    /// `Some` when panes are frosted slabs instead of opaque fills.
    pub glass: Option<Glass>,
}

/// The strict skin: exactly what `neg.nvim` draws, with nothing behind it.
pub const NEG_SKIN: Skin = Skin {
    name: "neg",
    theme: &NEG,
    note: "плоский neg: чёрный фон, непрозрачные панели",
    backdrop: Backdrop::None,
    backdrop_strength: 0.0,
    glass: None,
};

/// Frosted panes over the cover.
pub const GLASS: Skin = Skin {
    name: "neg-glass",
    theme: &NEG_HC,
    note: "матовое стекло над обложкой",
    backdrop: Backdrop::Art,
    backdrop_strength: 0.70,
    glass: Some(Glass {
        tint: [0.0431, 0.0510, 0.0627, 0.80], // #0b0d10 at 80%: a slab, not a veil
        refraction: 0.006,
    }),
};

/// The cover fills the frame behind opaque panes.
pub const VINYL: Skin = Skin {
    name: "neg-vinyl",
    theme: &NEG_HC,
    note: "обложка на весь кадр, панели непрозрачные",
    backdrop: Backdrop::Art,
    backdrop_strength: 0.95,
    glass: None,
};

/// A raymarched tunnel behind frosted panes.
pub const TUNNEL: Skin = Skin {
    name: "neg-tunnel",
    theme: &NEG_HC,
    note: "рейкастинг-туннель за стеклом",
    backdrop: Backdrop::Effect(1),
    backdrop_strength: 0.80,
    glass: Some(Glass {
        tint: [0.0314, 0.0431, 0.0471, 0.80], // #080b0c at 80%
        refraction: 0.008,
    }),
};

/// Slow interference fields.
pub const PLASMA: Skin = Skin {
    name: "neg-plasma",
    theme: &NEG_HC,
    note: "плазма, как в Windows Media Player",
    backdrop: Backdrop::Effect(2),
    backdrop_strength: 0.75,
    glass: Some(Glass {
        tint: [0.0431, 0.0392, 0.0627, 0.80], // #0b0a10 at 80%
        refraction: 0.009,
    }),
};

/// A mirrored spectrum along the bottom edge.
pub const SPECTRUM: Skin = Skin {
    name: "neg-spectrum",
    theme: &NEG_HC,
    note: "спектр-столбики во всю ширину",
    backdrop: Backdrop::Effect(3),
    backdrop_strength: 0.85,
    glass: Some(Glass {
        tint: [0.0353, 0.0431, 0.0627, 0.82], // #090b10 at 82%
        refraction: 0.005,
    }),
};

/// The quiet variant of the strict skin, kept next to it so the palette's soft palette is
/// reachable from the same key.
pub const SOFT: Skin = Skin {
    name: "neg-soft",
    theme: &NEG_SOFT,
    note: "тихий neg: те же краски, слабее подложки",
    backdrop: Backdrop::None,
    backdrop_strength: 0.0,
    glass: None,
};

/// Every skin, in the order the cycling key walks them: the strict look first, the loud ones
/// last, so a stray press is never a jump into the psychedelic end.
pub const SKINS: [&Skin; 7] = [
    &NEG_SKIN, &SOFT, &GLASS, &VINYL, &TUNNEL, &PLASMA, &SPECTRUM,
];

/// The names of `SKINS`, for completion and for the state file.
pub const SKIN_NAMES: [&str; 7] = [
    "neg",
    "neg-soft",
    "neg-glass",
    "neg-vinyl",
    "neg-tunnel",
    "neg-plasma",
    "neg-spectrum",
];

impl Skin {
    /// Resolve a name. Anything unknown — a typo, or a palette name from an older build —
    /// falls back to the strict skin, which is the only one that cannot surprise the user.
    pub fn by_name(name: &str) -> &'static Skin {
        SKINS
            .iter()
            .copied()
            .find(|s| s.name == name)
            .unwrap_or(&NEG_SKIN)
    }

    /// Canonical name for whatever was typed, so the UI shows `neg` instead of echoing a typo.
    pub fn canonical(name: &str) -> &'static str {
        Skin::by_name(name).name
    }

    /// The skin after `name`, wrapping around.
    pub fn next(name: &str) -> &'static Skin {
        let current = Skin::by_name(name);
        let index = SKINS
            .iter()
            .position(|s| s.name == current.name)
            .unwrap_or(0);
        SKINS[(index + 1) % SKINS.len()]
    }

    /// True when the frame has anything behind the panes, i.e. when the backdrop layer has to
    /// be rendered at all.
    pub fn has_backdrop(&self) -> bool {
        !matches!(self.backdrop, Backdrop::None) && self.backdrop_strength > 0.0
    }

    /// True when panes are painted as frosted slabs.
    pub fn frosted(&self) -> bool {
        self.glass.is_some()
    }

    /// The brightest surface this skin can put under a caption.
    ///
    /// A frosted slab is translucent, so the backdrop reaches the text through it, and the worst
    /// case is the brightest pixel the backdrop can produce: the accent tint at full strength,
    /// dimmed by the sheet the skin draws over the wallpaper, then mixed with the glass tint.
    /// That composited colour — not the tint, not the palette — is what a caption actually sits
    /// on, and it is what the readability test measures. A flat skin returns its own pane
    /// surface, which is the same question with a trivial answer.
    pub fn worst_surface_under_text(&self) -> Rgba {
        let theme = self.theme;
        // Opaque panes cover the wallpaper completely, so the caption sits on the pane surface
        // and the backdrop is irrelevant to readability — it only has to not distract.
        if !self.has_backdrop() || self.glass.is_none() {
            return theme.pane_rest.surface;
        }
        let brightest = match self.backdrop {
            // A cover is photographic: its bright pixels are near white, so the worst case is the
            // brightest thing the palette ever paints there — the emphasis ink.
            Backdrop::Art => theme.text_dim,
            // A procedural background is capped by the shader at the accent channel.
            Backdrop::Effect(_) => theme.accent_bright,
            Backdrop::None => theme.bg_top,
        };
        // The wallpaper as it arrives at the slab: the effect at its strength, over the ground.
        let sheet = crate::theme::over(
            crate::theme::with_alpha(theme.bg_top, 1.0 - self.backdrop_strength),
            brightest,
        );
        match self.glass {
            Some(glass) => crate::theme::over(glass.tint, sheet),
            None => sheet,
        }
    }
}

/// A skin after resolution: the built-ins and the ones from the user's `skins.toml` end up in
/// the same type, because at that point there is no difference between them — the config file is
/// only a way to author what the built-ins already are.
#[derive(Clone)]
pub struct Resolved {
    pub name: String,
    pub note: String,
    pub theme: Theme,
    pub backdrop: Backdrop,
    pub backdrop_strength: f32,
    pub glass: Option<Glass>,
}

impl Resolved {
    pub fn from_builtin(skin: &'static Skin) -> Self {
        Self {
            name: skin.name.to_string(),
            note: skin.note.to_string(),
            theme: skin.theme.clone(),
            backdrop: skin.backdrop,
            backdrop_strength: skin.backdrop_strength,
            glass: skin.glass,
        }
    }

    /// Resolve one `[[skin]]` block. `None` (with a problem pushed) when the block cannot be
    /// honoured — a skin that silently falls back to the palette would look like the config was
    /// ignored, which is exactly the confusion this file exists to avoid.
    pub fn from_spec(spec: &SkinSpec, problems: &mut Vec<String>) -> Option<Self> {
        if spec.name.trim().is_empty() {
            problems.push("a [[skin]] section has no name".to_string());
            return None;
        }
        let theme = match spec.theme.as_deref() {
            None => NEG.clone(),
            Some(name) => {
                let theme = crate::theme::Theme::by_name(name).clone();
                if theme.name != name {
                    problems.push(format!(
                        "skin '{}': unknown theme '{name}', using '{}'",
                        spec.name, theme.name
                    ));
                }
                theme
            }
        };
        let backdrop = match spec.backdrop.as_deref() {
            None | Some("none") => Backdrop::None,
            Some("art") => Backdrop::Art,
            Some("tunnel") => Backdrop::Effect(1),
            Some("plasma") => Backdrop::Effect(2),
            Some("spectrum") => Backdrop::Effect(3),
            Some(other) => {
                problems.push(format!(
                    "skin '{}': unknown backdrop '{other}' (none, art, tunnel, plasma, spectrum)",
                    spec.name
                ));
                Backdrop::None
            }
        };
        let strength = spec.strength.unwrap_or(0.7);
        let glass = match (spec.glass, spec.glass_tint.as_deref()) {
            (Some(false), _) => None,
            _ => {
                let tint = spec
                    .glass_tint
                    .as_deref()
                    .and_then(crate::color::parse_hex)
                    .map(|mut c| {
                        c[3] = spec.glass_alpha.unwrap_or(0.8);
                        c
                    })
                    .unwrap_or([0.0431, 0.0471, 0.0627, spec.glass_alpha.unwrap_or(0.8)]);
                if spec.glass.is_some() || spec.glass_tint.is_some() {
                    Some(Glass {
                        tint,
                        refraction: spec.refraction.unwrap_or(0.006),
                    })
                } else {
                    // No glass keys at all: inherit the look of the theme's own skin.
                    Skin::by_name(theme.name).glass
                }
            }
        };
        // Palette overrides last: they are the most specific statement the user can make, so
        // they win over everything the base theme implies. An unknown token is reported rather
        // than dropped, because a silently ignored colour is indistinguishable from a bug.
        let mut theme = theme;
        for (token, value) in &spec.colors {
            let Some(color) = crate::color::parse_hex(value) else {
                problems.push(format!(
                    "skin '{}': color.{token} = {value} is not a hex colour",
                    spec.name
                ));
                continue;
            };
            if !theme.set(token, color) {
                problems.push(format!(
                    "skin '{}': unknown colour token '{token}' (known: {})",
                    spec.name,
                    crate::theme::Theme::TOKENS.join(", ")
                ));
            }
        }
        Some(Self {
            name: spec.name.trim().to_string(),
            note: format!("своя тема: {} · {:?}", theme.name, backdrop).to_lowercase(),
            theme,
            backdrop,
            backdrop_strength: strength,
            glass,
        })
    }

    pub fn has_backdrop(&self) -> bool {
        !matches!(self.backdrop, Backdrop::None) && self.backdrop_strength > 0.0
    }

    pub fn frosted(&self) -> bool {
        self.glass.is_some()
    }
}

/// The full list a run offers: the built-ins in their documented order, then the user's skins.
/// A user skin that reuses a built-in name replaces it, which is the only sane meaning of
/// "override this look".
pub fn resolve(config: &crate::config::SkinConfig, problems: &mut Vec<String>) -> Vec<Resolved> {
    let mut skins: Vec<Resolved> = SKINS.iter().map(|s| Resolved::from_builtin(s)).collect();
    for spec in &config.skins {
        match Resolved::from_spec(spec, problems) {
            Some(skin) => {
                if let Some(slot) = skins.iter_mut().find(|s| s.name == skin.name) {
                    *slot = skin;
                } else {
                    skins.push(skin);
                }
            }
            None => {}
        }
    }
    skins
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_are_canonical_and_unique() {
        for (name, skin) in SKIN_NAMES.iter().zip(SKINS) {
            assert_eq!(*name, skin.name, "SKIN_NAMES and SKINS disagree");
            assert_eq!(Skin::canonical(name), *name);
        }
        assert_eq!(Skin::canonical("dark"), "neg");
        assert_eq!(Skin::canonical("nonsense"), "neg");
        assert_eq!(Skin::by_name("neg-tunnel").name, "neg-tunnel");
    }

    #[test]
    fn cycling_walks_every_skin_and_returns_home() {
        let mut name = SKIN_NAMES[0];
        for _ in 0..SKINS.len() {
            name = Skin::next(name).name;
        }
        assert_eq!(
            name, "neg",
            "one full cycle must come back to the first skin"
        );
    }

    /// A frosted skin has to have something to frost, and a skin that frosts must keep its
    /// tint translucent — an opaque "glass" is just a pane with extra cost.
    #[test]
    fn glass_skins_are_consistent() {
        for skin in SKINS {
            if let Some(glass) = skin.glass {
                assert!(
                    glass.tint[3] > 0.2 && glass.tint[3] < 0.9,
                    "{}: glass alpha {} is not a translucent slab",
                    skin.name,
                    glass.tint[3]
                );
                assert!(
                    glass.refraction >= 0.0 && glass.refraction <= 0.03,
                    "{}: refraction {} outside the shader's 0..0.03 screen-unit range",
                    skin.name,
                    glass.refraction
                );
            }
            if skin.has_backdrop() {
                assert!(
                    skin.backdrop_strength > 0.0 && skin.backdrop_strength <= 1.0,
                    "{}: backdrop strength {} out of range",
                    skin.name,
                    skin.backdrop_strength
                );
            }
            if matches!(skin.backdrop, Backdrop::Effect(_)) {
                assert!(
                    skin.has_backdrop(),
                    "{}: an effect backdrop with zero strength draws nothing",
                    skin.name
                );
            }
        }
    }

    /// Readability is a property of the *skin*, not of the palette: a translucent slab lets the
    /// wallpaper through, so the caption sits on whatever the compositor produced, not on the
    /// token the theme names. This is the invariant that keeps a loud skin honest.
    #[test]
    fn captions_stay_readable_on_the_brightest_surface_a_skin_can_paint() {
        for skin in SKINS {
            let ground = skin.worst_surface_under_text();
            for (label, ink) in [
                ("text", skin.theme.text),
                ("text_dim", skin.theme.text_dim),
                ("text_faint", skin.theme.text_faint),
            ] {
                let ratio = crate::color::contrast(ink, ground);
                assert!(
                    ratio >= 4.5,
                    "{}: {label} is {ratio:.2}:1 on the brightest slab it can be painted on, \
                     needs 4.5 (slab {} under {label} {})",
                    skin.name,
                    crate::color::hex(ground),
                    crate::color::hex(ink)
                );
            }
        }
    }

    /// The strict skin is the default for every unknown name, so it must stay effect-free:
    /// that is what makes "falls back to neg" a safe statement.
    #[test]
    fn the_fallback_skin_is_flat() {
        let skin = Skin::by_name("does-not-exist");
        assert_eq!(skin.name, "neg");
        assert!(!skin.has_backdrop());
        assert!(!skin.frosted());
    }
}
