// Day/night cycle.
//
// One full cycle takes four minutes, so a normal run sees at least one dusk
// or dawn transition. The phase tints the painting and scales enemy speed:
// night is hostile, day is calm. Tints are intentionally light — the painting
// must stay readable.

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Phase {
    Dawn,
    Day,
    Dusk,
    Night,
    Predawn,
}

impl Phase {
    pub fn label(self) -> &'static str {
        match self {
            Phase::Dawn => "РАССВЕТ",
            Phase::Day => "ДЕНЬ",
            Phase::Dusk => "ЗАКАТ",
            Phase::Night => "НОЧЬ",
            Phase::Predawn => "ПРЕДРАССВЕТ",
        }
    }
}

pub fn phase(t: f32) -> Phase {
    let t = t.rem_euclid(1.0);
    if t < 0.12 {
        Phase::Dawn
    } else if t < 0.45 {
        Phase::Day
    } else if t < 0.58 {
        Phase::Dusk
    } else if t < 0.85 {
        Phase::Night
    } else {
        Phase::Predawn
    }
}

/// Full-screen tint for the phase.
pub fn tint(t: f32) -> (u8, u8, u8, u8) {
    let t = t.rem_euclid(1.0);
    // Keyframes: (time, r, g, b, a).
    const KEYS: [(f32, u8, u8, u8, u8); 5] = [
        (0.00, 255, 160, 110, 34),
        (0.25, 0, 0, 0, 0),
        (0.50, 40, 20, 10, 0),
        (0.62, 120, 60, 120, 42),
        (0.80, 20, 40, 110, 78),
    ];
    // Wrap to predawn.
    if t >= 0.80 || t < 0.0 {
        // Between night (0.80) and dawn (1.0/0.0).
        let k = if t >= 0.80 { (t - 0.80) / 0.20 } else { 0.0 };
        let a = 78.0 * (1.0 - k);
        return (40, 50, 120, a as u8);
    }
    for pair in KEYS.windows(2) {
        let (t0, r0, g0, b0, a0) = pair[0];
        let (t1, r1, g1, b1, a1) = pair[1];
        if t >= t0 && t <= t1 {
            let k = if (t1 - t0).abs() < 1e-6 {
                0.0
            } else {
                (t - t0) / (t1 - t0)
            };
            let mix = |a: u8, b: u8| (a as f32 + (b as f32 - a as f32) * k) as u8;
            return (mix(r0, r1), mix(g0, g1), mix(b0, b1), mix(a0, a1));
        }
    }
    (0, 0, 0, 0)
}

/// 0 at full day, 1 at the darkest night.
pub fn nightness(t: f32) -> f32 {
    let (_, _, _, a) = tint(t);
    (a as f32 / 90.0).clamp(0.0, 1.0)
}

/// Enemy speed multiplier for the phase.
pub fn enemy_scale(t: f32) -> f32 {
    1.0 + nightness(t) * 0.28
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn phases_cover_the_cycle() {
        assert_eq!(phase(0.0), Phase::Dawn);
        assert_eq!(phase(0.3), Phase::Day);
        assert_eq!(phase(0.5), Phase::Dusk);
        assert_eq!(phase(0.7), Phase::Night);
        assert_eq!(phase(0.9), Phase::Predawn);
        assert_eq!(phase(1.3), Phase::Day);
    }

    #[test]
    fn night_is_darker_and_faster() {
        assert!(nightness(0.7) > 0.5);
        assert!(nightness(0.3) < 0.1);
        assert!(enemy_scale(0.7) > enemy_scale(0.3));
    }

    #[test]
    fn tint_is_bounded() {
        for i in 0..100 {
            let (_, _, _, a) = tint(i as f32 / 100.0);
            assert!(a <= 90);
        }
    }
}
