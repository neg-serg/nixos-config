// Particles and the moving-water overlays. The scene itself never moves:
// only translucent streaks and droplets animate, so the painting stays
// pixel-identical when the player stands still.

use crate::math::{hash01, Vec2};

#[derive(Clone, Copy, PartialEq)]
pub enum Kind {
    Dust,
    Splash,
    Spray,
    Sparkle,
    Mote,
}

#[derive(Clone, Copy)]
pub struct Particle {
    pub pos: Vec2,
    pub vel: Vec2,
    pub life: f32,
    pub max_life: f32,
    pub size: f32,
    pub color: (u8, u8, u8),
    pub gravity: f32,
    pub drag: f32,
    #[allow(dead_code)] // kept for per-kind tweaks in draw_particles
    pub kind: Kind,
}

pub struct Particles {
    pub items: Vec<Particle>,
    seed: u32,
}

impl Particles {
    pub fn new() -> Self {
        Self {
            items: Vec::new(),
            seed: 0x51ed_270b,
        }
    }

    fn next(&mut self) -> f32 {
        self.seed = self.seed.wrapping_add(0x9e37_79b9);
        hash01(self.seed)
    }

    fn push(&mut self, particle: Particle) {
        if self.items.len() < 900 {
            self.items.push(particle);
        }
    }

    pub fn update(&mut self, dt: f32) {
        for p in &mut self.items {
            p.life -= dt;
            p.vel.y += p.gravity * dt;
            p.vel *= (1.0 - p.drag * dt).clamp(0.0, 1.0);
            p.pos += p.vel * dt;
        }
        self.items.retain(|p| p.life > 0.0);
    }

    pub fn dust(&mut self, at: Vec2, dir: f32) {
        for _ in 0..4 {
            let spread = self.next() - 0.5;
            let vx = -dir * (30.0 + self.next() * 130.0);
            let vy = -20.0 - self.next() * 70.0;
            let life = 0.28 + self.next() * 0.22;
            let size = 2.0 + self.next() * 3.0;
            self.push(Particle {
                pos: at + Vec2::new(spread * 26.0, -2.0),
                vel: Vec2::new(vx, vy),
                life,
                max_life: 0.5,
                size,
                color: (201, 191, 158),
                gravity: 520.0,
                drag: 2.0,
                kind: Kind::Dust,
            });
        }
    }

    pub fn splash(&mut self, at: Vec2, power: f32) {
        for _ in 0..18 {
            let angle = -1.1 - self.next() * 1.0;
            let speed = (180.0 + self.next() * 520.0) * power;
            let vx = angle.cos() * speed * 0.7;
            let vy = angle.sin() * speed;
            let life = 0.35 + self.next() * 0.5;
            let size = 2.0 + self.next() * 4.0;
            let spread = (self.next() - 0.5) * 60.0;
            self.push(Particle {
                pos: at + Vec2::new(spread, 0.0),
                vel: Vec2::new(vx, vy),
                life,
                max_life: 0.85,
                size,
                color: (222, 240, 242),
                gravity: 1500.0,
                drag: 0.4,
                kind: Kind::Splash,
            });
        }
    }

    pub fn spray(&mut self, at: Vec2, strength: f32) {
        let vx = (self.next() - 0.5) * 90.0;
        let vy = -120.0 - self.next() * 260.0 * strength;
        let life = 0.7 + self.next() * 1.1;
        let size = 1.0 + self.next() * 2.6;
        let spread = (self.next() - 0.5) * 24.0;
        self.push(Particle {
            pos: at + Vec2::new(spread, 0.0),
            vel: Vec2::new(vx, vy),
            life,
            max_life: 1.8,
            size,
            color: (226, 240, 245),
            gravity: 120.0,
            drag: 1.2,
            kind: Kind::Spray,
        });
    }

    pub fn sparkle(&mut self, at: Vec2) {
        for _ in 0..12 {
            let angle = self.next() * std::f32::consts::TAU;
            let speed = 60.0 + self.next() * 160.0;
            let vx = angle.cos() * speed;
            let vy = angle.sin() * speed;
            let life = 0.3 + self.next() * 0.4;
            let size = 2.0 + self.next() * 3.0;
            self.push(Particle {
                pos: at,
                vel: Vec2::new(vx, vy),
                life,
                max_life: 0.7,
                size,
                color: (248, 236, 190),
                gravity: -60.0,
                drag: 2.4,
                kind: Kind::Sparkle,
            });
        }
    }

    /// A single slow golden glint, used to mark the goal from a distance.
    pub fn glint(&mut self, at: Vec2) {
        let vx = (self.next() - 0.5) * 40.0;
        let vy = -30.0 - self.next() * 60.0;
        let life = 0.8 + self.next() * 0.8;
        let size = 2.0 + self.next() * 3.0;
        self.push(Particle {
            pos: at,
            vel: Vec2::new(vx, vy),
            life,
            max_life: 1.6,
            size,
            color: (250, 226, 160),
            gravity: -10.0,
            drag: 0.6,
            kind: Kind::Sparkle,
        });
    }

    pub fn mote(&mut self, at: Vec2) {
        let vx = 8.0 + self.next() * 18.0;
        let vy = -6.0 - self.next() * 10.0;
        let life = 3.0 + self.next() * 4.0;
        let size = 1.0 + self.next() * 1.6;
        self.push(Particle {
            pos: at,
            vel: Vec2::new(vx, vy),
            life,
            max_life: 7.0,
            size,
            color: (238, 232, 196),
            gravity: 0.0,
            drag: 0.0,
            kind: Kind::Mote,
        });
    }

    pub fn alpha(p: &Particle) -> f32 {
        (p.life / p.max_life).clamp(0.0, 1.0).powf(0.7)
    }
}

/// One visible stripe of falling water, derived from the painting's bright
/// waterfall pixels. Streaks are born inside the column and die at its end.
#[derive(Clone, Copy)]
pub struct FallColumn {
    pub x: f32,
    pub top: f32,
    pub bottom: f32,
    pub speed: f32,
    pub len: f32,
    pub phase: f32,
    pub width: f32,
}

pub fn waterfall_columns(rgb: &[u8], width: usize, height: usize) -> Vec<FallColumn> {
    let mut cols = Vec::new();
    let step = 6;
    let mut x = 1310;
    while x < 1990 {
        let mut top = usize::MAX;
        let mut bottom = 0usize;
        let mut y = 560;
        while y < 2040 {
            let i = (y * width + x) * 3;
            let (r, g, b) = (rgb[i] as i32, rgb[i + 1] as i32, rgb[i + 2] as i32);
            let lum = (r * 30 + g * 59 + b * 11) / 100;
            if lum > 108 && b >= r - 12 {
                top = top.min(y);
                bottom = bottom.max(y);
            }
            y += 3;
        }
        if bottom > top && bottom - top > 260 {
            let jitter = hash01((x as u32).wrapping_mul(2_654_435_761));
            cols.push(FallColumn {
                x: x as f32,
                top: top as f32,
                bottom: bottom as f32,
                speed: 620.0 + jitter * 520.0,
                len: 46.0 + jitter * 120.0,
                phase: jitter * 900.0,
                width: if jitter > 0.72 { 5.0 } else { 2.0 },
            });
        }
        x += step;
    }
    let _ = height;
    cols
}
