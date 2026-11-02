//! A small TOML reader for `mpd-voice/config.toml`.
//!
//! The config file is a flat table of scalars under one section, so the parser
//! covers exactly that: `[section]` headers, `key = value` lines with strings,
//! integers, floats and booleans, and `#` comments. Anything else makes the
//! whole document unreadable — like `tomllib` rising on a syntax error, which
//! makes the caller skip the file.

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Str(String),
    Int(i64),
    Float(f64),
    Bool(bool),
}

#[derive(Debug, Default, Clone)]
pub struct Document {
    /// Section name (`None` for the root table) and its scalar entries.
    pub tables: Vec<(Option<String>, Vec<(String, Value)>)>,
}

impl Document {
    /// Entries of one section, or of the root table when `name` is `None`.
    pub fn table(&self, name: Option<&str>) -> Option<&[(String, Value)]> {
        self.tables
            .iter()
            .find(|(section, _)| section.as_deref() == name)
            .map(|(_, entries)| entries.as_slice())
    }
}

pub fn parse(source: &str) -> Option<Document> {
    let mut document = Document::default();
    let mut current: Option<String> = None;
    document.tables.push((None, Vec::new()));

    for raw in source.lines() {
        let line = strip_comment(raw).trim();
        if line.is_empty() {
            continue;
        }
        if let Some(rest) = line.strip_prefix('[') {
            let name = rest.strip_suffix(']')?.trim();
            if name.is_empty() {
                return None;
            }
            current = Some(name.to_string());
            if document.table(current.as_deref()).is_none() {
                document.tables.push((current.clone(), Vec::new()));
            }
            continue;
        }
        let (key, value) = line.split_once('=')?;
        let key = key.trim();
        if key.is_empty() {
            return None;
        }
        let value = parse_value(value.trim())?;
        let table = document
            .tables
            .iter_mut()
            .find(|(section, _)| section.as_deref() == current.as_deref())?;
        table.1.push((key.to_string(), value));
    }
    Some(document)
}

/// Drop a `#` comment that is not inside a string.
fn strip_comment(line: &str) -> &str {
    let mut quote: Option<char> = None;
    let mut escaped = false;
    for (index, ch) in line.char_indices() {
        match quote {
            Some(q) => {
                if escaped {
                    escaped = false;
                } else if ch == '\\' && q == '"' {
                    escaped = true;
                } else if ch == q {
                    quote = None;
                }
            }
            None => {
                if ch == '"' || ch == '\'' {
                    quote = Some(ch);
                } else if ch == '#' {
                    return &line[..index];
                }
            }
        }
    }
    line
}

fn parse_value(text: &str) -> Option<Value> {
    if let Some(rest) = text.strip_prefix('"') {
        let mut out = String::new();
        let mut chars = rest.chars();
        loop {
            match chars.next()? {
                '"' => {
                    if !chars.as_str().trim().is_empty() {
                        return None;
                    }
                    return Some(Value::Str(out));
                }
                '\\' => match chars.next()? {
                    'n' => out.push('\n'),
                    't' => out.push('\t'),
                    'r' => out.push('\r'),
                    '"' => out.push('"'),
                    '\\' => out.push('\\'),
                    _ => return None,
                },
                ch => out.push(ch),
            }
        }
    }
    if let Some(rest) = text.strip_prefix('\'') {
        let end = rest.find('\'')?;
        if !rest[end + 1..].trim().is_empty() {
            return None;
        }
        return Some(Value::Str(rest[..end].to_string()));
    }
    let lowered = text.to_lowercase();
    if lowered == "true" {
        return Some(Value::Bool(true));
    }
    if lowered == "false" {
        return Some(Value::Bool(false));
    }
    let digits = text.replace('_', "");
    if let Ok(value) = digits.parse::<i64>() {
        return Some(Value::Int(value));
    }
    if let Ok(value) = digits.parse::<f64>() {
        return Some(Value::Float(value));
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_a_section_of_scalars() {
        let doc = parse(
            "# comment\n[mpd-voice]\nmpd_host = \"localhost\"\nmpd_port = 6601\n\
             confirm = false\nvolume_step = 7\nmax_seconds = 2.5\n",
        )
        .expect("document");
        let table = doc.table(Some("mpd-voice")).expect("section");
        assert_eq!(
            table[0],
            ("mpd_host".to_string(), Value::Str("localhost".into()))
        );
        assert_eq!(table[1], ("mpd_port".to_string(), Value::Int(6601)));
        assert_eq!(table[2], ("confirm".to_string(), Value::Bool(false)));
        assert_eq!(table[3], ("volume_step".to_string(), Value::Int(7)));
        assert_eq!(table[4], ("max_seconds".to_string(), Value::Float(2.5)));
    }

    #[test]
    fn hash_inside_a_string_is_not_a_comment() {
        let doc = parse("[s]\ncmd = \"a # b\"\n").expect("document");
        assert_eq!(
            doc.table(Some("s")).unwrap()[0],
            ("cmd".to_string(), Value::Str("a # b".into()))
        );
    }

    #[test]
    fn quoted_and_escaped_strings() {
        let doc = parse("[s]\na = 'lit # eral'\nb = \"x\\\"y\"\n").expect("document");
        let table = doc.table(Some("s")).unwrap();
        assert_eq!(table[0].1, Value::Str("lit # eral".into()));
        assert_eq!(table[1].1, Value::Str("x\"y".into()));
    }

    #[test]
    fn root_keys_land_in_the_root_table() {
        let doc = parse("language = \"en\"\n").expect("document");
        assert_eq!(
            doc.table(None).unwrap()[0],
            ("language".to_string(), Value::Str("en".into()))
        );
    }

    #[test]
    fn garbage_is_rejected() {
        assert!(parse("[broken\n").is_none());
        assert!(parse("key =\n").is_none());
        assert!(parse("= 1\n").is_none());
        assert!(parse("key = not-a-value\n").is_none());
    }
}
