//! CPU-side draw data: a vertex format every UI pipeline shares, batching, and the
//! glyph atlas packer. Nothing in here touches Vulkan.

/// The glyph atlas is a single R8 sheet. It grew to 2048x2048 when the type scale did: 11-27 px
/// across two faces plus full Cyrillic is more coverage than 2048x1024 holds, and an atlas that
/// overflows does not fail — it silently drops glyphs, which read as tofu boxes in the middle of
/// a duration or a percentage.
pub const ATLAS_W: u32 = 2048;
pub const ATLAS_H: u32 = 2048;
pub const MAX_VERTICES: usize = 1 << 19;

/// One vertex layout for the whole UI: position in pixels, uv, two colours (gradient
/// endpoints) and shape parameters. Keeping a single layout means one vertex buffer and
/// one vertex shader; only the fragment stage differs per pipeline.
#[repr(C)]
#[derive(Clone, Copy, Default, Debug)]
pub struct Vertex {
    pub pos: [f32; 2],
    pub uv: [f32; 2],
    pub color: [f32; 4],
    pub color2: [f32; 4],
    /// x: corner radius px, y/z: quad size px, w: shadow blur px
    pub params: [f32; 4],
}

pub const VERTEX_SIZE: usize = std::mem::size_of::<Vertex>();

/// sRGB -> linear for one channel. Colours are authored as sRGB (the hex values in the theme),
/// while the swapchain format is SRGB: without this conversion the driver would encode them a
/// second time and the whole UI would look washed out.
fn lin_channel(c: f32) -> f32 {
    if c <= 0.04045 {
        c / 12.92
    } else {
        ((c + 0.055) / 1.055).powf(2.4)
    }
}

/// sRGB triple/quad -> linear, alpha untouched.
pub fn linear(c: [f32; 4]) -> [f32; 4] {
    [
        lin_channel(c[0]),
        lin_channel(c[1]),
        lin_channel(c[2]),
        c[3],
    ]
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Kind {
    Shape,
    Text,
    Image,
    /// A frosted-glass slab: samples the frame's backdrop texture with a refracted, blurred
    /// lookup instead of painting a flat colour. Same silhouette as `Shape`.
    Glass,
    /// A full-screen procedural background (`shaders/bg.frag`): tunnel, plasma, spectrum.
    Effect,
}

#[derive(Clone, Copy, Debug)]
pub struct Batch {
    pub kind: Kind,
    pub first: u32,
    pub count: u32,
    /// Scissor rect in *device* pixels: x, y, w, h. Clipping changes break batching.
    pub scissor: Option<[f32; 4]>,
}

pub struct DrawList {
    pub vertices: Vec<Vertex>,
    pub batches: Vec<Batch>,
    clip: Option<[f32; 4]>,
    /// Device pixels per logical unit: exactly the ratio the vertex shader divides by
    /// (`physical extent / resolution`). The list is *authored* in logical units — the layout's
    /// own space, so the same numbers describe the frame at every scale — and *uploaded* in
    /// device pixels: every edge is rounded onto this grid here. That is what keeps a hairline
    /// one device pixel wide at 1.25x, 1.5x and 2x, and what makes two neighbouring rects share
    /// an edge instead of overlapping it by a fraction of a pixel.
    scale: f32,
}

impl Default for DrawList {
    fn default() -> Self {
        Self::new()
    }
}

impl DrawList {
    pub fn new() -> Self {
        Self {
            vertices: Vec::with_capacity(8192),
            batches: Vec::with_capacity(256),
            clip: None,
            scale: 1.0,
        }
    }

    /// Set the logical -> device ratio this list snaps to. Called once per frame, before any
    /// primitive is pushed; the shader gets the physical extent as its resolution, so the
    /// vertices below are already final device pixels.
    pub fn set_scale(&mut self, scale: f32) {
        self.scale = scale.max(0.5);
    }

    /// Snap one logical coordinate to the device grid.
    fn dev(&self, v: f32) -> f32 {
        (v * self.scale).round()
    }

    /// Logical rect -> device (x, y, w, h). Both *edges* are rounded rather than the size, so
    /// adjacent rects land on one shared edge; a rect whose width would round away keeps one
    /// pixel, because a border that vanishes is worse than one that is a pixel wide.
    fn dev_rect(&self, x: f32, y: f32, w: f32, h: f32) -> (f32, f32, f32, f32) {
        let (x0, y0) = (self.dev(x), self.dev(y));
        let x1 = self.dev(x + w).max(x0 + if w > 0.0 { 1.0 } else { 0.0 });
        let y1 = self.dev(y + h).max(y0 + if h > 0.0 { 1.0 } else { 0.0 });
        (x0, y0, x1 - x0, y1 - y0)
    }

    /// A radius or blur in device pixels: the same physical softness at every scale.
    fn dev_len(&self, v: f32) -> f32 {
        (v * self.scale).round()
    }

    pub fn clear(&mut self) {
        self.vertices.clear();
        self.batches.clear();
        self.clip = None;
    }

    fn push(&mut self, kind: Kind, quad: [Vertex; 6]) {
        let first = self.vertices.len() as u32;
        self.vertices.extend_from_slice(&quad);
        let clip = self.clip;
        match self.batches.last_mut() {
            Some(b) if b.kind == kind && b.scissor == clip && b.first + b.count == first => {
                b.count += 6
            }
            _ => self.batches.push(Batch {
                kind,
                first,
                count: 6,
                scissor: clip,
            }),
        }
    }

    fn quad(
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        color: [f32; 4],
        color2: [f32; 4],
        params: [f32; 4],
    ) -> [Vertex; 6] {
        let (x1, y1) = (x + w, y + h);
        let (color, color2) = (linear(color), linear(color2));
        let v = |px: f32, py: f32, u: f32, vv: f32| Vertex {
            pos: [px, py],
            uv: [u, vv],
            color,
            color2,
            params,
        };
        [
            v(x, y, 0.0, 0.0),
            v(x1, y, 1.0, 0.0),
            v(x1, y1, 1.0, 1.0),
            v(x, y, 0.0, 0.0),
            v(x1, y1, 1.0, 1.0),
            v(x, y1, 0.0, 1.0),
        ]
    }

    /// Flat rectangle (radius 0, no gradient).
    pub fn rect(&mut self, x: f32, y: f32, w: f32, h: f32, color: [f32; 4]) {
        let (x, y, w, h) = self.dev_rect(x, y, w, h);
        self.push(
            Kind::Shape,
            Self::quad(x, y, w, h, color, color, [0.0, w, h, 0.0]),
        );
    }

    /// Vertical gradient rectangle.
    pub fn gradient(&mut self, x: f32, y: f32, w: f32, h: f32, top: [f32; 4], bottom: [f32; 4]) {
        let (x, y, w, h) = self.dev_rect(x, y, w, h);
        self.push(
            Kind::Shape,
            Self::quad(x, y, w, h, top, bottom, [0.0, w, h, 0.0]),
        );
    }

    /// Rounded rectangle, optionally with a vertical gradient.
    pub fn rounded(
        &mut self,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        radius: f32,
        top: [f32; 4],
        bottom: [f32; 4],
    ) {
        let (x, y, w, h) = self.dev_rect(x, y, w, h);
        // A radius larger than half the box inverts the SDF, so it is clamped *after* snapping:
        // the shape is evaluated in device pixels, next to the edges it rounds.
        let r = self.dev_len(radius).min(w.min(h) * 0.5);
        self.push(
            Kind::Shape,
            Self::quad(x, y, w, h, top, bottom, [r, w, h, 0.0]),
        );
    }

    /// A slab of frosted glass: the rounded-rect silhouette of `rounded`, filled with a
    /// blurred, refracted sample of the frame's backdrop instead of a colour.
    ///
    /// `tint` is the glass colour (its alpha is the opacity of the slab, so a lighter alpha
    /// lets more of the backdrop through), and `refraction` is how far the edge bends the
    /// backdrop, in logical pixels of displacement — 0 gives a plain frosted blur, 0.5-2 px
    /// gives the bevel that reads as "liquid". The value is carried in the quad's spare
    /// `params.w` slot, which the opaque shader uses for its shadow blur.
    pub fn glass(
        &mut self,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        radius: f32,
        tint: [f32; 4],
        refraction: f32,
    ) {
        let (x, y, w, h) = self.dev_rect(x, y, w, h);
        let r = self.dev_len(radius).min(w.min(h) * 0.5);
        self.push(
            Kind::Glass,
            Self::quad(x, y, w, h, tint, tint, [r, w, h, refraction]),
        );
    }

    /// A procedural background quad. `mode` selects the effect in `shaders/bg.frag`
    /// (0 flat, 1 tunnel, 2 plasma, 3 spectrum), `scale` is the effect's own frequency knob
    /// (cell size, tunnel scale or bar count) and `intensity` blends it in (0 = the flat
    /// ground colour, 1 = full strength). Drawn into the backdrop layer, i.e. behind every pane.
    ///
    /// The four `params` slots are packed to match the fragment shader exactly — `.x` mode,
    /// `.y` scale, `.z` unused, `.w` intensity — because the shader was written against that
    /// contract; the usual "radius, width, height, blur" meaning of the slot does not apply to
    /// a full-screen quad.
    pub fn effect(
        &mut self,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        mode: f32,
        scale: f32,
        intensity: f32,
        tint: [f32; 4],
        tint2: [f32; 4],
    ) {
        let (x, y, w, h) = self.dev_rect(x, y, w, h);
        self.push(
            Kind::Effect,
            Self::quad(x, y, w, h, tint, tint2, [mode, scale, 0.0, intensity]),
        );
    }

    /// Soft shadow: a rounded rect whose alpha fades out over `blur` px outside the edge.
    pub fn shadow(&mut self, x: f32, y: f32, w: f32, h: f32, radius: f32, blur: f32, alpha: f32) {
        let (x, y, w, h) = self.dev_rect(x, y, w, h);
        let (r, b) = (self.dev_len(radius), self.dev_len(blur).max(1.0));
        let c = [0.0, 0.0, 0.0, alpha];
        self.push(Kind::Shape, Self::quad(x, y, w, h, c, c, [r, w, h, b]));
    }

    /// Soft coloured halo: same SDF as `shadow`, but with an explicit colour (accent glows).
    pub fn glow(
        &mut self,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        radius: f32,
        blur: f32,
        color: [f32; 4],
    ) {
        let (x, y, w, h) = self.dev_rect(x, y, w, h);
        let (r, b) = (self.dev_len(radius), self.dev_len(blur).max(1.0));
        self.push(
            Kind::Shape,
            Self::quad(x, y, w, h, color, color, [r, w, h, b]),
        );
    }

    /// Textured rounded quad (album art). `tint` multiplies the texture; alpha fades it.
    pub fn image(&mut self, x: f32, y: f32, w: f32, h: f32, radius: f32, tint: [f32; 4]) {
        let (x, y, w, h) = self.dev_rect(x, y, w, h);
        let r = self.dev_len(radius).min(w.min(h) * 0.5);
        self.push(
            Kind::Image,
            Self::quad(x, y, w, h, tint, tint, [r, w, h, 0.0]),
        );
    }

    /// Raw glyph quad: `uv` are atlas coordinates, colour is flat. The bitmap was rasterised at
    /// the device scale, so its width and height are already whole device pixels: snapping the
    /// two edges keeps them exactly that, and the glyph lands 1:1 on the surface instead of
    /// being resampled.
    pub fn glyph(&mut self, x: f32, y: f32, w: f32, h: f32, uv: [f32; 4], color: [f32; 4]) {
        let (x, y, w, h) = self.dev_rect(x, y, w, h);
        let (x1, y1) = (x + w, y + h);
        let (u0, v0, u1, v1) = (uv[0], uv[1], uv[2], uv[3]);
        let c = linear(color);
        let v = |px: f32, py: f32, u: f32, vv: f32| Vertex {
            pos: [px, py],
            uv: [u, vv],
            color: c,
            color2: c,
            params: [0.0; 4],
        };
        self.push(
            Kind::Text,
            [
                v(x, y, u0, v0),
                v(x1, y, u1, v0),
                v(x1, y1, u1, v1),
                v(x, y, u0, v0),
                v(x1, y1, u1, v1),
                v(x, y1, u0, v1),
            ],
        );
    }

    /// Restrict subsequent primitives to a rect (break batching when it changes). The rect is
    /// authored in logical units like everything else and stored in device pixels, because that
    /// is the space the scissor is applied in.
    pub fn set_clip(&mut self, rect: Option<[f32; 4]>) {
        self.clip = rect.map(|[x, y, w, h]| {
            let (x, y, w, h) = self.dev_rect(x, y, w, h);
            [x, y, w, h]
        });
    }

    pub fn is_empty(&self) -> bool {
        self.batches.is_empty()
    }
}

// ---------------------------------------------------------------- glyph atlas

pub struct Atlas {
    pub pixels: Vec<u8>,
    shelf_x: u32,
    shelf_y: u32,
    row_h: u32,
}

impl Atlas {
    pub fn new() -> Self {
        Self {
            pixels: vec![0; (ATLAS_W * ATLAS_H) as usize],
            shelf_x: 0,
            shelf_y: 0,
            row_h: 0,
        }
    }

    /// Returns the [u0, v0, u1, v1] rect for the block, or None when the atlas is full.
    pub fn insert(&mut self, w: u32, h: u32, data: &[u8], stride: u32) -> Option<[f32; 4]> {
        if w == 0 || h == 0 || w > ATLAS_W || h > ATLAS_H {
            return None;
        }
        if self.shelf_x + w > ATLAS_W {
            self.shelf_y += self.row_h;
            self.shelf_x = 0;
            self.row_h = 0;
        }
        if self.shelf_y + h > ATLAS_H {
            return None;
        }
        let (x0, y0) = (self.shelf_x, self.shelf_y);
        for row in 0..h {
            let src = (row * stride) as usize;
            let dst = ((y0 + row) * ATLAS_W + x0) as usize;
            self.pixels[dst..dst + w as usize].copy_from_slice(&data[src..src + w as usize]);
        }
        self.shelf_x += w;
        self.row_h = self.row_h.max(h);
        let (fw, fh) = (ATLAS_W as f32, ATLAS_H as f32);
        Some([
            x0 as f32 / fw,
            y0 as f32 / fh,
            (x0 + w) as f32 / fw,
            (y0 + h) as f32 / fh,
        ])
    }
}
