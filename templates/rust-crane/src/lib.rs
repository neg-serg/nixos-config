//! Small demo library for the template.
//! Provides a simple JSON parser using serde and a sample type.

use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct User {
    pub id: u64,
    pub name: String,
}

/// Parse a JSON string into a `User`.
///
/// Expected shape: {"id": 1, "name": "alice"}
pub fn parse_user(json: &str) -> Result<User> {
    let u: User = serde_json::from_str(json).map_err(|e| anyhow!(e))?;
    Ok(u)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_user_ok() {
        let u = parse_user("{\"id\": 7, \"name\": \"bob\"}").unwrap();
        assert_eq!(u.id, 7);
        assert_eq!(u.name, "bob");
    }

    #[test]
    fn parse_user_err() {
        let err = parse_user("{not json}").unwrap_err();
        let msg = err.to_string();
        assert!(msg.contains("expected value") || msg.contains("at line"));
    }
}

