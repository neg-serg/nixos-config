// The level is the wallpaper itself: every platform sits on a rock the
// painting actually shows. Coordinates are native wallpaper pixels, so a
// platform edge can be checked against the texture with a one-pixel ruler.

use crate::math::{Rect, Vec2};

pub const WORLD_W: f32 = 7680.0;
pub const WORLD_H: f32 = 2160.0;
pub const VIEW_W: f32 = 1920.0;
pub const VIEW_H: f32 = 1080.0;

/// The crab's own ledge in the painting, feet on the grass fringe.
pub const SPAWN: Vec2 = Vec2::new(4560.0, 1840.0);

/// Number of spray drops hidden along the way.
pub const DROP_COUNT: usize = 7;

pub struct Drop {
    pub pos: Vec2,
    pub taken: bool,
    /// Phase offset so the drops do not bob in lockstep.
    pub phase: f32,
}

pub struct Level {
    pub platforms: Vec<Rect>,
    /// Solids generated on top of the painting (crates, structures). They are
    /// rebuilt whenever the active screen changes.
    pub extra: Vec<Rect>,
    pub drops: Vec<Drop>,
    pub goal: Vec2,
    /// Waterline control points, interpolated linearly; the lake surface in
    /// the painting is not horizontal (it rises toward the falls).
    water: Vec<(f32, f32)>,
}

impl Level {
    pub fn waterfall() -> Self {
        // Grass plateau on the right: the crab's home ledge.
        // The plateau is solid down to the bottom of the painting: the cliff
        // face below the grass is not a secret passage.
        let mut platforms = vec![Rect::new(4400.0, 1840.0, WORLD_W - 4400.0, 320.0)];

        // Boulder pile left of the falls, stepped on the painting's own rock
        // edges: 1810 / 1902 / 1988 read off a 1:1 grid crop, see README.
        platforms.extend([
            Rect::new(630.0, 1836.0, 210.0, 60.0),
            Rect::new(990.0, 1900.0, 180.0, 56.0),
            Rect::new(1210.0, 1984.0, 200.0, 50.0),
        ]);

        let drops = vec![
            // Two on the plateau, so the long grass walk is part of the game.
            Drop {
                pos: Vec2::new(5000.0, 1725.0),
                taken: false,
                phase: 0.0,
            },
            Drop {
                pos: Vec2::new(6350.0, 1725.0),
                taken: false,
                phase: 1.7,
            },
            // One just under the lake surface below the cliff: dive for it.
            Drop {
                pos: Vec2::new(4280.0, 2020.0),
                taken: false,
                phase: 3.1,
            },
            // Two floating above the lake: leap out of the water.
            Drop {
                pos: Vec2::new(3450.0, 1840.0),
                taken: false,
                phase: 0.8,
            },
            Drop {
                pos: Vec2::new(2600.0, 1832.0),
                taken: false,
                phase: 2.4,
            },
            // One above the middle step of the falls climb.
            Drop {
                pos: Vec2::new(1120.0, 1836.0),
                taken: false,
                phase: 4.0,
            },
            // The last one over the top boulder.
            Drop {
                pos: Vec2::new(820.0, 1726.0),
                taken: false,
                phase: 5.2,
            },
        ];

        Self {
            platforms,
            extra: Vec::new(),
            drops,
            // The goal is the spray ring at the foot of the waterfall.
            goal: Vec2::new(1480.0, 1900.0),
            water: vec![
                (0.0, 2100.0),
                (200.0, 2082.0),
                (600.0, 2076.0),
                (1000.0, 2070.0),
                (1300.0, 2052.0),
                (1700.0, 2046.0),
                (2100.0, 2004.0),
                (2500.0, 1998.0),
                (3000.0, 1992.0),
                (3400.0, 1978.0),
                (3800.0, 1966.0),
                (4200.0, 1960.0),
                (4400.0, 1955.0),
                (4400.1, 9000.0),
                (WORLD_W, 9000.0),
            ],
        }
    }

    /// Lake surface for a world x. A very large value means "no water here".
    pub fn waterline(&self, x: f32) -> f32 {
        let pts = &self.water;
        if x <= pts[0].0 {
            return pts[0].1;
        }
        for pair in pts.windows(2) {
            let (x0, y0) = pair[0];
            let (x1, y1) = pair[1];
            if x >= x0 && x <= x1 {
                let t = if (x1 - x0).abs() < f32::EPSILON {
                    0.0
                } else {
                    (x - x0) / (x1 - x0)
                };
                return y0 + (y1 - y0) * t;
            }
        }
        pts[pts.len() - 1].1
    }
}
