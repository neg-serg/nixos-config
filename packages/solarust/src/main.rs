use anyhow::Result;
use crossterm::{
    cursor::{Hide, Show},
    event::{self, Event, KeyCode},
    execute,
    terminal::{self, EnterAlternateScreen, LeaveAlternateScreen},
};
use rand::Rng;
use std::io::{stdout, Write};
use std::time::{Duration, Instant};

// ── Planet names from real solar system objects ──
const PLANET_NAMES: &[&str] = &[
    "Mercury", "Venus", "Terra",  "Mars",   "Ceres",  "Vesta",
    "Pallas",  "Juno",  "Hygiea", "Europa", "Ganymede","Callisto",
    "Titan",   "Rhea",  "Iapetus","Dione",  "Tethys", "Enceladus",
    "Mimas",   "Phobos","Deimos", "Io",     "Charon", "Nix",
    "Hydra",   "Styx",  "Kerberos","Orcus", "Quaoar", "Sedna",
    "Makemake","Haumea","Eris",   "Dysnomia","Gonggong","Ixion",
    "Varuna",  "Chaos", "Nyx",    "Asbolus","Chiron", "Pholus",
    "Nessus",  "Bienor", "Telesto","Calypso","Janus", "Epimetheus",
];

const COLORS: &[(&str, u8)] = &[
    ("red",       196),
    ("orange",    208),
    ("yellow",    226),
    ("green",     46),
    ("cyan",      51),
    ("blue",      33),
    ("purple",    129),
    ("magenta",   201),
    ("pink",      213),
    ("teal",      43),
    ("lime",      154),
    ("gold",      220),
    ("coral",     203),
    ("sky",       117),
    ("lavender",  183),
    ("mint",      157),
];

const PLANET_CHARS: &[char] = &['●', '◉', '◆', '★', '⚫', '◈', '⬟', '⬢', '⏣'];

// ── Planet struct ──
struct Planet {
    name: &'static str,
    color: u8,
    ch: char,
    orbit_radius: f64,
    angle: f64,
    angular_velocity: f64,
    has_ring: bool,
    moons: Vec<Moon>,
}

struct Moon {
    orbit_radius: f64,
    angle: f64,
    angular_velocity: f64,
}

impl Planet {
    fn random(rng: &mut impl Rng, index: usize, name: &'static str) -> Self {
        let color = COLORS[rng.gen_range(0..COLORS.len())].1;
        let ch = PLANET_CHARS[rng.gen_range(0..PLANET_CHARS.len())];
        let orbit_radius = 3.0 + index as f64 * 2.5 + rng.gen_range(0.0..1.8);
        let angle = rng.gen_range(0.0..std::f64::consts::TAU);
        let angular_velocity = 0.08 / (1.0 + index as f64 * 0.2) + rng.gen_range(0.0..0.01);
        let has_ring = index > 0 && rng.gen_bool(0.25);
        let n_moons = if index > 0 && rng.gen_bool(0.4) {
            rng.gen_range(1..=3)
        } else {
            0
        };
        let moons = (0..n_moons)
            .map(|_| {
                let mr = 0.6 + rng.gen_range(0.0..0.6);
                let ma = rng.gen_range(0.0..std::f64::consts::TAU);
                let mv = 0.3 + rng.gen_range(0.0..0.3);
                Moon {
                    orbit_radius: mr,
                    angle: ma,
                    angular_velocity: mv,
                }
            })
            .collect();

        Self {
            name,
            color,
            ch,
            orbit_radius,
            angle,
            angular_velocity,
            has_ring,
            moons,
        }
    }

    fn update(&mut self) {
        self.angle += self.angular_velocity;
        for moon in &mut self.moons {
            moon.angle += moon.angular_velocity;
        }
    }
}

// ── Asteroid Belt ──
#[allow(dead_code)]
struct AsteroidBelt {
    inner_radius: f64,
    outer_radius: f64,
    asteroids: Vec<(f64, f64)>, // (angle, radius offset)
}

impl AsteroidBelt {
    fn random(rng: &mut impl Rng, inner: f64, outer: f64) -> Self {
        let n = rng.gen_range(60..=120);
        let asteroids = (0..n)
            .map(|_| {
                let angle = rng.gen_range(0.0..std::f64::consts::TAU);
                let r = rng.gen_range(inner..outer);
                (angle, r)
            })
            .collect();
        Self {
            inner_radius: inner,
            outer_radius: outer,
            asteroids,
        }
    }
}

// ── Terminal helpers ──
fn goto(x: usize, y: usize) {
    print!("\x1b[{};{}H", y + 1, x + 1);
}

fn color_tile(ch: char, color: u8, x: usize, y: usize) {
    goto(x, y);
    print!("\x1b[38;5;{}m{}\x1b[0m", color, ch);
}

fn color_str(s: &str, color: u8) -> String {
    format!("\x1b[38;5;{}m{}\x1b[0m", color, s)
}

fn dim_str(s: &str) -> String {
    format!("\x1b[2m{}\x1b[0m", s)
}

// ── Main ──
fn main() -> Result<()> {
    let mut rng = rand::thread_rng();
    let mut stdout = stdout();

    // Terminal setup
    terminal::enable_raw_mode()?;
    execute!(stdout, EnterAlternateScreen, Hide)?;

    let (w, h) = terminal::size()?;
    let w = w as usize;
    let h = h as usize;
    let cx = w as f64 / 2.0;
    let cy = h as f64 / 2.0;

    // Generate random system
    let n_planets = rng.gen_range(4..=10);

    // Pick unique names
    let mut name_indices: Vec<usize> = (0..PLANET_NAMES.len()).collect();
    use rand::seq::SliceRandom;
    name_indices.shuffle(&mut rng);
    let selected_names: Vec<&str> = name_indices
        .iter()
        .take(n_planets)
        .map(|&i| PLANET_NAMES[i])
        .collect();

    let mut planets: Vec<Planet> = selected_names
        .into_iter()
        .enumerate()
        .map(|(i, name)| Planet::random(&mut rng, i, name))
        .collect();

    // Asteroid belt if enough room
    let belt = if n_planets >= 5 {
        let inner = planets[1].orbit_radius + 1.5;
        let outer = planets[2].orbit_radius - 0.5;
        if outer > inner + 1.0 {
            Some(AsteroidBelt::random(&mut rng, inner, outer))
        } else {
            None
        }
    } else {
        None
    };

    let mut frame = 0u64;
    let start = Instant::now();

    loop {
        // Non-blocking input
        if event::poll(Duration::from_millis(16))? {
            if let Event::Key(key) = event::read()? {
                match key.code {
                    KeyCode::Char('q') | KeyCode::Char('Q') | KeyCode::Esc => break,
                    _ => {}
                }
            }
        }

        // Clear
        print!("\x1b[2J");

        // ── Header ──
        goto(0, 0);
        let elapsed = start.elapsed().as_secs_f64();
        print!(
            "{} solarust {}",
            color_str("✦", 220),
            dim_str(&format!(
                "frame {}  time {:>7.1}s  planets {}  q to quit",
                frame, elapsed, n_planets
            ))
        );

        // ── Sun ──
        let sx = cx as usize;
        let sy = (cy - 1.0) as usize;
        let sun_label_y = if sy >= 2 { sy - 2 } else { 0 };
        goto(sx - 2, sun_label_y);
        print!("{}", color_str("☀ Sun", 220));
        // Sun glow: multiple rings
        for r in 1..=5 {
            let step = 12;
            for i in 0..step {
                let a = (i as f64 / step as f64) * std::f64::consts::TAU;
                let ex = (cx + r as f64 * a.cos()) as usize;
                let ey = (cy - 1.0 + r as f64 * a.sin() * 0.5) as usize;
                if ex < w && ey < h {
                    let brightness = 232 + (r * 4).min(23);
                    color_tile('·', brightness, ex, ey);
                }
            }
        }
        color_tile('☀', 226, sx, sy); // bright yellow sun

        // ── Orbits (faint dotted rings) ──
        for planet in &planets {
            let steps = 60.max((planet.orbit_radius * 8.0) as usize);
            for i in 0..steps {
                let a = (i as f64 / steps as f64) * std::f64::consts::TAU;
                let ox = (cx + planet.orbit_radius * a.cos()) as usize;
                let oy = (cy - 1.0 + planet.orbit_radius * a.sin() * 0.5) as usize;
                if ox < w && oy < h {
                    goto(ox, oy);
                    print!("{}", dim_str("·"));
                }
            }
        }

        // ── Asteroid belt ──
        if let Some(ref belt) = belt {
            for &(angle, r) in &belt.asteroids {
                let ax = (cx + r * angle.cos()) as usize;
                let ay = (cy - 1.0 + r * angle.sin() * 0.5) as usize;
                if ax < w && ay < h {
                    goto(ax, ay);
                    print!("{}", dim_str("."));
                }
            }
        }

        // ── Planets (sorted by orbit radius for depth) ──
        let mut sorted: Vec<usize> = (0..planets.len()).collect();
        sorted.sort_by(|&a, &b| {
            planets[a]
                .orbit_radius
                .partial_cmp(&planets[b].orbit_radius)
                .unwrap()
        });

        for &idx in &sorted {
            let planet = &planets[idx];
            let px = (cx + planet.orbit_radius * planet.angle.cos()) as usize;
            let py = (cy - 1.0 + planet.orbit_radius * planet.angle.sin() * 0.5) as usize;

            if px < w && py < h {
                // Ring display
                if planet.has_ring {
                    for ri in 1..=2 {
                        let rx = (px as f64 + ri as f64 * planet.angle.cos()) as usize;
                        let ry = (py as f64 + ri as f64 * planet.angle.sin() * 0.5) as usize;
                        if rx < w && ry < h {
                            color_tile('°', planet.color, rx, ry);
                        }
                        let rxo = (px as f64 - ri as f64 * planet.angle.cos()) as usize;
                        let ryo = (py as f64 - ri as f64 * planet.angle.sin() * 0.5) as usize;
                        if rxo < w && ryo < h {
                            color_tile('°', planet.color, rxo, ryo);
                        }
                    }
                }
                color_tile(planet.ch, planet.color, px, py);

                // Moons
                for moon in &planet.moons {
                    let mx = (px as f64 + moon.orbit_radius * moon.angle.cos()) as usize;
                    let my = (py as f64 + moon.orbit_radius * moon.angle.sin() * 0.5) as usize;
                    if mx < w && my < h {
                        color_tile('·', 250, mx, my);
                    }
                }

                // Label
                let label_x = if px + 2 < w - planet.name.len() {
                    px + 2
                } else {
                    px.saturating_sub(planet.name.len() + 1)
                };
                if label_x < w && py < h {
                    goto(label_x, py);
                    print!("{}", color_str(planet.name, planet.color));
                }
            }
        }

        stdout.flush()?;

        // ── Update ──
        for planet in &mut planets {
            planet.update();
        }
        frame += 1;
    }

    // Cleanup
    execute!(stdout, Show, LeaveAlternateScreen)?;
    terminal::disable_raw_mode()?;
    println!(
        "{} solarust finished — {} frames in {:.1}s",
        color_str("✦", 220),
        frame,
        start.elapsed().as_secs_f64()
    );
    Ok(())
}
