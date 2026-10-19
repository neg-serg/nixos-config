//! Startup probe: how long from `execve` to the first useful presented frame.
//!
//! `--frames N` renders N frames and exits, `--shot P` writes the frame offscreen as PPM,
//! `--bench N` reports per-frame cost without the compositor, `--bench-layout N` isolates
//! text shaping, `--hdr` requests an HDR10 swapchain. Timing marks are printed twice:
//! relative to `main` and as the exact process age.

use std::time::Instant;

use ash::vk;

use player_proto::gpu::{create_gpu, Gpu, InitTiming};
use player_proto::scene::DrawList;
use player_proto::text::Fonts;
use player_proto::theme::Face;
use player_proto::{ctor_age_ms, process_age_ms, Timing};

fn build_text_only(fonts: &mut Fonts, q: &mut DrawList, extent: vk::Extent2D) -> usize {
    let (w, h) = (extent.width as f32, extent.height as f32);
    let _ = w;
    let bright = [0.93, 0.95, 0.98, 1.0];
    let dim = [0.45, 0.50, 0.58, 1.0];
    fonts.layout_line(q, "Player", 64.0, 12.0, 26.0, Face::UiSemiBold, bright);
    fonts.layout_line(
        q,
        "symphonia -> resampler -> ringbuf -> cpal",
        200.0,
        22.0,
        15.0,
        Face::UiRegular,
        dim,
    );
    fonts.layout_line(q, "Now playing", 24.0, h * 0.30, 14.0, Face::UiMedium, dim);
    fonts.layout_line(
        q,
        "Vulkan UI prototype / first frame probe",
        24.0,
        h * 0.36,
        30.0,
        Face::UiSemiBold,
        bright,
    );
    fonts.layout_line(
        q,
        "ash + winit + cosmic-text, no GUI framework",
        24.0,
        h * 0.36 + 44.0,
        16.0,
        Face::UiRegular,
        dim,
    );
    0
}

fn build_ui(fonts: &mut Fonts, extent: vk::Extent2D) -> DrawList {
    let mut q = DrawList::new();
    let (w, h) = (extent.width as f32, extent.height as f32);
    let bg = [0.055, 0.063, 0.078, 1.0];
    let panel = [0.086, 0.098, 0.122, 1.0];
    let accent = [0.36, 0.72, 0.98, 1.0];
    let dim = [0.45, 0.50, 0.58, 1.0];
    let bright = [0.93, 0.95, 0.98, 1.0];

    q.rect(0.0, 0.0, w, h, bg);
    q.rect(0.0, 0.0, w, 64.0, panel);
    q.rect(24.0, 18.0, 28.0, 28.0, accent);

    fonts.layout_line(&mut q, "Player", 64.0, 12.0, 26.0, Face::UiRegular, bright);
    fonts.layout_line(
        &mut q,
        "symphonia → resampler → ringbuf → cpal",
        200.0,
        22.0,
        15.0,
        Face::UiRegular,
        dim,
    );

    fonts.layout_line(
        &mut q,
        "Now playing",
        24.0,
        h * 0.30,
        14.0,
        Face::UiRegular,
        dim,
    );
    fonts.layout_line(
        &mut q,
        "Vulkan UI prototype / first frame probe",
        24.0,
        h * 0.36,
        30.0,
        Face::UiSemiBold,
        bright,
    );
    fonts.layout_line(
        &mut q,
        "ash + winit + cosmic-text, no GUI framework",
        24.0,
        h * 0.36 + 44.0,
        16.0,
        Face::UiRegular,
        dim,
    );

    let bar_y = h * 0.62;
    q.rect(24.0, bar_y, w - 48.0, 4.0, panel);
    q.rect(24.0, bar_y, (w - 48.0) * 0.32, 4.0, accent);
    q.rect(20.0, bar_y - 4.0, 12.0, 12.0, bright);

    let bars = 48;
    let gap = 4.0;
    let bw = ((w - 48.0) - gap * (bars as f32 + 1.0)) / bars as f32;
    for i in 0..bars {
        let t = i as f32 / bars as f32;
        let amp =
            (0.15 + 0.85 * ((t * 9.7).sin().abs() * (t * 3.1 + 0.7).cos().abs())).clamp(0.05, 1.0);
        let bh = amp * 90.0;
        let x = 24.0 + gap + i as f32 * (bw + gap);
        let c = if t < 0.32 {
            accent
        } else {
            [0.20, 0.28, 0.36, 1.0]
        };
        q.rect(x, h * 0.74 - bh, bw, bh, c);
    }
    q
}

// ---------------------------------------------------------------- app

struct App {
    timing: Timing,
    json: bool,
    frames_wanted: u32,
    frames_drawn: u32,
    gpu: Option<Gpu>,
    window: Option<winit::window::Window>,
    fonts: Option<Fonts>,
    quads: Option<DrawList>,
    first_present_age_ms: f64,
    shot: Option<String>,
    bench: Option<u32>,
    layout_bench: Option<u32>,
    size: (f64, f64),
}

impl App {
    fn new(timing: Timing, json: bool, frames_wanted: u32) -> Self {
        Self {
            timing,
            json,
            frames_wanted,
            frames_drawn: 0,
            gpu: None,
            window: None,
            fonts: None,
            quads: None,
            first_present_age_ms: f64::NAN,
            shot: None,
            bench: None,
            layout_bench: None,
            size: (1100.0, 620.0),
        }
    }
}

impl winit::application::ApplicationHandler for App {
    fn resumed(&mut self, event_loop: &winit::event_loop::ActiveEventLoop) {
        let attrs = winit::window::Window::default_attributes()
            .with_title("player-proto")
            .with_inner_size(winit::dpi::LogicalSize::new(self.size.0, self.size.1));
        let window = match event_loop.create_window(attrs) {
            Ok(w) => w,
            Err(e) => {
                eprintln!("window creation failed: {e}");
                event_loop.exit();
                return;
            }
        };
        self.timing.mark("window");

        self.timing.mark("fonts_begin");
        let fonts = Fonts::new();
        self.timing.mark("fonts_ready");
        self.fonts = Some(fonts);

        let mut init = InitTiming {
            timing: &mut self.timing,
        };
        let forced = std::env::var("PROTO_CAPTURE").ok().and_then(|spec| {
            let (w, h) = spec.split_once('x')?;
            Some((w.parse::<u32>().ok()?, h.parse::<u32>().ok()?))
        });
        match create_gpu(&window, &mut init, forced) {
            Some(mut gpu) => {
                // Deterministic captures: the compositor may tile the window to something else.
                if forced.is_some() {
                    gpu.set_capture_size(forced);
                }
                self.gpu = Some(gpu);
            }
            None => {
                eprintln!("vulkan init failed");
                event_loop.exit();
                return;
            }
        }
        let gpu = self.gpu.as_mut().unwrap();
        let fonts = self.fonts.as_mut().unwrap();
        let quads = build_ui(fonts, gpu.extent);
        self.timing.mark("text_layout");
        unsafe {
            if let Err(e) = gpu.upload_atlas(&self.fonts.as_ref().unwrap().atlas) {
                eprintln!("atlas upload failed: {e}");
                event_loop.exit();
                return;
            }
        }
        self.timing.mark("atlas_upload");

        if let Some(frames) = self.layout_bench {
            let t = Instant::now();
            for _ in 0..frames {
                let mut scratch = DrawList::new();
                let _ = build_text_only(self.fonts.as_mut().unwrap(), &mut scratch, gpu.extent);
            }
            let per = t.elapsed().as_secs_f64() * 1000.0 / frames as f64;
            println!(
                "layout bench: {} iterations, {per:.3} ms per full-UI text layout",
                frames
            );
        }
        if let Some(frames) = self.bench {
            if let Err(e) = unsafe { gpu.bench(&quads, frames, [0.055, 0.063, 0.078, 1.0]) } {
                eprintln!("bench failed: {e}");
            }
            event_loop.exit();
            return;
        }

        self.quads = Some(quads);
        window.request_redraw();
        self.window = Some(window);
    }

    fn window_event(
        &mut self,
        event_loop: &winit::event_loop::ActiveEventLoop,
        _id: winit::window::WindowId,
        event: winit::event::WindowEvent,
    ) {
        match event {
            winit::event::WindowEvent::CloseRequested => event_loop.exit(),
            winit::event::WindowEvent::RedrawRequested => {
                let Some(gpu) = self.gpu.as_mut() else { return };
                let Some(quads) = self.quads.as_ref() else {
                    return;
                };
                match unsafe { gpu.draw(quads, [0.055, 0.063, 0.078, 1.0]) } {
                    Ok(()) => {
                        self.frames_drawn += 1;
                        if self.frames_drawn == 1 {
                            self.first_present_age_ms = process_age_ms().unwrap_or(f64::NAN);
                            self.timing.mark("first_present");
                            if let Some(path) = self.shot.clone() {
                                if let Err(e) =
                                    unsafe { gpu.shot(quads, &path, [0.055, 0.063, 0.078, 1.0]) }
                                {
                                    eprintln!("shot failed: {e}");
                                }
                            }
                        }
                        if self.frames_drawn >= self.frames_wanted {
                            self.timing.report(self.json);
                            event_loop.exit();
                        } else if let Some(w) = self.window.as_ref() {
                            // Ask for the next frame; its arrival means the compositor took ours.
                            w.request_redraw();
                        }
                    }
                    Err(e) => {
                        eprintln!("draw failed: {e}");
                        event_loop.exit();
                    }
                }
            }
            _ => {}
        }
    }
}

fn main() {
    let mut json = false;
    let mut frames = 1u32;
    let mut shot: Option<String> = None;
    let mut bench: Option<u32> = None;
    let mut layout_bench: Option<u32> = None;
    let mut size: (f64, f64) = (1100.0, 620.0);
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--json" => json = true,
            "--frames" => {
                i += 1;
                frames = args.get(i).and_then(|s| s.parse().ok()).unwrap_or(1);
            }
            "--hdr" => player_proto::gpu::request_hdr(true),
            "--size" => {
                i += 1;
                if let Some(v) = args.get(i) {
                    if let Some((w, h)) = v.split_once('x') {
                        if let (Ok(w), Ok(h)) = (w.parse::<f64>(), h.parse::<f64>()) {
                            size = (w, h);
                        }
                    }
                }
            }
            "--bench" => {
                i += 1;
                bench = args.get(i).and_then(|s| s.parse().ok());
            }
            "--bench-layout" => {
                i += 1;
                layout_bench = args.get(i).and_then(|s| s.parse().ok());
            }
            "--shot" => {
                i += 1;
                shot = args.get(i).cloned();
            }
            other => eprintln!("unknown arg: {other}"),
        }
        i += 1;
    }
    let mut timing = Timing::new();
    timing.mark("main");
    println!(
        "exec->ctor {:.1} ms, ctor->main {:.1} ms (approx)",
        ctor_age_ms().unwrap_or(f64::NAN),
        0.0_f64
    );
    let mut app = App::new(timing, json, frames);
    app.shot = shot;
    app.bench = bench;
    app.layout_bench = layout_bench;
    app.size = size;
    let event_loop = winit::event_loop::EventLoop::new().expect("event loop");
    let _ = event_loop.run_app(&mut app);
    if let Some(mut gpu) = app.gpu.take() {
        gpu.destroy();
    }
}
