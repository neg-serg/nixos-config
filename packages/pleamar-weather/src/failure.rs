//! A provider failure as the worker reports it: an error string, or the
//! interrupt that ends the process cleanly (SIGTERM/SIGINT during a request).

use crate::http::FetchError;

#[derive(Debug, PartialEq, Eq)]
pub enum Failure {
    Message(String),
    Interrupted,
}

impl Failure {
    /// Prefix a transport failure with the provider's wording, exactly as the
    /// shell's `ERR_MSG="… failed: $HTTP_ERROR"` lines did.
    pub fn fetch(error: FetchError, prefix: &str) -> Self {
        match error {
            FetchError::Message(text) => Self::Message(format!("{prefix}{text}")),
            FetchError::Interrupted => Self::Interrupted,
        }
    }
}
