use app::{parse_user, User};
use clap::Parser;

/// Simple demo binary: parses a JSON-encoded user and prints it back.
#[derive(Parser, Debug)]
#[command(name = "app", version, about = "Rust + crane template demo")]
struct Cli {
    /// JSON string of the form: {"id": 1, "name": "alice"}
    #[arg(short, long)]
    json: String,
}

fn main() {
    let cli = Cli::parse();
    match parse_user(&cli.json) {
        Ok(User { id, name }) => println!("user: id={id} name={name}"),
        Err(e) => {
            eprintln!("failed to parse user: {e}");
            std::process::exit(1);
        }
    }
}
