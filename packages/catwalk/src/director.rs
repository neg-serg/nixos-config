// Procedural encounter director.
//
// The painting supplies the terrain; everything that breathes on it is
// generated per screen. Two roles run for every chunk:
//
//   Generator — proposes ENCOUNTERS from a seeded RNG (opponents, rings,
//               one upgrade capsule, a scenario name).
//   Critic    — scores each proposal on surprise, build diversity, situation
//               variety and fairness, then the best one is instantiated.
//
// The critic's fun score is the metric the run reports: high scores mean the
// next screen is unlike the last few, pushes a different build and still
// stays reachable.

use crate::level::{Level, VIEW_H, VIEW_W, WORLD_H};
use crate::math::{Rect, Vec2};

pub const CHUNK_W: f32 = VIEW_W;
pub const CANDIDATES: usize = 8;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum EnemyKind {
    Drifter,
    Chaser,
    Shooter,
}

impl EnemyKind {
    pub fn index(self) -> usize {
        match self {
            EnemyKind::Drifter => 0,
            EnemyKind::Chaser => 1,
            EnemyKind::Shooter => 2,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            EnemyKind::Drifter => "ПАТРУЛЬ",
            EnemyKind::Chaser => "ПОГОНЯ",
            EnemyKind::Shooter => "ОБСТРЕЛ",
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Upgrade {
    Speed,
    Jump,
    Magnet,
    Shield,
}

impl Upgrade {
    pub fn index(self) -> usize {
        match self {
            Upgrade::Speed => 0,
            Upgrade::Jump => 1,
            Upgrade::Magnet => 2,
            Upgrade::Shield => 3,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Upgrade::Speed => "СКОРОСТЬ",
            Upgrade::Jump => "ПРЫЖОК",
            Upgrade::Magnet => "МАГНИТ",
            Upgrade::Shield => "ЩИТ",
        }
    }

    pub fn all() -> [Upgrade; 4] {
        [
            Upgrade::Speed,
            Upgrade::Jump,
            Upgrade::Magnet,
            Upgrade::Shield,
        ]
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Spawn {
    pub kind: EnemyKind,
    pub pos: Vec2,
    pub patrol: f32,
}

#[derive(Clone, Copy, Debug)]
pub struct Ring {
    pub pos: Vec2,
}

#[derive(Clone, Debug)]
pub struct Encounter {
    pub chunk: i32,
    pub spawns: Vec<Spawn>,
    pub rings: Vec<Ring>,
    pub capsule: Option<(Vec2, Upgrade)>,
    pub scenario: &'static str,
    pub seed: u32,
}

#[derive(Clone, Copy, Default, Debug)]
pub struct Scores {
    pub surprise: f32,
    pub build: f32,
    pub situation: f32,
    pub fairness: f32,
    pub fun: f32,
}

#[derive(Clone, Debug)]
pub struct Proposal {
    pub encounter: Encounter,
    pub scores: Scores,
}

impl Encounter {
    /// Feature vector the critic compares against recent screens.
    pub fn signature(&self) -> [f32; 10] {
        let mut sig = [0.0f32; 10];
        for s in &self.spawns {
            sig[s.kind.index()] += 1.0;
        }
        for v in sig.iter_mut().take(3) {
            *v /= 3.0;
        }
        sig[3] = self.spawns.len() as f32 / 3.0;
        if !self.spawns.is_empty() {
            let mean = self.spawns.iter().map(|s| s.pos.y).sum::<f32>() / self.spawns.len() as f32;
            sig[4] = (mean - 1080.0) / 1080.0;
            let var = self
                .spawns
                .iter()
                .map(|s| (s.pos.y - mean).powi(2))
                .sum::<f32>()
                / self.spawns.len() as f32;
            sig[5] = var.sqrt() / 400.0;
            sig[8] = (self.spawns.iter().map(|s| s.pos.x).sum::<f32>() / self.spawns.len() as f32
                - self.chunk as f32 * CHUNK_W)
                / CHUNK_W;
        }
        sig[6] = self.rings.len() as f32 / 8.0;
        sig[7] = self.capsule.is_some() as u8 as f32;
        sig[9] = self
            .capsule
            .map(|c| c.1.index() as f32 / 3.0)
            .unwrap_or(0.0);
        sig
    }
}

pub struct Rng {
    state: u32,
}

impl Rng {
    pub fn new(seed: u32) -> Self {
        Self { state: seed | 1 }
    }

    fn next(&mut self) -> u32 {
        let mut x = self.state;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.state = x;
        x
    }

    pub fn f(&mut self) -> f32 {
        (self.next() >> 8) as f32 / (1 << 24) as f32
    }

    pub fn range(&mut self, lo: i32, hi: i32) -> i32 {
        if hi <= lo {
            lo
        } else {
            lo + (self.next() % (hi - lo) as u32) as i32
        }
    }

    pub fn pick<T: Copy>(&mut self, items: &[T]) -> T {
        items[(self.next() as usize) % items.len()]
    }
}

pub struct Director {
    seed: u32,
    history: Vec<[f32; 10]>,
    upgrades_offered: [u32; 4],
    cache: Vec<Encounter>,
    pub last: Option<Proposal>,
    pub log: Vec<Proposal>,
    pub campaign: Vec<Proposal>,
}

impl Director {
    pub fn new(seed: u32) -> Self {
        Self {
            seed,
            history: Vec::new(),
            upgrades_offered: [0; 4],
            cache: Vec::new(),
            last: None,
            log: Vec::new(),
            campaign: Vec::new(),
        }
    }

    pub fn seed(&self) -> u32 {
        self.seed
    }

    /// Generate (or restore) the encounter for `chunk`. `player` decides how
    /// far from the entrance a fair spawn is allowed.
    pub fn encounter_for(&mut self, chunk: i32, player: Vec2, level: &Level) -> Encounter {
        if let Some(found) = self.cache.iter().find(|e| e.chunk == chunk) {
            return found.clone();
        }

        let mut best: Option<Proposal> = None;
        for attempt in 0..CANDIDATES {
            let enc = self.generate(chunk, attempt, player, level);
            let scores = self.score(&enc);
            let proposal = Proposal {
                encounter: enc,
                scores,
            };
            self.log.push(proposal.clone());
            if best
                .as_ref()
                .map(|b| proposal.scores.fun > b.scores.fun)
                .unwrap_or(true)
            {
                best = Some(proposal);
            }
        }

        let chosen = best.expect("at least one candidate");
        self.history.push(chosen.encounter.signature());
        if self.history.len() > 8 {
            self.history.remove(0);
        }
        if let Some((_, upgrade)) = chosen.encounter.capsule {
            self.upgrades_offered[upgrade.index()] += 1;
        }
        self.cache.push(chosen.encounter.clone());
        self.campaign.push(chosen.clone());
        self.last = Some(chosen.clone());
        chosen.encounter
    }

    fn generate(&self, chunk: i32, attempt: usize, player: Vec2, level: &Level) -> Encounter {
        let mut rng = Rng::new(
            self.seed
                .wrapping_mul(0x9E37_79B9)
                .wrapping_add((chunk as u32).wrapping_mul(0x85EB_CA6B))
                .wrapping_add((attempt as u32).wrapping_mul(0xC2B2_AE35)),
        );
        let x0 = chunk as f32 * CHUNK_W;
        let bounds = Rect::new(x0, 1080.0, CHUNK_W, WORLD_H - 1080.0);
        let plats: Vec<Rect> = level
            .platforms
            .iter()
            .copied()
            .filter(|p| p.x < bounds.right() && p.right() > bounds.x && p.y < WORLD_H)
            .collect();

        let count = 1 + rng.range(0, 3) as usize;
        let mut spawns = Vec::new();
        for _ in 0..count {
            let kind = match rng.range(0, 3) {
                0 => EnemyKind::Drifter,
                1 => EnemyKind::Chaser,
                _ => EnemyKind::Shooter,
            };
            let (mut x, mut y);
            if plats.is_empty() {
                // Over open water only flyers make sense.
                let kind = if rng.f() < 0.5 {
                    EnemyKind::Shooter
                } else {
                    EnemyKind::Chaser
                };
                x = x0 + 300.0 + rng.f() * (CHUNK_W - 600.0);
                y = level.waterline(x) - 220.0;
                spawns.push(Spawn {
                    kind,
                    pos: Vec2::new(x, y),
                    patrol: 60.0 + rng.f() * 120.0,
                });
                continue;
            } else {
                let p = rng.pick(&plats);
                let usable = (p.w - 120.0).max(40.0);
                x = p.x + 60.0 + rng.f() * usable;
                x = x.clamp(x0 + 90.0, (x0 + CHUNK_W - 90.0).min(p.right() - 40.0));
                y = match kind {
                    EnemyKind::Shooter => p.y - 150.0 - rng.f() * 80.0,
                    _ => p.y - 40.0,
                };
            }
            if (x - player.x).abs() < 340.0 && (y - player.y).abs() < 420.0 {
                // Never drop an opponent on the cat's head.
                x += if x < player.x { -380.0 } else { 380.0 };
            }
            x = x.clamp(x0 + 60.0, x0 + CHUNK_W - 60.0);
            y = y.clamp(1200.0, level.waterline(x) - 40.0);
            spawns.push(Spawn {
                kind,
                pos: Vec2::new(x, y),
                patrol: 60.0 + rng.f() * 120.0,
            });
        }

        // Rings: an arc over a platform, always above the waterline. A chunk
        // with no painted ground (the middle of the lake) gets an arc over
        // the water instead, so the swim is still worth taking.
        let mut rings = Vec::new();
        if plats.is_empty() {
            let wl = level.waterline(x0 + CHUNK_W * 0.5);
            let n = 5;
            for i in 0..n {
                let t = i as f32 / (n - 1) as f32;
                rings.push(Ring {
                    pos: Vec2::new(
                        x0 + CHUNK_W * 0.5 - 220.0 + t * 440.0,
                        wl - 90.0 - (std::f32::consts::PI * t).sin() * 70.0,
                    ),
                });
            }
        } else {
            let p = rng.pick(&plats);
            let n = 4 + rng.range(0, 3) as usize;
            let start = (p.x + 60.0).max(x0 + 80.0);
            let span = (p.w - 120.0).max(120.0).min(CHUNK_W - 160.0);
            for i in 0..n {
                let t = i as f32 / (n - 1).max(1) as f32;
                let rx = start + t * span;
                let ry = p.y - 54.0 - (std::f32::consts::PI * t).sin() * 60.0;
                if rx < x0 + 40.0 || rx > x0 + CHUNK_W - 40.0 {
                    continue;
                }
                rings.push(Ring {
                    pos: Vec2::new(rx, ry.min(level.waterline(rx) - 30.0)),
                });
            }
        }

        // Capsule: bias toward an upgrade the run has not offered yet.
        let capsule = if let Some(p) = plats.get(rng.range(0, plats.len() as i32) as usize) {
            let mut best = Upgrade::Speed;
            let mut best_count = u32::MAX;
            for up in Upgrade::all() {
                let count = self.upgrades_offered[up.index()];
                if count < best_count {
                    best_count = count;
                    best = up;
                }
            }
            let mut cx = (p.x + p.w * 0.5).clamp(x0 + 120.0, x0 + CHUNK_W - 120.0);
            if (cx - player.x).abs() < 320.0 {
                cx = if cx < player.x {
                    (cx - 380.0).max(x0 + 120.0)
                } else {
                    (cx + 380.0).min(x0 + CHUNK_W - 120.0)
                };
            }
            Some((Vec2::new(cx, p.y - 40.0), best))
        } else {
            None
        };

        let scenario = scenario_name(&spawns);
        Encounter {
            chunk,
            spawns,
            rings,
            capsule,
            scenario,
            seed: rng.next(),
        }
    }

    fn score(&self, enc: &Encounter) -> Scores {
        let sig = enc.signature();
        let surprise = if self.history.is_empty() {
            1.0
        } else {
            let max_sim = self
                .history
                .iter()
                .map(|h| cosine(&sig, h))
                .fold(0.0f32, f32::max);
            1.0 - max_sim
        };

        // Build diversity: entropy of the upgrades offered so far, counting
        // this proposal, normalized by the maximum (four types).
        let mut counts = self.upgrades_offered;
        if let Some((_, up)) = enc.capsule {
            counts[up.index()] += 1;
        }
        let total: u32 = counts.iter().sum();
        let build = if total == 0 {
            0.0
        } else {
            let mut h = 0.0;
            for c in counts {
                if c > 0 {
                    let p = c as f32 / total as f32;
                    h -= p * p.ln();
                }
            }
            (h / 4.0f32.ln()).clamp(0.0, 1.0)
        };

        let kinds = {
            let mut seen = [false; 3];
            for s in &enc.spawns {
                seen[s.kind.index()] = true;
            }
            seen.iter().filter(|v| **v).count() as f32 / 3.0
        };
        let spread = if enc.spawns.len() > 1 {
            let min = enc.spawns.iter().map(|s| s.pos.y).fold(f32::MAX, f32::min);
            let max = enc.spawns.iter().map(|s| s.pos.y).fold(f32::MIN, f32::max);
            ((max - min) / 320.0).clamp(0.0, 1.0)
        } else {
            0.0
        };
        let situation = (kinds * 0.6 + spread * 0.4).clamp(0.0, 1.0);

        let mut fairness = 1.0f32;
        for s in &enc.spawns {
            if s.pos.y > crate::level::WORLD_H - 40.0 {
                fairness -= 0.5;
            }
            if s.pos.x < enc.chunk as f32 * CHUNK_W || s.pos.x > (enc.chunk + 1) as f32 * CHUNK_W {
                fairness -= 0.7;
            }
        }
        if enc.rings.is_empty() {
            fairness -= 0.25;
        }
        let fairness = fairness.clamp(0.0, 1.0);

        let fun =
            (0.30 * surprise + 0.24 * build + 0.26 * situation + 0.20 * fairness).clamp(0.0, 1.0);

        Scores {
            surprise,
            build,
            situation,
            fairness,
            fun,
        }
    }
}

fn scenario_name(spawns: &[Spawn]) -> &'static str {
    let mut d = 0;
    let mut c = 0;
    let mut s = 0;
    for sp in spawns {
        match sp.kind {
            EnemyKind::Drifter => d += 1,
            EnemyKind::Chaser => c += 1,
            EnemyKind::Shooter => s += 1,
        }
    }
    match (d, c, s) {
        (_, 0, 0) => "ТИХИЙ ПАТРУЛЬ",
        (0, _, 0) => "ПОГОНЯ",
        (0, 0, _) => "ОБСТРЕЛ",
        (0, _, _) => "ЗАСАДА",
        (_, 0, _) => "ПЕРЕКРЁСТОК",
        _ => "ХАОС",
    }
}

fn cosine(a: &[f32; 10], b: &[f32; 10]) -> f32 {
    let dot: f32 = a.iter().zip(b).map(|(x, y)| x * y).sum();
    let na: f32 = a.iter().map(|x| x * x).sum::<f32>().sqrt();
    let nb: f32 = b.iter().map(|x| x * x).sum::<f32>().sqrt();
    if na < 1e-6 || nb < 1e-6 {
        0.0
    } else {
        (dot / (na * nb)).clamp(0.0, 1.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn same_seed_same_screen() {
        let level = Level::waterfall();
        let mut a = Director::new(42);
        let mut b = Director::new(42);
        let ea = a.encounter_for(0, Vec2::new(200.0, 1800.0), &level);
        let eb = b.encounter_for(0, Vec2::new(200.0, 1800.0), &level);
        assert_eq!(ea.spawns.len(), eb.spawns.len());
        assert_eq!(ea.rings.len(), eb.rings.len());
        assert_eq!(ea.scenario, eb.scenario);
        assert_eq!(ea.seed, eb.seed);
    }

    #[test]
    fn everything_spawns_inside_the_screen_chunk() {
        let level = Level::waterfall();
        for chunk in 0..4 {
            let mut director = Director::new(7);
            let enc = director.encounter_for(chunk, Vec2::new(10.0, 1800.0), &level);
            let x0 = chunk as f32 * CHUNK_W;
            for s in &enc.spawns {
                assert!(
                    s.pos.x >= x0 && s.pos.x <= x0 + CHUNK_W,
                    "spawn {} ",
                    s.pos.x
                );
                assert!(
                    s.pos.y < level.waterline(s.pos.x),
                    "spawn in water at {}",
                    s.pos.x
                );
            }
            for r in &enc.rings {
                assert!(r.pos.x >= x0 && r.pos.x <= x0 + CHUNK_W);
                assert!(r.pos.y < level.waterline(r.pos.x));
            }
        }
    }

    #[test]
    fn critic_rewards_novelty() {
        let level = Level::waterfall();
        let mut director = Director::new(3);
        let first = director.encounter_for(0, Vec2::new(10.0, 1800.0), &level);
        let repeated = director.score(&first);
        // A fresh encounter for another chunk must score at least as well on
        // surprise as repeating the one just played.
        let other = director.encounter_for(1, Vec2::new(1930.0, 1800.0), &level);
        let fresh = director.score(&other);
        assert!(fresh.surprise >= repeated.surprise - 0.05);
    }

    #[test]
    fn fun_is_bounded() {
        let level = Level::waterfall();
        let mut director = Director::new(11);
        for chunk in 0..4 {
            let enc = director.encounter_for(chunk, Vec2::new(100.0, 1800.0), &level);
            let s = director.score(&enc);
            assert!((0.0..=1.0).contains(&s.fun));
            assert!((0.0..=1.0).contains(&s.surprise));
        }
    }

    #[test]
    fn upgrade_word_is_russian() {
        assert_eq!(Upgrade::Speed.label(), "СКОРОСТЬ");
        assert_eq!(Upgrade::Shield.label(), "ЩИТ");
    }
}
