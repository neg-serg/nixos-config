// Dynamic entities: the run's opponents and procedurally placed pickups.
// Everything here is spawned by the director inside the active screen chunk.

use crate::director::{EnemyKind, Spawn, Upgrade};
use crate::level::Level;
use crate::math::{Rect, Vec2};
use crate::player::Player;

#[derive(Clone, Copy)]
pub struct Shot {
    pub pos: Vec2,
    pub vel: Vec2,
    pub life: f32,
}

pub struct Badnik {
    pub kind: EnemyKind,
    /// Centre of the shell.
    pub pos: Vec2,
    pub home: Vec2,
    pub patrol: f32,
    pub t: f32,
    pub alive: bool,
    pub cooldown: f32,
    pub dir: f32,
}

impl Badnik {
    pub fn from_spawn(spawn: Spawn) -> Self {
        Self {
            kind: spawn.kind,
            pos: spawn.pos,
            home: spawn.pos,
            patrol: spawn.patrol,
            t: 0.0,
            alive: true,
            cooldown: 0.6 + (spawn.pos.x as u32 % 7) as f32 * 0.1,
            dir: 1.0,
        }
    }

    pub fn hitbox(&self) -> Rect {
        Rect::new(self.pos.x - 28.0, self.pos.y - 26.0, 56.0, 52.0)
    }

    pub fn update(
        &mut self,
        dt: f32,
        player: &Player,
        level: &Level,
        chunk_x0: f32,
        shots: &mut Vec<Shot>,
    ) {
        self.t += dt;
        let center = player.center();
        let to_player = center - self.pos;
        let dist = to_player.len();
        match self.kind {
            EnemyKind::Drifter => {
                let want = self.home.x + (self.t * 1.2).sin() * self.patrol;
                self.dir = if want >= self.pos.x { 1.0 } else { -1.0 };
                self.pos.x = want;
                self.pos.y = self.home.y + (self.t * 3.4).sin() * 7.0;
            }
            EnemyKind::Chaser => {
                let speed = 165.0;
                if dist < 700.0 && dist > 1.0 {
                    let dir = Vec2::new(to_player.x, to_player.y * 0.8).normalized();
                    self.pos += dir * (speed * dt);
                    self.dir = if dir.x >= 0.0 { 1.0 } else { -1.0 };
                } else {
                    let back = self.home - self.pos;
                    if back.len() > 6.0 {
                        self.pos += back.normalized() * (80.0 * dt);
                    }
                }
            }
            EnemyKind::Shooter => {
                self.pos.x = self.home.x + (self.t * 0.7).sin() * 40.0;
                self.pos.y = self.home.y + (self.t * 2.2).sin() * 10.0;
                self.dir = if to_player.x >= 0.0 { 1.0 } else { -1.0 };
                self.cooldown -= dt;
                if self.cooldown <= 0.0 && dist < 900.0 {
                    self.cooldown = 1.9;
                    let dir = to_player.normalized();
                    shots.push(Shot {
                        pos: self.pos + dir * 30.0,
                        vel: dir * 280.0,
                        life: 3.2,
                    });
                }
            }
        }
        // Keep opponents on their screen and out of the lake.
        let wl = level.waterline(self.pos.x);
        self.pos.x = self
            .pos
            .x
            .clamp(chunk_x0 + 30.0, chunk_x0 + crate::director::CHUNK_W - 30.0);
        self.pos.y = self.pos.y.clamp(1140.0, wl - 30.0);
    }
}

pub fn update_shots(
    shots: &mut Vec<Shot>,
    dt: f32,
    player: &Player,
    level: &Level,
    chunk_x0: f32,
) -> i32 {
    let mut hits = 0;
    let body = player.hitbox();
    for shot in shots.iter_mut() {
        shot.life -= dt;
        shot.pos += shot.vel * dt;
        let r = Rect::new(shot.pos.x - 6.0, shot.pos.y - 6.0, 12.0, 12.0);
        if r.overlaps(body) {
            hits += 1;
            shot.life = 0.0;
        }
        if shot.pos.y > level.waterline(shot.pos.x)
            || shot.pos.x < chunk_x0
            || shot.pos.x > chunk_x0 + crate::director::CHUNK_W
        {
            shot.life = 0.0;
        }
    }
    shots.retain(|s| s.life > 0.0);
    hits
}

#[derive(Clone, Copy)]
pub struct RingPickup {
    pub pos: Vec2,
    pub taken: bool,
}

#[derive(Clone, Copy)]
pub struct Capsule {
    pub pos: Vec2,
    pub upgrade: Upgrade,
    pub taken: bool,
}

impl Capsule {
    pub fn hitbox(&self) -> Rect {
        Rect::new(self.pos.x - 22.0, self.pos.y - 26.0, 44.0, 52.0)
    }
}

pub fn apply_upgrade(player: &mut Player, upgrade: Upgrade) {
    match upgrade {
        Upgrade::Speed => player.speed_mult = (player.speed_mult + 0.15).min(1.6),
        Upgrade::Jump => player.jump_mult = (player.jump_mult + 0.12).min(1.5),
        Upgrade::Magnet => player.magnet = true,
        Upgrade::Shield => player.shield = true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::director::EnemyKind;
    use crate::level::Level;
    use crate::player::{Input, Player};

    fn badnik_at(x: f32, y: f32) -> Badnik {
        Badnik::from_spawn(Spawn {
            kind: EnemyKind::Drifter,
            pos: Vec2::new(x, y),
            patrol: 40.0,
        })
    }

    #[test]
    fn falling_cat_stomps_a_badnik() {
        let mut player = Player::new(Vec2::new(100.0, 900.0));
        player.vel.y = 600.0;
        player.on_ground = false;
        let badnik = badnik_at(100.0, 912.0);
        assert!(stomp_contact(&player, &badnik));
    }

    #[test]
    fn grounded_cat_is_hit_instead_of_stomping() {
        let mut player = Player::new(Vec2::new(100.0, 900.0));
        player.on_ground = true;
        let badnik = badnik_at(100.0, 912.0);
        assert!(!stomp_contact(&player, &badnik));
    }

    #[test]
    fn shots_hit_the_cat_and_expire() {
        let level = Level::waterfall();
        let mut player = Player::new(Vec2::new(1000.0, 1840.0));
        player.update(&Input::default(), 1.0 / 240.0, &level);
        let mut shots = vec![Shot {
            pos: player.center(),
            vel: Vec2::new(100.0, 0.0),
            life: 1.0,
        }];
        let hits = update_shots(&mut shots, 1.0 / 60.0, &player, &level, 0.0);
        assert_eq!(hits, 1);
        assert!(shots.is_empty());
    }

    #[test]
    fn upgrades_scale_the_cat() {
        let mut player = Player::new(Vec2::new(0.0, 0.0));
        apply_upgrade(&mut player, Upgrade::Speed);
        apply_upgrade(&mut player, Upgrade::Jump);
        apply_upgrade(&mut player, Upgrade::Shield);
        assert!(player.speed_mult > 1.0);
        assert!(player.jump_mult > 1.0);
        assert!(player.shield);
    }
}

/// Stomp when the cat is curled in the air and comes from above.
pub fn stomp_contact(player: &Player, badnik: &Badnik) -> bool {
    !player.on_ground
        && !player.in_water
        && player.pos.y < badnik.pos.y
        && player.vel.y > -40.0
        && player.hitbox().overlaps(badnik.hitbox())
}
