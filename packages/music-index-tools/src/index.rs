//! Building, loading, migrating and auditing the similarity index.
//!
//! On-disk format (identical to `music_index.py`):
//!
//! ```text
//! INDEX/vectors.npy   float32 (N, D), L2-normalised rows
//! INDEX/tracks.jsonl  {"path", "mtime", "size", "vector_index"} per line
//! INDEX/meta.json     model, layer, device, window_seconds, windows,
//!                     signature, dim, count, created
//! INDEX/cache/*.npy   per-file vector, keyed by path+mtime+size+signature
//! INDEX/center.npy    corpus mean, float32 (D,)
//! ```
//!
//! The `--selftest` code below is a full port of the Python self-check: it
//! drives the whole pipeline with the deterministic stub embedder, including
//! the legacy-cache migration scenarios.

use std::collections::HashSet;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::Instant;

use serde_json::{Map, Value};

use crate::embed::{save_vector, BatchFailure, Embedder};
use crate::fsutil::{self, TempDir};
use crate::jsonw::push_json_string;
use crate::keys::{embed_signature, file_key, legacy_file_key, stub_embed};
use crate::py::{float_repr, format_g6, parse_float, path_str};
use crate::timefmt::{hms, local_timestamp};
use crate::{AUDIO_EXTS, PROGRESS_EVERY, SETTINGS_KEYS, STUB_DIM};

/// Index missing, inconsistent or built with other settings.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct IndexProblem(pub String);

impl std::fmt::Display for IndexProblem {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl std::error::Error for IndexProblem {}

/// The four settings that decide the embedding values.
#[derive(Clone, Debug, PartialEq)]
pub struct Settings {
    pub model: String,
    pub layer: i64,
    pub window_seconds: f64,
    pub windows: i64,
}

/// A float32 matrix in C order.
#[derive(Clone, Debug, PartialEq)]
pub struct Matrix {
    pub rows: usize,
    pub cols: usize,
    pub data: Vec<f32>,
}

impl Matrix {
    pub fn new(rows: usize, cols: usize, data: Vec<f32>) -> Self {
        assert_eq!(
            rows * cols,
            data.len(),
            "matrix dimensions disagree with data"
        );
        Self { rows, cols, data }
    }

    pub fn row(&self, row: usize) -> &[f32] {
        &self.data[row * self.cols..(row + 1) * self.cols]
    }

    /// Column means, cast to float32 (what `matrix.mean(axis=0).astype(f32)` does).
    ///
    /// numpy accumulates float32 matrices in float32; the sum here is done in
    /// float64 and rounded once, which keeps the saved center slightly more
    /// accurate. Once written, every reader uses the stored center, so the
    /// difference never compounds.
    pub fn mean_axis0(&self) -> Vec<f32> {
        if self.rows == 0 {
            return vec![0.0; self.cols];
        }
        let mut sums = vec![0.0f64; self.cols];
        for row in 0..self.rows {
            for column in 0..self.cols {
                sums[column] += self.data[row * self.cols + column] as f64;
            }
        }
        sums.iter()
            .map(|sum| (sum / self.rows as f64) as f32)
            .collect()
    }
}

/// One `tracks.jsonl` line, in the order the Python payload writes it.
#[derive(Clone, Debug, PartialEq)]
pub struct TrackRecord {
    pub path: String,
    pub mtime: i64,
    pub size: i64,
    pub vector_index: usize,
}

/// A value in `meta.json`; the variant decides how the JSON text is written.
#[derive(Clone, Debug, PartialEq)]
pub enum MetaValue {
    Str(String),
    Int(i64),
    Float(f64),
    Bool(bool),
}

/// Ordered `meta.json` contents.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Meta {
    pub entries: Vec<(String, MetaValue)>,
}

impl Meta {
    pub fn get(&self, key: &str) -> Option<&MetaValue> {
        self.entries
            .iter()
            .find(|(name, _)| name == key)
            .map(|(_, value)| value)
    }

    pub fn get_str(&self, key: &str) -> Option<&str> {
        match self.get(key) {
            Some(MetaValue::Str(value)) => Some(value),
            _ => None,
        }
    }
}

fn write_message(writer: &mut dyn Write, text: &str) {
    let _ = writeln!(writer, "{text}");
}

fn emit(writer: &mut dyn Write, text: &str) -> Result<(), String> {
    writeln!(writer, "{text}").map_err(|error| error.to_string())
}

/// Python `str()` of a JSON value (used in error messages).
fn to_py_str(value: &Value) -> String {
    match value {
        Value::String(text) => text.clone(),
        Value::Null => "None".to_string(),
        Value::Bool(true) => "True".to_string(),
        Value::Bool(false) => "False".to_string(),
        Value::Number(number) => {
            if let Some(integer) = number.as_i64() {
                integer.to_string()
            } else if let Some(float) = number.as_f64() {
                float_repr(float)
            } else {
                number.to_string()
            }
        }
        other => other.to_string(),
    }
}

/// Python `int(value)` for the JSON scalar shapes meta.json can hold.
fn to_i64(value: &Value) -> Option<i64> {
    match value {
        Value::Number(number) => number
            .as_i64()
            .or_else(|| number.as_f64().map(|float| float.trunc() as i64)),
        Value::String(text) => text.trim().parse::<i64>().ok(),
        Value::Bool(flag) => Some(i64::from(*flag)),
        _ => None,
    }
}

/// Python `float(value)` for the JSON scalar shapes meta.json can hold.
fn to_f64(value: &Value) -> Option<f64> {
    match value {
        Value::Number(number) => number.as_f64(),
        Value::String(text) => parse_float(text),
        Value::Bool(flag) => Some(if *flag { 1.0 } else { 0.0 }),
        _ => None,
    }
}

/// Python truthiness of a JSON value.
fn truthy(value: &Value) -> bool {
    match value {
        Value::Null => false,
        Value::Bool(flag) => *flag,
        Value::Number(number) => number.as_f64().map(|float| float != 0.0).unwrap_or(false),
        Value::String(text) => !text.is_empty(),
        Value::Array(items) => !items.is_empty(),
        Value::Object(map) => !map.is_empty(),
    }
}

/// Embedding settings an index was built with.
pub fn index_settings(meta: &Value) -> Result<Settings, IndexProblem> {
    let missing: Vec<&str> = SETTINGS_KEYS
        .iter()
        .copied()
        .filter(|key| meta.get(*key).is_none())
        .collect();
    if !missing.is_empty() {
        return Err(IndexProblem(format!(
            "index meta.json is missing embed settings ({}); rebuild with music-index",
            missing.join(", ")
        )));
    }
    let model = to_py_str(meta.get("model").expect("checked above"));
    let layer = to_i64(meta.get("layer").expect("checked above")).ok_or_else(|| {
        IndexProblem(
            "index meta.json has an invalid embed setting (layer); rebuild with music-index"
                .to_string(),
        )
    })?;
    let window_seconds = to_f64(meta.get("window_seconds").expect("checked above")).ok_or_else(
        || {
            IndexProblem(
                "index meta.json has an invalid embed setting (window_seconds); rebuild with music-index"
                    .to_string(),
            )
        },
    )?;
    let windows = to_i64(meta.get("windows").expect("checked above")).ok_or_else(|| {
        IndexProblem(
            "index meta.json has an invalid embed setting (windows); rebuild with music-index"
                .to_string(),
        )
    })?;
    Ok(Settings {
        model,
        layer,
        window_seconds,
        windows,
    })
}

/// Signature the index must have for its own recorded settings.
///
/// Indexes built before signatures existed still record all four settings, so
/// their signature is derived exactly; a recorded signature that disagrees
/// with the settings is a mismatch.
pub fn index_signature(meta: &Value) -> Result<String, IndexProblem> {
    let settings = index_settings(meta)?;
    let expected = embed_signature(
        &settings.model,
        settings.layer,
        settings.window_seconds,
        settings.windows,
    );
    if let Some(recorded) = meta.get("signature").filter(|value| truthy(value)) {
        let recorded_text = match recorded {
            Value::String(text) => text.clone(),
            other => to_py_str(other),
        };
        if recorded_text != expected {
            return Err(IndexProblem(format!(
                "index signature {recorded_text} does not match its settings ({expected}); rebuild with music-index"
            )));
        }
    }
    Ok(expected)
}

/// `meta.json` as a JSON value, or `None` when absent or unreadable.
pub fn read_meta(out_dir: &Path) -> Option<Value> {
    let meta_path = out_dir.join("meta.json");
    if !meta_path.exists() {
        return None;
    }
    let text = fs::read_to_string(meta_path).ok()?;
    serde_json::from_str(&text).ok()
}

/// Load meta/tracks/vectors, refusing missing or incompatible indexes.
pub fn load_index(index_dir: &Path) -> Result<(Value, Vec<Value>, Matrix), IndexProblem> {
    let vectors_path = index_dir.join("vectors.npy");
    let tracks_path = index_dir.join("tracks.jsonl");
    if !vectors_path.exists() || !tracks_path.exists() {
        return Err(IndexProblem(format!(
            "no index in {}; build it with music-index",
            path_str(index_dir)
        )));
    }
    let meta_path = index_dir.join("meta.json");
    let meta = if meta_path.exists() {
        let text = fs::read_to_string(&meta_path).map_err(|error| {
            IndexProblem(format!("cannot read {}: {error}", path_str(&meta_path)))
        })?;
        serde_json::from_str(&text).map_err(|error| {
            IndexProblem(format!("cannot parse {}: {error}", path_str(&meta_path)))
        })?
    } else {
        Value::Object(Map::new())
    };

    let array = crate::npy::read_f32(&vectors_path).map_err(|error| {
        IndexProblem(format!("cannot read {}: {error}", path_str(&vectors_path)))
    })?;

    let tracks_text = fs::read_to_string(&tracks_path).map_err(|error| {
        IndexProblem(format!("cannot read {}: {error}", path_str(&tracks_path)))
    })?;
    let mut tracks = Vec::new();
    for line in tracks_text.lines() {
        if line.trim().is_empty() {
            continue;
        }
        let track: Value = serde_json::from_str(line).map_err(|error| {
            IndexProblem(format!("cannot parse {}: {error}", path_str(&tracks_path)))
        })?;
        tracks.push(track);
    }

    let rows = array.shape.first().copied().unwrap_or(0);
    let cols = array.shape.get(1).copied().unwrap_or(0);
    if array.shape.len() != 2 || rows != tracks.len() {
        return Err(IndexProblem(format!(
            "inconsistent index in {} ({} vectors, {} tracks); rebuild with music-index",
            path_str(index_dir),
            rows,
            tracks.len()
        )));
    }
    if let Some(count) = meta.get("count") {
        let count = to_i64(count).ok_or_else(|| {
            IndexProblem(format!(
                "index meta.json says {} tracks but holds {}; rebuild with music-index",
                to_py_str(meta.get("count").expect("present")),
                rows
            ))
        })?;
        if count != rows as i64 {
            return Err(IndexProblem(format!(
                "index meta.json says {} tracks but holds {}; rebuild with music-index",
                to_py_str(meta.get("count").expect("present")),
                rows
            )));
        }
    }
    if let Some(dim) = meta.get("dim") {
        let dim = to_i64(dim).ok_or_else(|| {
            IndexProblem(format!(
                "index meta.json says {} dims but holds {}; rebuild with music-index",
                to_py_str(meta.get("dim").expect("present")),
                cols
            ))
        })?;
        if dim != cols as i64 {
            return Err(IndexProblem(format!(
                "index meta.json says {} dims but holds {}; rebuild with music-index",
                to_py_str(meta.get("dim").expect("present")),
                cols
            )));
        }
    }
    index_signature(&meta)?;
    Ok((meta, tracks, Matrix::new(rows, cols, array.data)))
}

/// Write `vectors.npy`, `center.npy`, `tracks.jsonl` and `meta.json`.
pub fn write_index(
    out_dir: &Path,
    records: &[TrackRecord],
    matrix: &Matrix,
    meta: &Meta,
) -> std::io::Result<()> {
    fs::create_dir_all(out_dir)?;
    crate::npy::write_f32(
        &out_dir.join("vectors.npy"),
        &[matrix.rows, matrix.cols],
        &matrix.data,
    )?;
    // The corpus mean is what music-similar subtracts before cosine: MERT
    // embeddings are strongly anisotropic. Saving it keeps every reader on the
    // same transform; readers also derive it when it is absent.
    let center = matrix.mean_axis0();
    crate::npy::write_f32(&out_dir.join("center.npy"), &[center.len()], &center)?;

    let mut tracks = String::new();
    for record in records {
        tracks.push_str("{\"path\": ");
        push_json_string(&mut tracks, &record.path, false);
        tracks.push_str(&format!(
            ", \"mtime\": {}, \"size\": {}, \"vector_index\": {}",
            record.mtime, record.size, record.vector_index
        ));
        tracks.push_str("}\n");
    }
    fs::write(out_dir.join("tracks.jsonl"), tracks)?;

    let mut meta_text = String::from("{\n");
    for (index, (key, value)) in meta.entries.iter().enumerate() {
        meta_text.push_str("  ");
        push_json_string(&mut meta_text, key, true);
        meta_text.push_str(": ");
        match value {
            MetaValue::Str(text) => push_json_string(&mut meta_text, text, true),
            MetaValue::Int(number) => meta_text.push_str(&number.to_string()),
            MetaValue::Float(number) => meta_text.push_str(&float_repr(*number)),
            MetaValue::Bool(flag) => meta_text.push_str(if *flag { "true" } else { "false" }),
        }
        if index + 1 < meta.entries.len() {
            meta_text.push(',');
        }
        meta_text.push('\n');
    }
    meta_text.push('}');
    fs::write(out_dir.join("meta.json"), meta_text)?;
    Ok(())
}

/// True when `meta.json` attributes the legacy cache to these settings.
pub fn legacy_settings_match(out_dir: &Path, settings: &Settings) -> bool {
    match read_meta(out_dir) {
        Some(meta) => index_settings(&meta)
            .map(|recorded| recorded == *settings)
            .unwrap_or(false),
        None => false,
    }
}

/// Copy a pre-signature cache entry to its signature key when it is usable.
///
/// Copies instead of renaming so an older `music-index` process still running
/// finds its entries under the legacy name. Returns false (and leaves the file
/// alone) when the legacy entry is missing or unreadable.
pub fn migrate_legacy_vector(path: &Path, cache_file: &Path) -> bool {
    let parent = match cache_file.parent() {
        Some(parent) => parent,
        None => return false,
    };
    let legacy_file = parent.join(format!("{}.npy", legacy_file_key(path)));
    if !legacy_file.exists() {
        return false;
    }
    let vector = match crate::npy::read_f32(&legacy_file) {
        Ok(vector) => vector,
        Err(_) => return false,
    };
    let file_name = cache_file
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_default();
    let partial = cache_file.with_file_name(format!("{file_name}.part.npy"));
    if crate::npy::write_f32(&partial, &vector.shape, &vector.data).is_err() {
        let _ = fs::remove_file(&partial);
        return false;
    }
    if fs::rename(&partial, cache_file).is_err() {
        let _ = fs::remove_file(&partial);
        return false;
    }
    true
}

fn print_progress(
    done: usize,
    total: usize,
    started: Instant,
    err: &mut dyn Write,
) -> Result<(), String> {
    let elapsed = started.elapsed().as_secs_f64().max(1e-9);
    let rate = done as f64 / elapsed;
    let remaining = if rate > 0.0 {
        total.saturating_sub(done) as f64 / rate
    } else {
        0.0
    };
    let eta = hms(remaining);
    emit(
        err,
        &format!(
            "[music-index] {done}/{total} files, {elapsed:.1}s elapsed, {rate:.2} files/s, ETA {eta}"
        ),
    )
}

/// Options for one index build; mirrors `build_index(...)` keyword arguments.
#[derive(Clone, Debug)]
pub struct BuildOptions {
    pub settings: Settings,
    pub device: String,
    pub jobs: i64,
    pub limit: Option<i64>,
    pub rebuild: bool,
    pub quiet: bool,
    pub threads: i64,
    pub adopt_legacy: bool,
}

/// Maximum number of failed `music-embed` batch attempts in the bisection
/// fallback (bounded so a broken model cannot cause thousands of model loads).
const MAX_BATCH_FAILURES: u32 = 64;

type StubEmbed<'a> = &'a dyn Fn(&Path) -> Vec<f64>;

fn slice_limit<T>(items: &[T], limit: i64) -> &[T] {
    if limit >= 0 {
        let limit = (limit as usize).min(items.len());
        &items[..limit]
    } else {
        let drop = limit.unsigned_abs() as usize;
        &items[..items.len().saturating_sub(drop)]
    }
}

/// Embed every audio file under `root` and write the index.
///
/// `embed` overrides the model with a plain callable (used by `--selftest`);
/// with it no `music-embed` process is started. Returns an exit code.
pub fn build_index(
    root: &Path,
    out_dir: &Path,
    options: &BuildOptions,
    embed: Option<StubEmbed<'_>>,
    err: &mut dyn Write,
) -> i32 {
    let root = fsutil::expand_user(root);
    if !root.is_dir() {
        write_message(
            err,
            &format!("[music-index] not a directory: {}", path_str(&root)),
        );
        return 2;
    }
    let out_dir = fsutil::expand_user(out_dir);
    let cache_dir = out_dir.join("cache");
    if let Err(error) = fs::create_dir_all(&cache_dir) {
        write_message(
            err,
            &format!(
                "[music-index] cannot create {}: {error}",
                path_str(&cache_dir)
            ),
        );
        return 1;
    }
    let settings = &options.settings;
    let signature = embed_signature(
        &settings.model,
        settings.layer,
        settings.window_seconds,
        settings.windows,
    );

    // Building with different settings than the index on disk means
    // re-embedding every file; say so before the pass starts.
    if let Some(existing_meta) = read_meta(&out_dir) {
        if !options.rebuild {
            if let Ok(recorded) = index_settings(&existing_meta) {
                if recorded != *settings {
                    write_message(
                        err,
                        &format!(
                            "[music-index] WARNING: the index in {} was built with model={} layer={} window_seconds={} windows={}; the current settings differ, so every file will be re-embedded. Re-run with --model {} --layer {} --window-seconds {} --windows {} to keep it, or pass --adopt-legacy to reuse its cache.",
                            path_str(&out_dir),
                            recorded.model,
                            recorded.layer,
                            format_g6(recorded.window_seconds),
                            recorded.windows,
                            recorded.model,
                            recorded.layer,
                            format_g6(recorded.window_seconds),
                            recorded.windows,
                        ),
                    );
                }
            }
        }
    }

    let mut files = fsutil::scan(&root, AUDIO_EXTS);
    if let Some(limit) = options.limit {
        if limit != 0 {
            files = slice_limit(&files, limit).to_vec();
        }
    }
    if files.is_empty() {
        write_message(
            err,
            &format!("[music-index] no audio files under {}", path_str(&root)),
        );
        return 2;
    }

    let stub = embed.is_some();
    let device = if stub {
        "stub".to_string()
    } else {
        options.device.clone()
    };
    if !options.quiet {
        write_message(
            err,
            &format!(
                "[music-index] {} files, {} on {}",
                files.len(),
                settings.model,
                device
            ),
        );
    }

    // Pre-signature entries are only trustworthy when meta.json attributes the
    // cache to the current settings; --rebuild always re-embeds.
    let can_migrate =
        !options.rebuild && (options.adopt_legacy || legacy_settings_match(&out_dir, settings));
    if options.adopt_legacy && !options.quiet {
        write_message(
            err,
            &format!(
                "[music-index] --adopt-legacy: treating pre-signature cache entries as if built with model={} layer={} window_seconds={} windows={}",
                settings.model,
                settings.layer,
                format_g6(settings.window_seconds),
                settings.windows,
            ),
        );
    }

    let mut pending: Vec<(PathBuf, PathBuf)> = Vec::new();
    let mut migrated = 0usize;
    for path in &files {
        let cache_file = cache_dir.join(format!("{}.npy", file_key(path, &signature)));
        if !options.rebuild && cache_file.exists() {
            continue;
        }
        if can_migrate && migrate_legacy_vector(path, &cache_file) {
            migrated += 1;
            continue;
        }
        pending.push((path.clone(), cache_file));
    }
    if migrated > 0 && !options.quiet {
        write_message(
            err,
            &format!("[music-index] migrated {migrated} cached vectors from the pre-signature key"),
        );
    }

    let started = Instant::now();
    let mut done = 0usize;
    let mut device_seen: Option<String> = None;
    if !pending.is_empty() {
        match embed {
            Some(stub_embedder) => {
                for (path, cache_file) in &pending {
                    let values = stub_embedder(path);
                    let values: Vec<f32> = values.into_iter().map(|value| value as f32).collect();
                    if let Err(error) = save_vector(cache_file, &values) {
                        write_message(
                            err,
                            &format!(
                                "[music-index] cannot write {}: {error}",
                                path_str(cache_file)
                            ),
                        );
                        return 1;
                    }
                    done += 1;
                    if !options.quiet && done % PROGRESS_EVERY == 0 {
                        if print_progress(done, pending.len(), started, err).is_err() {
                            return 1;
                        }
                    }
                }
            }
            None => match embed_pending(
                &pending,
                &cache_dir,
                options,
                err,
                started,
                &mut device_seen,
            ) {
                Ok(embedded) => done = embedded,
                Err(message) => {
                    write_message(err, &format!("[music-index] {message}"));
                    return 1;
                }
            },
        }
    }

    let device = if stub {
        "stub".to_string()
    } else {
        device_seen.unwrap_or_else(|| options.device.clone())
    };

    let mut rows: Vec<Vec<f32>> = Vec::new();
    let mut records: Vec<TrackRecord> = Vec::new();
    for path in &files {
        let cache_file = cache_dir.join(format!("{}.npy", file_key(path, &signature)));
        if !cache_file.exists() {
            continue;
        }
        let vector = match crate::npy::read_f32(&cache_file) {
            Ok(vector) => vector,
            Err(error) => {
                write_message(
                    err,
                    &format!(
                        "[music-index] cannot read {}: {error}",
                        path_str(&cache_file)
                    ),
                );
                return 1;
            }
        };
        if vector.shape.len() != 1 {
            write_message(
                err,
                &format!(
                    "[music-index] cached vector {} is not one-dimensional",
                    path_str(&cache_file)
                ),
            );
            return 1;
        }
        let metadata = path.metadata();
        let (mtime, size) = match metadata {
            Ok(metadata) => {
                use std::os::unix::fs::MetadataExt;
                (
                    metadata.mtime() * 1_000_000_000 + metadata.mtime_nsec(),
                    metadata.len() as i64,
                )
            }
            Err(_) => (0, 0),
        };
        let vector_index = rows.len();
        rows.push(vector.data);
        records.push(TrackRecord {
            path: path_str(path),
            mtime,
            size,
            vector_index,
        });
    }
    if rows.is_empty() {
        write_message(err, "[music-index] nothing embedded");
        return 1;
    }
    let dim = rows[0].len();
    if rows.iter().any(|row| row.len() != dim) {
        write_message(
            err,
            "[music-index] cached vectors disagree on their dimension; rebuild with music-index",
        );
        return 1;
    }
    let flat: Vec<f32> = rows.into_iter().flatten().collect();
    let matrix = Matrix::new(flat.len() / dim, dim, flat);
    let meta = Meta {
        entries: vec![
            ("model".to_string(), MetaValue::Str(settings.model.clone())),
            ("layer".to_string(), MetaValue::Int(settings.layer)),
            ("device".to_string(), MetaValue::Str(device.clone())),
            (
                "window_seconds".to_string(),
                MetaValue::Float(settings.window_seconds),
            ),
            ("windows".to_string(), MetaValue::Int(settings.windows)),
            ("signature".to_string(), MetaValue::Str(signature.clone())),
            ("dim".to_string(), MetaValue::Int(matrix.cols as i64)),
            ("count".to_string(), MetaValue::Int(matrix.rows as i64)),
            ("created".to_string(), MetaValue::Str(local_timestamp())),
        ],
    };
    if let Err(error) = write_index(&out_dir, &records, &matrix, &meta) {
        write_message(
            err,
            &format!("[music-index] cannot write the index: {error}"),
        );
        return 1;
    }
    if !options.quiet {
        write_message(
            err,
            &format!(
                "[music-index] {} tracks x {} dims -> {} ({} new, {:.1}s)",
                matrix.rows,
                matrix.cols,
                path_str(&out_dir),
                done,
                started.elapsed().as_secs_f64()
            ),
        );
    }
    0
}

/// Upper bound on files per `music-embed` invocation.
///
/// Linux caps argv at roughly 2 MiB (`E2BIG`), and a 37k-track library has
/// several megabytes of paths, so the pending list is passed in bounded chunks:
/// a handful of model loads instead of one process that cannot even be spawned.
/// The byte cap also keeps the temporary `.npy` matrix (and its memory use)
/// bounded and leaves room for unusually long paths.
const EMBED_CHUNK_FILES: usize = 8192;
const EMBED_CHUNK_BYTES: usize = 1_000_000;

/// Contiguous `[start, end)` ranges of `pending` that fit in one invocation.
fn embed_chunk_ranges(pending: &[(PathBuf, PathBuf)]) -> Vec<(usize, usize)> {
    let mut ranges = Vec::new();
    let mut start = 0usize;
    let mut bytes = 0usize;
    for (index, (path, _)) in pending.iter().enumerate() {
        let path_bytes = path_str(path).len() + 1;
        let full = index - start >= EMBED_CHUNK_FILES;
        let too_long = bytes > 0 && bytes + path_bytes > EMBED_CHUNK_BYTES;
        if index > start && (full || too_long) {
            ranges.push((start, index));
            start = index;
            bytes = 0;
        }
        bytes += path_bytes;
    }
    if start < pending.len() {
        ranges.push((start, pending.len()));
    }
    ranges
}

type GroupResult = Result<(Vec<Result<Vec<f32>, String>>, Option<String>), String>;

/// Embed a group of files, bisecting on failure so one bad file does not
/// discard the rest of the batch.
fn embed_group(
    files: &[PathBuf],
    embedder: &Embedder,
    cache_dir: &Path,
    seed: &str,
    progress: Option<&mut dyn FnMut(usize)>,
) -> GroupResult {
    let mut failures = 0u32;
    embed_group_inner(files, embedder, cache_dir, seed, progress, &mut failures)
}

fn embed_group_inner(
    files: &[PathBuf],
    embedder: &Embedder,
    cache_dir: &Path,
    seed: &str,
    progress: Option<&mut dyn FnMut(usize)>,
    failures: &mut u32,
) -> GroupResult {
    if files.is_empty() {
        return Ok((Vec::new(), None));
    }
    let tag = fsutil::unique_tag(seed);
    match embedder.embed_batch(files, cache_dir, &tag, progress) {
        Ok((array, device)) if array.shape.len() == 2 && array.shape[0] == files.len() => {
            let cols = array.shape[1];
            let mut results = Vec::with_capacity(files.len());
            for row in 0..files.len() {
                results.push(Ok(array.data[row * cols..(row + 1) * cols].to_vec()));
            }
            Ok((results, device))
        }
        Ok(_) => split_or_report(
            files,
            embedder,
            cache_dir,
            seed,
            failures,
            "music-embed returned an unexpected matrix shape".to_string(),
        ),
        Err(failure) if failure.spawn => Err(failure.message),
        Err(BatchFailure { message, .. }) => {
            // A failure that names one of the requested files is that file's
            // problem (bad audio, unreadable container); anything else came
            // from the model/environment and would fail every sub-batch, so
            // abort instead of bisecting into dozens of model loads.
            if files.len() > 1 && !failure_names_a_file(&message, files) {
                return Err(message);
            }
            split_or_report(files, embedder, cache_dir, seed, failures, message)
        }
    }
}

fn failure_names_a_file(message: &str, files: &[PathBuf]) -> bool {
    files.iter().any(|file| message.contains(&path_str(file)))
}

fn split_or_report(
    files: &[PathBuf],
    embedder: &Embedder,
    cache_dir: &Path,
    seed: &str,
    failures: &mut u32,
    message: String,
) -> GroupResult {
    if files.len() <= 1 {
        return Ok((vec![Err(message)], None));
    }
    *failures += 1;
    if *failures > MAX_BATCH_FAILURES {
        return Err(format!("music-embed failed repeatedly: {message}"));
    }
    let middle = files.len() / 2;
    let (mut left, left_device) =
        embed_group_inner(&files[..middle], embedder, cache_dir, seed, None, failures)?;
    let (right, right_device) =
        embed_group_inner(&files[middle..], embedder, cache_dir, seed, None, failures)?;
    left.extend(right);
    Ok((left, left_device.or(right_device)))
}

/// Embed one chunk at a time, streaming progress from `music-embed`'s
/// per-file stderr lines and writing each chunk's cache entries before the
/// next model load starts.
fn run_serial(
    pending: &[(PathBuf, PathBuf)],
    ranges: &[(usize, usize)],
    cache_dir: &Path,
    embedder: &Embedder,
    options: &BuildOptions,
    err: &mut dyn Write,
    started: Instant,
) -> Result<(usize, Option<String>), String> {
    let mut done = 0usize;
    let mut device: Option<String> = None;
    for (start, end) in ranges {
        let files: Vec<PathBuf> = pending[*start..*end]
            .iter()
            .map(|(path, _)| path.clone())
            .collect();
        let base = done;
        let tag = fsutil::unique_tag("serial");
        let (group, group_device) = {
            let mut callback = |count: usize| {
                let global = base + count;
                if !options.quiet && global % PROGRESS_EVERY == 0 {
                    let _ = print_progress(global, pending.len(), started, &mut *err);
                }
            };
            embed_group(&files, embedder, cache_dir, &tag, Some(&mut callback))?
        };
        if device.is_none() {
            device = group_device;
        }
        if group.len() != end - start {
            return Err(format!(
                "music-embed returned {} results for {} files",
                group.len(),
                end - start
            ));
        }
        for ((path, cache_file), result) in pending[*start..*end].iter().zip(group) {
            match result {
                Ok(values) => {
                    save_vector(cache_file, &values).map_err(|error| {
                        format!("cannot write {}: {error}", path_str(cache_file))
                    })?;
                    done += 1;
                }
                Err(message) => {
                    emit(
                        err,
                        &format!("[music-index] skip {}: {message}", path_str(path)),
                    )?;
                }
            }
        }
    }
    Ok((done, device))
}

/// Embed the chunks on up to `jobs` worker threads, one `music-embed` per
/// chunk (so `-j` really means several concurrent model processes).
fn run_parallel(
    pending: &[(PathBuf, PathBuf)],
    ranges: &[(usize, usize)],
    cache_dir: &Path,
    embedder: &Embedder,
    options: &BuildOptions,
) -> Result<(Vec<Result<Vec<f32>, String>>, Option<String>), String> {
    let workers = (options.jobs as usize).min(ranges.len()).max(1);
    let mut assignments: Vec<Vec<(usize, Vec<PathBuf>)>> =
        (0..workers).map(|_| Vec::new()).collect();
    for (ordinal, (start, end)) in ranges.iter().enumerate() {
        let files: Vec<PathBuf> = pending[*start..*end]
            .iter()
            .map(|(path, _)| path.clone())
            .collect();
        assignments[ordinal % workers].push((ordinal, files));
    }

    let mut threads = Vec::new();
    for assignment in assignments {
        let embedder = embedder.clone();
        let cache_dir = cache_dir.to_path_buf();
        threads.push(std::thread::spawn(move || {
            let mut chunks = Vec::new();
            for (ordinal, files) in assignment {
                let seed = format!("batch{ordinal}");
                let (group, device) = embed_group(&files, &embedder, &cache_dir, &seed, None)?;
                chunks.push((ordinal, group, device));
            }
            Ok::<_, String>(chunks)
        }));
    }

    let mut fatal: Option<String> = None;
    let mut groups: Vec<Option<(Vec<Result<Vec<f32>, String>>, Option<String>)>> =
        (0..ranges.len()).map(|_| None).collect();
    for thread in threads {
        match thread.join() {
            Ok(Ok(chunks)) => {
                if fatal.is_none() {
                    for (ordinal, group, device) in chunks {
                        if ordinal < groups.len() {
                            groups[ordinal] = Some((group, device));
                        }
                    }
                }
            }
            Ok(Err(message)) => {
                if fatal.is_none() {
                    fatal = Some(message);
                }
            }
            Err(_) => {
                if fatal.is_none() {
                    fatal = Some("a music-embed worker panicked".to_string());
                }
            }
        }
    }
    if let Some(message) = fatal {
        return Err(message);
    }

    let mut results = Vec::with_capacity(pending.len());
    let mut device = None;
    for group in groups {
        let (group, group_device) =
            group.ok_or_else(|| "a music-embed worker returned no results".to_string())?;
        if device.is_none() {
            device = group_device;
        }
        results.extend(group);
    }
    Ok((results, device))
}

fn embed_pending(
    pending: &[(PathBuf, PathBuf)],
    cache_dir: &Path,
    options: &BuildOptions,
    err: &mut dyn Write,
    started: Instant,
    device_seen: &mut Option<String>,
) -> Result<usize, String> {
    let settings = &options.settings;
    let embedder = Embedder::new(
        &settings.model,
        settings.layer,
        settings.window_seconds,
        settings.windows,
        &options.device,
        options.threads,
    );
    let ranges = embed_chunk_ranges(pending);
    if ranges.is_empty() {
        *device_seen = None;
        return Ok(0);
    }

    if options.jobs > 1 && ranges.len() > 1 {
        match run_parallel(pending, &ranges, cache_dir, &embedder, options) {
            Ok((results, device)) => {
                if results.len() != pending.len() {
                    return Err(format!(
                        "music-embed returned {} results for {} files",
                        results.len(),
                        pending.len()
                    ));
                }
                let mut done = 0usize;
                for ((path, cache_file), result) in pending.iter().zip(results) {
                    match result {
                        Ok(values) => {
                            save_vector(cache_file, &values).map_err(|error| {
                                format!("cannot write {}: {error}", path_str(cache_file))
                            })?;
                            done += 1;
                            if !options.quiet && done % PROGRESS_EVERY == 0 {
                                print_progress(done, pending.len(), started, err)?;
                            }
                        }
                        Err(message) => {
                            emit(
                                err,
                                &format!("[music-index] skip {}: {message}", path_str(path)),
                            )?;
                        }
                    }
                }
                *device_seen = device;
                return Ok(done);
            }
            Err(message) => {
                emit(
                    err,
                    &format!(
                        "[music-index] parallel workers unavailable ({message}); running serially"
                    ),
                )?;
            }
        }
    }

    let (done, device) = run_serial(
        pending, &ranges, cache_dir, &embedder, options, err, started,
    )?;
    *device_seen = device;
    Ok(done)
}

/// `--audit`: list scanned files that are not in the index.
pub fn audit_index(
    root: &Path,
    out_dir: &Path,
    limit: i64,
    stdout: &mut dyn Write,
    stderr: &mut dyn Write,
) -> i32 {
    let (meta, tracks, _matrix) = match load_index(out_dir) {
        Ok(index) => index,
        Err(problem) => {
            write_message(stderr, &format!("[music-index] {problem}"));
            return 2;
        }
    };
    let indexed: HashSet<String> = tracks
        .iter()
        .filter_map(|track| track.get("path").and_then(Value::as_str))
        .map(str::to_string)
        .collect();
    let scanned: Vec<String> = fsutil::scan(root, AUDIO_EXTS)
        .iter()
        .map(|path| path_str(path))
        .collect();
    let missing: Vec<&String> = scanned
        .iter()
        .filter(|path| !indexed.contains(*path))
        .collect();
    let created = meta
        .get("created")
        .map(to_py_str)
        .unwrap_or_else(|| "?".to_string());
    write_message(
        stdout,
        &format!(
            "[music-index] audit: {} indexed, {} scanned, {} missing (index built {})",
            indexed.len(),
            scanned.len(),
            missing.len(),
            created
        ),
    );
    if !missing.is_empty() {
        let mut by_ext: Vec<(String, usize)> = Vec::new();
        for path in &missing {
            let extension = std::path::Path::new(path)
                .extension()
                .map(|extension| format!(".{}", extension.to_string_lossy().to_lowercase()))
                .filter(|extension| !extension.is_empty())
                .unwrap_or_else(|| "?".to_string());
            match by_ext
                .iter_mut()
                .find(|(recorded, _)| *recorded == extension)
            {
                Some(entry) => entry.1 += 1,
                None => by_ext.push((extension, 1)),
            }
        }
        by_ext.sort_by(|left, right| right.1.cmp(&left.1));
        let summary = by_ext
            .iter()
            .map(|(extension, count)| format!("{extension} {count}"))
            .collect::<Vec<_>>()
            .join(", ");
        write_message(stdout, &format!("[music-index] by extension: {summary}"));
    }
    for path in slice_limit(&missing, limit) {
        write_message(stdout, path.as_str());
    }
    if missing.len() as i64 > limit {
        write_message(
            stdout,
            &format!("... and {} more", missing.len() as i64 - limit),
        );
    }
    0
}

/// Layer to pool: the explicit request wins, else the measured per-model one.
pub fn resolve_layer(model: &str, requested: Option<i64>) -> i64 {
    if let Some(layer) = requested {
        return layer;
    }
    match model {
        "m-a-p/MERT-v1-95M" => -2,
        "m-a-p/MERT-v2-30s" => -1,
        _ => -2,
    }
}

/// Parsed `music-index` command line.
#[derive(Clone, Debug)]
pub struct IndexArgs {
    pub root: String,
    pub out: String,
    pub model: String,
    pub layer: Option<i64>,
    pub device: String,
    pub window_seconds: f64,
    pub windows: i64,
    pub jobs: i64,
    pub limit: Option<i64>,
    pub rebuild: bool,
    pub threads: i64,
    pub quiet: bool,
    pub adopt_legacy: bool,
    pub selftest: bool,
    pub audit: bool,
    pub audit_limit: i64,
    pub help: bool,
}

impl IndexArgs {
    fn defaults() -> Self {
        Self {
            root: path_str(&crate::default_music_dir()),
            out: path_str(&crate::default_index_dir()),
            model: std::env::var("MUSIC_EMBED_MODEL")
                .unwrap_or_else(|_| crate::DEFAULT_MODEL.to_string()),
            layer: None,
            device: "auto".to_string(),
            window_seconds: crate::DEFAULT_WINDOW_SECONDS,
            windows: crate::DEFAULT_WINDOWS,
            jobs: 1,
            limit: None,
            rebuild: false,
            threads: 0,
            quiet: false,
            adopt_legacy: false,
            selftest: false,
            audit: false,
            audit_limit: 20,
            help: false,
        }
    }
}

pub fn usage() -> &'static str {
    "usage: music-index [-h] [--out OUT] [--model MODEL] [--layer LAYER]\n                   [--device DEVICE] [--window-seconds WINDOW_SECONDS]\n                   [--windows WINDOWS] [-j JOBS] [-n LIMIT] [--rebuild]\n                   [--threads THREADS] [--quiet] [--adopt-legacy] [--selftest]\n                   [--audit] [--audit-limit AUDIT_LIMIT] [root]"
}

pub fn help() -> &'static str {
    "usage: music-index [-h] [--out OUT] [--model MODEL] [--layer LAYER]\n                   [--device DEVICE] [--window-seconds WINDOW_SECONDS]\n                   [--windows WINDOWS] [-j JOBS] [-n LIMIT] [--rebuild]\n                   [--threads THREADS] [--quiet] [--adopt-legacy] [--selftest]\n                   [--audit] [--audit-limit AUDIT_LIMIT] [root]\n\nBuild a similarity index for a music library from model embeddings.\n\npositional arguments:\n  root                  music library root (default: ~/music)\n\noptions:\n  -h, --help            show this help message and exit\n  --out OUT             index dir (default: ~/.cache/music-index)\n  --model MODEL         model id (default: $MUSIC_EMBED_MODEL or m-a-p/MERT-v1-95M)\n  --layer LAYER         hidden layer to pool\n  --device DEVICE       auto, cpu or cuda\n  --window-seconds N    analysis window length (default: 10.0)\n  --windows N           windows per track (default: 3)\n  -j, --jobs N          parallel music-embed processes\n  -n, --limit N         only the first N files\n  --rebuild             ignore the cache\n  --threads N           torch CPU threads for embedding (0 = default)\n  --quiet               no progress output\n  --adopt-legacy        trust pre-signature cache entries\n  --selftest            run the offline stub-embedder self-check and exit\n  --audit               report scanned files missing from the index and exit\n  --audit-limit N       how many missing paths --audit prints (default: 20)\n"
}

fn option_value(
    argv: &[String],
    index: &mut usize,
    inline: Option<&str>,
    flag: &str,
) -> Result<String, String> {
    if let Some(value) = inline {
        return Ok(value.to_string());
    }
    *index += 1;
    argv.get(*index)
        .cloned()
        .ok_or_else(|| format!("argument {flag}: expected one argument"))
}

fn short_value(
    argv: &[String],
    index: &mut usize,
    rest: &str,
    flag: &str,
) -> Result<String, String> {
    if !rest.is_empty() {
        return Ok(rest.to_string());
    }
    *index += 1;
    argv.get(*index)
        .cloned()
        .ok_or_else(|| format!("argument {flag}: expected one argument"))
}

fn parse_int(flag: &str, text: &str) -> Result<i64, String> {
    text.parse::<i64>()
        .map_err(|_| format!("argument {flag}: invalid int value: '{text}'"))
}

fn parse_window_seconds(flag: &str, text: &str) -> Result<f64, String> {
    parse_float(text).ok_or_else(|| format!("argument {flag}: invalid float value: '{text}'"))
}

pub fn parse_args(argv: &[String]) -> Result<IndexArgs, String> {
    let mut args = IndexArgs::defaults();
    let mut positionals: Vec<String> = Vec::new();
    let mut index = 0;
    while index < argv.len() {
        let token = &argv[index];
        if token == "--" {
            positionals.extend_from_slice(&argv[index + 1..]);
            break;
        }
        if let Some(long) = token.strip_prefix("--") {
            let (name, inline) = match long.split_once('=') {
                Some((name, value)) => (name, Some(value)),
                None => (long, None),
            };
            match name {
                "help" => args.help = true,
                "rebuild" => args.rebuild = true,
                "quiet" => args.quiet = true,
                "adopt-legacy" => args.adopt_legacy = true,
                "selftest" => args.selftest = true,
                "audit" => args.audit = true,
                "out" => args.out = option_value(argv, &mut index, inline, "--out")?,
                "model" => args.model = option_value(argv, &mut index, inline, "--model")?,
                "layer" => {
                    let value = option_value(argv, &mut index, inline, "--layer")?;
                    args.layer = Some(parse_int("--layer", &value)?);
                }
                "device" => args.device = option_value(argv, &mut index, inline, "--device")?,
                "window-seconds" => {
                    let value = option_value(argv, &mut index, inline, "--window-seconds")?;
                    args.window_seconds = parse_window_seconds("--window-seconds", &value)?;
                }
                "windows" => {
                    let value = option_value(argv, &mut index, inline, "--windows")?;
                    args.windows = parse_int("--windows", &value)?;
                }
                "jobs" => {
                    let value = option_value(argv, &mut index, inline, "--jobs")?;
                    args.jobs = parse_int("-j/--jobs", &value)?;
                }
                "limit" => {
                    let value = option_value(argv, &mut index, inline, "--limit")?;
                    args.limit = Some(parse_int("-n/--limit", &value)?);
                }
                "threads" => {
                    let value = option_value(argv, &mut index, inline, "--threads")?;
                    args.threads = parse_int("--threads", &value)?;
                }
                "audit-limit" => {
                    let value = option_value(argv, &mut index, inline, "--audit-limit")?;
                    args.audit_limit = parse_int("--audit-limit", &value)?;
                }
                _ => return Err(format!("unrecognized arguments: {token}")),
            }
        } else if token.len() > 1 && token.starts_with('-') {
            let body = &token[1..];
            let mut chars = body.chars();
            let short = chars.next().expect("body is non-empty");
            let rest: String = chars.collect();
            let rest = rest.strip_prefix('=').unwrap_or(&rest).to_string();
            match short {
                'h' if rest.is_empty() => args.help = true,
                'j' => {
                    let value = short_value(argv, &mut index, &rest, "-j/--jobs")?;
                    args.jobs = parse_int("-j/--jobs", &value)?;
                }
                'n' => {
                    let value = short_value(argv, &mut index, &rest, "-n/--limit")?;
                    args.limit = Some(parse_int("-n/--limit", &value)?);
                }
                _ => return Err(format!("unrecognized arguments: {token}")),
            }
        } else {
            positionals.push(token.clone());
        }
        index += 1;
    }
    if positionals.len() > 1 {
        return Err(format!(
            "unrecognized arguments: {}",
            positionals[1..].join(" ")
        ));
    }
    if let Some(root) = positionals.pop() {
        args.root = root;
    }
    Ok(args)
}

fn check(condition: bool, message: impl Into<String>) -> Result<(), String> {
    if condition {
        Ok(())
    } else {
        Err(message.into())
    }
}

fn selftest_options(settings: Settings) -> BuildOptions {
    BuildOptions {
        settings,
        device: "auto".to_string(),
        jobs: 1,
        limit: None,
        rebuild: false,
        quiet: false,
        threads: 0,
        adopt_legacy: false,
    }
}

fn write_settings_only(out_dir: &Path, settings: &Settings) -> Result<(), String> {
    let value = serde_json::json!({
        "model": settings.model.clone(),
        "layer": settings.layer,
        "window_seconds": settings.window_seconds,
        "windows": settings.windows,
    });
    let text = serde_json::to_string(&value).map_err(|error| error.to_string())?;
    fs::create_dir_all(out_dir).map_err(|error| error.to_string())?;
    fs::write(out_dir.join("meta.json"), text).map_err(|error| error.to_string())
}

/// Offline self-check with the deterministic stub embedder.
pub fn selftest() -> i32 {
    match selftest_inner() {
        Ok(()) => {
            println!("[music-index] selftest: ok");
            0
        }
        Err(message) => {
            eprintln!("music-index selftest: {message}");
            1
        }
    }
}

fn selftest_inner() -> Result<(), String> {
    let signature = embed_signature("stub/model", -2, 10.0, 3);
    let variants = [
        embed_signature("other/model", -2, 10.0, 3),
        embed_signature("stub/model", -1, 10.0, 3),
        embed_signature("stub/model", -2, 5.0, 3),
        embed_signature("stub/model", -2, 10.0, 1),
    ];
    let mut distinct: HashSet<String> = HashSet::new();
    distinct.insert(signature.clone());
    distinct.extend(variants.iter().cloned());
    check(distinct.len() == 5, "signature ignores a setting")?;

    let first_temp = TempDir::new("music-index-selftest").map_err(|error| error.to_string())?;
    let path = first_temp.path().join("a.flac");
    fs::write(&path, b"").map_err(|error| error.to_string())?;
    let mut keys: HashSet<String> = HashSet::new();
    keys.insert(file_key(&path, &signature));
    for variant in &variants {
        keys.insert(file_key(&path, variant));
    }
    check(keys.len() == 5, "cache key does not fold in the signature")?;
    let vector = stub_embed(&path, STUB_DIM);
    check(
        vector == stub_embed(&path, STUB_DIM),
        "stub embedder is unstable",
    )?;
    check(vector.len() == STUB_DIM, "stub embedder has the wrong dim")?;
    let norm: f64 = vector.iter().map(|value| value * value).sum();
    check(
        (norm - 1.0).abs() < 1e-9,
        "stub embedder is not a unit vector",
    )?;
    drop(first_temp);

    let settings = Settings {
        model: "stub/model".to_string(),
        layer: -2,
        window_seconds: 10.0,
        windows: 3,
    };
    let stub = |path: &Path| stub_embed(path, STUB_DIM);
    let embed: Option<&dyn Fn(&Path) -> Vec<f64>> = Some(&stub);
    let expected = embed_signature(
        &settings.model,
        settings.layer,
        settings.window_seconds,
        settings.windows,
    );

    let temp = TempDir::new("music-index-selftest").map_err(|error| error.to_string())?;
    let root = temp.path().join("music");
    let out_dir = temp.path().join("index");
    let cache_dir = out_dir.join("cache");
    fs::create_dir_all(&cache_dir).map_err(|error| error.to_string())?;
    fs::create_dir(&root).map_err(|error| error.to_string())?;
    let mut legacy_names = Vec::new();
    for name in ["a", "b", "c"] {
        let file = root.join(format!("{name}.flac"));
        fs::write(&file, b"").map_err(|error| error.to_string())?;
        let legacy = legacy_file_key(&file);
        fs::write(cache_dir.join(format!("{legacy}.npy")), b"legacy")
            .map_err(|error| error.to_string())?;
        legacy_names.push(legacy);
    }
    let mut stderr = Vec::new();
    let options = selftest_options(settings.clone());
    let rc = build_index(&root, &out_dir, &options, embed, &mut stderr);
    let text = String::from_utf8_lossy(&stderr);
    check(rc == 0, "build_index failed")?;
    check(text.contains("3 new"), "first pass did not embed 3 files")?;
    check(
        !text.contains("migrated"),
        "legacy cache migrated without meta.json",
    )?;
    for legacy in &legacy_names {
        check(
            fs::read(cache_dir.join(format!("{legacy}.npy")))
                .map(|contents| contents == b"legacy")
                .unwrap_or(false),
            "an old cache file was deleted or overwritten",
        )?;
    }
    let (meta, tracks, matrix) = load_index(&out_dir).map_err(|problem| problem.0)?;
    check(
        matrix.rows == 3 && matrix.cols == STUB_DIM,
        format!("bad matrix ({}, {})", matrix.rows, matrix.cols),
    )?;
    check(tracks.len() == 3, "bad track records")?;
    check(
        meta.get("count").and_then(to_i64) == Some(3),
        "bad count in meta",
    )?;
    check(
        meta.get("dim").and_then(to_i64) == Some(STUB_DIM as i64),
        "bad dim in meta",
    )?;
    check(
        meta.get("signature").and_then(Value::as_str) == Some(expected.as_str()),
        "meta signature does not match the settings",
    )?;
    check(
        index_settings(&meta).map_err(|problem| problem.0)? == settings,
        "meta does not record the settings",
    )?;

    let mut stderr = Vec::new();
    let rc = build_index(&root, &out_dir, &options, embed, &mut stderr);
    let text = String::from_utf8_lossy(&stderr);
    check(rc == 0, "cached rebuild failed")?;
    check(text.contains("0 new"), "re-run did not reuse the cache")?;

    let mut changed = settings.clone();
    changed.windows = 1;
    let changed_options = selftest_options(changed);
    let mut stderr = Vec::new();
    let rc = build_index(&root, &out_dir, &changed_options, embed, &mut stderr);
    let text = String::from_utf8_lossy(&stderr);
    check(rc == 0, "rebuild after a settings change failed")?;
    check(
        text.contains("3 new"),
        "a settings change reused cached vectors",
    )?;

    // Legacy cache + matching meta.json: the vectors are copied under the
    // signature key instead of being re-embedded, and the legacy file is kept
    // for a concurrently running older build.
    let legacy_root = temp.path().join("legacy-music");
    let legacy_out = temp.path().join("legacy-index");
    let legacy_cache = legacy_out.join("cache");
    fs::create_dir(&legacy_root).map_err(|error| error.to_string())?;
    fs::create_dir_all(&legacy_cache).map_err(|error| error.to_string())?;
    let mut original: Vec<(PathBuf, Vec<f32>)> = Vec::new();
    for name in ["a", "b", "c"] {
        let file = legacy_root.join(format!("{name}.flac"));
        fs::write(&file, b"").map_err(|error| error.to_string())?;
        let vector: Vec<f32> = stub_embed(&file, STUB_DIM)
            .into_iter()
            .map(|value| value as f32)
            .collect();
        crate::npy::write_f32(
            &legacy_cache.join(format!("{}.npy", legacy_file_key(&file))),
            &[STUB_DIM],
            &vector,
        )
        .map_err(|error| error.to_string())?;
        original.push((file, vector));
    }
    write_settings_only(&legacy_out, &settings)?;

    let legacy_options = selftest_options(settings.clone());
    let mut stderr = Vec::new();
    let rc = build_index(
        &legacy_root,
        &legacy_out,
        &legacy_options,
        embed,
        &mut stderr,
    );
    let text = String::from_utf8_lossy(&stderr);
    check(rc == 0, "build with a matching legacy cache failed")?;
    check(
        text.contains("migrated 3 cached vectors"),
        "matching legacy cache was not migrated",
    )?;
    check(text.contains("0 new"), "migration did not reuse the cache")?;
    check(!text.contains("3 new"), "migration re-embedded anyway")?;
    for (file, vector) in &original {
        check(
            legacy_cache
                .join(format!("{}.npy", legacy_file_key(file)))
                .exists(),
            "migration deleted a legacy cache file",
        )?;
        let migrated =
            crate::npy::read_f32(&legacy_cache.join(format!("{}.npy", file_key(file, &expected))))
                .map_err(|error| error.to_string())?;
        check(
            migrated.data == *vector,
            "migrated vector differs from the legacy one",
        )?;
    }

    // Legacy cache + meta.json with other settings: no attribution, so the
    // files must be re-embedded.
    let mismatch_root = &legacy_root;
    let mismatch_out = temp.path().join("mismatch-index");
    let mismatch_cache = mismatch_out.join("cache");
    fs::create_dir_all(&mismatch_cache).map_err(|error| error.to_string())?;
    for (file, vector) in &original {
        crate::npy::write_f32(
            &mismatch_cache.join(format!("{}.npy", legacy_file_key(file))),
            &[STUB_DIM],
            vector,
        )
        .map_err(|error| error.to_string())?;
    }
    let mut mismatch = settings.clone();
    mismatch.windows = 1;
    write_settings_only(&mismatch_out, &mismatch)?;
    let mut stderr = Vec::new();
    let rc = build_index(
        mismatch_root,
        &mismatch_out,
        &legacy_options,
        embed,
        &mut stderr,
    );
    let text = String::from_utf8_lossy(&stderr);
    check(rc == 0, "build with a mismatching meta.json failed")?;
    check(
        !text.contains("migrated"),
        "mismatching meta migrated cache",
    )?;
    check(text.contains("3 new"), "mismatching meta did not re-embed")?;

    let incomplete = serde_json::json!({"model": "incomplete"});
    check(
        index_signature(&incomplete).is_err(),
        "incomplete meta was accepted",
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn per_file_failures_are_recognised_by_path() {
        let files = vec![
            PathBuf::from("/music/a.flac"),
            PathBuf::from("/music/b.flac"),
        ];
        assert!(failure_names_a_file(
            "no decodable audio in /music/b.flac (corrupt or empty file?)",
            &files
        ));
        assert!(!failure_names_a_file(
            "OSError: model m-a-p/MERT-v1-95M could not be downloaded",
            &files
        ));
    }
}

#[cfg(test)]
mod chunk_tests {
    use super::*;

    #[test]
    fn chunks_cover_all_files_and_bound_argv() {
        let pending: Vec<(PathBuf, PathBuf)> = (0..20_000)
            .map(|index| {
                (
                    PathBuf::from(format!("/music/album/{index}{}.flac", "x".repeat(100))),
                    PathBuf::new(),
                )
            })
            .collect();
        let ranges = embed_chunk_ranges(&pending);
        assert!(ranges.len() > 1);
        assert_eq!(ranges.first().unwrap().0, 0);
        assert_eq!(ranges.last().unwrap().1, pending.len());
        for (start, end) in &ranges {
            assert!(start < end, "empty chunk");
            assert!(end - start <= EMBED_CHUNK_FILES, "chunk too large");
            let bytes: usize = pending[*start..*end]
                .iter()
                .map(|(path, _)| path_str(path).len() + 1)
                .sum();
            assert!(bytes <= EMBED_CHUNK_BYTES, "chunk argv too large");
        }
        for pair in ranges.windows(2) {
            assert_eq!(pair[0].1, pair[1].0, "chunks do not cover every file");
        }
    }

    #[test]
    fn empty_pending_has_no_chunks() {
        assert!(embed_chunk_ranges(&[]).is_empty());
    }
}
