//! A minimal MPRIS player on the session bus, for checking what a scene does
//! with a player that cannot skip.
//!
//! Port of `files/pleamar/scripts/fixtures/mpris-stub.py`. It owns
//! `org.mpris.MediaPlayer2.stub` by default, so the engine's `media` service
//! follows it as the most recent player, and its answers are arguments:
//!
//!     mpris-stub --can-go-next false     # the dimmed transport button
//!     mpris-stub --can-go-next true      # the plain one
//!
//! `pleamar --say bar "get media.can_go_next"` answers what it says.

use std::collections::HashMap;
use std::process::ExitCode;
use zbus::blocking::Connection;
use zbus::interface;
use zbus::zvariant::{ObjectPath, Value};

const TRACK: &str = "/org/stub/Track/1";

struct Args {
    name: String,
    title: String,
    artist: String,
    art: String,
    url: String,
    status: String,
    can_go_next: bool,
    can_go_previous: bool,
    can_play: bool,
    can_pause: bool,
}

const USAGE: &str = "\
usage: mpris-stub [-h] [--name NAME] [--title TITLE] [--artist ARTIST]
                  [--art ART] [--url URL] [--status STATUS]
                  [--can-go-next {true,false}] [--can-go-prev {true,false}]
                  [--can-play {true,false}] [--can-pause {true,false}]";

fn usage_error(message: &str) -> ExitCode {
    eprintln!("usage: mpris-stub [-h] [--name NAME] [--title TITLE] [--artist ARTIST]");
    eprintln!("                   [--art ART] [--url URL] [--status STATUS]");
    eprintln!("                   [--can-go-next {{true,false}}] [--can-go-prev {{true,false}}]");
    eprintln!("                   [--can-play {{true,false}}] [--can-pause {{true,false}}]");
    eprintln!("mpris-stub: error: {message}");
    ExitCode::from(2)
}

fn parse_bool(option: &str, value: &str) -> Result<bool, String> {
    match value {
        "true" => Ok(true),
        "false" => Ok(false),
        other => Err(format!(
            "argument {option}: invalid choice: '{other}' (choose from 'true', 'false')"
        )),
    }
}

fn parse_args() -> Result<Args, String> {
    let mut args = Args {
        name: "org.mpris.MediaPlayer2.stub".to_string(),
        title: "Stub track".to_string(),
        artist: "Stub artist".to_string(),
        art: "file:///tmp/stub-cover.jpg".to_string(),
        url: String::new(),
        status: "Playing".to_string(),
        can_go_next: false,
        can_go_previous: true,
        can_play: true,
        can_pause: true,
    };
    let mut argv = std::env::args().skip(1);
    while let Some(arg) = argv.next() {
        if arg == "-h" || arg == "--help" {
            println!("{USAGE}");
            std::process::exit(0);
        }
        let (option, value) = match arg.split_once('=') {
            Some((option, value)) => (option.to_string(), Some(value.to_string())),
            None => (arg.clone(), None),
        };
        let mut take = |name: &str| -> Result<String, String> {
            value
                .clone()
                .or_else(|| argv.next())
                .ok_or_else(|| format!("argument {name}: expected one argument"))
        };
        match option.as_str() {
            "--name" => args.name = take("--name")?,
            "--title" => args.title = take("--title")?,
            "--artist" => args.artist = take("--artist")?,
            "--art" => args.art = take("--art")?,
            "--url" => args.url = take("--url")?,
            "--status" => args.status = take("--status")?,
            "--can-go-next" => {
                args.can_go_next = parse_bool("--can-go-next", &take("--can-go-next")?)?
            }
            "--can-go-prev" => {
                args.can_go_previous = parse_bool("--can-go-prev", &take("--can-go-prev")?)?
            }
            "--can-play" => args.can_play = parse_bool("--can-play", &take("--can-play")?)?,
            "--can-pause" => args.can_pause = parse_bool("--can-pause", &take("--can-pause")?)?,
            other => return Err(format!("unrecognized arguments: {other}")),
        }
    }
    Ok(args)
}

struct Player {
    args: Args,
    loop_status: String,
    rate: f64,
    shuffle: bool,
    volume: f64,
}

/// `org.mpris.MediaPlayer2` is a separate type: zbus generates one
/// `Interface` impl per type, so two interfaces cannot share one struct.
struct Root;

#[interface(name = "org.mpris.MediaPlayer2")]
impl Root {
    fn raise(&self) {}
    fn quit(&self) {}

    #[zbus(property)]
    fn can_quit(&self) -> bool {
        false
    }

    #[zbus(property)]
    fn can_raise(&self) -> bool {
        false
    }

    #[zbus(property)]
    fn has_track_list(&self) -> bool {
        false
    }

    #[zbus(property)]
    fn identity(&self) -> String {
        "stub".to_string()
    }

    #[zbus(property)]
    fn desktop_entry(&self) -> String {
        "stub".to_string()
    }

    #[zbus(property)]
    fn supported_uri_schemes(&self) -> Vec<String> {
        Vec::new()
    }

    #[zbus(property)]
    fn supported_mime_types(&self) -> Vec<String> {
        Vec::new()
    }
}

#[interface(name = "org.mpris.MediaPlayer2.Player")]
impl Player {
    fn next(&self) {}
    fn previous(&self) {}
    fn pause(&self) {}
    fn play_pause(&self) {}
    fn stop(&self) {}
    fn play(&self) {}

    fn seek(&self, offset: i64) {
        let _ = offset;
    }

    fn set_position(&self, track_id: ObjectPath<'_>, position: i64) {
        let _ = (track_id, position);
    }

    fn open_uri(&self, uri: String) {
        let _ = uri;
    }

    #[zbus(signal)]
    async fn seeked(context: &zbus::SignalContext<'_>, position: i64) -> zbus::Result<()>;

    #[zbus(property)]
    fn playback_status(&self) -> String {
        self.args.status.clone()
    }

    #[zbus(property)]
    fn loop_status(&self) -> String {
        self.loop_status.clone()
    }

    #[zbus(property)]
    fn set_loop_status(&mut self, value: String) {
        self.loop_status = value;
    }

    #[zbus(property)]
    fn rate(&self) -> f64 {
        self.rate
    }

    #[zbus(property)]
    fn set_rate(&mut self, value: f64) {
        self.rate = value;
    }

    #[zbus(property)]
    fn shuffle(&self) -> bool {
        self.shuffle
    }

    #[zbus(property)]
    fn set_shuffle(&mut self, value: bool) {
        self.shuffle = value;
    }

    #[zbus(property)]
    fn metadata(&self) -> HashMap<String, Value<'static>> {
        let mut metadata = HashMap::new();
        metadata.insert(
            "mpris:trackid".to_string(),
            Value::from(ObjectPath::from_static_str_unchecked(TRACK)),
        );
        metadata.insert(
            "xesam:title".to_string(),
            Value::from(self.args.title.clone()),
        );
        metadata.insert(
            "xesam:artist".to_string(),
            Value::from(vec![self.args.artist.clone()]),
        );
        metadata.insert(
            "mpris:artUrl".to_string(),
            Value::from(self.args.art.clone()),
        );
        if !self.args.url.is_empty() {
            metadata.insert("xesam:url".to_string(), Value::from(self.args.url.clone()));
        }
        metadata
    }

    #[zbus(property)]
    fn volume(&self) -> f64 {
        self.volume
    }

    #[zbus(property)]
    fn set_volume(&mut self, value: f64) {
        self.volume = value;
    }

    #[zbus(property)]
    fn position(&self) -> i64 {
        0
    }

    #[zbus(property)]
    fn minimum_rate(&self) -> f64 {
        1.0
    }

    #[zbus(property)]
    fn maximum_rate(&self) -> f64 {
        1.0
    }

    #[zbus(property)]
    fn can_go_next(&self) -> bool {
        self.args.can_go_next
    }

    #[zbus(property)]
    fn can_go_previous(&self) -> bool {
        self.args.can_go_previous
    }

    #[zbus(property)]
    fn can_play(&self) -> bool {
        self.args.can_play
    }

    #[zbus(property)]
    fn can_pause(&self) -> bool {
        self.args.can_pause
    }

    #[zbus(property)]
    fn can_seek(&self) -> bool {
        false
    }

    #[zbus(property)]
    fn can_control(&self) -> bool {
        true
    }
}

fn main() -> ExitCode {
    let args = match parse_args() {
        Ok(args) => args,
        Err(message) => return usage_error(&message),
    };
    let player = Player {
        loop_status: "None".to_string(),
        rate: 1.0,
        shuffle: false,
        volume: 1.0,
        args,
    };
    let name = player.args.name.clone();
    let status = player.args.status.clone();
    let can_go_next = player.args.can_go_next;

    let connection = match Connection::session() {
        Ok(connection) => connection,
        Err(error) => {
            eprintln!("mpris-stub: cannot connect to the session bus: {error}");
            return ExitCode::FAILURE;
        }
    };
    if let Err(error) = connection.request_name(name.as_str()) {
        eprintln!("mpris-stub: cannot own {name}: {error}");
        return ExitCode::FAILURE;
    }
    let object_server = connection.object_server();
    if let Err(error) = object_server.at("/org/mpris/MediaPlayer2", Root) {
        eprintln!("mpris-stub: cannot export the root interface: {error}");
        return ExitCode::FAILURE;
    }
    if let Err(error) = object_server.at("/org/mpris/MediaPlayer2", player) {
        eprintln!("mpris-stub: cannot export the player interface: {error}");
        return ExitCode::FAILURE;
    }
    println!("serving {name} · status {status} · can_go_next {can_go_next}");
    std::thread::park();
    ExitCode::SUCCESS
}
