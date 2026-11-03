// Mechanics generator.
//
// The content director invents *screens*; this module invents *rules*. A
// mechanic is a pair of executable effects drawn from a small DSL, scored by
// the same critic pattern: novelty against what the run already used, synergy
// of the pair, balance of the magnitudes and variety of categories. Every
// effect listed here is implemented by the game, so a generated mechanic is
// playable, not a label.
//
// The lab (`--mechanics N`) samples millions of candidates, picks winners and
// reports which combinations the metric likes.

use crate::math::hash01;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Effect {
    DoubleJump,
    Glide,
    TripleShot,
    Shockwave,
    Magnet,
    Bounce,
}

impl Effect {
    pub fn all() -> [Effect; 6] {
        [
            Effect::DoubleJump,
            Effect::Glide,
            Effect::TripleShot,
            Effect::Shockwave,
            Effect::Magnet,
            Effect::Bounce,
        ]
    }

    pub fn index(self) -> usize {
        match self {
            Effect::DoubleJump => 0,
            Effect::Glide => 1,
            Effect::TripleShot => 2,
            Effect::Shockwave => 3,
            Effect::Magnet => 4,
            Effect::Bounce => 5,
        }
    }

    pub fn code(self) -> &'static str {
        match self {
            Effect::DoubleJump => "double_jump",
            Effect::Glide => "glide",
            Effect::TripleShot => "triple_shot",
            Effect::Shockwave => "shockwave",
            Effect::Magnet => "magnet",
            Effect::Bounce => "bounce",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Effect::DoubleJump => "ДВОЙНОЙ ПРЫЖОК",
            Effect::Glide => "ПЛАНИРОВАНИЕ",
            Effect::TripleShot => "ТРОЙНОЙ ШАР",
            Effect::Shockwave => "УДАРНАЯ ВОЛНА",
            Effect::Magnet => "МАГНИТ",
            Effect::Bounce => "БАТУТ",
        }
    }

    pub fn category(self) -> usize {
        match self {
            Effect::DoubleJump | Effect::Glide | Effect::Bounce => 0, // movement
            Effect::TripleShot | Effect::Shockwave => 1,              // offence
            Effect::Magnet => 2,                                      // utility
        }
    }
}

/// Pair synergy. The generator uses it to prefer combinations that create a
/// situation neither effect has alone (glide + double jump, stomp + wave).
fn synergy(a: Effect, b: Effect) -> f32 {
    use Effect::*;
    let pair = |x, y| (a == x && b == y) || (a == y && b == x);
    if a == b {
        0.0
    } else if pair(DoubleJump, Glide) {
        0.95
    } else if pair(DoubleJump, Bounce) {
        0.8
    } else if pair(Shockwave, TripleShot) {
        0.85
    } else if pair(Shockwave, Bounce) {
        0.9
    } else if pair(Magnet, TripleShot) {
        0.55
    } else if pair(Magnet, Glide) {
        0.6
    } else {
        0.4
    }
}

/// How much a pair distorts the game; high values are "fun but risky".
fn stress(a: Effect, b: Effect) -> f32 {
    use Effect::*;
    let heavy = |e| matches!(e, DoubleJump | Shockwave | Bounce);
    (heavy(a) as u8 as f32 + heavy(b) as u8 as f32) * 0.25
}

#[derive(Clone, Copy, Debug)]
pub struct Mechanic {
    pub primary: Effect,
    pub secondary: Effect,
    pub magnitude: f32,
}

impl Mechanic {
    pub fn label(&self) -> String {
        format!("{} + {}", self.primary.label(), self.secondary.label())
    }

    pub fn has(&self, effect: Effect) -> bool {
        self.primary == effect || self.secondary == effect
    }

    /// Air-jump impulse for the double-jump rule (0 when absent).
    pub fn air_jump(&self) -> f32 {
        if self.has(Effect::DoubleJump) {
            880.0 * self.magnitude
        } else {
            0.0
        }
    }

    pub fn bounce(&self) -> f32 {
        if self.has(Effect::Bounce) {
            700.0 * self.magnitude
        } else {
            0.0
        }
    }

    pub fn glide(&self) -> bool {
        self.has(Effect::Glide)
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Scored {
    pub mechanic: Mechanic,
    pub novelty: f32,
    pub synergy: f32,
    pub balance: f32,
    pub variety: f32,
    pub fun: f32,
}

pub struct Lab {
    history: Vec<[f32; 6]>,
    seed: u32,
}

impl Lab {
    pub fn new(seed: u32) -> Self {
        Self {
            history: Vec::new(),
            seed,
        }
    }

    fn sample(&mut self, attempt: u32) -> Mechanic {
        let mut h = self.seed ^ attempt.wrapping_mul(0x9E37_79B9);
        h = h.wrapping_mul(747_796_405).wrapping_add(2_891_336_453);
        let mut n = |k: u32| {
            h = h.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
            (h >> 16) % k
        };
        let effects = Effect::all();
        let primary = effects[n(6) as usize];
        let mut secondary = effects[n(6) as usize];
        if secondary == primary {
            secondary = effects[((primary.index() + 1 + n(5) as usize) % 6) as usize];
        }
        let magnitude = 0.65 + hash01(h) * 0.7;
        Mechanic {
            primary,
            secondary,
            magnitude,
        }
    }

    fn score(&self, m: &Mechanic) -> Scored {
        // Novelty: how different the effect histogram is from the recent sets.
        let mut sig = [0.0f32; 6];
        sig[m.primary.index()] += 0.5;
        sig[m.secondary.index()] += 0.5;
        let novelty = if self.history.is_empty() {
            1.0
        } else {
            let max_sim = self
                .history
                .iter()
                .map(|h| {
                    let dot: f32 = sig.iter().zip(h).map(|(a, b)| a * b).sum();
                    let na: f32 = sig.iter().map(|a| a * a).sum::<f32>().sqrt();
                    let nb: f32 = h.iter().map(|b| b * b).sum::<f32>().sqrt();
                    if na < 1e-6 || nb < 1e-6 {
                        0.0
                    } else {
                        dot / (na * nb)
                    }
                })
                .fold(0.0f32, f32::max);
            (1.0 - max_sim).clamp(0.0, 1.0)
        };

        let synergy = synergy(m.primary, m.secondary);
        // Balance: extreme magnitudes and two heavy effects are risky.
        let balance =
            (1.0 - (m.magnitude - 1.0).abs() * 0.9 - stress(m.primary, m.secondary) * 0.5)
                .clamp(0.0, 1.0);
        let variety = if m.primary.category() != m.secondary.category() {
            1.0
        } else {
            0.6
        };
        let fun =
            (0.30 * novelty + 0.30 * synergy + 0.22 * balance + 0.18 * variety).clamp(0.0, 1.0);
        Scored {
            mechanic: *m,
            novelty,
            synergy,
            balance,
            variety,
            fun,
        }
    }

    /// Invent one mechanic: sample 8 candidates, keep the best, remember it.
    pub fn next(&mut self, attempt: u32) -> Scored {
        let mut best: Option<Scored> = None;
        for k in 0..8 {
            let m = self.sample(attempt * 8 + k);
            let s = self.score(&m);
            if best.as_ref().map(|b| s.fun > b.fun).unwrap_or(true) {
                best = Some(s);
            }
        }
        let chosen = best.expect("at least one candidate");
        let mut sig = [0.0f32; 4];
        sig[chosen.mechanic.primary.category()] += 0.5;
        sig[chosen.mechanic.secondary.category()] += 0.5;
        // History keeps the effect histogram for novelty.
        let mut h = [0.0f32; 6];
        h[chosen.mechanic.primary.index()] += 0.5;
        h[chosen.mechanic.secondary.index()] += 0.5;
        self.history.push(h);
        if self.history.len() > 8 {
            self.history.remove(0);
        }
        let _ = sig;
        chosen
    }
}

/// One row of the lab report.
#[derive(Clone, Copy)]
pub struct Row {
    pub scored: Scored,
}

pub struct LabReport {
    pub runs: u64,
    pub elapsed: f32,
    pub best: Vec<Scored>,
    pub frequency: [u64; 6],
    pub mean_fun: f64,
    pub mean_novelty: f64,
    pub mean_synergy: f64,
    pub mean_balance: f64,
}

pub fn run_lab(runs: u64, seed: u32) -> LabReport {
    use std::time::Instant;
    let started = Instant::now();
    let mut lab = Lab::new(seed);
    let mut best: Vec<Scored> = Vec::new();
    let mut frequency = [0u64; 6];
    let (mut sf, mut sn, mut ss, mut sb) = (0.0f64, 0.0f64, 0.0f64, 0.0f64);
    for i in 0..runs {
        let s = lab.next(i as u32);
        frequency[s.mechanic.primary.index()] += 1;
        frequency[s.mechanic.secondary.index()] += 1;
        sf += s.fun as f64;
        sn += s.novelty as f64;
        ss += s.synergy as f64;
        sb += s.balance as f64;
        if best.len() < 5 {
            best.push(s);
            best.sort_by(|a, b| b.fun.total_cmp(&a.fun));
        } else if s.fun > best.last().unwrap().fun {
            best[4] = s;
            best.sort_by(|a, b| b.fun.total_cmp(&a.fun));
        }
    }
    let n = runs.max(1) as f64;
    LabReport {
        runs,
        elapsed: started.elapsed().as_secs_f32(),
        best,
        frequency,
        mean_fun: sf / n,
        mean_novelty: sn / n,
        mean_synergy: ss / n,
        mean_balance: sb / n,
    }
}

impl LabReport {
    pub fn report(&self) -> String {
        let mut out = String::new();
        out.push_str(&format!(
            "mechanics lab: {} sets in {:.2}s ({:.0}/s)\n",
            self.runs,
            self.elapsed,
            self.runs as f64 / self.elapsed.max(1e-6) as f64
        ));
        out.push_str(&format!(
            "fun {:.3} | novelty {:.3} synergy {:.3} balance {:.3}\n",
            self.mean_fun, self.mean_novelty, self.mean_synergy, self.mean_balance
        ));
        out.push_str("effects: ");
        for e in Effect::all() {
            out.push_str(&format!(
                "{} {:.2}  ",
                e.code(),
                self.frequency[e.index()] as f64 / (self.runs.max(1) * 2) as f64
            ));
        }
        out.push('\n');
        for s in &self.best {
            out.push_str(&format!(
                "  {:.3}  {} + {}  (m {:.2})\n",
                s.fun,
                s.mechanic.primary.code(),
                s.mechanic.secondary.code(),
                s.mechanic.magnitude
            ));
        }
        out
    }

    pub fn json(&self) -> String {
        let items: Vec<String> = self
            .best
            .iter()
            .map(|s| {
                format!(
                    "{{\"primary\":\"{}\",\"secondary\":\"{}\",\"magnitude\":{:.3},\"fun\":{:.3},\"novelty\":{:.3},\"synergy\":{:.3},\"balance\":{:.3}}}",
                    s.mechanic.primary.code(),
                    s.mechanic.secondary.code(),
                    s.mechanic.magnitude,
                    s.fun,
                    s.novelty,
                    s.synergy,
                    s.balance
                )
            })
            .collect();
        format!(
            "{{\"runs\":{},\"elapsed\":{:.2},\"mean_fun\":{:.4},\"mean_novelty\":{:.4},\"mean_synergy\":{:.4},\"mean_balance\":{:.4},\"best\":[{}]}}",
            self.runs,
            self.elapsed,
            self.mean_fun,
            self.mean_novelty,
            self.mean_synergy,
            self.mean_balance,
            items.join(",")
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lab_is_deterministic() {
        let mut a = Lab::new(77);
        let mut b = Lab::new(77);
        for i in 0..32 {
            let x = a.next(i);
            let y = b.next(i);
            assert_eq!(x.mechanic.primary, y.mechanic.primary);
            assert_eq!(x.mechanic.secondary, y.mechanic.secondary);
            assert!((x.mechanic.magnitude - y.mechanic.magnitude).abs() < 1e-6);
        }
    }

    #[test]
    fn generated_mechanics_are_playable_pairs() {
        let mut lab = Lab::new(5);
        for i in 0..500 {
            let s = lab.next(i);
            assert_ne!(s.mechanic.primary, s.mechanic.secondary);
            assert!((0.65..=1.35).contains(&s.mechanic.magnitude));
            assert!((0.0..=1.0).contains(&s.fun));
            assert!((0.0..=1.0).contains(&s.synergy));
        }
    }

    #[test]
    fn double_jump_impulse_tracks_magnitude() {
        let m = Mechanic {
            primary: Effect::DoubleJump,
            secondary: Effect::Glide,
            magnitude: 1.0,
        };
        assert!(m.air_jump() > 800.0);
        assert!(m.glide());
    }
}
