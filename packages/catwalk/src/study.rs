// Headless fun study.
//
// Runs the exact director the game uses, millions of times, in parallel, and
// reports what the metric actually rewards. A campaign is the four screens the
// cat can visit (the falls, the lake, the plateau and the far right), each one
// generating eight candidate encounters through generator + critic.
//
// This measures a proxy: surprise/build/situation are properties of the
// generated screens, not a human rating. The point is to see which weights
// produce the most varied campaigns and how quickly novelty wears off.

use std::thread;
use std::time::Instant;

use crate::director::{Director, Weights, CHUNK_W};
use crate::level::Level;
use crate::math::Vec2;

/// The route the game actually plays: spawn on the plateau, then west through
/// the lake and the falls, with the far-right screen as an optional detour.
const ROUTE: [(i32, f32); 4] = [(2, 4560.0), (1, 2800.0), (0, 1300.0), (3, 6000.0)];
const SCENARIO_KEYS: [&str; 6] = ["patrol", "chase", "shoot", "ambush", "crossing", "chaos"];

fn scenario_index(slug: &str) -> usize {
    SCENARIO_KEYS.iter().position(|k| *k == slug).unwrap_or(5)
}

#[derive(Clone, Copy, Default)]
pub struct Stats {
    pub n: u64,
    pub sum: f64,
    pub sumsq: f64,
}

impl Stats {
    fn push(&mut self, v: f32) {
        let v = v as f64;
        self.n += 1;
        self.sum += v;
        self.sumsq += v * v;
    }

    pub fn mean(&self) -> f64 {
        if self.n == 0 {
            0.0
        } else {
            self.sum / self.n as f64
        }
    }

    pub fn sd(&self) -> f64 {
        if self.n < 2 {
            return 0.0;
        }
        let m = self.mean();
        ((self.sumsq / self.n as f64) - m * m).max(0.0).sqrt()
    }
}

#[derive(Clone, Default)]
pub struct Acc {
    pub runs: u64,
    pub fun: Stats,
    pub surprise: Stats,
    pub build: Stats,
    pub situation: Stats,
    pub fairness: Stats,
    pub scenarios: [u64; 6],
    pub upgrades: [u64; 4],
    pub kinds: [u64; 3],
    pub fun_bins: [u64; 10],
    pub chunk_surprise: [Stats; 4],
    pub corr_fun_surprise: (f64, f64, f64),
    pub corr_fun_build: (f64, f64, f64),
    pub corr_fun_situation: (f64, f64, f64),
    pub corr_fun_fairness: (f64, f64, f64),
    pub variety_sum: f64,
}

impl Acc {
    fn merge(&mut self, other: &Acc) {
        self.runs += other.runs;
        merge_stats(&mut self.fun, &other.fun);
        merge_stats(&mut self.surprise, &other.surprise);
        merge_stats(&mut self.build, &other.build);
        merge_stats(&mut self.situation, &other.situation);
        merge_stats(&mut self.fairness, &other.fairness);
        for i in 0..6 {
            self.scenarios[i] += other.scenarios[i];
        }
        for i in 0..4 {
            self.upgrades[i] += other.upgrades[i];
            self.chunk_surprise[i] = merge_copy(self.chunk_surprise[i], &other.chunk_surprise[i]);
        }
        for i in 0..3 {
            self.kinds[i] += other.kinds[i];
        }
        for i in 0..10 {
            self.fun_bins[i] += other.fun_bins[i];
        }
        add_corr(&mut self.corr_fun_surprise, other.corr_fun_surprise);
        add_corr(&mut self.corr_fun_build, other.corr_fun_build);
        add_corr(&mut self.corr_fun_situation, other.corr_fun_situation);
        add_corr(&mut self.corr_fun_fairness, other.corr_fun_fairness);
        self.variety_sum += other.variety_sum;
    }
}

fn merge_stats(dst: &mut Stats, src: &Stats) {
    dst.n += src.n;
    dst.sum += src.sum;
    dst.sumsq += src.sumsq;
}

fn merge_copy(mut dst: Stats, src: &Stats) -> Stats {
    merge_stats(&mut dst, src);
    dst
}

fn add_corr(dst: &mut (f64, f64, f64), src: (f64, f64, f64)) {
    dst.0 += src.0;
    dst.1 += src.1;
    dst.2 += src.2;
}

fn entropy(counts: &[u64]) -> f64 {
    let total: u64 = counts.iter().sum();
    if total == 0 {
        return 0.0;
    }
    let mut h = 0.0;
    for &c in counts {
        if c > 0 {
            let p = c as f64 / total as f64;
            h -= p * p.ln();
        }
    }
    h
}

fn correlation(t: (f64, f64, f64), n: f64, sx: f64, sy: f64, sxx: f64, syy: f64) -> f64 {
    let sxy = t.2;
    let cov = sxy - sx * sy / n;
    let vx = sxx - sx * sx / n;
    let vy = syy - sy * sy / n;
    if vx <= 0.0 || vy <= 0.0 {
        0.0
    } else {
        cov / (vx * vy).sqrt()
    }
}

pub struct Study {
    pub runs: u64,
    pub elapsed: f32,
    pub acc: Acc,
    pub sweep: Vec<(Weights, f64, Acc)>,
}

pub fn run_study(runs: u64, threads: usize, base_seed: u32) -> Study {
    let level = Level::waterfall();
    let started = Instant::now();
    let sweep = weight_sweep(&level, runs, threads, base_seed);
    let acc = simulate(&level, runs, threads, base_seed, Weights::default());
    Study {
        runs,
        elapsed: started.elapsed().as_secs_f32(),
        acc,
        sweep,
    }
}

fn simulate(level: &Level, runs: u64, threads: usize, base_seed: u32, weights: Weights) -> Acc {
    let threads = threads.max(1);
    let per_thread = runs / threads as u64;
    let mut acc = Acc::default();
    thread::scope(|scope| {
        let level = &level;
        let handles: Vec<_> = (0..threads)
            .map(|t| {
                scope.spawn(move || {
                    let mut local = Acc::default();
                    let start = t as u64 * per_thread;
                    let end = if t + 1 == threads {
                        runs
                    } else {
                        (t as u64 + 1) * per_thread
                    };
                    for run in start..end {
                        let seed = base_seed.wrapping_add((run as u32).wrapping_mul(0x9E37_79B9));
                        simulate_run(level, seed, weights, &mut local);
                    }
                    local
                })
            })
            .collect();
        for handle in handles {
            acc.merge(&handle.join().unwrap());
        }
    });
    acc
}

fn simulate_run(level: &Level, seed: u32, weights: Weights, acc: &mut Acc) {
    let mut director = Director::new(seed);
    director.weights = weights;
    let mut fun_sum = 0.0f64;
    let mut surprise_sum = 0.0f64;
    let mut build_sum = 0.0f64;
    let mut situation_sum = 0.0f64;
    let mut fairness_sum = 0.0f64;
    let mut kinds_seen = [false; 3];
    let mut chunks = 0.0f64;

    for (i, (chunk, px)) in ROUTE.iter().enumerate() {
        let enc = director.encounter_for(*chunk, Vec2::new(*px, 1800.0), level);
        let Some(last) = director.last.as_ref() else {
            continue;
        };
        let s = last.scores;
        fun_sum += s.fun as f64;
        surprise_sum += s.surprise as f64;
        build_sum += s.build as f64;
        situation_sum += s.situation as f64;
        fairness_sum += s.fairness as f64;
        chunks += 1.0;
        acc.chunk_surprise[i].push(s.surprise);
        acc.scenarios[scenario_index(enc.scenario_slug())] += 1;
        for sp in &enc.spawns {
            kinds_seen[sp.kind.index()] = true;
        }
        if let Some((_, up)) = enc.capsule {
            acc.upgrades[up.index()] += 1;
        }
        let _ = CHUNK_W;
    }
    if chunks == 0.0 {
        return;
    }
    let fun = (fun_sum / chunks) as f32;
    let surprise = (surprise_sum / chunks) as f32;
    let build = (build_sum / chunks) as f32;
    let situation = (situation_sum / chunks) as f32;
    let fairness = (fairness_sum / chunks) as f32;
    acc.runs += 1;
    acc.fun.push(fun);
    acc.surprise.push(surprise);
    acc.build.push(build);
    acc.situation.push(situation);
    acc.fairness.push(fairness);
    let bin = ((fun * 10.0) as usize).min(9);
    acc.fun_bins[bin] += 1;
    for k in 0..3 {
        if kinds_seen[k] {
            acc.kinds[k] += 1;
        }
    }
    // Pairwise sums for the correlations against fun.
    let f = fun as f64;
    for (slot, x) in [
        (&mut acc.corr_fun_surprise, surprise as f64),
        (&mut acc.corr_fun_build, build as f64),
        (&mut acc.corr_fun_situation, situation as f64),
        (&mut acc.corr_fun_fairness, fairness as f64),
    ] {
        slot.0 += f;
        slot.1 += x;
        slot.2 += f * x;
    }
}

fn weight_sweep(
    level: &Level,
    runs: u64,
    threads: usize,
    base_seed: u32,
) -> Vec<(Weights, f64, Acc)> {
    let mut results = Vec::new();
    let per_weight = (runs / 12).max(64);
    let mut rng = crate::director::Rng::new(base_seed ^ 0xA5A5_5A5A);
    for _ in 0..12 {
        let mut w = [
            0.15 + rng.f(),
            0.15 + rng.f(),
            0.15 + rng.f(),
            0.05 + rng.f() * 0.5,
        ];
        let sum: f32 = w.iter().sum();
        for v in &mut w {
            *v /= sum;
        }
        let weights = Weights {
            surprise: w[0],
            build: w[1],
            situation: w[2],
            fairness: w[3],
        };
        let acc = simulate(level, per_weight, threads, base_seed ^ 0x1234_5678, weights);
        let objective = entropy(&acc.scenarios)
            + entropy(&acc.upgrades)
            + acc.surprise.mean()
            + acc.situation.mean()
            + (acc.kinds.iter().filter(|c| **c > 0).count() as f64 / 3.0);
        results.push((weights, objective, acc));
    }
    results.sort_by(|a, b| b.1.total_cmp(&a.1));
    results
}

impl Study {
    pub fn report(&self) -> String {
        let a = &self.acc;
        let n = a.runs as f64;
        let mean_fun = a.fun.mean();
        let scenario_total: u64 = a.scenarios.iter().sum();
        let upgrade_total: u64 = a.upgrades.iter().sum();
        let mut out = String::new();
        out.push_str(&format!(
            "runs {} in {:.2}s ({:.0} runs/s, {} threads)\n",
            self.runs,
            self.elapsed,
            self.runs as f64 / self.elapsed.max(1e-6) as f64,
            std::thread::available_parallelism()
                .map(|v| v.get())
                .unwrap_or(1)
        ));
        out.push_str(&format!(
            "fun     mean {:.3} sd {:.3} | surprise {:.3} build {:.3} situation {:.3} fairness {:.3}\n",
            mean_fun,
            a.fun.sd(),
            a.surprise.mean(),
            a.build.mean(),
            a.situation.mean(),
            a.fairness.mean()
        ));
        out.push_str("scenarios: ");
        for (i, key) in SCENARIO_KEYS.iter().enumerate() {
            let share = if scenario_total > 0 {
                a.scenarios[i] as f64 / scenario_total as f64
            } else {
                0.0
            };
            out.push_str(&format!("{key} {:.2}  ", share));
        }
        out.push('\n');
        out.push_str(&format!(
            "upgrades: speed {:.2} jump {:.2} magnet {:.2} shield {:.2} ({} capsules)\n",
            if upgrade_total > 0 {
                a.upgrades[0] as f64 / upgrade_total as f64
            } else {
                0.0
            },
            if upgrade_total > 0 {
                a.upgrades[1] as f64 / upgrade_total as f64
            } else {
                0.0
            },
            if upgrade_total > 0 {
                a.upgrades[2] as f64 / upgrade_total as f64
            } else {
                0.0
            },
            if upgrade_total > 0 {
                a.upgrades[3] as f64 / upgrade_total as f64
            } else {
                0.0
            },
            upgrade_total
        ));
        out.push_str("novelty by chunk: ");
        for s in &a.chunk_surprise {
            out.push_str(&format!("{:.2}  ", s.mean()));
        }
        out.push('\n');
        let sx = a.surprise.sum;
        let sb = a.build.sum;
        let ss = a.situation.sum;
        let sf = a.fairness.sum;
        let sxx = a.surprise.sumsq;
        let sbb = a.build.sumsq;
        let sss = a.situation.sumsq;
        let sff = a.fairness.sumsq;
        let sf2 = a.fun.sumsq;
        let sfx = a.fun.sum;
        out.push_str(&format!(
            "corr(fun,x): surprise {:+.2} build {:+.2} situation {:+.2} fairness {:+.2}\n",
            correlation(a.corr_fun_surprise, n, sx, sfx, sxx, sf2),
            correlation(a.corr_fun_build, n, sb, sfx, sbb, sf2),
            correlation(a.corr_fun_situation, n, ss, sfx, sss, sf2),
            correlation(a.corr_fun_fairness, n, sf, sfx, sff, sf2)
        ));
        out.push_str(&format!(
            "scenario entropy {:.3} | upgrade entropy {:.3}\n",
            entropy(&a.scenarios),
            entropy(&a.upgrades)
        ));
        if let Some((w, obj, acc)) = self.sweep.first() {
            out.push_str(&format!(
                "best weights: surprise {:.2} build {:.2} situation {:.2} fairness {:.2} -> variety {:.3} (fun {:.3})\n",
                w.surprise,
                w.build,
                w.situation,
                w.fairness,
                obj,
                acc.fun.mean()
            ));
        }
        out
    }

    pub fn json(&self) -> String {
        let a = &self.acc;
        let mut scenarios = String::new();
        for (i, key) in SCENARIO_KEYS.iter().enumerate() {
            if i > 0 {
                scenarios.push(',');
            }
            scenarios.push_str(&format!("\"{}\":{}", key, a.scenarios[i]));
        }
        let sweep: Vec<String> = self
            .sweep
            .iter()
            .map(|(w, obj, acc)| {
                format!(
                    "{{\"surprise\":{:.3},\"build\":{:.3},\"situation\":{:.3},\"fairness\":{:.3},\"variety\":{:.3},\"fun\":{:.3}}}",
                    w.surprise,
                    w.build,
                    w.situation,
                    w.fairness,
                    obj,
                    acc.fun.mean()
                )
            })
            .collect();
        format!(
            "{{\"runs\":{},\"elapsed\":{:.2},\"fun\":{{\"mean\":{:.4},\"sd\":{:.4}}},\"components\":{{\"surprise\":{:.4},\"build\":{:.4},\"situation\":{:.4},\"fairness\":{:.4}}},\"scenarios\":{{{}}},\"scenario_entropy\":{:.4},\"upgrade_entropy\":{:.4},\"sweep\":[{}]}}",
            self.runs,
            self.elapsed,
            a.fun.mean(),
            a.fun.sd(),
            a.surprise.mean(),
            a.build.mean(),
            a.situation.mean(),
            a.fairness.mean(),
            scenarios,
            entropy(&a.scenarios),
            entropy(&a.upgrades),
            sweep.join(",")
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn campaign_offers_every_upgrade_once() {
        let level = Level::waterfall();
        let mut d = Director::new(1234);
        let mut seen = [0u8; 4];
        for (chunk, px) in ROUTE {
            let enc = d.encounter_for(chunk, Vec2::new(px, 1800.0), &level);
            if let Some((_, up)) = enc.capsule {
                eprintln!("chunk {chunk}: capsule {:?}, platforms ok", up);
                seen[up.index()] += 1;
            } else {
                eprintln!("chunk {chunk}: no capsule");
            }
        }
        eprintln!("seen {seen:?}");
        assert_eq!(seen, [1, 1, 1, 1]);
    }
}
