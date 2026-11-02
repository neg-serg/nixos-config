//! `music-embed` subprocess integration.
//!
//! The embedding model stays in Python (`music-embed`), so the Rust index calls
//! the existing executable instead of importing torch. One process handles a
//! batch of files through `--out FILE.npy` so the model is loaded once per
//! batch; `-j N` launches up to N such batches concurrently. `MUSIC_EMBED_BIN`
//! overrides the executable looked up on PATH.

use std::fs;
use std::io::{self, BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::npy::{self, NpyArray};

/// A failed `music-embed` invocation.
#[derive(Clone, Debug)]
pub struct BatchFailure {
    /// True when the process could not be started at all (missing binary,
    /// permission error); false when it ran and exited non-zero.
    pub spawn: bool,
    pub message: String,
}

/// Settings needed to rebuild the same vectors the Python payload produced.
#[derive(Clone, Debug)]
pub struct Embedder {
    pub bin: String,
    pub model: String,
    pub layer: i64,
    pub window_seconds: f64,
    pub windows: i64,
    pub device: String,
    pub threads: i64,
}

impl Embedder {
    pub fn new(
        model: &str,
        layer: i64,
        window_seconds: f64,
        windows: i64,
        device: &str,
        threads: i64,
    ) -> Self {
        Self {
            bin: std::env::var("MUSIC_EMBED_BIN").unwrap_or_else(|_| "music-embed".to_string()),
            model: model.to_string(),
            layer,
            window_seconds,
            windows,
            device: device.to_string(),
            threads,
        }
    }

    /// Base command with the flags `music_index.py` used to pass in-process.
    ///
    /// `--threads` has no `music-embed` flag; torch reads `OMP_NUM_THREADS` at
    /// process start, which is the same setting administered through the
    /// environment for the child process.
    fn command(&self, quiet: bool) -> Command {
        let mut command = Command::new(&self.bin);
        command
            .arg("--model")
            .arg(&self.model)
            .arg("--layer")
            .arg(self.layer.to_string())
            .arg("--window-seconds")
            .arg(crate::py::float_repr(self.window_seconds))
            .arg("--windows")
            .arg(self.windows.to_string())
            .arg("--device")
            .arg(&self.device);
        if self.threads > 0 {
            let threads = self.threads.to_string();
            command.env("OMP_NUM_THREADS", &threads);
            command.env("MKL_NUM_THREADS", &threads);
        }
        if quiet {
            command.arg("--quiet");
        }
        command
    }

    /// Embed `files` with one model load, writing a stacked matrix via `--out`.
    ///
    /// The returned device is the one `music-embed` resolved for `--device
    /// auto`, parsed from its banner; this keeps `meta.json`'s `device` field
    /// meaningful without duplicating torch's resolution here.
    pub fn embed_batch(
        &self,
        files: &[PathBuf],
        cache_dir: &Path,
        tag: &str,
        mut on_embedded: Option<&mut dyn FnMut(usize)>,
    ) -> Result<(NpyArray, Option<String>), BatchFailure> {
        let out_path = cache_dir.join(format!(".music-embed-{tag}.npy"));
        let mut command = self.command(false);
        command.arg("--out").arg(&out_path);
        for file in files {
            command.arg(file);
        }
        command
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped());

        let mut child = match command.spawn() {
            Ok(child) => child,
            Err(error) => {
                return Err(BatchFailure {
                    spawn: true,
                    message: format!("cannot run {}: {error}", self.bin),
                });
            }
        };
        // `music-embed` prints one banner line and then one `name: dim N` line
        // per finished file; consuming stderr here both keeps memory bounded
        // and lets the index print progress while the model is still busy.
        let mut device = None;
        let mut embedded = 0usize;
        let mut last_line = String::new();
        if let Some(stderr) = child.stderr.take() {
            for line in BufReader::new(stderr).lines() {
                let line = match line {
                    Ok(line) => line,
                    Err(_) => break,
                };
                if device.is_none() {
                    device = parse_device_line(&line);
                }
                if line.contains(": dim ") {
                    embedded += 1;
                    if let Some(callback) = on_embedded.as_mut() {
                        callback(embedded);
                    }
                }
                if !line.trim().is_empty() {
                    last_line = line;
                }
            }
        }
        let status = match child.wait() {
            Ok(status) => status,
            Err(error) => {
                let _ = fs::remove_file(&out_path);
                return Err(BatchFailure {
                    spawn: false,
                    message: format!("cannot wait for {}: {error}", self.bin),
                });
            }
        };
        if !status.success() {
            let _ = fs::remove_file(&out_path);
            let message = if last_line.trim().is_empty() {
                format!("{} exited with {status}", self.bin)
            } else {
                clean_error(&last_line)
            };
            return Err(BatchFailure {
                spawn: false,
                message,
            });
        }
        match npy::read_f32(&out_path) {
            Ok(array) => {
                let _ = fs::remove_file(&out_path);
                Ok((array, device))
            }
            Err(error) => {
                let _ = fs::remove_file(&out_path);
                Err(BatchFailure {
                    spawn: false,
                    message: format!("cannot read music-embed output: {error}"),
                })
            }
        }
    }

    /// Embed one query file; `--quiet` keeps the JSONL/banner off stderr.
    pub fn embed_query(&self, path: &Path) -> Result<Vec<f32>, String> {
        let out_path = std::env::temp_dir().join(format!(
            "music-similar-{}.npy",
            crate::fsutil::unique_tag("query")
        ));
        let mut command = self.command(true);
        command.arg("--out").arg(&out_path).arg(path);
        let output = match command.output() {
            Ok(output) => output,
            Err(error) => {
                let _ = fs::remove_file(&out_path);
                return Err(format!("cannot run {}: {error}", self.bin));
            }
        };
        if !output.status.success() {
            let _ = fs::remove_file(&out_path);
            let text = String::from_utf8_lossy(&output.stderr);
            let detail = last_nonempty_line(&text)
                .map(|line| clean_error(line))
                .unwrap_or_else(|| format!("{} exited with {}", self.bin, output.status));
            return Err(format!("music-embed failed: {detail}"));
        }
        let array = match npy::read_f32(&out_path) {
            Ok(array) => array,
            Err(error) => {
                let _ = fs::remove_file(&out_path);
                return Err(format!("cannot read music-embed output: {error}"));
            }
        };
        let _ = fs::remove_file(&out_path);
        if array.shape.len() != 2 || array.shape[0] != 1 {
            return Err(format!(
                "music-embed returned shape {:?} for one file",
                array.shape
            ));
        }
        Ok(array.data)
    }
}

/// Parse `[music-embed] <model> on <device>` from the batch banner.
fn parse_device_line(line: &str) -> Option<String> {
    if !line.starts_with("[music-embed] ") {
        return None;
    }
    let position = line.rfind(" on ")?;
    let device = line[position + 4..].trim();
    if device.is_empty() {
        None
    } else {
        Some(device.to_string())
    }
}

fn last_nonempty_line(text: &str) -> Option<&str> {
    text.lines().rev().find(|line| !line.trim().is_empty())
}

/// Drop the `SomeError: ` prefix from a Python traceback's final line.
fn clean_error(line: &str) -> String {
    let line = line.trim();
    if let Some((prefix, rest)) = line.split_once(": ") {
        if prefix.ends_with("Error") || prefix.ends_with("Exception") {
            return rest.to_string();
        }
    }
    line.to_string()
}

/// Write a per-file cache vector as a 1-D float32 `.npy` file.
pub fn save_vector(path: &Path, values: &[f32]) -> io::Result<()> {
    npy::write_f32(path, &[values.len()], values)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_the_banner_device() {
        let temp = crate::fsutil::TempDir::new("embed-test").unwrap();
        let log = temp.path().join("stderr.log");
        fs::write(
            &log,
            "[music-embed] m-a-p/MERT-v1-95M on cuda\n[music-embed] a.flac: dim 768\n",
        )
        .unwrap();
        let text = fs::read_to_string(&log).unwrap();
        let first = text.lines().next().unwrap();
        assert_eq!(parse_device_line(first), Some("cuda".to_string()));
        assert_eq!(parse_device_line("[music-embed] layer -2"), None);
    }

    #[test]
    fn reads_the_last_error_line() {
        let text = "Traceback (most recent call last):\n  File \"x\"\nRuntimeError: no decodable audio in /tmp/a.flac (corrupt or empty file?)\n";
        let line = last_nonempty_line(text).unwrap();
        assert_eq!(
            clean_error(line),
            "no decodable audio in /tmp/a.flac (corrupt or empty file?)"
        );
    }
}
