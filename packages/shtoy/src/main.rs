use std::process::ExitCode;

use shtoy::env::Env;
use shtoy::http::ReqwestHttp;

fn main() -> ExitCode {
    let environment = Env::from_process();
    let http = ReqwestHttp::new();
    let arguments: Vec<_> = std::env::args_os().skip(1).collect();

    match shtoy::run(arguments, &environment, &http) {
        Ok(code) => ExitCode::from((code & 0xff) as u8),
        Err(failure) => {
            eprintln!("{}: {}", shtoy::PROG, failure);
            ExitCode::from(1)
        }
    }
}
