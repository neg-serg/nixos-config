//! Smoke tool for the MPD client: calls every command the client can send, once, and prints what
//! came back.
//!
//! Usage: `mpdtest [ADDR]` (default `127.0.0.1:6600`).
//!
//! It has to be safe to run against a daemon somebody is listening to, so the split is:
//!
//! * read-only checks run always — `status`, `stats`, `replay_gain_status`, the read form of
//!   `crossfade`, and `update`/`rescan` on a URI no library contains (the daemon queues a job that
//!   finds nothing, which is exactly enough to prove the `updating_db:` reply is parsed);
//! * mutating checks (setting crossfade, replay gain, `shuffle`, `prio`, `addtagid`/`cleartagid`,
//!   `seek_cur`) only run with `PLAYER_ALLOW_WRITES=1`, and the ones that flip a setting flip it
//!   back, so a run against a live daemon leaves it as it was;
//! * a full `update`/`rescan` walks the whole music directory, which is minutes of disk work on a
//!   real library, so it needs `PLAYER_FULL_SCAN=1` on top of the writes switch;
//! * a daemon that is not there is not an error: the line says `skip: <reason>` and the run goes on,
//!   so the tool doubles as a probe.
//!
//! `load`/`rm` are exercised on their **error** path here (a playlist name that cannot exist),
//! because their success path would append to or delete from real playlists; that path is covered
//! against the stub daemon instead.

use player_proto::mpd::{Client, ReplayGainMode, SeekSpec};
use std::time::Duration;

/// A URI no library contains, so `update`/`rescan` finish without touching the real database.
const VOID_URI: &str = "zzz-mpdtest-does-not-exist";
/// A playlist name no daemon has, so `load`/`rm` are answered with an ACK instead of acting.
const VOID_PLAYLIST: &str = "zzz-mpdtest-no-such-playlist";

const TIMEOUT: Duration = Duration::from_millis(2000);

fn main() {
    let addr = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "127.0.0.1:6600".to_string());
    let writes = writes_allowed();
    println!(
        "# addr={addr} writes={} (PLAYER_ALLOW_WRITES=1 enables the mutating half)",
        if writes { "on" } else { "off" }
    );

    let mut client = match Client::connect(&addr, TIMEOUT) {
        Ok(client) => Some(client),
        Err(e) => {
            println!("skip: connect {addr}: {e}");
            None
        }
    };

    // ---- read-only checks --------------------------------------------------------------

    report(&mut client, "status", |c| {
        let s = c.status()?;
        Ok(format!(
            "state={} volume={} song={:?} songid={:?} elapsed={:.3} duration={:.3} queue={} \
             repeat={} random={} single={} consume={}",
            s.state,
            s.volume,
            s.song,
            s.songid,
            s.elapsed,
            s.duration,
            s.queue_len,
            s.repeat,
            s.random,
            s.single,
            s.consume
        ))
    });
    report(&mut client, "status (new fields)", |c| {
        let s = c.status()?;
        Ok(format!(
            "crossfade={} replay_gain_mode={:?} bitrate={:?} audio={:?} playlist_version={} \
             error={:?}",
            s.crossfade, s.replay_gain_mode, s.bitrate, s.audio, s.playlist_version, s.error
        ))
    });
    report(&mut client, "crossfade() [read]", |c| {
        match c.crossfade(None)? {
            Some(secs) => Ok(format!("{secs} s")),
            None => Ok("not reported by this daemon (MPD >= 0.24 keeps it write-only)".to_string()),
        }
    });
    report(&mut client, "replay_gain_status()", |c| {
        Ok(format!("{}", c.replay_gain_status()?))
    });
    report(&mut client, "stats()", |c| {
        let s = c.stats()?;
        Ok(format!(
            "artists={} albums={} songs={} uptime={}s playtime={}s db_playtime={}s db_update={}",
            s.artists,
            s.albums,
            s.songs,
            s.uptime_secs,
            s.playtime_secs,
            s.db_playtime_secs,
            s.db_update_secs
        ))
    });
    report(&mut client, "update(Some(VOID_URI))", |c| {
        Ok(format!("job id {}", c.update(Some(VOID_URI))?))
    });
    report(&mut client, "rescan(Some(VOID_URI))", |c| {
        Ok(format!("job id {}", c.rescan(Some(VOID_URI))?))
    });
    // Expected ACK: proves the argument went out quoted and the ACK comes back as an error.
    report(
        &mut client,
        "load(VOID_PLAYLIST) [expect ACK]",
        |c| match c.load(VOID_PLAYLIST) {
            Ok(()) => Ok("OK (this daemon has such a playlist?)".to_string()),
            Err(e) => Ok(format!("ACK as expected: {e}")),
        },
    );
    report(
        &mut client,
        "rm(VOID_PLAYLIST, VOID_URI) [expect ACK]",
        |c| match c.rm(VOID_PLAYLIST, VOID_URI) {
            Ok(()) => Ok("OK (this daemon has such a playlist?)".to_string()),
            Err(e) => Ok(format!("ACK as expected: {e}")),
        },
    );

    // Value checks are local: they never touch the socket, so they run with or without a daemon.
    // They are what proves the client refuses to build a malformed line.
    for (spec, _note) in [
        (SeekSpec::Percent(101.0), "percent above 100"),
        (
            SeekSpec::Absolute(-5.0),
            "negative absolute (mean 'relative' on the wire)",
        ),
        (SeekSpec::Relative(f64::NAN), "not a number"),
        (SeekSpec::Absolute(86_401.0), "past the one-day cap"),
    ] {
        println!(
            "seek_cur({spec:?}) rejected locally: {}",
            described(spec.arg())
        );
    }

    // Legacy calls, kept so this stays the one binary that exercises the whole client.
    report(&mut client, "current_song()", |c| {
        match c.current_song()? {
            Some(song) => Ok(format!(
                "id={:?} artist={:?} title={:?}",
                song.id, song.artist, song.title
            )),
            None => Ok("none".to_string()),
        }
    });
    report(&mut client, "queue()", |c| {
        let q = c.queue()?;
        Ok(format!(
            "{} songs, first: {:?}",
            q.len(),
            q.first().map(|s| &s.title)
        ))
    });
    report(&mut client, "list_dir(\"\")", |c| {
        let e = c.list_dir("")?;
        Ok(format!("{} entries, first: {:?}", e.len(), e.first()))
    });
    report(&mut client, "search(\"a\")", |c| {
        Ok(format!("{} hits", c.search("a")?.len()))
    });
    report(&mut client, "list_tag(\"Artist\")", |c| {
        let v = c.list_tag("Artist")?;
        Ok(format!("{} artists (first {:?})", v.len(), v.first()))
    });
    report(&mut client, "playlists()", |c| {
        let v = c.playlists()?;
        Ok(format!("{:?}", v))
    });
    report(&mut client, "outputs()", |c| {
        let v = c.outputs()?;
        Ok(format!("{} outputs: {:?}", v.len(), v.first()))
    });
    report(&mut client, "find(Artist, \"Global Sect\")", |c| {
        Ok(format!("{} songs", c.find("Artist", "Global Sect")?.len()))
    });
    report(&mut client, "album_art(current)", |c| {
        match c.current_song()? {
            Some(song) => match c.album_art(&song.file) {
                Ok(bytes) => Ok(format!("{} bytes", bytes.len())),
                Err(e) => Ok(format!("no cover: {e}")),
            },
            None => Ok("nothing playing".to_string()),
        }
    });

    // ---- mutating checks ---------------------------------------------------------------

    if !writes {
        for name in [
            "crossfade(Some(current)) [round trip]",
            "replay_gain_mode(current) [no-op write]",
            "shuffle()",
            "prio(0, 0, 1)",
            "addtagid/cleartagid(current song)",
            "seek_cur(Relative(0.0))",
        ] {
            skip(
                name,
                "read-only run, set PLAYER_ALLOW_WRITES=1 to exercise it",
            );
        }
        finish();
        return;
    }

    // Read before write so the round trip can put the old value back.
    let current_crossfade = client
        .as_mut()
        .and_then(|c| c.crossfade(None).ok())
        .flatten()
        .unwrap_or(0);
    report(&mut client, "crossfade(Some(current)) [round trip]", |c| {
        let reported = c.crossfade(Some(current_crossfade))?;
        Ok(format!(
            "sent {current_crossfade}, daemon reports {reported:?}"
        ))
    });
    let current_gain = client
        .as_mut()
        .and_then(|c| c.replay_gain_status().ok())
        .unwrap_or(ReplayGainMode::Off);
    report(
        &mut client,
        "replay_gain_mode(current) [no-op write]",
        |c| {
            c.replay_gain_mode(current_gain)?;
            Ok(format!(
                "re-set {current_gain}, reads back {}",
                c.replay_gain_status()?
            ))
        },
    );
    report(&mut client, "shuffle()", |c| {
        c.shuffle()?;
        Ok("OK (queue order randomised)".to_string())
    });
    report(&mut client, "prio(0, 0, 1)", |c| {
        c.prio(0, 0, 1)?;
        Ok("OK (priority of the first queue entry set to 0)".to_string())
    });
    report(&mut client, "addtagid/cleartagid(current song)", |c| {
        let Some(song) = c.current_song()? else {
            return Ok("nothing playing, nothing to tag".to_string());
        };
        let Some(id) = song.id else {
            return Ok("current song carries no Id".to_string());
        };
        let id = id as u32;
        c.addtagid(id, "Title", "mpdtest")?;
        let seen = c
            .current_song()?
            .map(|s| s.title)
            .unwrap_or_else(|| "?".to_string());
        // Dropping the queue tag brings back what the file says, so the round trip leaves no trace.
        c.cleartagid(id, "Title")?;
        let restored = c
            .current_song()?
            .map(|s| s.title)
            .unwrap_or_else(|| "?".to_string());
        Ok(format!(
            "songid {id}: queue title {seen:?} while set, {restored:?} after cleartagid"
        ))
    });
    report(&mut client, "seek_cur(Relative(0.0))", |c| {
        c.seek_cur(SeekSpec::Relative(0.0))?;
        Ok("OK (seek to the position it is already at)".to_string())
    });
    // A full walk of the music directory: minutes of disk work, so it needs its own switch.
    if full_scan_allowed() {
        report(&mut client, "update(None)", |c| {
            Ok(format!("job id {}", c.update(None)?))
        });
        report(&mut client, "rescan(None)", |c| {
            Ok(format!("job id {}", c.rescan(None)?))
        });
    } else {
        for name in ["update(None)", "rescan(None)"] {
            skip(name, "whole-library scan, set PLAYER_FULL_SCAN=1 to run it");
        }
    }

    finish();
}

/// `PLAYER_ALLOW_WRITES=1` (anything but empty or `0`) turns the mutating half on.
fn writes_allowed() -> bool {
    switch("PLAYER_ALLOW_WRITES")
}

/// `PLAYER_FULL_SCAN=1` adds the two whole-library scans on top of that.
fn full_scan_allowed() -> bool {
    writes_allowed() && switch("PLAYER_FULL_SCAN")
}

fn switch(name: &str) -> bool {
    match std::env::var(name) {
        Ok(v) => !v.is_empty() && v != "0",
        Err(_) => false,
    }
}

fn skip(name: &str, reason: &str) {
    println!("skip: {name}: {reason}");
}

fn described(result: std::io::Result<String>) -> String {
    match result {
        Ok(text) => text,
        Err(e) => format!("refused: {e}"),
    }
}

/// Run one check and print its outcome; a missing client is a skip with a reason, never a panic.
///
/// The boxed error is what lets one closure mix the two error types the client has: `MpdError` from
/// the older methods and `io::Error` from the newer ones.
fn report<F>(client: &mut Option<Client>, name: &str, check: F)
where
    F: FnOnce(&mut Client) -> Result<String, Box<dyn std::error::Error>>,
{
    match client {
        None => skip(name, "no daemon connection"),
        Some(c) => match check(c) {
            Ok(text) => println!("{name}: {text}"),
            Err(e) => println!("{name} error: {e}"),
        },
    }
}

fn finish() {
    println!("# done");
}
