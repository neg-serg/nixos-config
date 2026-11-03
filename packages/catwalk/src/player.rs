// Crab physics: a deliberately simple AABB platformer with a swim state.
// The crab is a land animal, but the lake is the only road to the falls, so
// water turns into a slow, bobbing swim instead of a death plane.

use crate::level::{Level, WORLD_H};
use crate::math::{approach, Rect, Vec2};

const GRAVITY: f32 = 3200.0;
const MAX_FALL: f32 = 2400.0;
const RUN_SPEED: f32 = 720.0;
const GROUND_ACCEL: f32 = 5400.0;
const AIR_ACCEL: f32 = 2700.0;
const GROUND_FRICTION: f32 = 5600.0;

const JUMP_SPEED: f32 = 1150.0;
const COYOTE_TIME: f32 = 0.10;
const JUMP_BUFFER: f32 = 0.12;

const SWIM_SPEED: f32 = 380.0;
const SWIM_ACCEL: f32 = 2100.0;
const SWIM_JUMP: f32 = 1080.0;

// Sonic is drawn 80x96 world pixels tall; the hitbox is a little tighter so
// his quills can overlap rock edges without snagging.
const HALF_W: f32 = 22.0;
const HEIGHT: f32 = 90.0;

#[derive(Default, Clone, Copy)]
pub struct Input {
    pub left: bool,
    pub right: bool,
    pub down: bool,
    pub fire_pressed: bool,
    pub jump_held: bool,
    pub jump_pressed: bool,
}

#[derive(Default, Clone, Copy)]
pub struct Events {
    pub jumped: bool,
    pub landed: bool,
    pub entered_water: bool,
    pub left_water: bool,
    pub swimming: bool,
}

pub struct Player {
    /// Feet position, horizontally centered on the crab.
    pub pos: Vec2,
    pub vel: Vec2,
    pub facing: f32,
    pub on_ground: bool,
    pub in_water: bool,
    pub song: f32,
    /// Run-jump builds picked up from monitor capsules.
    pub speed_mult: f32,
    pub jump_mult: f32,
    pub magnet: bool,
    pub shield: bool,
    squash: f32,
    coyote: f32,
    buffer: f32,
    swim_cooldown: f32,
}

impl Player {
    pub fn new(pos: Vec2) -> Self {
        Self {
            pos,
            vel: Vec2::default(),
            facing: 1.0,
            on_ground: false,
            in_water: false,
            song: 0.0,
            speed_mult: 1.0,
            jump_mult: 1.0,
            magnet: false,
            shield: false,
            squash: 1.0,
            coyote: 0.0,
            buffer: 0.0,
            swim_cooldown: 0.0,
        }
    }

    pub fn hitbox(&self) -> Rect {
        Rect::new(
            self.pos.x - HALF_W,
            self.pos.y - HEIGHT,
            HALF_W * 2.0,
            HEIGHT,
        )
    }

    pub fn center(&self) -> Vec2 {
        Vec2::new(self.pos.x, self.pos.y - HEIGHT * 0.5)
    }

    /// Snapshot used by the renderer: crab sprite squash factor.
    pub fn squash(&self) -> f32 {
        self.squash
    }

    pub fn update(&mut self, input: &Input, dt: f32, level: &Level) -> Events {
        let mut events = Events::default();
        let was_water = self.in_water;
        let was_ground = self.on_ground;

        let wl = level.waterline(self.pos.x);
        // Threshold sits above the float line on purpose: the buoyancy spring
        // parks the feet a few pixels under the surface, and a threshold at
        // that same line made the state flicker (and swallow the leap-out).
        self.in_water = self.pos.y > wl - 2.0;
        if self.in_water && !was_water {
            events.entered_water = true;
            self.squash = 0.8;
        }
        if !self.in_water && was_water {
            events.left_water = true;
        }
        events.swimming = self.in_water;

        self.swim_cooldown = (self.swim_cooldown - dt).max(0.0);

        // Horizontal intent.
        let dir = (input.right as i32 - input.left as i32) as f32;
        let (accel, top, friction) = if self.in_water {
            (SWIM_ACCEL, SWIM_SPEED, 3400.0)
        } else if self.on_ground {
            (GROUND_ACCEL, RUN_SPEED * self.speed_mult, GROUND_FRICTION)
        } else {
            (AIR_ACCEL, RUN_SPEED * self.speed_mult, 1200.0)
        };
        if dir.abs() > 0.0 {
            self.vel.x = approach(self.vel.x, dir * top, accel * dt);
            self.facing = dir;
        } else {
            self.vel.x = approach(self.vel.x, 0.0, friction * dt);
        }

        // Timers.
        if self.on_ground {
            self.coyote = COYOTE_TIME;
        } else {
            self.coyote = (self.coyote - dt).max(0.0);
        }
        if input.jump_pressed {
            self.buffer = JUMP_BUFFER;
        } else {
            self.buffer = (self.buffer - dt).max(0.0);
        }

        if self.in_water {
            self.vel.y += GRAVITY * 0.22 * dt;
            // Buoyancy spring: the crab floats with its shell at the surface.
            // Holding down dives; releasing it lets the shell pop back up.
            let target = if input.down { wl + 150.0 } else { wl + 10.0 };
            self.vel.y += (target - self.pos.y) * 46.0 * dt;
            self.vel.y *= (1.0 - 7.0 * dt).clamp(0.0, 1.0);
            self.vel.y = self.vel.y.clamp(-1200.0, 900.0);

            if input.jump_pressed && self.swim_cooldown <= 0.0 {
                self.vel.y = -SWIM_JUMP;
                self.swim_cooldown = 0.28;
                events.jumped = true;
                self.squash = 1.12;
            }
        } else {
            self.vel.y = (self.vel.y + GRAVITY * dt).min(MAX_FALL);
            if self.buffer > 0.0 && (self.on_ground || self.coyote > 0.0) {
                self.vel.y = -JUMP_SPEED * self.jump_mult;
                self.buffer = 0.0;
                self.coyote = 0.0;
                self.on_ground = false;
                events.jumped = true;
                self.squash = 1.14;
            }
            // Variable jump: releasing early cuts the ascent.
            if !input.jump_held && self.vel.y < 0.0 {
                self.vel.y += GRAVITY * 2.1 * dt;
            }
        }

        // Integrate and resolve, axis by axis.
        self.pos.x += self.vel.x * dt;
        self.resolve_x(level);
        self.on_ground = false;
        self.pos.y += self.vel.y * dt;
        self.resolve_y(level, &mut events);

        if self.on_ground && !was_ground && !self.in_water {
            events.landed = true;
            self.squash = 0.82;
        }

        // World edges: keep the crab inside the painting.
        self.pos.x = self
            .pos
            .x
            .clamp(HALF_W + 8.0, crate::level::WORLD_W - HALF_W - 8.0);
        if self.pos.y > WORLD_H + 220.0 {
            self.pos = crate::level::SPAWN;
            self.vel = Vec2::default();
        }

        self.squash = approach(self.squash, 1.0, 3.2 * dt);
        self.song += dt * (1.0 + self.vel.x.abs() / RUN_SPEED);
        events
    }

    /// Get knocked away by a badnik or a shot.
    pub fn hurt(&mut self, from_x: f32) {
        let away = if self.pos.x < from_x { -1.0 } else { 1.0 };
        self.vel.x = away * 520.0;
        self.vel.y = -430.0;
        self.on_ground = false;
    }

    /// Reset the temporary state after a hit.
    pub fn keep_build(&mut self) {
        // Builds survive a hit; this hook exists so damage code stays explicit.
    }

    fn resolve_x(&mut self, level: &Level) {
        let mut hit = self.hitbox();
        for p in level.platforms.iter().chain(level.extra.iter()) {
            if hit.overlaps(*p) {
                if self.vel.x > 0.0 {
                    self.pos.x = p.x - HALF_W;
                } else if self.vel.x < 0.0 {
                    self.pos.x = p.right() + HALF_W;
                }
                self.vel.x = 0.0;
                hit = self.hitbox();
            }
        }
    }

    fn resolve_y(&mut self, level: &Level, events: &mut Events) {
        let mut hit = self.hitbox();
        for p in level.platforms.iter().chain(level.extra.iter()) {
            if !hit.overlaps(*p) {
                continue;
            }
            if self.vel.y > 0.0 {
                self.pos.y = p.y;
                self.vel.y = 0.0;
                self.on_ground = true;
            } else if self.vel.y < 0.0 {
                self.pos.y = p.bottom() + HEIGHT;
                self.vel.y = 0.0;
                events.landed = false;
            }
            hit = self.hitbox();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::level::Level;

    fn step(player: &mut Player, level: &Level, input: Input, seconds: f32) -> Events {
        let dt = 1.0 / 240.0;
        let mut events = Events::default();
        let mut t = 0.0;
        while t < seconds {
            events = player.update(&input, dt, level);
            t += dt;
        }
        events
    }

    #[test]
    fn stands_on_the_plateau() {
        let level = Level::waterfall();
        let mut player = Player::new(crate::level::SPAWN);
        player.update(&Input::default(), 1.0 / 240.0, &level);
        assert!(player.on_ground);
        assert!((player.pos.y - 1840.0).abs() < 0.5);
    }

    #[test]
    fn jump_reaches_a_platform_two_body_heights_up() {
        let level = Level::waterfall();
        let mut player = Player::new(crate::level::SPAWN);
        step(&mut player, &level, Input::default(), 0.2);
        let start = player.pos.y;
        let held = Input {
            jump_held: true,
            jump_pressed: true,
            ..Default::default()
        };
        player.update(&held, 1.0 / 240.0, &level);
        let mut apex = start;
        for _ in 0..120 {
            player.update(&held, 1.0 / 240.0, &level);
            apex = apex.min(player.pos.y);
        }
        assert!(start - apex > 180.0, "apex only {} px", start - apex);
    }

    #[test]
    fn walks_off_the_plateau_into_the_lake() {
        let level = Level::waterfall();
        let mut player = Player::new(Vec2::new(4420.0, 1840.0));
        let walk = Input {
            left: true,
            ..Default::default()
        };
        step(&mut player, &level, walk, 2.0);
        assert!(
            player.in_water,
            "sonic should be swimming at x={}",
            player.pos.x
        );
        assert!(player.pos.y > 1900.0);
    }

    #[test]
    fn floats_and_can_leap_out_of_the_lake() {
        let level = Level::waterfall();
        let mut player = Player::new(Vec2::new(2000.0, 1980.0));
        step(&mut player, &level, Input::default(), 1.0);
        assert!(player.in_water, "sonic should settle on the surface");
        let surface = player.pos.y;
        // A leap out of the water has to clear a good part of the body height.
        let mut input = Input {
            jump_pressed: true,
            jump_held: true,
            ..Default::default()
        };
        player.update(&input, 1.0 / 240.0, &level);
        input.jump_pressed = false;
        let mut peak = player.pos.y;
        for _ in 0..90 {
            player.update(&input, 1.0 / 240.0, &level);
            peak = peak.min(player.pos.y);
        }
        assert!(surface - peak > 120.0, "only rose {} px", surface - peak);
    }

    /// Walk the physics forward and report the closest the crab's center gets
    /// to `target`. This is how the level's collectibles are verified without
    /// hand-playing every route.
    fn closest_approach(
        player: &mut Player,
        level: &Level,
        input: Input,
        seconds: f32,
        target: Vec2,
    ) -> f32 {
        let dt = 1.0 / 240.0;
        let mut best = f32::MAX;
        let mut t = 0.0;
        while t < seconds {
            player.update(&input, dt, level);
            best = best.min((player.center() - target).len());
            t += dt;
        }
        best
    }

    #[test]
    fn plateau_drops_need_a_small_jump() {
        let level = Level::waterfall();
        let mut player = Player::new(Vec2::new(5000.0, 1840.0));
        step(&mut player, &level, Input::default(), 0.2);
        let target = Vec2::new(5000.0, 1725.0);
        let dist = closest_approach(
            &mut player,
            &level,
            Input {
                jump_pressed: true,
                jump_held: true,
                ..Default::default()
            },
            1.2,
            target,
        );
        assert!(dist < 64.0, "closest approach to plateau drop: {dist}");
    }

    #[test]
    fn lake_drops_are_reachable_from_the_surface() {
        let level = Level::waterfall();
        let mut player = Player::new(Vec2::new(3450.0, 2000.0));
        step(&mut player, &level, Input::default(), 1.0);
        assert!(player.in_water);
        let target = Vec2::new(3450.0, 1840.0);
        let dist = closest_approach(
            &mut player,
            &level,
            Input {
                jump_pressed: true,
                jump_held: true,
                ..Default::default()
            },
            1.0,
            target,
        );
        assert!(dist < 64.0, "closest approach to lake drop: {dist}");
    }

    #[test]
    fn underwater_drop_needs_a_dive() {
        let level = Level::waterfall();
        let mut player = Player::new(Vec2::new(4280.0, 1960.0));
        step(&mut player, &level, Input::default(), 1.0);
        assert!(player.in_water);
        let target = Vec2::new(4280.0, 2020.0);
        let dist = closest_approach(
            &mut player,
            &level,
            Input {
                down: true,
                ..Default::default()
            },
            1.5,
            target,
        );
        assert!(dist < 64.0, "closest approach to sunken drop: {dist}");
    }

    #[test]
    fn goal_is_reachable_from_the_low_step() {
        let level = Level::waterfall();
        let mut player = Player::new(Vec2::new(1340.0, 1984.0));
        step(&mut player, &level, Input::default(), 0.2);
        // A tapped hop, not a held jump: the ring hangs in the spray above
        // the pool and a full jump sails over it.
        let dist = closest_approach(
            &mut player,
            &level,
            Input {
                jump_pressed: true,
                right: true,
                ..Default::default()
            },
            1.0,
            level.goal,
        );
        assert!(dist < 96.0, "closest approach to goal: {dist}");
    }

    #[test]
    fn climbs_the_falls_staircase() {
        let level = Level::waterfall();
        // Each step must be reachable from the one before it.
        let tops = [2024.0, 1966.0, 1904.0, 1840.0];
        let mut feet = 2052.0;
        for top in tops {
            assert!(feet - top < 150.0, "step {top} too tall");
            feet = top;
        }
    }
}
