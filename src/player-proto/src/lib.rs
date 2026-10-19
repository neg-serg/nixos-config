//! Player prototype library: Vulkan renderer, text stack, scene primitives and the MPD client.
//!
//! Two binaries build on it: `player-proto` (the startup probe) and `player` (the rmpc-like UI).

use std::time::Instant;

pub mod color;
pub mod config;
pub mod cover;
pub mod gpu;
pub mod mpd;
pub mod panels;
pub mod preload;
pub mod scene;
pub mod skin;
pub mod text;
pub mod theme;
pub mod widgets;

/// Boot clock captured from an ELF `.init_array` constructor, i.e. before Rust's `main`.
/// Used to split "exec -> loader/ctors" from "ctors -> main" in the startup budget.
static mut BOOT_NS_AT_CTOR: i64 = 0;

extern "C" fn ctor_stamp() {
    let mut ts = libc::timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    if unsafe { libc::clock_gettime(libc::CLOCK_BOOTTIME, &mut ts) } == 0 {
        unsafe { BOOT_NS_AT_CTOR = ts.tv_sec * 1_000_000_000 + ts.tv_nsec };
    }
}

#[used]
#[link_section = ".init_array"]
static CTOR_STAMP: extern "C" fn() = ctor_stamp;

// ---------------------------------------------------------------- timing

#[derive(Default)]
pub struct Mark {
    pub name: &'static str,
    pub rel_ms: f64,
    pub age_ms: f64,
}

pub struct Timing {
    t0: Instant,
    pub marks: Vec<Mark>,
}

impl Timing {
    pub fn new() -> Self {
        Self {
            t0: Instant::now(),
            marks: Vec::new(),
        }
    }

    pub fn mark(&mut self, name: &'static str) {
        let rel_ms = self.t0.elapsed().as_secs_f64() * 1000.0;
        let age_ms = process_age_ms().unwrap_or(f64::NAN);
        self.marks.push(Mark {
            name,
            rel_ms,
            age_ms,
        });
    }

    pub fn report(&self, json: bool) {
        if json {
            let body: Vec<String> = self
                .marks
                .iter()
                .map(|m| {
                    format!(
                        "\"{}\":{{\"rel_ms\":{:.3},\"proc_ms\":{:.3}}}",
                        m.name, m.rel_ms, m.age_ms
                    )
                })
                .collect();
            println!("{{\"marks\":{{{}}}}}", body.join(","));
        } else {
            println!("{:<22} {:>10} {:>12}", "mark", "main+ms", "process+ms");
            for m in &self.marks {
                println!("{:<22} {:>10.3} {:>12.3}", m.name, m.rel_ms, m.age_ms);
            }
        }
    }
}

/// Exact age of this process, in milliseconds: CLOCK_BOOTTIME now minus the
/// starttime field of /proc/self/stat. No estimates, no launcher involvement.
pub fn ctor_age_ms() -> Option<f64> {
    let stat = std::fs::read_to_string("/proc/self/stat").ok()?;
    let rest = stat.rsplit_once(')')?.1;
    let start_ticks: f64 = rest.split_whitespace().nth(19)?.parse().ok()?;
    let hz = unsafe { libc::sysconf(libc::_SC_CLK_TCK) } as f64;
    let boot_ns = unsafe { BOOT_NS_AT_CTOR };
    if boot_ns == 0 {
        return None;
    }
    Some(boot_ns as f64 / 1e6 - start_ticks * 1000.0 / hz)
}

pub fn process_age_ms() -> Option<f64> {
    let stat = std::fs::read_to_string("/proc/self/stat").ok()?;
    let rest = stat.rsplit_once(')')?.1;
    // After "comm)", index 0 is the `state` field (field 3), so starttime (22) is index 19.
    let start_ticks: f64 = rest.split_whitespace().nth(19)?.parse().ok()?;
    let hz = unsafe { libc::sysconf(libc::_SC_CLK_TCK) } as f64;
    let mut ts = libc::timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    if unsafe { libc::clock_gettime(libc::CLOCK_BOOTTIME, &mut ts) } != 0 {
        return None;
    }
    let now_ms = ts.tv_sec as f64 * 1000.0 + ts.tv_nsec as f64 / 1e6;
    Some(now_ms - start_ticks * 1000.0 / hz)
}

// ---------------------------------------------------------------- geometry

// ---- layout contract -------------------------------------------------------
//
// `draw_ui` records the rectangles it composes the frame from, so the *invariants* a design
// review cares about (what is centred, what is flush, what shares an edge) can be asserted
// arithmetically instead of guessed from pixels. Enabled only under PLAYER_RECTS so the normal
// run pays nothing.

use std::sync::{Mutex, OnceLock};

static RECTS: Mutex<Vec<(String, [f32; 4])>> = Mutex::new(Vec::new());

fn rects_enabled() -> bool {
    static ON: OnceLock<bool> = OnceLock::new();
    *ON.get_or_init(|| std::env::var("PLAYER_RECTS").is_ok())
}

/// Record one composed element, in logical units.
pub fn record_rect(name: &str, x: f32, y: f32, w: f32, h: f32) {
    if !rects_enabled() {
        return;
    }
    if let Ok(mut v) = RECTS.lock() {
        v.push((name.to_string(), [x, y, w, h]));
    }
}

/// Write the recorded rectangles as JSON lines: `{"name":[x,y,w,h], ...}`.
pub fn dump_rects(path: &str) -> std::io::Result<()> {
    let rects = RECTS.lock().map(|v| v.clone()).unwrap_or_default();
    let mut out = String::from("{");
    for (i, (name, [x, y, w, h])) in rects.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push_str(&format!("\"{name}\":[{x:.2},{y:.2},{w:.2},{h:.2}]"));
    }
    out.push('}');
    std::fs::write(path, out)
}
