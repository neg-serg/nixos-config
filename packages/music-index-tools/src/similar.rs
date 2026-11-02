//! Querying the nearest neighbours of a track from a music-index directory.
//!
//! Without an AUDIO argument the current track comes from `playerctl` (MPRIS),
//! which makes the binary a one-liner for a key binding. The embedding settings
//! come from the index `meta.json`, so a query is never embedded with settings
//! other than the ones the stored vectors were built with.

use std::fs;
use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};

use serde_json::Value;

use crate::embed::Embedder;
use crate::fsutil::{self, TempDir};
use crate::index::{
    index_settings, index_signature, load_index, write_index, Matrix, Meta, MetaValue, TrackRecord,
};
use crate::jsonw::push_json_string;
use crate::keys::{embed_signature, stub_embed};
use crate::py::{float_repr, path_str, round_to};
use crate::STUB_DIM;

/// Path of the track MPRIS reports as playing.
pub fn current_track_path() -> Option<String> {
    let output = Command::new("playerctl")
        .args(["metadata", "xesam:url"])
        .stderr(Stdio::inherit())
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let url = String::from_utf8_lossy(&output.stdout).trim().to_string();
    file_url_path(&url)
}

/// `unquote(urlparse(url).path)` for a `file://` URL.
fn file_url_path(url: &str) -> Option<String> {
    let rest = url.strip_prefix("file://")?;
    // urlparse treats everything up to the first slash as the host and stops
    // the path at a query or fragment.
    let path = match rest.find('/') {
        Some(position) => &rest[position..],
        None => "",
    };
    let path = path.split(['?', '#']).next().unwrap_or("");
    Some(percent_decode(path))
}

/// `urllib.parse.unquote` (UTF-8, invalid sequences replaced).
fn percent_decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' && index + 2 < bytes.len() {
            if let (Some(high), Some(low)) =
                (hex_value(bytes[index + 1]), hex_value(bytes[index + 2]))
            {
                out.push(high * 16 + low);
                index += 3;
                continue;
            }
        }
        out.push(bytes[index]);
        index += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn hex_value(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

/// Corpus mean vector: `center.npy` when the index has one, else derived.
fn load_center(index_dir: &Path, matrix: &Matrix) -> Vec<f32> {
    let center_path = index_dir.join("center.npy");
    if center_path.exists() {
        if let Ok(center) = crate::npy::read_f32(&center_path) {
            if center.shape == vec![matrix.cols] {
                return center.data;
            }
        }
    }
    matrix.mean_axis0()
}

/// Center both sides on the corpus mean and re-normalise to unit length.
///
/// MERT embeddings are strongly anisotropic, so neighbours were dominated by
/// hubs; subtracting the corpus mean from both sides and re-normalising lifted
/// same-album rank-1 from 0.213 to 0.232 and same-artist from 0.310 to 0.331 on
/// a 2000-query probe.
pub fn centered(
    mut matrix: Matrix,
    mut query: Vec<f32>,
    index_dir: &Path,
    enabled: bool,
) -> (Matrix, Vec<f32>) {
    if !enabled {
        return (matrix, query);
    }
    let center = load_center(index_dir, &matrix);
    for row in 0..matrix.rows {
        let start = row * matrix.cols;
        for column in 0..matrix.cols {
            matrix.data[start + column] -= center[column];
        }
        let mut squares = 0.0f32;
        for column in 0..matrix.cols {
            let value = matrix.data[start + column];
            squares += value * value;
        }
        let norm = squares.sqrt() + 1e-8f32;
        for column in 0..matrix.cols {
            matrix.data[start + column] /= norm;
        }
    }
    for (value, mean) in query.iter_mut().zip(center.iter()) {
        *value -= mean;
    }
    let mut squares = 0.0f32;
    for value in &query {
        squares += value * value;
    }
    let norm = squares.sqrt() + 1e-8f32;
    for value in query.iter_mut() {
        *value /= norm;
    }
    (matrix, query)
}

/// Top-k `(score, path)` pairs by cosine similarity, highest first.
pub fn rank(
    matrix: &Matrix,
    query: &[f32],
    k: i64,
    paths: Option<&[String]>,
    exclude_path: Option<&str>,
) -> Vec<(f64, String)> {
    if k <= 0 {
        return Vec::new();
    }
    let mut scores: Vec<f32> = Vec::with_capacity(matrix.rows);
    for row in 0..matrix.rows {
        let values = matrix.row(row);
        let mut score = 0.0f32;
        for column in 0..matrix.cols {
            score += values[column] * query[column];
        }
        scores.push(score);
    }
    let mut order: Vec<usize> = (0..matrix.rows).collect();
    // Python uses np.argsort(-scores), an unstable sort; a stable sort keeps
    // the index order for exact ties, which is at least deterministic.
    order.sort_by(|left, right| {
        scores[*right]
            .partial_cmp(&scores[*left])
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let excluded = exclude_path.map(resolved_path);
    let mut results = Vec::new();
    for row in order {
        let path = match paths {
            Some(paths) => paths[row].clone(),
            None => row.to_string(),
        };
        if let Some(excluded) = &excluded {
            if &resolved_path(&path) == excluded {
                continue;
            }
        }
        results.push((f64::from(scores[row]), path));
        if results.len() as i64 >= k {
            break;
        }
    }
    results
}

/// `Path(path).resolve()`; missing files fall back to a lexical absolute path.
fn resolved_path(path: &str) -> String {
    match fs::canonicalize(path) {
        Ok(resolved) => path_str(&resolved),
        Err(_) => path_str(&fsutil::lexical_absolute(Path::new(path))),
    }
}

/// Append every neighbour to the MPD queue; returns how many were queued.
pub fn queue_neighbours(
    results: &[(f64, String)],
    music_dir: &Path,
    mpc_cmd: &str,
    dry_run: bool,
    out: &mut dyn Write,
    err: &mut dyn Write,
) -> Result<usize, String> {
    let mut queued = 0usize;
    for (_score, path) in results {
        let uri = fsutil::relative_path(Path::new(path), music_dir);
        if uri.starts_with("..") {
            let _ = writeln!(
                err,
                "[music-similar] not under {}, skipped: {}",
                path_str(music_dir),
                path
            );
            continue;
        }
        if dry_run {
            let _ = writeln!(out, "{mpc_cmd} add {uri}");
            queued += 1;
            continue;
        }
        let output = Command::new(mpc_cmd)
            .arg("add")
            .arg(&uri)
            .output()
            .map_err(|error| format!("cannot run {mpc_cmd}: {error}"))?;
        if !output.status.success() {
            let stderr_text = String::from_utf8_lossy(&output.stderr);
            let stdout_text = String::from_utf8_lossy(&output.stdout);
            let source = if stderr_text.is_empty() {
                stdout_text
            } else {
                stderr_text
            };
            let detail = source.trim().lines().last().unwrap_or("").to_string();
            let _ = writeln!(err, "[music-similar] mpc add {uri} failed: {detail}");
            continue;
        }
        let _ = writeln!(out, "queued: {uri}");
        queued += 1;
    }
    Ok(queued)
}

/// Parsed `music-similar` command line.
#[derive(Clone, Debug)]
pub struct SimilarArgs {
    pub audio: Option<String>,
    pub index: String,
    pub k: i64,
    pub json: bool,
    pub device: String,
    pub keep_self: bool,
    pub selftest: bool,
    pub queue: bool,
    pub music_dir: String,
    pub mpc_cmd: String,
    pub dry_run: bool,
    pub no_center: bool,
    pub help: bool,
}

impl SimilarArgs {
    fn defaults() -> Self {
        Self {
            audio: None,
            index: path_str(&crate::default_index_dir()),
            k: 15,
            json: false,
            device: "auto".to_string(),
            keep_self: false,
            selftest: false,
            queue: false,
            music_dir: std::env::var("MUSIC_DIR")
                .unwrap_or_else(|_| path_str(&crate::default_music_dir())),
            mpc_cmd: std::env::var("MPC_CMD").unwrap_or_else(|_| "mpc".to_string()),
            dry_run: false,
            no_center: false,
            help: false,
        }
    }
}

pub fn usage() -> &'static str {
    "usage: music-similar [-h] [--index INDEX] [-k K] [--json] [--device DEVICE]\n                     [--self] [--selftest] [--queue] [--music-dir MUSIC_DIR]\n                     [--mpc-cmd MPC_CMD] [--dry-run] [--no-center] [audio]"
}

pub fn help() -> &'static str {
    "usage: music-similar [-h] [--index INDEX] [-k K] [--json] [--device DEVICE]\n                     [--self] [--selftest] [--queue] [--music-dir MUSIC_DIR]\n                     [--mpc-cmd MPC_CMD] [--dry-run] [--no-center] [audio]\n\nQuery the nearest neighbours of a track from a music-index directory.\n\npositional arguments:\n  audio                 query file (default: playerctl)\n\noptions:\n  -h, --help            show this help message and exit\n  --index INDEX         index dir (default: ~/.cache/music-index)\n  -k K                  neighbours to print (default: 15)\n  --json                machine output\n  --device DEVICE       auto, cpu or cuda\n  --self                keep the query track itself in the results\n  --selftest            run the offline stub-embedder self-check and exit\n  --queue               append the neighbours to the MPD queue with mpc\n  --music-dir MUSIC_DIR MPD music_directory (default: $MUSIC_DIR or ~/music)\n  --mpc-cmd MPC_CMD     command used for --queue (default: $MPC_CMD or mpc)\n  --dry-run             with --queue: print the commands without running them\n  --no-center           skip the corpus-mean correction\n"
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

pub fn parse_args(argv: &[String]) -> Result<SimilarArgs, String> {
    let mut args = SimilarArgs::defaults();
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
                "json" => args.json = true,
                "self" => args.keep_self = true,
                "selftest" => args.selftest = true,
                "queue" => args.queue = true,
                "dry-run" => args.dry_run = true,
                "no-center" => args.no_center = true,
                "index" => args.index = option_value(argv, &mut index, inline, "--index")?,
                "device" => args.device = option_value(argv, &mut index, inline, "--device")?,
                "music-dir" => {
                    args.music_dir = option_value(argv, &mut index, inline, "--music-dir")?
                }
                "mpc-cmd" => args.mpc_cmd = option_value(argv, &mut index, inline, "--mpc-cmd")?,
                "k" => {
                    let value = option_value(argv, &mut index, inline, "-k")?;
                    args.k = parse_int("-k", &value)?;
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
                'k' => {
                    let value = short_value(argv, &mut index, &rest, "-k")?;
                    args.k = parse_int("-k", &value)?;
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
    if let Some(audio) = positionals.pop() {
        args.audio = Some(audio);
    }
    Ok(args)
}

/// Run one query or queue request; returns the process exit code.
pub fn run(args: &SimilarArgs, out: &mut dyn Write, err: &mut dyn Write) -> i32 {
    let index_dir = fsutil::expand_user(Path::new(&args.index));
    let (meta, tracks, matrix) = match load_index(&index_dir) {
        Ok(index) => index,
        Err(problem) => {
            let _ = writeln!(err, "[music-similar] {problem}");
            return 2;
        }
    };
    let settings = match index_settings(&meta) {
        Ok(settings) => settings,
        Err(problem) => {
            let _ = writeln!(err, "[music-similar] {problem}");
            return 2;
        }
    };

    let audio = args
        .audio
        .as_deref()
        .filter(|audio| !audio.is_empty())
        .map(str::to_string)
        .or_else(current_track_path);
    let audio = match audio {
        Some(audio) if !audio.is_empty() => audio,
        _ => {
            let _ = writeln!(
                err,
                "[music-similar] no audio argument and no playerctl track"
            );
            return 2;
        }
    };
    let query_path = fsutil::expand_user(Path::new(&audio));
    if !query_path.exists() {
        let _ = writeln!(
            err,
            "[music-similar] file not found: {}",
            path_str(&query_path)
        );
        return 2;
    }

    let embedder = Embedder::new(
        &settings.model,
        settings.layer,
        settings.window_seconds,
        settings.windows,
        &args.device,
        0,
    );
    let query = match embedder.embed_query(&query_path) {
        Ok(query) => query,
        Err(message) => {
            let _ = writeln!(err, "[music-similar] {message}");
            return 1;
        }
    };

    let paths: Vec<String> = tracks
        .iter()
        .map(|track| {
            track
                .get("path")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string()
        })
        .collect();
    let exclude = if args.keep_self {
        None
    } else {
        Some(path_str(&query_path))
    };
    let (matrix, query) = centered(matrix, query, &index_dir, !args.no_center);
    let results = rank(&matrix, &query, args.k, Some(&paths), exclude.as_deref());

    if args.queue {
        let music_dir = fsutil::expand_user(Path::new(&args.music_dir));
        if !music_dir.is_dir() {
            let _ = writeln!(
                err,
                "[music-similar] music directory not found: {}",
                path_str(&music_dir)
            );
            return 2;
        }
        let queued =
            match queue_neighbours(&results, &music_dir, &args.mpc_cmd, args.dry_run, out, err) {
                Ok(queued) => queued,
                Err(message) => {
                    let _ = writeln!(err, "[music-similar] {message}");
                    return 1;
                }
            };
        let _ = writeln!(err, "[music-similar] queued {queued} of {}", results.len());
        return if queued > 0 { 0 } else { 1 };
    }

    if args.json {
        let mut text = String::from("{\"query\": ");
        push_json_string(&mut text, &path_str(&query_path), false);
        text.push_str(", \"model\": ");
        push_json_string(&mut text, &settings.model, false);
        text.push_str(", \"results\": [");
        for (position, (score, path)) in results.iter().enumerate() {
            if position > 0 {
                text.push_str(", ");
            }
            text.push_str("{\"score\": ");
            text.push_str(&float_repr(round_to(*score, 4)));
            text.push_str(", \"path\": ");
            push_json_string(&mut text, path, false);
            text.push('}');
        }
        text.push_str("]}");
        let _ = writeln!(out, "{text}");
    } else {
        for (score, path) in &results {
            let _ = writeln!(out, "{score:6.3}  {path}");
        }
    }
    0
}

fn check(condition: bool, message: impl Into<String>) -> Result<(), String> {
    if condition {
        Ok(())
    } else {
        Err(message.into())
    }
}

/// Offline self-check: stub vectors, ranking and index errors.
pub fn selftest() -> i32 {
    match selftest_inner() {
        Ok(()) => {
            println!("[music-similar] selftest: ok");
            0
        }
        Err(message) => {
            eprintln!("music-similar selftest: {message}");
            1
        }
    }
}

fn selftest_inner() -> Result<(), String> {
    let incomplete = serde_json::json!({"model": "incomplete"});
    check(
        index_signature(&incomplete).is_err(),
        "incomplete meta was accepted",
    )?;

    let matrix = Matrix::new(
        3,
        3,
        vec![
            1.0, 0.0, 0.0, // the query vector itself
            1.0, 0.0, 0.0, // its identical twin
            0.0, 1.0, 0.0, // orthogonal
        ],
    );
    let query = vec![1.0, 0.0, 0.0];
    let paths = vec![
        "self.wav".to_string(),
        "twin.wav".to_string(),
        "other.wav".to_string(),
    ];
    let results = rank(&matrix, &query, 3, Some(&paths), None);
    let mut nearest: Vec<&str> = results
        .iter()
        .take(2)
        .map(|(_score, path)| path.as_str())
        .collect();
    nearest.sort_unstable();
    check(
        nearest == ["self.wav", "twin.wav"],
        "nearest neighbours are not the identical pair",
    )?;
    check(results[0].0 > 0.999, "identical vector score is not 1")?;
    check(
        results[2].1 == "other.wav" && results[2].0.abs() < 1e-6,
        "orthogonal vector is not ranked last",
    )?;
    check(
        rank(&matrix, &query, 1, Some(&paths), None).len() == 1,
        "-k not honoured",
    )?;
    check(
        rank(&matrix, &query, 0, Some(&paths), None).is_empty(),
        "-k 0 not honoured",
    )?;
    let excluded = rank(&matrix, &query, 3, Some(&paths), Some("self.wav"));
    check(
        excluded
            .iter()
            .map(|(_score, path)| path.as_str())
            .collect::<Vec<_>>()
            == ["twin.wav", "other.wav"],
        "self-exclusion dropped the wrong row",
    )?;
    let selftest_args = parse_args(&["--selftest".to_string()])?;
    check(selftest_args.selftest, "--selftest not parsed")?;
    let short_args = parse_args(&["-k".to_string(), "3".to_string()])?;
    check(short_args.k == 3, "-k not parsed")?;

    let temp = TempDir::new("music-similar-selftest").map_err(|error| error.to_string())?;
    let audio = temp.path().join("query.wav");
    fs::write(&audio, b"").map_err(|error| error.to_string())?;
    let twin_dir = temp.path().join("twin");
    fs::create_dir(&twin_dir).map_err(|error| error.to_string())?;
    let twin = twin_dir.join("query.wav");
    fs::write(&twin, b"").map_err(|error| error.to_string())?;
    let other = temp.path().join("other.wav");
    fs::write(&other, b"x").map_err(|error| error.to_string())?;
    let query_vec = stub_embed(&audio, STUB_DIM);
    let twin_vec = stub_embed(&twin, STUB_DIM);
    check(query_vec == twin_vec, "stub embedder is not name-stable")?;
    let mut stub_data: Vec<f32> = Vec::new();
    for vector in [&query_vec, &twin_vec, &stub_embed(&other, STUB_DIM)] {
        stub_data.extend(vector.iter().map(|value| *value as f32));
    }
    let stub_matrix = Matrix::new(3, STUB_DIM, stub_data);
    let stub_paths = vec![path_str(&audio), path_str(&twin), path_str(&other)];
    let query32: Vec<f32> = query_vec.iter().map(|value| *value as f32).collect();
    let neighbours = rank(&stub_matrix, &query32, 2, Some(&stub_paths), None);
    check(
        neighbours[0].0 > 0.99 && stub_paths[..2].contains(&neighbours[0].1),
        "stub nearest neighbour is wrong",
    )?;

    let missing = temp.path().join("missing-index");
    match load_index(&missing) {
        Err(problem) => check(
            problem.0.contains("no index"),
            format!("unclear error: {}", problem.0),
        )?,
        Ok(_) => return Err("missing index was accepted".to_string()),
    }
    let missing_args = parse_args(&[
        "--index".to_string(),
        path_str(&missing),
        "--json".to_string(),
    ])?;
    let mut out = Vec::new();
    let mut err = Vec::new();
    let rc = run(&missing_args, &mut out, &mut err);
    check(rc != 0, "main accepted a missing index")?;
    check(
        String::from_utf8_lossy(&err).contains("no index"),
        "main error is unclear",
    )?;

    let index_dir = temp.path().join("index");
    let records = vec![TrackRecord {
        path: path_str(&audio),
        mtime: 0,
        size: 0,
        vector_index: 0,
    }];
    let vectors = Matrix::new(1, 3, vec![1.0, 0.0, 0.0]);
    let signature = embed_signature("stub/model", -2, 10.0, 3);
    let meta = Meta {
        entries: vec![
            (
                "model".to_string(),
                MetaValue::Str("stub/model".to_string()),
            ),
            ("layer".to_string(), MetaValue::Int(-2)),
            ("window_seconds".to_string(), MetaValue::Float(10.0)),
            ("windows".to_string(), MetaValue::Int(3)),
            ("signature".to_string(), MetaValue::Str(signature.clone())),
            ("dim".to_string(), MetaValue::Int(3)),
            ("count".to_string(), MetaValue::Int(1)),
        ],
    };
    write_index(&index_dir, &records, &vectors, &meta).map_err(|error| error.to_string())?;
    let (loaded_meta, loaded_tracks, loaded) =
        load_index(&index_dir).map_err(|problem| problem.0)?;
    check(
        loaded.rows == 1
            && loaded.cols == 3
            && loaded_meta.get("signature").and_then(Value::as_str) == Some(signature.as_str()),
        "load_index returned the wrong data",
    )?;
    check(
        loaded_tracks[0].get("path").and_then(Value::as_str) == Some(path_str(&audio).as_str()),
        "load_index returned the wrong tracks",
    )?;

    // A legacy index without a signature is accepted when its settings are
    // complete: the signature is derived from the recorded settings.
    let legacy_meta = Meta {
        entries: meta
            .entries
            .iter()
            .filter(|(key, _)| key != "signature")
            .cloned()
            .collect(),
    };
    write_index(&index_dir, &records, &vectors, &legacy_meta).map_err(|error| error.to_string())?;
    load_index(&index_dir).map_err(|problem| problem.0)?;

    // A signature that disagrees with the recorded settings is refused.
    let mut bad = meta.clone();
    for (key, value) in bad.entries.iter_mut() {
        if key == "signature" {
            *value = MetaValue::Str("0".repeat(12));
        }
    }
    write_index(&index_dir, &records, &vectors, &bad).map_err(|error| error.to_string())?;
    match load_index(&index_dir) {
        Err(problem) => check(
            problem.0.contains("signature"),
            format!("unclear error: {}", problem.0),
        )?,
        Ok(_) => return Err("mismatched signature was accepted".to_string()),
    }
    let bad_args = parse_args(&[
        "--index".to_string(),
        path_str(&index_dir),
        "--json".to_string(),
    ])?;
    let mut out = Vec::new();
    let mut err = Vec::new();
    let rc = run(&bad_args, &mut out, &mut err);
    check(rc != 0, "main accepted an incompatible index")?;
    check(
        String::from_utf8_lossy(&err).contains("signature"),
        "main signature error is unclear",
    )?;

    // Incomplete meta (settings cannot be established) is refused too.
    let mut incomplete_meta = meta.clone();
    incomplete_meta
        .entries
        .retain(|(key, _)| key != "signature" && key != "windows");
    write_index(&index_dir, &records, &vectors, &incomplete_meta)
        .map_err(|error| error.to_string())?;
    check(
        load_index(&index_dir).is_err(),
        "incomplete meta was accepted",
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn file_urls_decode_like_python() {
        assert_eq!(
            file_url_path("file:///home/neg/music/a%20b.flac").as_deref(),
            Some("/home/neg/music/a b.flac")
        );
        assert_eq!(
            file_url_path("file://host/tmp/caf%C3%A9.flac?x=1#y").as_deref(),
            Some("/tmp/café.flac")
        );
        assert_eq!(file_url_path("http://example/x"), None);
        assert_eq!(
            file_url_path("file:///tmp/a%2").as_deref(),
            Some("/tmp/a%2")
        );
    }

    #[test]
    fn centering_uses_the_saved_corpus_mean() {
        let temp = TempDir::new("center-test").unwrap();
        let center = temp.path().join("center.npy");
        crate::npy::write_f32(&center, &[2], &[1.0, 0.0]).unwrap();
        let matrix = Matrix::new(2, 2, vec![2.0, 0.0, 0.0, 1.0]);
        let query = vec![2.0, 0.0];
        let (centered_matrix, centered_query) =
            centered(matrix.clone(), query.clone(), temp.path(), true);
        assert!((centered_matrix.row(0)[0] - 1.0).abs() < 1e-6);
        assert!(centered_matrix.row(0)[1].abs() < 1e-6);
        let norm = (centered_matrix.row(1)[0].powi(2) + centered_matrix.row(1)[1].powi(2)).sqrt();
        assert!((norm - 1.0).abs() < 1e-6);
        assert!((centered_query[0] - 1.0).abs() < 1e-6);
        // --no-center leaves both sides untouched.
        let (plain_matrix, plain_query) =
            centered(matrix.clone(), query.clone(), temp.path(), false);
        assert_eq!(plain_matrix, matrix);
        assert_eq!(plain_query, query);
    }

    #[test]
    fn rank_orders_and_excludes() {
        let matrix = Matrix::new(3, 2, vec![1.0, 0.0, 0.0, 1.0, -1.0, 0.0]);
        let paths = vec!["a".to_string(), "b".to_string(), "c".to_string()];
        let results = rank(&matrix, &[1.0, 0.0], 3, Some(&paths), None);
        assert_eq!(results[0].1, "a");
        assert_eq!(results[1].1, "b");
        assert_eq!(results[2].1, "c");
        assert!(results[2].0 < 0.0);
        assert_eq!(rank(&matrix, &[1.0, 0.0], -1, Some(&paths), None), vec![]);
        let excluded = rank(&matrix, &[1.0, 0.0], 5, Some(&paths), Some("a"));
        assert_eq!(
            excluded
                .iter()
                .map(|(_score, path)| path.as_str())
                .collect::<Vec<_>>(),
            ["b", "c"]
        );
    }
}
