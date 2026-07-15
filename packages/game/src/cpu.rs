//! CPU topology detection and affinity pinning.
//!
//! Detects V-Cache CCD (largest L3 cache group) on AMD X3D CPUs
//! and sets CPU affinity via `sched_setaffinity`.

use std::fs;
use std::io;
use std::path::Path;

/// Parse a CPU set string like "0-3,16-19" into a sorted list of CPU indices.
pub fn parse_cpuset(s: &str) -> Vec<usize> {
    let mut cpus = Vec::new();
    for part in s.split(',') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }
        if let Some((a, b)) = part.split_once('-') {
            let lo: usize = a.trim().parse().unwrap_or(0);
            let hi: usize = b.trim().parse().unwrap_or(lo);
            for cpu in lo..=hi {
                cpus.push(cpu);
            }
        } else if let Ok(n) = part.parse::<usize>() {
            cpus.push(n);
        }
    }
    cpus.sort_unstable();
    cpus.dedup();
    cpus
}

/// Parse a size string like "32M", "1024K", "1G" into bytes.
fn parse_size(s: &str) -> u64 {
    let s = s.trim().to_uppercase();
    if s.is_empty() {
        return 0;
    }
    let (num, mult) = if s.ends_with('K') {
        (&s[..s.len() - 1], 1024u64)
    } else if s.ends_with('M') {
        (&s[..s.len() - 1], 1024u64 * 1024)
    } else if s.ends_with('G') {
        (&s[..s.len() - 1], 1024u64 * 1024 * 1024)
    } else {
        (&s[..], 1u64)
    };
    num.trim().parse::<u64>().unwrap_or(0) * mult
}

/// A unique L3 cache group: total cache size and the list of CPUs sharing it.
#[derive(Debug, Clone)]
pub struct L3Group {
    pub size_bytes: u64,
    pub cpus: Vec<usize>,
}

/// Detect all unique L3 cache groups by scanning `/sys/devices/system/cpu/cpu*/cache/index3/`.
pub fn detect_l3_groups() -> io::Result<Vec<L3Group>> {
    let sysfs = Path::new("/sys/devices/system/cpu");
    let mut groups: Vec<(Vec<usize>, u64)> = Vec::new();

    let entries = fs::read_dir(sysfs)?;
    for entry in entries {
        let entry = entry?;
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if !name.starts_with("cpu") {
            continue;
        }
        // Ensure numeric suffix
        if name[3..].parse::<usize>().is_err() {
            continue;
        }

        let size_path = entry.path().join("cache/index3/size");
        let share_path = entry.path().join("cache/index3/shared_cpu_list");

        let size_str = match fs::read_to_string(&size_path) {
            Ok(s) => s,
            Err(_) => continue,
        };
        let share_str = match fs::read_to_string(&share_path) {
            Ok(s) => s,
            Err(_) => continue,
        };

        let size = parse_size(&size_str);
        let cpus = parse_cpuset(&share_str);
        if cpus.is_empty() {
            continue;
        }

        // Deduplicate by CPU tuple
        if !groups.iter().any(|(g, _)| g == &cpus) {
            groups.push((cpus, size));
        }
    }

    Ok(groups
        .into_iter()
        .map(|(cpus, size)| L3Group {
            size_bytes: size,
            cpus,
        })
        .collect())
}

/// Auto-detect the best CPU set (largest L3 = V-Cache CCD on AMD X3D).
/// Applies `GAME_PIN_AUTO_LIMIT` env var if set.
pub fn auto_cpuset() -> io::Result<Vec<usize>> {
    let groups = detect_l3_groups()?;
    if groups.is_empty() {
        // Fallback: read "online" CPUs
        let online = fs::read_to_string("/sys/devices/system/cpu/online")?;
        return Ok(parse_cpuset(online.trim()));
    }

    // Pick group with largest L3. Tie: more CPUs, then higher min CPU index.
    let best = groups
        .into_iter()
        .max_by(|a, b| {
            a.size_bytes
                .cmp(&b.size_bytes)
                .then_with(|| a.cpus.len().cmp(&b.cpus.len()))
                .then_with(|| {
                    let a_first = a.cpus.first().copied();
                    let b_first = b.cpus.first().copied();
                    a_first.cmp(&b_first)
                })
        })
        .unwrap();

    // Optional limit via env var
    let limit = std::env::var("GAME_PIN_AUTO_LIMIT")
        .ok()
        .and_then(|v| v.parse::<usize>().ok());
    if let Some(lim) = limit {
        if lim > 0 && lim < best.cpus.len() {
            return Ok(best.cpus[..lim].to_vec());
        }
    }

    Ok(best.cpus)
}

/// Human-readable description of the CPU topology.
pub fn describe_topology() -> String {
    let mut out = String::new();

    match detect_l3_groups() {
        Ok(groups) => {
            out.push_str("L3 cache groups:\n");
            for g in &groups {
                let size_mb = g.size_bytes as f64 / (1024.0 * 1024.0);
                let cpu_str = g
                    .cpus
                    .chunk_by(|a, b| *b == a + 1)
                    .map(|chunk| {
                        if chunk.len() > 1 {
                            format!("{}-{}", chunk[0], chunk[chunk.len() - 1])
                        } else {
                            format!("{}", chunk[0])
                        }
                    })
                    .collect::<Vec<_>>()
                    .join(",");
                out.push_str(&format!("  {size_mb:.0}M  CPUs [{cpu_str}]\n"));
            }
        }
        Err(e) => out.push_str(&format!("  (detection failed: {e})\n")),
    }

    if let Ok(cpus) = auto_cpuset() {
        let cpu_str = cpus
            .chunk_by(|a, b| *b == a + 1)
            .map(|chunk| {
                if chunk.len() > 1 {
                    format!("{}-{}", chunk[0], chunk[chunk.len() - 1])
                } else {
                    format!("{}", chunk[0])
                }
            })
            .collect::<Vec<_>>()
            .join(",");
        out.push_str(&format!("Selected CPUs (auto): [{cpu_str}]\n"));
    }

    out
}
