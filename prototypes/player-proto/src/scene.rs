//! CPU-side draw data: a vertex format every UI pipeline shares, batching, and the
//! glyph atlas packer. Nothing in here touches Vulkan.

pub const ATLAS_W: u32 = 2048;
pub const ATLAS_H: u32 = 1024;
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
}

#[derive(Clone, Copy, Debug)]
pub struct Batch {
    pub kind: Kind,
    pub first: u32,
    pub count: u32,
    /// Scissor rect in pixels: x, y, w, h. Clipping changes break batching.
    pub scissor: Option<[f32; 4]>,
}

#[derive(Default)]
pub struct DrawList {
    pub vertices: Vec<Vertex>,
    pub batches: Vec<Batch>,
    clip: Option<[f32; 4]>,
}

impl DrawList {
    pub fn new() -> Self {
        Self {
            vertices: Vec::with_capacity(8192),
            batches: Vec::with_capacity(256),
            clip: None,
        }
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
        self.push(
            Kind::Shape,
            Self::quad(x, y, w, h, color, color, [0.0, w, h, 0.0]),
        );
    }

    /// Vertical gradient rectangle.
    pub fn gradient(&mut self, x: f32, y: f32, w: f32, h: f32, top: [f32; 4], bottom: [f32; 4]) {
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
        self.push(
            Kind::Shape,
            Self::quad(x, y, w, h, top, bottom, [radius, w, h, 0.0]),
        );
    }

    /// Soft shadow: a rounded rect whose alpha fades out over `blur` px outside the edge.
    pub fn shadow(&mut self, x: f32, y: f32, w: f32, h: f32, radius: f32, blur: f32, alpha: f32) {
        let c = [0.0, 0.0, 0.0, alpha];
        self.push(
            Kind::Shape,
            Self::quad(x, y, w, h, c, c, [radius, w, h, blur.max(1.0)]),
        );
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
        self.push(
            Kind::Shape,
            Self::quad(x, y, w, h, color, color, [radius, w, h, blur.max(1.0)]),
        );
    }

    /// Textured rounded quad (album art). `tint` multiplies the texture; alpha fades it.
    pub fn image(&mut self, x: f32, y: f32, w: f32, h: f32, radius: f32, tint: [f32; 4]) {
        self.push(
            Kind::Image,
            Self::quad(x, y, w, h, tint, tint, [radius, w, h, 0.0]),
        );
    }

    /// Raw glyph quad: `uv` are atlas coordinates, colour is flat.
    pub fn glyph(&mut self, x: f32, y: f32, w: f32, h: f32, uv: [f32; 4], color: [f32; 4]) {
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

    /// Restrict subsequent primitives to a pixel rect (break batching when it changes).
    pub fn set_clip(&mut self, rect: Option<[f32; 4]>) {
        self.clip = rect;
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
