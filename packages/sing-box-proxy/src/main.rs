#![forbid(unsafe_code)]

fn main() {
    let args: Vec<String> = std::env::args().collect();
    std::process::exit(sing_box_proxy::cli::run(&args));
}
