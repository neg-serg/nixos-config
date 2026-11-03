// crabwalk — a miniature platformer painted on the waterfall wallpaper.
//
// World rule: one world unit is one wallpaper pixel. The background is copied
// 1:1 (integer scale 2 in windowed play), so a standing-still frame is the
// wallpaper itself; only the crab, the drops and the water overlays move.

mod assets;
mod effects;
mod font;
mod level;
mod math;
mod player;
mod render;

use std::io::Write;
use std::time::Instant;

use sdl2::event::Event;
use sdl2::keyboard::{Keycode, Scancode};
use sdl2::pixels::{Color, PixelFormatEnum};
use sdl2::rect::Rect as SdlRect;
use sdl2::render::{BlendMode, Canvas, RenderTarget, TextureCreator};
use sdl2::video::WindowContext;

use assets::Assets;
use effects::Particles;
use level::{DROP_COUNT, SPAWN, VIEW_H, VIEW_W, WORLD_H, WORLD_W};
use math::{hash01, smooth, Rect, Vec2};
use player::{Input, Player};
use render::Cam;

const SCALE: i32 = 2;

#[derive(Clone, Copy, PartialEq)]
enum State {
    Title,
    Play,
    Won,
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
    drops: usize,
    state: State,
    hint: f32,
    toast: f32,
    toast_text: String,
    clean: bool,
    debug: bool,
    dust_clock: f32,
    mote_clock: f32,
    spray_clock: f32,
    goal_clock: f32,
}

impl<'a> Game<'a> {
    fn new(assets: Assets<'a>, debug: bool) -> Self {
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
            drops: 0,
            state: State::Title,
            hint: 0.0,
            toast: 0.0,
            toast_text: String::new(),
            clean: false,
            debug,
            dust_clock: 0.0,
            mote_clock: 0.0,
            spray_clock: 0.0,
            goal_clock: 0.0,
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

                self.collect_drops();
                self.check_goal();
                self.follow_camera(dt);
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
        let sq = p.squash();
        let w = self.assets.crab_w * (1.0 + (1.0 - sq) * 0.5);
        let h = self.assets.crab_h * sq;
        let wl = self.level.waterline(p.pos.x);
        let bottom = if p.in_water { wl + 8.0 } else { p.pos.y };
        let x = p.pos.x - w * 0.5;
        let y = bottom - h;

        let shadow_y = if p.in_water { wl + 5.0 } else { p.pos.y };
        for (sw, sh, a) in [(34.0, 4.0, 70u8), (22.0, 3.0, 90), (12.0, 2.0, 110)] {
            render::fill_rect(
                canvas,
                cam,
                scale,
                Rect::new(p.pos.x - sw * 0.5, shadow_y - sh * 0.5, sw, sh),
                Color::RGBA(6, 14, 14, a),
            )?;
        }

        self.assets.crab.set_alpha_mod(255);
        render::draw_texture(
            canvas,
            cam,
            scale,
            &self.assets.crab,
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
                "A D — ИДТИ · ПРОБЕЛ — ПРЫЖОК · S — НЫРЯТЬ",
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
                    "КРАБ ИДЁТ К БОЛЬШОЙ ВОДЕ",
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
                    "КРАБ ДОБРАЛСЯ ДО БОЛЬШОЙ ВОДЫ",
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
            "crabwalk — a miniature platformer on the waterfall wallpaper\n\n\
             USAGE: crabwalk [OPTIONS]\n\n\
             OPTIONS:\n\
             \x20 --shot PATH      render one 1920x1080 frame to a PPM and exit\n\
             \x20 --cam X,Y        camera position for --shot\n\
             \x20 --time SECS      animation clock for --shot\n\
             \x20 --state S        title | play | won (for --shot)\n\
             \x20 --pos X,Y        spawn position (QA)\n\
             \x20 --debug          draw platform and hitbox outlines\n\
             \x20 --clean          background only (pixel comparison)\n\n\
             KEYS: A/D or arrows walk, Space jump, S dive, R restart, F11 fullscreen,\n\
             \x20     F12 screenshot to /tmp/crabwalk.ppm, Esc quit"
        );
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
    let mut game = Game::new(assets, debug);
    game.clean = clean;

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
    if let Some(pos) = value("--pos") {
        let mut it = pos.split(',');
        let x = it.next().and_then(|v| v.parse::<f32>().ok());
        let y = it.next().and_then(|v| v.parse::<f32>().ok());
        if let (Some(x), Some(y)) = (x, y) {
            game.player.pos = Vec2::new(x, y);
            game.cam = home_camera(Vec2::new(x, y));
        }
    }
    if let Some(cam) = forced_cam {
        game.cam = Vec2::new(
            cam.x.clamp(0.0, WORLD_W - VIEW_W),
            cam.y.clamp(0.0, WORLD_H - VIEW_H),
        );
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
        println!("saved {path}");
        return Ok(());
    }

    let mut events = sdl.event_pump()?;
    let mut timer = Instant::now();
    let mut start_pressed = false;
    let mut jump_pressed = false;

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
                        if let Err(e) = save_ppm(&canvas, "/tmp/crabwalk.ppm") {
                            eprintln!("screenshot failed: {e}");
                        }
                    }
                    if key == Keycode::R && game.state == State::Won {
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
        };

        game.update(dt, &input, start_pressed);
        jump_pressed = false;
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
