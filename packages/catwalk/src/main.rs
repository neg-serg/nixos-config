// crabwalk — a miniature platformer painted on the waterfall wallpaper.
//
// World rule: one world unit is one wallpaper pixel. The background is copied
// 1:1 (integer scale 2 in windowed play), so a standing-still frame is the
// wallpaper itself; only the crab, the drops and the water overlays move.

mod assets;
mod director;
mod effects;
mod font;
mod gameplay;
mod level;
mod math;
mod mechanics;
mod player;
mod render;
mod study;

use std::io::Write;
use std::time::Instant;

use sdl2::event::Event;
use sdl2::keyboard::{Keycode, Scancode};
use sdl2::pixels::{Color, PixelFormatEnum};
use sdl2::rect::Rect as SdlRect;
use sdl2::render::{BlendMode, Canvas, RenderTarget, TextureCreator};
use sdl2::video::WindowContext;

use assets::Assets;
use director::{Director, Upgrade, CHUNK_W};
use effects::Particles;
use gameplay::{Badnik, Capsule, Crate, CrateLoot, Hairball, RingPickup, Shot, Spring};
use level::{DROP_COUNT, SPAWN, VIEW_H, VIEW_W, WORLD_H, WORLD_W};
use math::{hash01, smooth, Rect, Vec2};
use mechanics::{Effect, Mechanic};
use player::{Input, Player};
use render::Cam;

const SCALE: i32 = 2;

#[derive(Clone, Copy, PartialEq)]
enum State {
    Title,
    Play,
    Won,
    Lost,
}

struct Game<'a> {
    assets: Assets<'a>,
    level: level::Level,
    player: Player,
    particles: Particles,
    cam: Vec2,
    time: f32,
    title_t: f32,
    won_t: f32,
    lost_t: f32,
    director: Director,
    current_chunk: i32,
    badniks: Vec<Badnik>,
    shots: Vec<Shot>,
    rings: Vec<RingPickup>,
    capsule: Option<Capsule>,
    crates: Vec<Crate>,
    springs: Vec<Spring>,
    hairballs: Vec<Hairball>,
    weapon_cooldown: f32,
    shots_fired: u32,
    crates_broken: u32,
    springs_used: u32,
    hearts: i32,
    invuln: f32,
    landed_this_frame: bool,
    rings_taken: u32,
    stomps: u32,
    hits_taken: u32,
    builds: [u32; 4],
    fun: f32,
    novelty: f32,
    scenario: String,
    scenario_t: f32,
    metrics_path: Option<String>,
    seed: u32,
    mechanics: Mechanic,
    bounce_cooldown: f32,
    drops: usize,
    state: State,
    hint: f32,
    toast: f32,
    toast_text: String,
    clean: bool,
    debug: bool,
    frame_override: Option<usize>,
    dust_clock: f32,
    mote_clock: f32,
    spray_clock: f32,
    goal_clock: f32,
}

impl<'a> Game<'a> {
    fn new(assets: Assets<'a>, debug: bool, seed: u32) -> Self {
        let level = level::Level::waterfall();
        let player = Player::new(SPAWN);
        Self {
            assets,
            level,
            player,
            particles: Particles::new(),
            cam: home_camera(SPAWN),
            time: 0.0,
            title_t: 0.0,
            won_t: 0.0,
            lost_t: 0.0,
            director: Director::new(seed),
            current_chunk: i32::MIN,
            badniks: Vec::new(),
            shots: Vec::new(),
            rings: Vec::new(),
            capsule: None,
            crates: Vec::new(),
            springs: Vec::new(),
            hairballs: Vec::new(),
            weapon_cooldown: 0.0,
            shots_fired: 0,
            crates_broken: 0,
            springs_used: 0,
            hearts: 3,
            invuln: 0.0,
            landed_this_frame: false,
            rings_taken: 0,
            stomps: 0,
            hits_taken: 0,
            builds: [0; 4],
            fun: 0.0,
            novelty: 0.0,
            scenario: String::new(),
            scenario_t: 0.0,
            metrics_path: None,
            seed,
            mechanics: {
                let mut lab = mechanics::Lab::new(seed);
                lab.next(seed).mechanic
            },
            bounce_cooldown: 0.0,
            drops: 0,
            state: State::Title,
            hint: 0.0,
            toast: 0.0,
            toast_text: String::new(),
            clean: false,
            debug,
            frame_override: None,
            dust_clock: 0.0,
            mote_clock: 0.0,
            spray_clock: 0.0,
            goal_clock: 0.0,
        }
    }

    fn apply_mechanics(&mut self) {
        self.player.rules.double_jump = self.mechanics.has(Effect::DoubleJump);
        self.player.rules.glide = self.mechanics.glide();
        self.player.rules.air_jump = self.mechanics.air_jump();
        if self.mechanics.has(Effect::Magnet) {
            self.player.magnet = true;
        }
    }

    fn reset(&mut self) {
        self.level = level::Level::waterfall();
        self.player = Player::new(SPAWN);
        self.particles.items.clear();
        self.drops = 0;
        self.toast = 0.0;
        self.hint = 9.0;
        self.cam = home_camera(SPAWN);
        self.state = State::Play;
        self.title_t = 0.0;
        self.won_t = 0.0;
        self.lost_t = 0.0;
        self.current_chunk = i32::MIN;
        self.badniks.clear();
        self.shots.clear();
        self.rings.clear();
        self.capsule = None;
        self.crates.clear();
        self.springs.clear();
        self.hairballs.clear();
        self.level.extra.clear();
        self.weapon_cooldown = 0.0;
        self.shots_fired = 0;
        self.crates_broken = 0;
        self.springs_used = 0;
        self.hearts = 3;
        self.invuln = 0.0;
        self.rings_taken = 0;
        self.stomps = 0;
        self.hits_taken = 0;
        self.builds = [0; 4];
        self.fun = 0.0;
        self.novelty = 0.0;
        self.scenario.clear();
        self.scenario_t = 0.0;
        self.mechanics = {
            let mut lab = mechanics::Lab::new(self.seed);
            lab.next(self.seed).mechanic
        };
        self.bounce_cooldown = 0.0;
        self.apply_mechanics();
    }

    fn enter_chunk(&mut self, chunk: i32) {
        let encounter = self
            .director
            .encounter_for(chunk, self.player.pos, &self.level);
        self.badniks = encounter
            .spawns
            .iter()
            .map(|s| Badnik::from_spawn(*s))
            .collect();
        self.rings = encounter
            .rings
            .iter()
            .map(|r| RingPickup {
                pos: r.pos,
                taken: false,
            })
            .collect();
        self.capsule = encounter.capsule.map(|(pos, upgrade)| Capsule {
            pos,
            upgrade,
            taken: false,
        });
        self.crates = encounter
            .crates
            .iter()
            .map(|pos| Crate {
                pos: *pos,
                hp: 2,
                alive: true,
                loot: gameplay::crate_loot(pos.x),
            })
            .collect();
        self.springs = encounter
            .springs
            .iter()
            .map(|pos| Spring {
                pos: *pos,
                cooldown: 0.0,
            })
            .collect();
        self.hairballs.clear();
        self.sync_solids();
        self.scenario = encounter.scenario.to_string();
        self.scenario_t = 3.0;
        self.current_chunk = chunk;
        self.shots.clear();
        if let Some(last) = &self.director.last {
            self.fun = last.scores.fun;
            self.novelty = last.scores.surprise;
        }
    }

    fn sync_solids(&mut self) {
        self.level.extra.clear();
        for c in &self.crates {
            if c.alive {
                self.level.extra.push(c.hitbox());
            }
        }
    }

    fn break_crate(&mut self, index: usize) {
        if !self.crates[index].alive {
            return;
        }
        self.crates[index].alive = false;
        self.crates_broken += 1;
        let c = self.crates[index];
        self.particles.sparkle(c.pos + Vec2::new(0.0, -22.0));
        let _ = c;
        match self.crates[index].loot {
            CrateLoot::Rings(n) => {
                for k in 0..n as i32 {
                    let offset = (k as f32 - n as f32 * 0.5) * 20.0;
                    self.rings.push(RingPickup {
                        pos: self.crates[index].pos + Vec2::new(offset, -36.0 - k as f32 * 6.0),
                        taken: false,
                    });
                }
            }
            CrateLoot::Heart => {
                self.hearts = (self.hearts + 1).min(5);
                self.toast = 1.8;
                self.toast_text = "СЕРДЦЕ".into();
            }
            CrateLoot::Nothing => {}
        }
        self.sync_solids();
    }

    fn update_encounter(&mut self, dt: f32, fire: bool) {
        let chunk_x0 = self.current_chunk as f32 * CHUNK_W;
        for badnik in &mut self.badniks {
            if badnik.alive {
                badnik.update(dt, &self.player, &self.level, chunk_x0, &mut self.shots);
            }
        }

        let mut stomped = Vec::new();
        let mut hurt = false;
        let mut killed = false;
        {
            let p = &self.player;
            let invulnerable = self.invuln > 0.0;
            for badnik in &mut self.badniks {
                if !badnik.alive || !badnik.hitbox().overlaps(p.hitbox()) {
                    continue;
                }
                if gameplay::stomp_contact(p, badnik) {
                    stomped.push(badnik.pos);
                } else if !invulnerable {
                    hurt = true;
                }
            }
        }
        for pos in &stomped {
            for badnik in &mut self.badniks {
                if (badnik.pos - *pos).len() < 1.0 {
                    badnik.alive = false;
                }
            }
            self.stomps += 1;
            self.particles.sparkle(*pos);
        }
        if !stomped.is_empty() {
            killed = true;
        }
        if hurt {
            self.damage();
        }

        let shot_hits =
            gameplay::update_shots(&mut self.shots, dt, &self.player, &self.level, chunk_x0);
        if shot_hits > 0 && self.invuln <= 0.0 {
            self.damage();
        }

        self.invuln = (self.invuln - dt).max(0.0);
        self.scenario_t = (self.scenario_t - dt).max(0.0);

        let center = self.player.center();
        let magnet = self.player.magnet;
        for ring in &mut self.rings {
            if ring.taken {
                continue;
            }
            if magnet {
                let d = center - ring.pos;
                if d.len() < 190.0 {
                    ring.pos += d.normalized() * (460.0 * dt);
                }
            }
            if (center - ring.pos).len() < 42.0 {
                ring.taken = true;
                self.rings_taken += 1;
                self.particles.sparkle(ring.pos);
            }
        }
        if let Some(capsule) = &mut self.capsule {
            if !capsule.taken && capsule.hitbox().overlaps(self.player.hitbox()) {
                capsule.taken = true;
                let upgrade = capsule.upgrade;
                gameplay::apply_upgrade(&mut self.player, upgrade);
                self.builds[upgrade.index()] += 1;
                self.particles.sparkle(capsule.pos);
                self.toast = 2.4;
                self.toast_text = format!("СБОРКА: {}", upgrade.label());
            }
        }

        // Springs launch the cat; great for reaching high rings.
        for spring in &mut self.springs {
            spring.cooldown = (spring.cooldown - dt).max(0.0);
            if spring.cooldown <= 0.0
                && self.player.on_ground
                && spring.trigger().overlaps(self.player.hitbox())
            {
                spring.cooldown = 0.45;
                self.player.vel.y = -1550.0;
                self.player.on_ground = false;
                self.springs_used += 1;
                self.particles.dust(self.player.pos, 1.0);
                self.particles.sparkle(spring.pos + Vec2::new(0.0, -12.0));
            }
        }

        // Weapon: a furball every third of a second.
        self.weapon_cooldown = (self.weapon_cooldown - dt).max(0.0);
        if fire && self.weapon_cooldown <= 0.0 {
            self.weapon_cooldown = 0.34;
            self.shots_fired += 1;
            let c = self.player.center();
            let angles: &[f32] = if self.mechanics.has(Effect::TripleShot) {
                &[-0.17, 0.0, 0.17]
            } else {
                &[0.0]
            };
            for angle in angles {
                let (sin, cos) = angle.sin_cos();
                let dir = Vec2::new(self.player.facing * cos, sin);
                self.hairballs.push(Hairball {
                    pos: c + Vec2::new(self.player.facing * 36.0, 4.0),
                    vel: Vec2::new(dir.x * 920.0, dir.y * 920.0 - 80.0),
                    life: 1.5,
                    bounces: 0,
                });
            }
        }

        let chunk_x0 = self.current_chunk as f32 * CHUNK_W;
        for ball in &mut self.hairballs {
            ball.life -= dt;
            ball.vel.y += 1000.0 * dt;
            ball.pos += ball.vel * dt;
            let wl = self.level.waterline(ball.pos.x);
            if ball.pos.y > wl - 2.0 {
                if ball.bounces == 0 {
                    ball.pos.y = wl - 2.0;
                    ball.vel.y = -520.0;
                    ball.bounces = 1;
                } else {
                    ball.life = 0.0;
                }
            }
            if ball.pos.x < chunk_x0 || ball.pos.x > chunk_x0 + CHUNK_W {
                ball.life = 0.0;
            }
        }

        let mut hits: Vec<(usize, Option<usize>, Option<usize>)> = Vec::new();
        for bi in 0..self.hairballs.len() {
            if self.hairballs[bi].life <= 0.0 {
                continue;
            }
            let hb = self.hairballs[bi].hitbox();
            let bad = self
                .badniks
                .iter()
                .position(|b| b.alive && b.hitbox().overlaps(hb));
            let cr = self
                .crates
                .iter()
                .position(|c| c.alive && c.hitbox().overlaps(hb));
            if bad.is_some() || cr.is_some() {
                hits.push((bi, bad, cr));
            }
        }
        for (bi, bad, cr) in hits {
            self.hairballs[bi].life = 0.0;
            let at = self.hairballs[bi].pos;
            if let Some(b) = bad {
                self.badniks[b].alive = false;
                self.stomps += 1;
                killed = true;
                let pos = self.badniks[b].pos;
                self.particles.sparkle(pos);
            }
            if let Some(ci) = cr {
                self.crates[ci].hp = self.crates[ci].hp.saturating_sub(1);
                if self.crates[ci].hp == 0 {
                    self.break_crate(ci);
                }
            }
            self.particles.dust(at, 1.0);
        }
        self.hairballs.retain(|b| b.life > 0.0);

        // Generated mechanic: stomps send a shockwave through nearby badniks.
        if killed && self.mechanics.has(Effect::Shockwave) {
            let at = self.player.pos + Vec2::new(0.0, -20.0);
            for badnik in &mut self.badniks {
                if badnik.alive && (badnik.pos - at).len() < 240.0 {
                    badnik.alive = false;
                }
            }
            for i in 0..14 {
                let a = i as f32 / 14.0 * std::f32::consts::TAU;
                self.particles.mote(at + Vec2::new(a.cos(), a.sin()) * 60.0);
            }
        }

        // Stomping a crate breaks it and drops the loot.
        if self.landed_this_frame {
            if let Some(i) = self.crates.iter().position(|c| {
                c.alive
                    && (self.player.pos.x - c.pos.x).abs() < 34.0
                    && (self.player.pos.y - (c.pos.y - 44.0)).abs() < 8.0
            }) {
                self.break_crate(i);
                self.player.vel.y = -520.0;
                self.player.on_ground = false;
            }
        }
    }

    fn damage(&mut self) {
        if self.invuln > 0.0 {
            return;
        }
        let from = self.player.pos.x;
        self.hits_taken += 1;
        self.invuln = 1.35;
        self.particles
            .sparkle(self.player.pos + Vec2::new(0.0, -40.0));
        if self.player.shield {
            self.player.shield = false;
            self.toast = 1.6;
            self.toast_text = "ЩИТ РАЗБИТ".into();
            return;
        }
        self.player.keep_build();
        self.player.hurt(from);
        self.hearts -= 1;
        if self.hearts <= 0 {
            self.hearts = 0;
            self.state = State::Lost;
            self.lost_t = 0.0;
            self.write_metrics();
        }
    }

    fn metrics_json(&self) -> String {
        let mut chunks = String::new();
        for p in &self.director.campaign {
            if !chunks.is_empty() {
                chunks.push(',');
            }
            chunks.push_str(&format!(
                "{{\"chunk\":{},\"scenario\":\"{}\",\"fun\":{:.3},\"surprise\":{:.3},\"build\":{:.3},\"situation\":{:.3},\"fairness\":{:.3},\"enemies\":{},\"rings\":{}}}",
                p.encounter.chunk,
                p.encounter.scenario,
                p.scores.fun,
                p.scores.surprise,
                p.scores.build,
                p.scores.situation,
                p.scores.fairness,
                p.encounter.spawns.len(),
                p.encounter.rings.len()
            ));
        }
        let fun_avg = if self.director.campaign.is_empty() {
            0.0
        } else {
            self.director
                .campaign
                .iter()
                .map(|p| p.scores.fun)
                .sum::<f32>()
                / self.director.campaign.len() as f32
        };
        let novelty_avg = if self.director.campaign.is_empty() {
            0.0
        } else {
            self.director
                .campaign
                .iter()
                .map(|p| p.scores.surprise)
                .sum::<f32>()
                / self.director.campaign.len() as f32
        };
        format!(
            "{{\"seed\":{},\"hearts\":{},\"drops\":{},\"chunks\":[{}],\"events\":{{\"rings\":{},\"stomps\":{},\"hits\":{},\"shots\":{},\"crates\":{},\"springs\":{},\"upgrades\":{{\"speed\":{},\"jump\":{},\"magnet\":{},\"shield\":{}}}}},\"summary\":{{\"fun_avg\":{:.3},\"novelty_avg\":{:.3},\"scenarios\":{}}}}}",
            self.seed,
            self.hearts,
            self.drops,
            chunks,
            self.rings_taken,
            self.stomps,
            self.hits_taken,
            self.shots_fired,
            self.crates_broken,
            self.springs_used,
            self.builds[0],
            self.builds[1],
            self.builds[2],
            self.builds[3],
            fun_avg,
            novelty_avg,
            self.director.campaign.len()
        )
    }

    fn write_metrics(&self) {
        if let Some(path) = &self.metrics_path {
            let _ = std::fs::write(path, self.metrics_json());
        }
    }

    fn start_playing(&mut self) {
        self.state = State::Play;
        self.hint = 9.0;
    }

    fn update(&mut self, dt: f32, input: &Input, start_pressed: bool) {
        self.time += dt;
        self.particles.update(dt);
        self.hint = (self.hint - dt).max(0.0);
        self.toast = (self.toast - dt).max(0.0);
        self.ambient(dt);

        match self.state {
            State::Title => {
                self.title_t += dt;
                self.player.song += dt;
                if start_pressed || input.jump_pressed {
                    self.start_playing();
                }
            }
            State::Play => {
                let events = self.player.update(input, dt, &self.level);
                if events.jumped {
                    self.particles
                        .dust(self.player.pos + Vec2::new(0.0, 2.0), self.player.facing);
                }
                if events.entered_water {
                    let wl = self.level.waterline(self.player.pos.x);
                    self.particles
                        .splash(Vec2::new(self.player.pos.x, wl + 2.0), 1.0);
                }
                if events.landed {
                    self.particles
                        .dust(self.player.pos + Vec2::new(0.0, 2.0), self.player.facing);
                }
                if self.player.on_ground && self.player.vel.x.abs() > 240.0 {
                    self.dust_clock -= dt;
                    if self.dust_clock <= 0.0 {
                        self.dust_clock = 0.16;
                        self.particles
                            .dust(self.player.pos + Vec2::new(0.0, 2.0), self.player.facing);
                    }
                }

                let chunk = (self.player.pos.x / CHUNK_W).floor() as i32;
                if chunk != self.current_chunk {
                    self.enter_chunk(chunk);
                }
                self.landed_this_frame = events.landed;
                self.bounce_cooldown = (self.bounce_cooldown - dt).max(0.0);
                if events.landed && self.bounce_cooldown <= 0.0 && self.mechanics.bounce() > 0.0 {
                    self.player.vel.y = -self.mechanics.bounce();
                    self.player.on_ground = false;
                    self.bounce_cooldown = 0.6;
                    self.particles.dust(self.player.pos, 1.0);
                }
                self.update_encounter(dt, input.fire_pressed);
                self.collect_drops();
                self.check_goal();
                self.follow_camera(dt);
            }
            State::Lost => {
                self.lost_t += dt;
            }
            State::Won => {
                self.won_t += dt;
                if self.particles.items.len() < 90 {
                    let seed = (self.time * 60.0) as u32;
                    let x = 700.0 + hash01(seed) * 1100.0;
                    self.particles
                        .sparkle(Vec2::new(x, 1450.0 + hash01(seed + 1) * 380.0));
                }
            }
        }
    }

    fn ambient(&mut self, dt: f32) {
        self.spray_clock -= dt;
        if self.spray_clock <= 0.0 {
            self.spray_clock = 0.035;
            let seed = (self.time * 400.0) as u32;
            let x = 1340.0 + hash01(seed) * 620.0;
            self.particles
                .spray(Vec2::new(x, 2038.0), 0.6 + hash01(seed + 7));
        }

        if self.state == State::Play || self.state == State::Title {
            self.goal_clock -= dt;
            if self.goal_clock <= 0.0 {
                self.goal_clock = 0.13;
                let seed = (self.time * 90.0) as u32;
                let angle = hash01(seed) * std::f32::consts::TAU;
                let radius = 20.0 + hash01(seed + 3) * 40.0;
                let at = Vec2::new(
                    self.level.goal.x + angle.cos() * radius,
                    self.level.goal.y + angle.sin() * radius * 0.8,
                );
                self.particles.glint(at);
            }
        }

        self.mote_clock -= dt;
        if self.mote_clock <= 0.0 {
            self.mote_clock = 0.5;
            let seed = (self.time * 60.0) as u32;
            let x = hash01(seed.wrapping_mul(7)) * WORLD_W;
            let y = 1500.0 + hash01(seed.wrapping_mul(13)) * 420.0;
            self.particles.mote(Vec2::new(x, y));
        }
    }

    fn collect_drops(&mut self) {
        let center = self.player.center();
        let mut picked = Vec::new();
        for (i, drop) in self.level.drops.iter().enumerate() {
            if !drop.taken && (center - drop.pos).len() < 64.0 {
                picked.push(i);
            }
        }
        for i in picked {
            self.level.drops[i].taken = true;
            let pos = self.level.drops[i].pos;
            self.particles.sparkle(pos);
            self.drops += 1;
        }
    }

    fn check_goal(&mut self) {
        let goal = self.level.goal;
        if (self.player.center() - goal).len() < 96.0 {
            if self.drops >= DROP_COUNT {
                if self.state != State::Won {
                    self.state = State::Won;
                    self.won_t = 0.0;
                    for _ in 0..6 {
                        self.particles.sparkle(goal);
                    }
                    self.write_metrics();
                }
            } else {
                self.toast = 2.2;
                let left = DROP_COUNT - self.drops;
                self.toast_text = format!("ЕЩЁ {} {}", left, drops_word(left));
            }
        }
    }

    fn follow_camera(&mut self, dt: f32) {
        let look = self.player.facing * 90.0;
        let target_x = self.player.pos.x + look - VIEW_W * 0.5;
        let target_y = self.player.pos.y - 110.0 - VIEW_H * 0.5;
        self.cam.x = smooth(self.cam.x, target_x, 4.2, dt).clamp(0.0, WORLD_W - VIEW_W);
        self.cam.y = smooth(self.cam.y, target_y, 3.2, dt).clamp(0.0, WORLD_H - VIEW_H);
    }

    fn draw<RT: RenderTarget>(
        &mut self,
        canvas: &mut Canvas<RT>,
        scale: i32,
    ) -> Result<(), String> {
        let cam = Cam {
            x: self.cam.x.floor(),
            y: self.cam.y.floor(),
        };

        canvas.set_blend_mode(BlendMode::Blend);
        canvas.set_draw_color(Color::RGB(0, 0, 0));
        canvas.clear();

        let src = SdlRect::new(cam.x as i32, cam.y as i32, VIEW_W as u32, VIEW_H as u32);
        let dst = SdlRect::new(
            0,
            0,
            (VIEW_W as i32 * scale) as u32,
            (VIEW_H as i32 * scale) as u32,
        );
        canvas.copy(&self.assets.world, Some(src), Some(dst))?;

        if self.clean {
            return Ok(());
        }

        self.draw_water(canvas, cam, scale)?;
        self.draw_encounter(canvas, cam, scale)?;
        self.draw_goal(canvas, cam, scale)?;
        self.draw_drops(canvas, cam, scale)?;
        self.draw_player(canvas, cam, scale)?;
        self.draw_particles(canvas, cam, scale)?;
        if self.debug {
            self.draw_debug(canvas, cam, scale)?;
        }
        self.draw_hud(canvas, scale)?;
        self.draw_overlay(canvas, scale)
    }

    fn draw_water<RT: RenderTarget>(
        &mut self,
        canvas: &mut Canvas<RT>,
        cam: Cam,
        scale: i32,
    ) -> Result<(), String> {
        let t = self.time;

        let mut shimmer = Vec::new();
        for point in &self.assets.shimmer {
            let phase = point.phrase();
            let wave = (t * (0.18 + phase * 0.22) + phase * 6.28).sin();
            if wave < 0.84 {
                continue;
            }
            let dx = (t * (7.0 + phase * 9.0) + phase * 40.0) % 90.0;
            shimmer.push(Rect::new(
                point.x - dx,
                point.y,
                10.0 + phase * 22.0,
                if phase > 0.86 { 2.0 } else { 1.0 },
            ));
        }
        render::fill_rects(canvas, cam, scale, &shimmer, Color::RGBA(226, 242, 246, 22))?;

        let mut bright = Vec::new();
        let mut faint = Vec::new();
        for col in &self.assets.falls {
            let span = col.bottom - col.top;
            if span <= 0.0 {
                continue;
            }
            let travel = (t * col.speed + col.phase) % (span + col.len);
            let y = (col.top + travel - col.len).max(col.top);
            let r = Rect::new(col.x, y, col.width, col.len);
            if col.width > 4.0 {
                bright.push(r);
            } else {
                faint.push(r);
            }
        }
        render::fill_rects(canvas, cam, scale, &faint, Color::RGBA(230, 244, 250, 30))?;
        render::fill_rects(canvas, cam, scale, &bright, Color::RGBA(252, 252, 248, 38))?;
        Ok(())
    }

    fn draw_drops<RT: RenderTarget>(
        &mut self,
        canvas: &mut Canvas<RT>,
        cam: Cam,
        scale: i32,
    ) -> Result<(), String> {
        let time = self.time;
        let remaining: Vec<(f32, f32, f32)> = self
            .level
            .drops
            .iter()
            .filter(|d| !d.taken)
            .map(|d| (d.pos.x, d.pos.y, d.phase))
            .collect();
        for (x, y, phase) in remaining {
            let bob = (time * 2.1 + phase).sin() * 5.0;
            let cx = x;
            let cy = y + bob;
            render::ring(
                canvas,
                cam,
                scale,
                (cx, cy),
                26.0,
                2.0,
                12,
                Color::RGBA(222, 242, 248, 60),
            )?;
            let rows = [
                (cx - 2.0, cy - 15.0, 4.0, 4.0),
                (cx - 4.0, cy - 11.0, 8.0, 4.0),
                (cx - 6.0, cy - 7.0, 12.0, 8.0),
                (cx - 7.0, cy + 1.0, 14.0, 6.0),
                (cx - 5.0, cy + 7.0, 10.0, 4.0),
            ];
            for (rx, ry, rw, rh) in rows {
                render::fill_rect(
                    canvas,
                    cam,
                    scale,
                    Rect::new(rx, ry, rw, rh),
                    Color::RGBA(196, 232, 244, 235),
                )?;
            }
            render::fill_rect(
                canvas,
                cam,
                scale,
                Rect::new(cx - 3.0, cy - 4.0, 3.0, 4.0),
                Color::RGBA(252, 254, 255, 240),
            )?;
        }
        Ok(())
    }

    fn draw_encounter<RT: RenderTarget>(
        &mut self,
        canvas: &mut Canvas<RT>,
        cam: Cam,
        scale: i32,
    ) -> Result<(), String> {
        let time = self.time;
        let palette = self.assets.palette;

        for c in &self.crates {
            if !c.alive {
                continue;
            }
            let x = c.pos.x - 22.0;
            let y = c.pos.y - 44.0;
            render::fill_rect(
                canvas,
                cam,
                scale,
                Rect::new(x - 2.0, y - 2.0, 48.0, 48.0),
                Color::RGBA(8, 14, 16, 220),
            )?;
            render::fill_rect(
                canvas,
                cam,
                scale,
                Rect::new(x, y, 44.0, 44.0),
                Color::RGBA(150, 100, 56, 255),
            )?;
            render::fill_rect(
                canvas,
                cam,
                scale,
                Rect::new(x, y, 44.0, 6.0),
                Color::RGBA(190, 140, 86, 255),
            )?;
            render::fill_rect(
                canvas,
                cam,
                scale,
                Rect::new(x + 6.0, y + 8.0, 4.0, 28.0),
                Color::RGBA(96, 62, 34, 255),
            )?;
            render::fill_rect(
                canvas,
                cam,
                scale,
                Rect::new(x + 34.0, y + 8.0, 4.0, 28.0),
                Color::RGBA(96, 62, 34, 255),
            )?;
            match c.loot {
                CrateLoot::Rings(_) => {
                    render::ring(
                        canvas,
                        cam,
                        scale,
                        (x + 22.0, y + 22.0),
                        7.0,
                        3.0,
                        8,
                        Color::RGBA(250, 214, 110, 240),
                    )?;
                }
                CrateLoot::Heart => {
                    render::fill_rect(
                        canvas,
                        cam,
                        scale,
                        Rect::new(x + 17.0, y + 16.0, 10.0, 10.0),
                        Color::RGBA(228, 74, 74, 240),
                    )?;
                }
                CrateLoot::Nothing => {}
            }
        }

        for spring in &self.springs {
            let x = spring.pos.x;
            let y = spring.pos.y;
            render::fill_rect(
                canvas,
                cam,
                scale,
                Rect::new(x - 18.0, y - 8.0, 36.0, 8.0),
                Color::RGBA(44, 52, 56, 240),
            )?;
            for i in 0..3 {
                let w = 22.0 - i as f32 * 2.0;
                render::fill_rect(
                    canvas,
                    cam,
                    scale,
                    Rect::new(x - w * 0.5, y - 14.0 - i as f32 * 6.0, w, 4.0),
                    Color::RGBA(150, 162, 168, 240),
                )?;
            }
            render::fill_rect(
                canvas,
                cam,
                scale,
                Rect::new(x - 22.0, y - 36.0, 44.0, 7.0),
                Color::RGBA(228, 60, 60, 245),
            )?;
            render::fill_rect(
                canvas,
                cam,
                scale,
                Rect::new(x - 22.0, y - 36.0, 44.0, 2.0),
                Color::RGBA(255, 150, 140, 245),
            )?;
        }

        for ball in &self.hairballs {
            let cx = ball.pos.x;
            let cy = ball.pos.y;
            render::fill_rect(
                canvas,
                cam,
                scale,
                Rect::new(cx - 7.0, cy - 7.0, 14.0, 14.0),
                Color::RGBA(240, 236, 218, 255),
            )?;
            render::fill_rect(
                canvas,
                cam,
                scale,
                Rect::new(cx - 4.0, cy - 9.0, 8.0, 4.0),
                Color::RGBA(240, 236, 218, 255),
            )?;
            render::fill_rect(
                canvas,
                cam,
                scale,
                Rect::new(cx - 3.0, cy - 2.0, 6.0, 6.0),
                Color::RGBA(198, 158, 118, 255),
            )?;
        }

        for badnik in &self.badniks {
            if !badnik.alive {
                continue;
            }
            let frame = (badnik.t * 14.0) as usize % 2;
            let src = SdlRect::new((frame as u32 * 36) as i32, 0, 36, 36);
            let bob = (badnik.t * 3.0).sin() * 4.0;
            let dst = Rect::new(badnik.pos.x - 36.0, badnik.pos.y - 36.0 + bob, 72.0, 72.0);
            render::draw_texture_frame(
                canvas,
                cam,
                scale,
                &self.assets.badnik,
                src,
                dst,
                badnik.dir < 0.0,
            )?;
        }

        for shot in &self.shots {
            render::ring(
                canvas,
                cam,
                scale,
                (shot.pos.x, shot.pos.y),
                9.0,
                3.0,
                8,
                Color::RGBA(255, 120, 60, 220),
            )?;
            render::fill_rect(
                canvas,
                cam,
                scale,
                Rect::new(shot.pos.x - 3.0, shot.pos.y - 3.0, 6.0, 6.0),
                Color::RGBA(255, 232, 150, 240),
            )?;
        }

        for ring in &self.rings {
            if ring.taken {
                continue;
            }
            let bob = (time * 2.4 + ring.pos.x * 0.01).sin() * 3.0;
            render::ring(
                canvas,
                cam,
                scale,
                (ring.pos.x, ring.pos.y + bob),
                12.0,
                3.0,
                12,
                Color::RGBA(250, 214, 110, 235),
            )?;
            render::fill_rect(
                canvas,
                cam,
                scale,
                Rect::new(ring.pos.x - 2.0, ring.pos.y + bob - 12.0, 4.0, 3.0),
                Color::RGBA(255, 250, 220, 240),
            )?;
        }

        if let Some(capsule) = &self.capsule {
            if !capsule.taken {
                let bob = (time * 2.0).sin() * 3.0;
                let x = capsule.pos.x;
                let y = capsule.pos.y + bob;
                // Monitor body.
                render::fill_rect(
                    canvas,
                    cam,
                    scale,
                    Rect::new(x - 24.0, y - 30.0, 48.0, 58.0),
                    Color::RGBA(8, 14, 18, 200),
                )?;
                render::fill_rect(
                    canvas,
                    cam,
                    scale,
                    Rect::new(x - 21.0, y - 27.0, 42.0, 52.0),
                    Color::RGBA(178, 192, 200, 255),
                )?;
                render::fill_rect(
                    canvas,
                    cam,
                    scale,
                    Rect::new(x - 16.0, y - 22.0, 32.0, 30.0),
                    match capsule.upgrade {
                        Upgrade::Speed => Color::RGBA(250, 206, 90, 255),
                        Upgrade::Jump => Color::RGBA(120, 190, 255, 255),
                        Upgrade::Magnet => Color::RGBA(196, 140, 250, 255),
                        Upgrade::Shield => Color::RGBA(120, 220, 160, 255),
                    },
                )?;
                render::fill_rect(
                    canvas,
                    cam,
                    scale,
                    Rect::new(x - 12.0, y + 12.0, 24.0, 6.0),
                    Color::RGBA(90, 104, 112, 255),
                )?;
                if let Some(glyph) = capsule.upgrade.label().chars().next() {
                    let label = glyph.to_string();
                    render::text_centered(
                        canvas,
                        cam,
                        scale,
                        x,
                        y - 16.0,
                        &label,
                        4,
                        Color::RGBA(20, 24, 28, 235),
                        Color::RGBA(20, 24, 28, 0),
                    )?;
                }
            }
        }
        let _ = palette;
        Ok(())
    }

    fn draw_goal<RT: RenderTarget>(
        &mut self,
        canvas: &mut Canvas<RT>,
        cam: Cam,
        scale: i32,
    ) -> Result<(), String> {
        let pulse = (self.time * 1.8).sin() * 0.5 + 0.5;
        let ready = self.drops >= DROP_COUNT;
        let alpha = if ready { 235 } else { 165 };
        let radius = 44.0 + pulse * 6.0;
        let goal = self.level.goal;
        render::ring(
            canvas,
            cam,
            scale,
            (goal.x, goal.y),
            radius + 2.0,
            3.0,
            40,
            Color::RGBA(8, 16, 18, 90),
        )?;
        render::ring(
            canvas,
            cam,
            scale,
            (goal.x, goal.y),
            radius,
            4.0,
            40,
            Color::RGBA(255, 214, 122, alpha),
        )?;
        render::ring(
            canvas,
            cam,
            scale,
            (goal.x, goal.y),
            radius * 0.60,
            3.0,
            24,
            Color::RGBA(255, 238, 190, (alpha as f32 * 0.8) as u8),
        )?;
        if ready {
            for i in 0..5 {
                let a = self.time * 1.4 + i as f32 * 1.256;
                let r = 20.0 + (self.time * 2.0 + i as f32).sin() * 10.0;
                render::fill_rect(
                    canvas,
                    cam,
                    scale,
                    Rect::new(goal.x + a.cos() * r, goal.y + a.sin() * r * 0.7, 4.0, 4.0),
                    Color::RGBA(250, 240, 200, 220),
                )?;
            }
        }
        Ok(())
    }

    fn draw_player<RT: RenderTarget>(
        &mut self,
        canvas: &mut Canvas<RT>,
        cam: Cam,
        scale: i32,
    ) -> Result<(), String> {
        let p = &self.player;
        let wl = self.level.waterline(p.pos.x);
        let speed = p.vel.x.abs();

        // Sheet layout: idle 0..1, run 2..5, spin ball 6..8.
        let computed = if p.in_water {
            2 + (self.time * 7.0) as usize % 4
        } else if !p.on_ground {
            6 + (self.time * 18.0) as usize % 3
        } else if speed > 40.0 {
            2 + (p.song * 6.0) as usize % 4
        } else if (self.time * 1.8).sin() > 0.0 {
            1
        } else {
            0
        };
        let frame = self.frame_override.unwrap_or(computed);
        let spinning = frame >= 6;

        let sq = p.squash();
        let fw = self.assets.cat_frame_w * 2.0;
        let fh = self.assets.cat_frame_h * 2.0;
        let (w, h) = if spinning {
            (fw, fh)
        } else {
            (fw * (1.0 + (1.0 - sq) * 0.5), fh * sq)
        };
        let (x, y) = if spinning {
            // The ball frame is centred on the body, not on the feet.
            let c = p.center();
            (c.x - w * 0.5, c.y - h * 0.5)
        } else {
            let bottom = if p.in_water { wl + 8.0 } else { p.pos.y };
            (p.pos.x - w * 0.5, bottom - h)
        };

        let shadow_y = if p.in_water { wl + 5.0 } else { p.pos.y };
        let (sw, sh) = if spinning { (26.0, 3.0) } else { (34.0, 4.0) };
        render::fill_rect(
            canvas,
            cam,
            scale,
            Rect::new(p.pos.x - sw * 0.5, shadow_y - sh * 0.5, sw, sh),
            Color::RGBA(6, 14, 14, 80),
        )?;

        if self.invuln > 0.0 && (self.time * 22.0).sin() < 0.0 {
            return Ok(());
        }
        let src = SdlRect::new(
            (frame as u32 * self.assets.cat_frame_w as u32) as i32,
            0,
            self.assets.cat_frame_w as u32,
            self.assets.cat_frame_h as u32,
        );
        render::draw_texture_frame(
            canvas,
            cam,
            scale,
            &self.assets.cat,
            src,
            Rect::new(x, y, w, h),
            p.facing < 0.0,
        )?;

        if p.in_water {
            let ripple = (self.time * 1.6).sin() * 3.0;
            render::ring(
                canvas,
                cam,
                scale,
                (p.pos.x, wl + 6.0),
                34.0 + ripple,
                2.0,
                14,
                Color::RGBA(226, 242, 246, 70),
            )?;
        }
        Ok(())
    }

    fn draw_particles<RT: RenderTarget>(
        &mut self,
        canvas: &mut Canvas<RT>,
        cam: Cam,
        scale: i32,
    ) -> Result<(), String> {
        for p in &self.particles.items {
            let a = (Particles::alpha(p) * 255.0) as u8;
            render::fill_rect(
                canvas,
                cam,
                scale,
                Rect::new(p.pos.x, p.pos.y, p.size, p.size),
                Color::RGBA(p.color.0, p.color.1, p.color.2, a),
            )?;
        }
        Ok(())
    }

    fn draw_debug<RT: RenderTarget>(
        &mut self,
        canvas: &mut Canvas<RT>,
        cam: Cam,
        scale: i32,
    ) -> Result<(), String> {
        for p in &self.level.platforms {
            render::fill_rect(
                canvas,
                cam,
                scale,
                Rect::new(p.x, p.y, p.w, 1.0),
                Color::RGBA(255, 0, 220, 220),
            )?;
            render::fill_rect(
                canvas,
                cam,
                scale,
                Rect::new(p.x, p.y, 1.0, p.h),
                Color::RGBA(255, 0, 220, 90),
            )?;
        }
        let hb = self.player.hitbox();
        render::fill_rect(
            canvas,
            cam,
            scale,
            Rect::new(hb.x, hb.y, hb.w, 1.0),
            Color::RGBA(0, 255, 180, 220),
        )?;
        render::fill_rect(
            canvas,
            cam,
            scale,
            Rect::new(hb.x, hb.bottom() - 1.0, hb.w, 1.0),
            Color::RGBA(0, 255, 180, 220),
        )?;
        render::fill_rect(
            canvas,
            cam,
            scale,
            Rect::new(self.level.goal.x - 3.0, self.level.goal.y - 3.0, 6.0, 6.0),
            Color::RGBA(255, 240, 0, 220),
        )?;
        Ok(())
    }

    fn draw_hud<RT: RenderTarget>(
        &mut self,
        canvas: &mut Canvas<RT>,
        scale: i32,
    ) -> Result<(), String> {
        let palette = self.assets.palette;
        let cam = Cam::default();
        let left = 48.0;
        let top = 42.0;

        render::fill_rect(
            canvas,
            cam,
            scale,
            Rect::new(26.0, 24.0, DROP_COUNT as f32 * 30.0 + 118.0, 58.0),
            Color::RGBA(6, 12, 13, 84),
        )?;

        for i in 0..DROP_COUNT {
            let x = left + i as f32 * 30.0;
            let filled = i < self.drops;
            let (body, hi) = if filled {
                (palette.foam, palette.cream)
            } else {
                (
                    Color::RGBA(122, 150, 158, 210),
                    Color::RGBA(196, 214, 214, 190),
                )
            };
            // Ink silhouette first: the icon stays readable over sky or rock.
            for (rx, ry, rw, rh) in [
                (x + 3.0, top - 1.0, 6.0, 4.0),
                (x + 1.0, top + 3.0, 10.0, 4.0),
                (x - 1.0, top + 7.0, 14.0, 8.0),
                (x + 1.0, top + 15.0, 10.0, 4.0),
            ] {
                render::fill_rect(
                    canvas,
                    cam,
                    scale,
                    Rect::new(rx, ry, rw, rh),
                    Color::RGBA(8, 14, 15, 190),
                )?;
            }
            for (rx, ry, rw, rh) in [
                (x + 4.0, top, 4.0, 3.0),
                (x + 2.0, top + 3.0, 8.0, 4.0),
                (x, top + 7.0, 12.0, 8.0),
                (x + 2.0, top + 15.0, 8.0, 3.0),
            ] {
                render::fill_rect(canvas, cam, scale, Rect::new(rx, ry, rw, rh), body)?;
            }
            render::fill_rect(
                canvas,
                cam,
                scale,
                Rect::new(x + 2.0, top + 7.0, 2.0, 3.0),
                hi,
            )?;
        }

        render::text_shadow(
            canvas,
            cam,
            scale,
            left + DROP_COUNT as f32 * 30.0 + 12.0,
            top + 2.0,
            &format!("{}/{}", self.drops, DROP_COUNT),
            4,
            palette.cream,
            palette.ink,
        )?;

        if self.hint > 0.0 {
            let alpha = (self.hint.min(1.0) * 235.0) as u8;
            render::text_centered(
                canvas,
                cam,
                scale,
                VIEW_W * 0.5,
                VIEW_H - 76.0,
                "A D — БЕГ · ПРОБЕЛ — ПРЫЖОК · J — ШАРИК · S — НЫРЯТЬ",
                3,
                Color::RGBA(246, 238, 212, alpha),
                Color::RGBA(8, 14, 15, alpha),
            )?;
        }

        if self.toast > 0.0 {
            let alpha = (self.toast.min(1.0) * 235.0) as u8;
            render::text_centered(
                canvas,
                cam,
                scale,
                VIEW_W * 0.5,
                VIEW_H * 0.5 - 210.0,
                &self.toast_text,
                4,
                Color::RGBA(246, 238, 212, alpha),
                Color::RGBA(8, 14, 15, alpha),
            )?;
        }

        // Hearts.
        for i in 0..3 {
            let x = left + i as f32 * 26.0;
            let y = top + 42.0;
            let col = if (i as i32) < self.hearts {
                Color::RGBA(228, 74, 74, 245)
            } else {
                Color::RGBA(40, 30, 32, 170)
            };
            for (rx, ry, rw, rh) in [
                (x + 2.0, y, 2.0, 2.0),
                (x + 6.0, y, 2.0, 2.0),
                (x, y + 2.0, 10.0, 4.0),
                (x + 2.0, y + 6.0, 6.0, 2.0),
                (x + 4.0, y + 8.0, 2.0, 2.0),
            ] {
                render::fill_rect(canvas, cam, scale, Rect::new(rx, ry, rw, rh), col)?;
            }
        }
        // Rings.
        let rx = left + 3.0 * 26.0 + 18.0;
        let ry = top + 46.0;
        render::ring(
            canvas,
            cam,
            scale,
            (rx, ry),
            8.0,
            3.0,
            10,
            Color::RGBA(250, 214, 110, 240),
        )?;
        render::text_shadow(
            canvas,
            cam,
            scale,
            rx + 14.0,
            top + 38.0,
            &format!("{}", self.rings_taken),
            3,
            palette.cream,
            palette.ink,
        )?;

        // Build badges.
        let mut bx = left + 3.0 * 26.0 + 86.0;
        for upgrade in Upgrade::all() {
            if self.builds[upgrade.index()] > 0 {
                let col = match upgrade {
                    Upgrade::Speed => Color::RGBA(250, 206, 90, 240),
                    Upgrade::Jump => Color::RGBA(120, 190, 255, 240),
                    Upgrade::Magnet => Color::RGBA(196, 140, 250, 240),
                    Upgrade::Shield => Color::RGBA(120, 220, 160, 240),
                };
                render::fill_rect(
                    canvas,
                    cam,
                    scale,
                    Rect::new(bx, top + 38.0, 12.0, 12.0),
                    col,
                )?;
                bx += 18.0;
            }
        }

        render::text_shadow(
            canvas,
            cam,
            scale,
            48.0,
            VIEW_H - 42.0,
            &format!("МЕХАНИКА: {}", self.mechanics.label()),
            2,
            Color::RGBA(246, 238, 212, 200),
            palette.ink,
        )?;

        // Director readout: the fun metric the critic maximised.
        render::text_right(
            canvas,
            cam,
            scale,
            VIEW_W - 46.0,
            40.0,
            &format!("ФАН {:.2}", self.fun),
            3,
            palette.cream,
            palette.ink,
        )?;
        render::text_right(
            canvas,
            cam,
            scale,
            VIEW_W - 46.0,
            70.0,
            &format!("НОВИЗНА {:.2}", self.novelty),
            2,
            Color::RGBA(206, 220, 210, 210),
            palette.ink,
        )?;
        let bar_w = 150.0;
        render::fill_rect(
            canvas,
            cam,
            scale,
            Rect::new(VIEW_W - 46.0 - bar_w, 104.0, bar_w, 6.0),
            Color::RGBA(8, 14, 15, 150),
        )?;
        render::fill_rect(
            canvas,
            cam,
            scale,
            Rect::new(
                VIEW_W - 46.0 - bar_w,
                104.0,
                bar_w * self.fun.clamp(0.0, 1.0),
                6.0,
            ),
            Color::RGBA(250, 214, 110, 220),
        )?;

        if self.scenario_t > 0.0 {
            let alpha = (self.scenario_t.min(1.0) * 235.0) as u8;
            render::text_centered(
                canvas,
                cam,
                scale,
                VIEW_W * 0.5,
                150.0,
                &format!("СЦЕНАРИЙ: {} · ФАН {:.2}", self.scenario, self.fun),
                3,
                Color::RGBA(246, 238, 212, alpha),
                Color::RGBA(8, 14, 15, alpha),
            )?;
        }

        Ok(())
    }

    fn draw_overlay<RT: RenderTarget>(
        &mut self,
        canvas: &mut Canvas<RT>,
        scale: i32,
    ) -> Result<(), String> {
        let palette = self.assets.palette;
        let cam = Cam::default();
        match self.state {
            State::Title => {
                let fade = (self.title_t / 0.9).clamp(0.0, 1.0);
                render::fill_rect(
                    canvas,
                    cam,
                    scale,
                    Rect::new(0.0, 0.0, VIEW_W, VIEW_H),
                    Color::RGBA(6, 12, 13, (90.0 * fade) as u8),
                )?;
                render::text_centered(
                    canvas,
                    cam,
                    scale,
                    VIEW_W * 0.5,
                    352.0,
                    "К ВОДОПАДУ",
                    11,
                    palette.cream,
                    palette.ink,
                )?;
                render::text_centered(
                    canvas,
                    cam,
                    scale,
                    VIEW_W * 0.5,
                    462.0,
                    "КОТИК БЕЖИТ К БОЛЬШОЙ ВОДЕ",
                    3,
                    Color::RGBA(230, 236, 220, 220),
                    palette.ink,
                )?;
                let blink = ((self.title_t * 2.2).sin() * 0.5 + 0.5) * 0.65 + 0.35;
                render::text_centered(
                    canvas,
                    cam,
                    scale,
                    VIEW_W * 0.5,
                    700.0,
                    "ПРОБЕЛ — НАЧАТЬ",
                    4,
                    Color::RGBA(246, 238, 212, (blink * 240.0) as u8),
                    palette.ink,
                )?;
                render::text_centered(
                    canvas,
                    cam,
                    scale,
                    VIEW_W * 0.5,
                    820.0,
                    "7 КАПЕЛЬ · ОДИН ВОДОПАД",
                    2,
                    Color::RGBA(210, 220, 206, 170),
                    palette.ink,
                )?;
            }
            State::Won => {
                let fade = (self.won_t / 0.7).clamp(0.0, 1.0);
                render::fill_rect(
                    canvas,
                    cam,
                    scale,
                    Rect::new(0.0, 0.0, VIEW_W, VIEW_H),
                    Color::RGBA(6, 12, 13, (110.0 * fade) as u8),
                )?;
                render::text_centered(
                    canvas,
                    cam,
                    scale,
                    VIEW_W * 0.5,
                    360.0,
                    "ВОДОПАД!",
                    11,
                    palette.cream,
                    palette.ink,
                )?;
                render::text_centered(
                    canvas,
                    cam,
                    scale,
                    VIEW_W * 0.5,
                    470.0,
                    "7 КАПЕЛЬ ИЗ 7",
                    4,
                    Color::RGBA(224, 238, 240, 235),
                    palette.ink,
                )?;
                render::text_centered(
                    canvas,
                    cam,
                    scale,
                    VIEW_W * 0.5,
                    540.0,
                    "КОТИК ДОБРАЛСЯ ДО БОЛЬШОЙ ВОДЫ",
                    3,
                    Color::RGBA(224, 232, 214, 220),
                    palette.ink,
                )?;
                render::text_centered(
                    canvas,
                    cam,
                    scale,
                    VIEW_W * 0.5,
                    720.0,
                    "R — ЕЩЁ РАЗ · ESC — ВЫХОД",
                    3,
                    Color::RGBA(246, 238, 212, 220),
                    palette.ink,
                )?;
            }
            State::Lost => {
                let fade = (self.lost_t / 0.7).clamp(0.0, 1.0);
                render::fill_rect(
                    canvas,
                    cam,
                    scale,
                    Rect::new(0.0, 0.0, VIEW_W, VIEW_H),
                    Color::RGBA(20, 8, 10, (120.0 * fade) as u8),
                )?;
                render::text_centered(
                    canvas,
                    cam,
                    scale,
                    VIEW_W * 0.5,
                    360.0,
                    "КОТИК УСТАЛ",
                    10,
                    Color::RGBA(250, 226, 220, 240),
                    palette.ink,
                )?;
                render::text_centered(
                    canvas,
                    cam,
                    scale,
                    VIEW_W * 0.5,
                    470.0,
                    &format!(
                        "ФАН {:.2} · КОЛЬЦА {} · СЦЕНАРИИ {}",
                        self.fun,
                        self.rings_taken,
                        self.director.campaign.len()
                    ),
                    3,
                    Color::RGBA(236, 220, 210, 230),
                    palette.ink,
                )?;
                render::text_centered(
                    canvas,
                    cam,
                    scale,
                    VIEW_W * 0.5,
                    720.0,
                    "R — ЕЩЁ РАЗ · ESC — ВЫХОД",
                    3,
                    Color::RGBA(246, 238, 212, 220),
                    palette.ink,
                )?;
            }
            State::Play => {}
        }
        Ok(())
    }
}

fn home_camera(from: Vec2) -> Vec2 {
    Vec2::new(
        (from.x + 70.0 - VIEW_W * 0.5).clamp(0.0, WORLD_W - VIEW_W),
        (from.y - 110.0 - VIEW_H * 0.5).clamp(0.0, WORLD_H - VIEW_H),
    )
}

fn drops_word(n: usize) -> &'static str {
    match n % 10 {
        1 if n % 100 != 11 => "КАПЛЯ",
        2..=4 if !(12..=14).contains(&(n % 100)) => "КАПЛИ",
        _ => "КАПЕЛЬ",
    }
}

fn save_ppm<RT: RenderTarget>(canvas: &Canvas<RT>, path: &str) -> Result<(), String> {
    let (w, h) = canvas.output_size()?;
    let pixels = canvas
        .read_pixels(None, PixelFormatEnum::RGB24)
        .map_err(|e| e.to_string())?;
    let mut out = std::fs::File::create(path).map_err(|e| e.to_string())?;
    write!(out, "P6\n{} {}\n255\n", w, h).map_err(|e| e.to_string())?;
    out.write_all(&pixels).map_err(|e| e.to_string())?;
    Ok(())
}

fn main() -> Result<(), String> {
    let args: Vec<String> = std::env::args().collect();
    let flag = |name: &str| args.iter().any(|a| a == name);
    let value = |name: &str| {
        args.iter()
            .position(|a| a == name)
            .and_then(|i| args.get(i + 1))
            .cloned()
    };

    if flag("--help") || flag("-h") {
        println!(
            "catwalk — a miniature cat platformer on the waterfall wallpaper\n\n\
             USAGE: catwalk [OPTIONS]\n\n\
             OPTIONS:\n\
             \x20 --shot PATH      render one 1920x1080 frame to a PPM and exit\n\
             \x20 --cam X,Y        camera position for --shot\n\
             \x20 --time SECS      animation clock for --shot\n\
             \x20 --state S        title | play | won (for --shot)\n\
             \x20 --pos X,Y        spawn position (QA)\n\
             \x20 --frame N        force sprite-sheet frame 0..8 (QA)\n\
             \x20 --warmup SECS    simulate before a --shot (QA)\n\
             \x20 --seed N         director seed (default 0x5EED)\n\
             \x20 --metrics PATH   write the run's fun metrics as JSON\n\
             \x20 --study N        simulate N campaigns headlessly and report\n\
             \x20 --mechanics N    generate N mechanics, report the best\n\
             \x20 --mechanics-json P  write the mechanics lab as JSON\n\
             \x20 --study-json P   write the study report as JSON\n\
             \x20 --study-threads T  worker threads for --study\n\
             \x20 --debug          draw platform and hitbox outlines\n\
             \x20 --clean          background only (pixel comparison)\n\n\
             KEYS: A/D or arrows walk, Space jump, S dive, R restart, F11 fullscreen,\n\
             \x20     F12 screenshot to /tmp/catwalk.ppm, Esc quit"
        );
        return Ok(());
    }

    if let Some(runs) = value("--mechanics").and_then(|v| v.parse::<u64>().ok()) {
        let base = value("--seed")
            .and_then(|v| v.parse::<u32>().ok())
            .unwrap_or(0xC0FF_EE11);
        let lab = mechanics::run_lab(runs, base);
        print!("{}", lab.report());
        if let Some(path) = value("--mechanics-json") {
            let _ = std::fs::write(path, lab.json());
        }
        return Ok(());
    }

    if let Some(runs) = value("--study").and_then(|v| v.parse::<u64>().ok()) {
        let threads = value("--study-threads")
            .and_then(|v| v.parse::<usize>().ok())
            .unwrap_or_else(|| {
                std::thread::available_parallelism()
                    .map(|v| v.get())
                    .unwrap_or(8)
            });
        let base = value("--study-seed")
            .and_then(|v| v.parse::<u32>().ok())
            .unwrap_or(0xC0FF_EE11);
        let study = study::run_study(runs, threads, base);
        print!("{}", study.report());
        if let Some(path) = value("--study-json") {
            let _ = std::fs::write(path, study.json());
        }
        return Ok(());
    }

    let shot = value("--shot");
    let clean = flag("--clean");
    let debug = flag("--debug");
    let headless = shot.is_some();

    let forced_cam = value("--cam").map(|s| {
        let mut it = s.split(',');
        let x = it.next().and_then(|v| v.parse::<f32>().ok()).unwrap_or(0.0);
        let y = it.next().and_then(|v| v.parse::<f32>().ok()).unwrap_or(0.0);
        Vec2::new(x, y)
    });
    let forced_time = value("--time").and_then(|v| v.parse::<f32>().ok());
    let forced_state = value("--state").unwrap_or_else(|| "title".into());
    let seed = value("--seed")
        .and_then(|v| v.parse::<u32>().ok())
        .unwrap_or(0x5EED);
    let metrics_path = value("--metrics");

    let sdl = sdl2::init()?;
    let _ = sdl2::hint::set("SDL_RENDER_SCALE_QUALITY", "0");
    let video = sdl.video()?;

    let window = if headless {
        video
            .window("crabwalk", VIEW_W as u32, VIEW_H as u32)
            .hidden()
            .build()
            .map_err(|e| e.to_string())?
    } else {
        video
            .window(
                "crabwalk",
                (VIEW_W as i32 * SCALE) as u32,
                (VIEW_H as i32 * SCALE) as u32,
            )
            .position_centered()
            .fullscreen_desktop()
            .allow_highdpi()
            .build()
            .map_err(|e| e.to_string())?
    };

    let mut canvas = window
        .into_canvas()
        .accelerated()
        .present_vsync()
        .build()
        .map_err(|e| e.to_string())?;

    let creator: TextureCreator<WindowContext> = canvas.texture_creator();
    let assets = Assets::load(&creator)?;
    let mut game = Game::new(assets, debug, seed);
    game.clean = clean;
    game.metrics_path = metrics_path;
    game.apply_mechanics();
    println!(
        "catwalk seed: {seed} (mechanics: {})",
        game.mechanics.label()
    );

    if let Some(time) = forced_time {
        game.time = time;
    }
    match forced_state.as_str() {
        "play" => {
            game.state = State::Play;
            game.hint = 0.0;
        }
        "won" => {
            game.state = State::Won;
            game.drops = DROP_COUNT;
            game.won_t = 2.0;
        }
        _ => {}
    }
    if let Some(frame) = value("--frame") {
        game.frame_override = frame.parse::<usize>().ok().map(|f| f.min(8));
    }
    if let Some(pos) = value("--pos") {
        let mut it = pos.split(',');
        let x = it.next().and_then(|v| v.parse::<f32>().ok());
        let y = it.next().and_then(|v| v.parse::<f32>().ok());
        if let (Some(x), Some(y)) = (x, y) {
            game.player.pos = Vec2::new(x, y);
            game.cam = home_camera(Vec2::new(x, y));
        }
    }
    if flag("--fire") {
        let c = game.player.center();
        game.hairballs.push(gameplay::Hairball {
            pos: c + Vec2::new(game.player.facing * 36.0, 4.0),
            vel: Vec2::new(game.player.facing * 920.0, -80.0),
            life: 1.5,
            bounces: 0,
        });
    }
    if let Some(cam) = forced_cam {
        game.cam = Vec2::new(
            cam.x.clamp(0.0, WORLD_W - VIEW_W),
            cam.y.clamp(0.0, WORLD_H - VIEW_H),
        );
    }
    if let Some(secs) = value("--warmup").and_then(|v| v.parse::<f32>().ok()) {
        let dt = 1.0 / 60.0;
        let idle = Input::default();
        for _ in 0..(secs * 60.0) as usize {
            game.update(dt, &idle, false);
        }
    }

    if let Some(path) = shot {
        let mut target = creator
            .create_texture_target(PixelFormatEnum::RGBA32, VIEW_W as u32, VIEW_H as u32)
            .map_err(|e| e.to_string())?;
        let mut pixels: Vec<u8> = Vec::new();
        let mut failure: Option<String> = None;
        canvas
            .with_texture_canvas(&mut target, |c| {
                if let Err(e) = game.draw(c, 1) {
                    failure = Some(e);
                    return;
                }
                match c.read_pixels(None, PixelFormatEnum::RGB24) {
                    Ok(bytes) => pixels = bytes,
                    Err(e) => failure = Some(e),
                }
            })
            .map_err(|e| e.to_string())?;
        if let Some(e) = failure {
            return Err(e);
        }
        let mut out = std::fs::File::create(&path).map_err(|e| e.to_string())?;
        write!(out, "P6\n{} {}\n255\n", VIEW_W, VIEW_H).map_err(|e| e.to_string())?;
        out.write_all(&pixels).map_err(|e| e.to_string())?;
        game.write_metrics();
        println!("saved {path}");
        return Ok(());
    }

    let mut events = sdl.event_pump()?;
    let mut timer = Instant::now();
    let mut start_pressed = false;
    let mut jump_pressed = false;
    let mut fire_pressed = false;

    'run: loop {
        let dt = timer.elapsed().as_secs_f32().min(1.0 / 30.0);
        timer = Instant::now();

        for event in events.poll_iter() {
            match event {
                Event::Quit { .. } => break 'run,
                Event::KeyDown {
                    keycode: Some(key),
                    repeat,
                    ..
                } => {
                    if key == Keycode::Escape {
                        break 'run;
                    }
                    if key == Keycode::F12 {
                        if let Err(e) = save_ppm(&canvas, "/tmp/catwalk.ppm") {
                            eprintln!("screenshot failed: {e}");
                        }
                    }
                    if key == Keycode::R && matches!(game.state, State::Won | State::Lost) {
                        game.reset();
                    }
                    if !repeat
                        && matches!(
                            key,
                            Keycode::Space
                                | Keycode::Return
                                | Keycode::R
                                | Keycode::W
                                | Keycode::Up
                                | Keycode::Z
                        )
                    {
                        jump_pressed = true;
                    }
                    if !repeat && matches!(key, Keycode::Space | Keycode::Return) {
                        start_pressed = true;
                    }
                    if !repeat && matches!(key, Keycode::J | Keycode::X) {
                        fire_pressed = true;
                    }
                }
                _ => {}
            }
        }

        let keys = events.keyboard_state();
        let input = Input {
            left: keys.is_scancode_pressed(Scancode::A) || keys.is_scancode_pressed(Scancode::Left),
            right: keys.is_scancode_pressed(Scancode::D)
                || keys.is_scancode_pressed(Scancode::Right),
            down: keys.is_scancode_pressed(Scancode::S) || keys.is_scancode_pressed(Scancode::Down),
            jump_held: keys.is_scancode_pressed(Scancode::Space)
                || keys.is_scancode_pressed(Scancode::W)
                || keys.is_scancode_pressed(Scancode::Up)
                || keys.is_scancode_pressed(Scancode::Z),
            jump_pressed,
            fire_pressed,
        };

        game.update(dt, &input, start_pressed);
        jump_pressed = false;
        fire_pressed = false;
        start_pressed = false;

        game.draw(&mut canvas, SCALE)?;
        canvas.present();

        // The panel runs at 240 Hz; the game does not need it. Cap the loop at
        // 60 fps to keep the fans quiet, still well above the animation rate.
        let budget = std::time::Duration::from_micros(16_600);
        let spent = timer.elapsed();
        if spent < budget {
            std::thread::sleep(budget - spent);
        }
    }

    Ok(())
}
