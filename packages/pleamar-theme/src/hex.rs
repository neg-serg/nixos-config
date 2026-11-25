//! `normalize_hex` from the shell: lower-case, accept `#rgb` and `#rrggbb`,
//! expand the short form, reject everything else.

/// Return the canonical lower-case `#rrggbb` form, or `None` when the value
/// is not a hex colour the shell accepted.
pub fn normalize(value: &str) -> Option<String> {
    let lowered = value.to_ascii_lowercase();
    let bytes = lowered.as_bytes();
    let is_hex = |slice: &[u8]| slice.iter().all(u8::is_ascii_hexdigit);
    match bytes.len() {
        7 if bytes[0] == b'#' && is_hex(&bytes[1..]) => Some(lowered),
        4 if bytes[0] == b'#' && is_hex(&bytes[1..]) => {
            let mut expanded = String::with_capacity(7);
            expanded.push('#');
            for &digit in &bytes[1..] {
                expanded.push(char::from(digit));
                expanded.push(char::from(digit));
            }
            Some(expanded)
        }
        _ => None,
    }
}
