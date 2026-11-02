//! Rust port of `packages/local-bin/bin/shtoy`.
//!
//! The shell helper resolved a shader (a file, stdin, a cached or shipped id,
//! or a shadertoy.com URL), prepared it for `esshader`, and handed it to the
//! viewer. This crate keeps the same CLI, cache layout, diagnostics and exit
//! codes. The network paths (mirror search, API import) sit behind the
//! [`http::Http`] trait so tests can use fixtures instead of the network.
//!
//! Notes carried over from the shell helper:
//! - `_localbin.sh` defines no colour helpers, so every diagnostic is the plain
//!   `<prog>: <message>` line on stderr that `die`/`require` print.
//! - Shader preparation rewrites only what esshader cannot supply: `#version`
//!   and shebang lines are dropped, and `iFrame`/`iTimeDelta`/`iFrameRate`
//!   become defines when the source uses them without declaring them.
//! - `--mirror` never contacts shadertoy.com; it searches Sourcegraph and reads
//!   candidates from raw.githubusercontent.com through the same SOCKS proxy.
//!
//! One deliberate deviation in the mirror pipeline: the shell ran its `jq`
//! ranking once per `data:` line of the Sourcegraph stream (jq applies the
//! program to every input separately), while the documented ranking is global.
//! Here the `content` events of all `data:` lines are merged before
//! deduplication, sorting and the eight-candidate limit, which keeps the
//! ordering described in the shell header meaningful across a multi-batch
//! response. Everything else in the pipeline follows the jq expressions.

pub mod api;
pub mod cli;
pub mod env;
pub mod http;
pub mod mirror;
pub mod paths;
pub mod prepare;
pub mod source;
pub mod tempfile;
#[cfg(test)]
mod test_support;
pub mod viewer;

use std::ffi::OsString;
use std::fmt;
use std::io::Write;

/// Program name used as the prefix of every diagnostic (the shell helper took
/// it from its own file name, which is always `shtoy`).
pub const PROG: &str = "shtoy";

/// Help text: comment lines 2-51 of the original shell helper, already stripped
/// of the leading `# ` that `usage_from_header` removed.
pub const HELP: &str = include_str!("help.txt");

/// A fatal condition reported as `<prog>: <message>` with exit status 1.
#[derive(Debug)]
pub struct Die(String);

impl Die {
    pub fn new(message: impl Into<String>) -> Self {
        Self(message.into())
    }
}

impl fmt::Display for Die {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl std::error::Error for Die {}

/// Run the tool. Returns the process exit status on success; every expected
/// failure is a [`Die`] that `main` reports with exit status 1.
pub fn run(
    arguments: Vec<OsString>,
    environment: &env::Env,
    http: &dyn http::Http,
) -> Result<i32, Die> {
    let options = match cli::parse(&arguments)? {
        cli::Parsed::Help => {
            write_stdout(HELP)?;
            return Ok(0);
        }
        cli::Parsed::Run(options) => options,
    };

    let paths = paths::Paths::from_env(environment)?;

    if options.mode == cli::Mode::List {
        let listing = paths.list_shaders()?;
        write_stdout(&listing)?;
        return Ok(0);
    }

    let argument = options
        .arg
        .as_deref()
        .ok_or_else(|| Die::new("no shader given (see --help)"))?;
    let api_key = source::api_key(environment, &paths);
    let resolved = source::resolve(
        &options,
        argument,
        &paths,
        environment,
        http,
        api_key.as_deref(),
    )?;

    if options.save {
        write_stdout(&format!("{}\n", resolved.raw.display()))?;
        return Ok(0);
    }

    let shader_source = std::fs::read(&resolved.raw)
        .map_err(|error| Die::new(format!("cannot read {}: {error}", resolved.raw.display())))?;
    let rewrite = prepare::rewrite(&shader_source);

    // The guard keeps the prepared copy alive until esshader has exited.
    let (shader_file, _prepared_temp) = if rewrite.needed {
        let temporary = tempfile::TempFile::create(environment, "shtoy-", ".frag")?;
        std::fs::write(temporary.path(), &rewrite.body).map_err(|error| {
            Die::new(format!(
                "cannot write {}: {error}",
                temporary.path().display()
            ))
        })?;
        (temporary.path().to_path_buf(), Some(temporary))
    } else {
        (resolved.raw.clone(), None)
    };

    for channel in prepare::unbound_channels(&shader_source, &options.bound_channels) {
        eprintln!(
            "{PROG}: note: {} samples iChannel{} with no texture bound (--channel {} FILE)",
            resolved.raw.display(),
            channel,
            channel
        );
    }

    let mut legacy = options.legacy;
    if !legacy && prepare::auto_legacy(&shader_source) {
        legacy = true;
        eprintln!("{PROG}: GLES2/GLSL 100 requested by source (texture2D)");
    }

    let esshader = viewer::find_program("esshader", environment)
        .ok_or_else(|| Die::new("missing dependency: esshader"))?;

    let mut viewer_args: Vec<OsString> = vec![
        OsString::from("-f"),
        OsString::from("-s"),
        shader_file.clone().into_os_string(),
    ];
    if legacy {
        viewer_args.push(OsString::from("-l"));
    }
    if let Some(channel) = options.keyboard {
        viewer_args.push(OsString::from("-k"));
        viewer_args.push(OsString::from(channel.to_string()));
    }
    for (channel, file) in &options.channels {
        viewer_args.push(OsString::from(format!("-{channel}")));
        viewer_args.push(file.clone());
    }

    eprintln!("{PROG}: running {}", shader_file.display());
    viewer::run(&esshader, &viewer_args)
}

fn write_stdout(text: &str) -> Result<(), Die> {
    let mut stdout = std::io::stdout().lock();
    stdout
        .write_all(text.as_bytes())
        .and_then(|()| stdout.flush())
        .map_err(|error| Die::new(format!("cannot write to stdout: {error}")))
}
