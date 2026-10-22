//! Byte-class scanning at 16 bytes per instruction.
//!
//! The scanners walk log lines byte by byte looking for the end of a run of
//! "word bytes", "path bytes" or digits, and the stream splitter looks for a line
//! terminator. Those loops are the hottest code in the crate, and they are a
//! perfect fit for SSE2, which every x86-64 CPU has: compare 16 bytes against a
//! handful of ranges, build a mask, and take the first zero bit.
//!
//! Every function here has a scalar twin behind `cfg` and a test that checks the
//! two agree, so a build for another architecture (or a CPU without SSE2) is
//! correct, just slower.

/// Whether AVX2 is available, asked once per process.
#[cfg(target_arch = "x86_64")]
fn have_avx2() -> bool {
    static HAVE: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *HAVE.get_or_init(|| std::arch::is_x86_feature_detected!("avx2"))
}

/// Index of the first byte equal to `a` or `b`.
pub fn find2(a: u8, b: u8, hay: &[u8]) -> Option<usize> {
    #[cfg(target_arch = "x86_64")]
    {
        // SAFETY: `have_avx2` gates the AVX2 path, SSE2 is part of the x86-64
        // baseline, and the intrinsics only read `hay`.
        if hay.len() >= 64 && have_avx2() {
            return unsafe { avx::find2(a, b, hay) };
        }
        return unsafe { x86::find2(a, b, hay) };
    }
    #[allow(unreachable_code)]
    scalar::find2(a, b, hay)
}

/// Length of the leading run of `[0-9A-Za-z_]`.
pub fn word_run(hay: &[u8]) -> usize {
    #[cfg(target_arch = "x86_64")]
    {
        // SAFETY: as in `find2` -- AVX2 gated, SSE2 baseline, reads only.
        if hay.len() >= 64 && have_avx2() {
            return unsafe { avx::word_run(hay) };
        }
        return unsafe { x86::word_run(hay) };
    }
    #[allow(unreachable_code)]
    scalar::word_run(hay)
}

/// Length of the leading run of digits.
pub fn digit_run(hay: &[u8]) -> usize {
    #[cfg(target_arch = "x86_64")]
    {
        // SAFETY: as in `find2` -- AVX2 gated, SSE2 baseline, reads only.
        if hay.len() >= 64 && have_avx2() {
            return unsafe { avx::digit_run(hay) };
        }
        return unsafe { x86::digit_run(hay) };
    }
    #[allow(unreachable_code)]
    scalar::digit_run(hay)
}

/// How many times `needle` occurs in `hay`.
pub fn count_byte(needle: u8, hay: &[u8]) -> usize {
    #[cfg(target_arch = "x86_64")]
    {
        // SAFETY: as in `find2` -- AVX2 gated, SSE2 baseline, reads only.
        if hay.len() >= 64 && have_avx2() {
            return unsafe { avx::count_byte(needle, hay) };
        }
        return unsafe { x86::count_byte(needle, hay) };
    }
    #[allow(unreachable_code)]
    scalar::count_byte(needle, hay)
}

/// Length of the leading run of path bytes: alphanumerics plus `/. - _ ~ + @ %`.
pub fn path_run(hay: &[u8]) -> usize {
    #[cfg(target_arch = "x86_64")]
    {
        // SAFETY: as in `find2` -- AVX2 gated, SSE2 baseline, reads only.
        if hay.len() >= 64 && have_avx2() {
            return unsafe { avx::path_run(hay) };
        }
        return unsafe { x86::path_run(hay) };
    }
    #[allow(unreachable_code)]
    scalar::path_run(hay)
}

#[cfg(target_arch = "x86_64")]
#[allow(unsafe_code)]
mod x86 {
    use std::arch::x86_64::*;

    /// `[0-9A-Za-z_]` for sixteen bytes at once, as a 0xFF per matching lane.
    #[inline]
    #[target_feature(enable = "sse2")]
    unsafe fn word_mask(chunk: __m128i) -> __m128i {
        let digit = and(
            cmpgt(chunk, _mm_set1_epi8((b'0' - 1) as i8)),
            cmpgt(_mm_set1_epi8((b'9' + 1) as i8), chunk),
        );
        let upper = and(
            cmpgt(chunk, _mm_set1_epi8((b'A' - 1) as i8)),
            cmpgt(_mm_set1_epi8((b'Z' + 1) as i8), chunk),
        );
        let lower = and(
            cmpgt(chunk, _mm_set1_epi8((b'a' - 1) as i8)),
            cmpgt(_mm_set1_epi8((b'z' + 1) as i8), chunk),
        );
        let underscore = _mm_cmpeq_epi8(chunk, _mm_set1_epi8(b'_' as i8));
        or(or(digit, upper), or(lower, underscore))
    }

    #[inline]
    #[target_feature(enable = "sse2")]
    unsafe fn cmpgt(a: __m128i, b: __m128i) -> __m128i {
        _mm_cmpgt_epi8(a, b)
    }

    #[inline]
    #[target_feature(enable = "sse2")]
    unsafe fn and(a: __m128i, b: __m128i) -> __m128i {
        _mm_and_si128(a, b)
    }

    #[inline]
    #[target_feature(enable = "sse2")]
    unsafe fn or(a: __m128i, b: __m128i) -> __m128i {
        _mm_or_si128(a, b)
    }

    /// Count of leading lanes whose mask byte is `0xFF`.
    #[inline]
    #[target_feature(enable = "sse2")]
    unsafe fn leading(mask: __m128i) -> usize {
        // Invert: a set lane becomes 0, so the first zero bit is the first
        // byte that did not match.
        (_mm_movemask_epi8(mask) as u32).trailing_ones() as usize
    }

    #[inline]
    #[target_feature(enable = "sse2")]
    pub unsafe fn find2(a: u8, b: u8, hay: &[u8]) -> Option<usize> {
        let mut i = 0usize;
        let lane_a = _mm_set1_epi8(a as i8);
        let lane_b = _mm_set1_epi8(b as i8);
        while i + 16 <= hay.len() {
            let chunk = _mm_loadu_si128(hay.as_ptr().add(i) as *const __m128i);
            let hit = or(_mm_cmpeq_epi8(chunk, lane_a), _mm_cmpeq_epi8(chunk, lane_b));
            let mask = _mm_movemask_epi8(hit) as u32;
            if mask != 0 {
                return Some(i + mask.trailing_zeros() as usize);
            }
            i += 16;
        }
        super::scalar::find2(a, b, &hay[i..]).map(|offset| i + offset)
    }

    #[inline]
    #[target_feature(enable = "sse2")]
    pub unsafe fn count_byte(needle: u8, hay: &[u8]) -> usize {
        let mut count = 0usize;
        let mut i = 0usize;
        let lane = _mm_set1_epi8(needle as i8);
        while i + 16 <= hay.len() {
            let chunk = _mm_loadu_si128(hay.as_ptr().add(i) as *const __m128i);
            count += (_mm_movemask_epi8(_mm_cmpeq_epi8(chunk, lane)) as u32).count_ones() as usize;
            i += 16;
        }
        count + super::scalar::count_byte(needle, &hay[i..])
    }

    #[inline]
    #[target_feature(enable = "sse2")]
    pub unsafe fn word_run(hay: &[u8]) -> usize {
        let mut i = 0usize;
        while i + 16 <= hay.len() {
            let chunk = _mm_loadu_si128(hay.as_ptr().add(i) as *const __m128i);
            let matched = leading(word_mask(chunk));
            if matched < 16 {
                return i + matched;
            }
            i += 16;
        }
        i + super::scalar::word_run(&hay[i..])
    }

    #[inline]
    #[target_feature(enable = "sse2")]
    pub unsafe fn digit_run(hay: &[u8]) -> usize {
        let mut i = 0usize;
        let low = _mm_set1_epi8((b'0' - 1) as i8);
        let high = _mm_set1_epi8((b'9' + 1) as i8);
        while i + 16 <= hay.len() {
            let chunk = _mm_loadu_si128(hay.as_ptr().add(i) as *const __m128i);
            let mask = and(_mm_cmpgt_epi8(chunk, low), _mm_cmpgt_epi8(high, chunk));
            let matched = leading(mask);
            if matched < 16 {
                return i + matched;
            }
            i += 16;
        }
        i + super::scalar::digit_run(&hay[i..])
    }

    #[inline]
    #[target_feature(enable = "sse2")]
    pub unsafe fn path_run(hay: &[u8]) -> usize {
        let mut i = 0usize;
        while i + 16 <= hay.len() {
            let chunk = _mm_loadu_si128(hay.as_ptr().add(i) as *const __m128i);
            let mut mask = word_mask(chunk);
            for special in [b'/', b'.', b'-', b'~', b'+', b'@', b'%'] {
                mask = or(mask, _mm_cmpeq_epi8(chunk, _mm_set1_epi8(special as i8)));
            }
            let matched = leading(mask);
            if matched < 16 {
                return i + matched;
            }
            i += 16;
        }
        i + super::scalar::path_run(&hay[i..])
    }
}

#[cfg(target_arch = "x86_64")]
#[allow(unsafe_code)]
mod avx {
    //! 32 bytes per instruction on Zen 5, with the SSE2 path as the fallback.

    use std::arch::x86_64::*;

    #[inline]
    #[target_feature(enable = "avx2")]
    unsafe fn word_mask(chunk: __m256i) -> __m256i {
        let digit = _mm256_and_si256(
            _mm256_cmpgt_epi8(chunk, _mm256_set1_epi8((b'0' - 1) as i8)),
            _mm256_cmpgt_epi8(_mm256_set1_epi8((b'9' + 1) as i8), chunk),
        );
        let upper = _mm256_and_si256(
            _mm256_cmpgt_epi8(chunk, _mm256_set1_epi8((b'A' - 1) as i8)),
            _mm256_cmpgt_epi8(_mm256_set1_epi8((b'Z' + 1) as i8), chunk),
        );
        let lower = _mm256_and_si256(
            _mm256_cmpgt_epi8(chunk, _mm256_set1_epi8((b'a' - 1) as i8)),
            _mm256_cmpgt_epi8(_mm256_set1_epi8((b'z' + 1) as i8), chunk),
        );
        let underscore = _mm256_cmpeq_epi8(chunk, _mm256_set1_epi8(b'_' as i8));
        _mm256_or_si256(
            _mm256_or_si256(digit, upper),
            _mm256_or_si256(lower, underscore),
        )
    }

    #[inline]
    #[target_feature(enable = "avx2")]
    unsafe fn leading(mask: __m256i) -> usize {
        (_mm256_movemask_epi8(mask) as u32).trailing_ones() as usize
    }

    #[inline]
    #[target_feature(enable = "avx2")]
    pub unsafe fn find2(a: u8, b: u8, hay: &[u8]) -> Option<usize> {
        let mut i = 0usize;
        let lane_a = _mm256_set1_epi8(a as i8);
        let lane_b = _mm256_set1_epi8(b as i8);
        while i + 32 <= hay.len() {
            let chunk = _mm256_loadu_si256(hay.as_ptr().add(i) as *const __m256i);
            let hit = _mm256_or_si256(
                _mm256_cmpeq_epi8(chunk, lane_a),
                _mm256_cmpeq_epi8(chunk, lane_b),
            );
            let mask = _mm256_movemask_epi8(hit) as u32;
            if mask != 0 {
                return Some(i + mask.trailing_zeros() as usize);
            }
            i += 32;
        }
        super::x86::find2(a, b, &hay[i..]).map(|offset| i + offset)
    }

    #[inline]
    #[target_feature(enable = "avx2")]
    pub unsafe fn word_run(hay: &[u8]) -> usize {
        let mut i = 0usize;
        while i + 32 <= hay.len() {
            let chunk = _mm256_loadu_si256(hay.as_ptr().add(i) as *const __m256i);
            let matched = leading(word_mask(chunk));
            if matched < 32 {
                return i + matched;
            }
            i += 32;
        }
        i + super::x86::word_run(&hay[i..])
    }

    #[inline]
    #[target_feature(enable = "avx2")]
    pub unsafe fn digit_run(hay: &[u8]) -> usize {
        let mut i = 0usize;
        let low = _mm256_set1_epi8((b'0' - 1) as i8);
        let high = _mm256_set1_epi8((b'9' + 1) as i8);
        while i + 32 <= hay.len() {
            let chunk = _mm256_loadu_si256(hay.as_ptr().add(i) as *const __m256i);
            let mask = _mm256_and_si256(
                _mm256_cmpgt_epi8(chunk, low),
                _mm256_cmpgt_epi8(high, chunk),
            );
            let matched = leading(mask);
            if matched < 32 {
                return i + matched;
            }
            i += 32;
        }
        i + super::x86::digit_run(&hay[i..])
    }

    #[inline]
    #[target_feature(enable = "avx2")]
    pub unsafe fn path_run(hay: &[u8]) -> usize {
        let mut i = 0usize;
        while i + 32 <= hay.len() {
            let chunk = _mm256_loadu_si256(hay.as_ptr().add(i) as *const __m256i);
            let mut mask = word_mask(chunk);
            for special in [b'/', b'.', b'-', b'~', b'+', b'@', b'%'] {
                mask = _mm256_or_si256(
                    mask,
                    _mm256_cmpeq_epi8(chunk, _mm256_set1_epi8(special as i8)),
                );
            }
            let matched = leading(mask);
            if matched < 32 {
                return i + matched;
            }
            i += 32;
        }
        i + super::x86::path_run(&hay[i..])
    }

    #[inline]
    #[target_feature(enable = "avx2")]
    pub unsafe fn count_byte(needle: u8, hay: &[u8]) -> usize {
        let mut count = 0usize;
        let mut i = 0usize;
        let lane = _mm256_set1_epi8(needle as i8);
        while i + 32 <= hay.len() {
            let chunk = _mm256_loadu_si256(hay.as_ptr().add(i) as *const __m256i);
            count +=
                (_mm256_movemask_epi8(_mm256_cmpeq_epi8(chunk, lane)) as u32).count_ones() as usize;
            i += 32;
        }
        count + super::x86::count_byte(needle, &hay[i..])
    }
}

mod scalar {
    pub fn count_byte(needle: u8, hay: &[u8]) -> usize {
        hay.iter().filter(|byte| **byte == needle).count()
    }

    pub fn find2(a: u8, b: u8, hay: &[u8]) -> Option<usize> {
        hay.iter().position(|byte| *byte == a || *byte == b)
    }

    fn is_word(byte: u8) -> bool {
        byte.is_ascii_alphanumeric() || byte == b'_'
    }

    pub fn word_run(hay: &[u8]) -> usize {
        hay.iter()
            .position(|byte| !is_word(*byte))
            .unwrap_or(hay.len())
    }

    pub fn digit_run(hay: &[u8]) -> usize {
        hay.iter()
            .position(|byte| !byte.is_ascii_digit())
            .unwrap_or(hay.len())
    }

    pub fn path_run(hay: &[u8]) -> usize {
        hay.iter()
            .position(|byte| {
                !(is_word(*byte) || matches!(*byte, b'/' | b'.' | b'-' | b'~' | b'+' | b'@' | b'%'))
            })
            .unwrap_or(hay.len())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every length and every offset, against the scalar twin.
    fn check(hay: &[u8]) {
        assert_eq!(
            find2(b'\n', b'\r', hay),
            scalar::find2(b'\n', b'\r', hay),
            "find2 on {hay:?}"
        );
        assert_eq!(word_run(hay), scalar::word_run(hay), "word_run on {hay:?}");
        assert_eq!(
            digit_run(hay),
            scalar::digit_run(hay),
            "digit_run on {hay:?}"
        );
        assert_eq!(path_run(hay), scalar::path_run(hay), "path_run on {hay:?}");
        assert_eq!(
            count_byte(b'/', hay),
            scalar::count_byte(b'/', hay),
            "count_byte on {hay:?}"
        );
    }

    #[test]
    fn agree_with_the_scalar_version() {
        let alphabet = b"ab Z9_/.-~+@%:\n\r\t;,0";
        // Every two- and three-byte word over a hostile alphabet, plus runs of
        // every length up to 40 to cross the 16-byte lanes.
        for a in alphabet {
            for b in alphabet {
                check(&[*a, *b]);
                for c in alphabet {
                    check(&[*a, *b, *c]);
                }
            }
        }
        for len in 0..40 {
            let text = b"abc_def-9.8/7~x+y@z%Q";
            check(&text[..len.min(text.len())]);
            let digits = b"0123456789012345678901234567890123456789";
            check(&digits[..len.min(digits.len())]);
        }
    }

    #[test]
    fn finds_the_first_terminator() {
        assert_eq!(find2(b'\n', b'\r', b"abcdefghijklmnop\nrest"), Some(16));
        assert_eq!(find2(b'\n', b'\r', b"abcdefghijklmnopqrest"), None);
        assert_eq!(find2(b'\n', b'\r', b"\rrest"), Some(0));
    }

    #[test]
    fn runs_stop_at_the_right_byte() {
        assert_eq!(word_run(b"abc def"), 3);
        assert_eq!(word_run(b"abcdefghijklmnopq"), 17);
        assert_eq!(digit_run(b"12345x"), 5);
        assert_eq!(path_run(b"src/main.rs\n"), 11);
    }
}
