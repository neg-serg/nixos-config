//! A pipeline failure as the worker reports it: an error string, or the
//! interrupt that ends the process cleanly (SIGTERM/SIGINT during a request).

#[derive(Debug, PartialEq, Eq)]
pub enum Failure {
    Message(String),
    Interrupted,
}
