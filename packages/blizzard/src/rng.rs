//! Mersenne Twister 19937 with the two seeding schemes the Python generator
//! relies on.
//!
//! `random.Random(seed)` seeds the generator through `init_by_array`, while
//! NumPy's legacy `RandomState(seed)` uses plain `init_genrand`. Reproducing
//! both bit-for-bit keeps the snowflake placement and the `noise` dithering
//! identical to the original script, which is what makes the visual parity
//! check meaningful.

const N: usize = 624;
const M: usize = 397;
const MATRIX_A: u32 = 0x9908_b0df;
const UPPER_MASK: u32 = 0x8000_0000;
const LOWER_MASK: u32 = 0x7fff_ffff;

pub struct Mt19937 {
    mt: [u32; N],
    index: usize,
}

impl Mt19937 {
    /// CPython's `init_genrand`, also used by NumPy's `RandomState`.
    fn init_genrand(seed: u32) -> Self {
        let mut mt = [0u32; N];
        mt[0] = seed;
        for i in 1..N {
            mt[i] = 1_812_433_253u32
                .wrapping_mul(mt[i - 1] ^ (mt[i - 1] >> 30))
                .wrapping_add(i as u32);
        }
        Self { mt, index: N }
    }

    /// CPython's `init_by_array`, which is what `random.Random(int)` uses.
    fn init_by_array(key: &[u32]) -> Self {
        let mut rng = Self::init_genrand(19_650_218);
        let mut i = 1usize;
        let mut j = 0usize;
        let mut k = N.max(key.len());
        while k > 0 {
            let prev = rng.mt[i - 1];
            let mixed = (prev ^ (prev >> 30)).wrapping_mul(1_664_525);
            rng.mt[i] = (rng.mt[i] ^ mixed)
                .wrapping_add(key[j])
                .wrapping_add(j as u32);
            i += 1;
            j += 1;
            if i >= N {
                rng.mt[0] = rng.mt[N - 1];
                i = 1;
            }
            if j >= key.len() {
                j = 0;
            }
            k -= 1;
        }
        let mut k = N - 1;
        while k > 0 {
            let prev = rng.mt[i - 1];
            let mixed = (prev ^ (prev >> 30)).wrapping_mul(1_566_083_941);
            rng.mt[i] = (rng.mt[i] ^ mixed).wrapping_sub(i as u32);
            i += 1;
            if i >= N {
                rng.mt[0] = rng.mt[N - 1];
                i = 1;
            }
            k -= 1;
        }
        rng.mt[0] = UPPER_MASK;
        rng.index = N;
        rng
    }

    /// Number of 32-bit words CPython derives from an arbitrary-size seed.
    fn python_words(seed: i64) -> Vec<u32> {
        let mut n = seed.unsigned_abs();
        let mut words = Vec::new();
        loop {
            words.push(n as u32);
            n >>= 32;
            if n == 0 {
                break;
            }
        }
        words
    }

    /// `random.Random(seed)` with an integer seed.
    pub fn from_python_seed(seed: i64) -> Self {
        Self::init_by_array(&Self::python_words(seed))
    }

    /// `numpy.random.RandomState(seed)`, whose scalar seed path is
    /// `init_genrand(seed)`.
    pub fn from_numpy_seed(seed: u32) -> Self {
        Self::init_genrand(seed)
    }

    fn twist(&mut self) {
        let mut mt = self.mt;
        for kk in 0..N - M {
            let y = (mt[kk] & UPPER_MASK) | (mt[kk + 1] & LOWER_MASK);
            mt[kk] = mt[kk + M] ^ (y >> 1) ^ if y & 1 != 0 { MATRIX_A } else { 0 };
        }
        for kk in N - M..N - 1 {
            let y = (mt[kk] & UPPER_MASK) | (mt[kk + 1] & LOWER_MASK);
            mt[kk] = mt[kk + M - N] ^ (y >> 1) ^ if y & 1 != 0 { MATRIX_A } else { 0 };
        }
        let y = (mt[N - 1] & UPPER_MASK) | (mt[0] & LOWER_MASK);
        mt[N - 1] = mt[M - 1] ^ (y >> 1) ^ if y & 1 != 0 { MATRIX_A } else { 0 };
        self.mt = mt;
        self.index = 0;
    }

    pub fn next_u32(&mut self) -> u32 {
        if self.index >= N {
            self.twist();
        }
        let mut y = self.mt[self.index];
        self.index += 1;
        y ^= y >> 11;
        y ^= (y << 7) & 0x9d2c_5680;
        y ^= (y << 15) & 0xefc6_0000;
        y ^= y >> 18;
        y
    }

    /// Both CPython's `random()` and NumPy's `rk_double` build a double from
    /// two 32-bit words in exactly this way.
    pub fn random(&mut self) -> f64 {
        let a = (self.next_u32() >> 5) as f64;
        let b = (self.next_u32() >> 6) as f64;
        (a * 67_108_864.0 + b) / 9_007_199_254_740_992.0
    }

    /// CPython's `uniform(a, b)`.
    pub fn uniform(&mut self, a: f64, b: f64) -> f64 {
        a + (b - a) * self.random()
    }
}

#[cfg(test)]
mod tests {
    use super::Mt19937;

    #[test]
    fn python_seed_matches_cpython() {
        // python3 -c 'import random; r=random.Random(7); print(r.random())'
        let mut rng = Mt19937::from_python_seed(7);
        let expected = [
            0.323_832_764_833_162_37,
            0.150_849_173_924_501_92,
            0.650_934_473_039_853_7,
            0.072_436_286_667_542_76,
        ];
        for want in expected {
            let got = rng.random();
            assert!((got - want).abs() < 1e-18, "got {got} want {want}");
        }
    }

    #[test]
    fn numpy_seed_matches_numpy() {
        // python3 -c 'import numpy as np; print(np.random.RandomState(0).rand())'
        let mut rng = Mt19937::from_numpy_seed(0);
        let expected = [
            0.548_813_503_927_324_8,
            0.715_189_366_372_419_5,
            0.602_763_376_071_643_9,
            0.544_883_182_996_896_9,
        ];
        for want in expected {
            let got = rng.random();
            assert!((got - want).abs() < 1e-18, "got {got} want {want}");
        }
    }

    #[test]
    fn uniform_matches_python() {
        let mut rng = Mt19937::from_python_seed(7);
        for _ in 0..4 {
            rng.random();
        }
        assert!((rng.uniform(0.0, 640.0) - 342.964_482_756_281_1).abs() < 1e-9);
    }
}
