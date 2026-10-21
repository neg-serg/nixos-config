//! Spans produced by the scanners and rules, and the overlap resolution that
//! turns them into a paintable list.

use crate::theme::Kind;

/// A candidate coloured span inside one line.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Hit {
    pub start: u32,
    pub end: u32,
    pub kind: Kind,
    /// Higher wins when two hits claim the same bytes.
    pub prio: u16,
    /// 0 = take the style from the theme by `kind`; otherwise a 1-based slot in
    /// the run's style table (user rules may name a colour directly).
    pub style: u16,
}

impl Hit {
    pub fn new(start: usize, end: usize, kind: Kind, prio: u16) -> Hit {
        Hit {
            start: start as u32,
            end: end as u32,
            kind,
            prio,
            style: 0,
        }
    }

    /// Same as [`Hit::new`], but with an explicit style slot.
    pub fn styled(start: usize, end: usize, kind: Kind, prio: u16, style: u16) -> Hit {
        Hit {
            start: start as u32,
            end: end as u32,
            kind,
            prio,
            style,
        }
    }

    pub fn len(&self) -> u32 {
        self.end - self.start
    }
}

/// Sort hits by position and drop every one that overlaps an already accepted
/// span, so the renderer can walk the line once, left to right.
///
/// Precedence: earlier start first, then higher priority, then longer span.
/// A rule therefore always beats a scanner that started at the same byte, and a
/// span that starts inside an accepted one is discarded (spans never nest).
/// Equal starts cannot produce duplicates because the second one starts before
/// the cursor has moved past the first.
pub fn normalize(hits: &mut Vec<Hit>) {
    hits.retain(|h| h.end > h.start);
    hits.sort_unstable_by(|a, b| {
        a.start
            .cmp(&b.start)
            .then(b.prio.cmp(&a.prio))
            .then(b.len().cmp(&a.len()))
    });
    let mut cursor: u32 = 0;
    let mut write = 0usize;
    for read in 0..hits.len() {
        let hit = hits[read];
        if hit.start >= cursor {
            cursor = hit.end;
            hits[write] = hit;
            write += 1;
        }
    }
    hits.truncate(write);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::Kind;

    #[test]
    fn overlapping_hits_keep_the_first() {
        let mut hits = vec![
            Hit::new(0, 4, Kind::Err, 100),
            Hit::new(2, 8, Kind::Ok, 200),
            Hit::new(9, 12, Kind::Info, 100),
        ];
        normalize(&mut hits);
        assert_eq!(hits.len(), 2);
        assert_eq!(hits[0].kind, Kind::Err);
        assert_eq!(hits[1].kind, Kind::Info);
    }

    #[test]
    fn higher_priority_wins_at_the_same_start() {
        let mut hits = vec![
            Hit::new(3, 9, Kind::Dim, 100),
            Hit::new(3, 6, Kind::Key, 400),
        ];
        normalize(&mut hits);
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].kind, Kind::Key);
    }

    #[test]
    fn empty_hits_are_dropped() {
        let mut hits = vec![Hit::new(4, 4, Kind::Err, 1), Hit::new(1, 2, Kind::Ok, 1)];
        normalize(&mut hits);
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].kind, Kind::Ok);
    }
}
