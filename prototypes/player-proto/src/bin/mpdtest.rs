use player_proto::mpd::Client;
use std::time::Duration;

fn main() {
    let mut c = Client::connect("127.0.0.1:6600", Duration::from_millis(2000)).expect("connect");
    println!("status: {:?}", c.status());
    println!("current: {:?}", c.current_song());
    match c.queue() {
        Ok(q) => println!(
            "queue: {} songs, first: {:?}",
            q.len(),
            q.first().map(|s| &s.title)
        ),
        Err(e) => println!("queue error: {e}"),
    }
    match c.list_dir("/") {
        Ok(e) => println!("lsinfo /: {} entries, first: {:?}", e.len(), e.first()),
        Err(e) => println!("lsinfo error: {e}"),
    }
    match c.search("a") {
        Ok(s) => println!("search: {} hits", s.len()),
        Err(e) => println!("search error: {e}"),
    }
    let uri = "new/Global Sect - 7CD VA - Hallucinations Of The Buddha. Part II/Global Sect - 7CD VA - Hallucinations Of The Buddha. Part II - 11 CD VIII. Clementz - Screams from Ancient Times.flac";
    for root in ["/home/neg/music", "/music", "/home/neg/Music"] {
        let path = format!("{root}/{uri}");
        if std::path::Path::new(&path).exists() {
            let pic = player_proto::cover::embedded_picture(&path);
            println!("cover from {root}: {:?}", pic.map(|p| p.len()));
            if let Some(bytes) = player_proto::cover::embedded_picture(&path) {
                match image::load_from_memory(&bytes) {
                    Ok(img) => println!("decoded: {:?}", img.to_rgba8().dimensions()),
                    Err(e) => println!("decode error: {e}"),
                }
            }
        }
    }
    match c.list_tag("Artist") {
        Ok(v) => println!("artists: {} (first {:?})", v.len(), v.first()),
        Err(e) => println!("artists err: {e}"),
    }
    match c.list_tag("Album") {
        Ok(v) => println!("albums: {} (first {:?})", v.len(), v.first()),
        Err(e) => println!("albums err: {e}"),
    }
    match c.playlists() {
        Ok(v) => println!("playlists: {:?}", v),
        Err(e) => println!("playlists err: {e}"),
    }
    match c.outputs() {
        Ok(v) => println!("outputs: {:?}", v),
        Err(e) => println!("outputs err: {e}"),
    }
    match c.find("Artist", "Global Sect") {
        Ok(v) => println!("find artist: {} songs", v.len()),
        Err(e) => println!("find err: {e}"),
    }
    let st = c.status().unwrap();
    if let Some(song) = c.current_song().unwrap_or(None) {
        match c.album_art(&song.file) {
            Ok(b) => println!("albumart: {} bytes", b.len()),
            Err(e) => println!("albumart error: {e}"),
        }
    }
    let _ = st;
}
