//! The small part of Python's `pathlib` that `music-highlevel` relies on.
//!
//! `Path(value)` normalises separators and `.` components and keeps `..` as a
//! literal component; `rglob("*")` walks below a directory without following
//! directory symlinks; `sorted()` orders paths component by component. Those
//! three details decide which files are processed and in what order, so they
//! are reproduced here with byte strings (Unix paths are bytes).

use std::ffi::{OsStr, OsString};
use std::fs;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::path::Path;

use crate::env;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Root {
    Relative,
    Absolute,
    DoubleSlash,
}

#[derive(Debug, Clone)]
pub struct PyPath {
    raw: Vec<u8>,
    root: Root,
    parts: Vec<Vec<u8>>,
}

fn normalise(input: &[u8]) -> (Vec<u8>, Root, Vec<Vec<u8>>) {
    let mut root = Root::Relative;
    let mut index = 0usize;
    if input.starts_with(b"/") {
        let slashes = input.iter().take_while(|byte| **byte == b'/').count();
        if slashes == 2 && input.get(2) != Some(&b'/') {
            root = Root::DoubleSlash;
            index = 2;
        } else {
            root = Root::Absolute;
            index = slashes;
        }
    }
    let mut parts: Vec<Vec<u8>> = Vec::new();
    for component in input[index..].split(|byte| *byte == b'/') {
        if component.is_empty() || component == b"." {
            continue;
        }
        parts.push(component.to_vec());
    }
    let raw = if parts.is_empty() {
        match root {
            Root::Relative => b".".to_vec(),
            Root::Absolute => b"/".to_vec(),
            Root::DoubleSlash => b"//".to_vec(),
        }
    } else {
        let mut joined = Vec::new();
        match root {
            Root::Relative => {}
            Root::Absolute => joined.push(b'/'),
            Root::DoubleSlash => joined.extend_from_slice(b"//"),
        }
        for (position, part) in parts.iter().enumerate() {
            if position > 0 {
                joined.push(b'/');
            }
            joined.extend_from_slice(part);
        }
        joined
    };
    (raw, root, parts)
}

impl PyPath {
    pub fn from_bytes(input: &[u8]) -> Self {
        let (raw, root, parts) = normalise(input);
        Self { raw, root, parts }
    }

    pub fn from_os(input: &OsStr) -> Self {
        Self::from_bytes(input.as_bytes())
    }

    pub fn as_bytes(&self) -> &[u8] {
        &self.raw
    }

    pub fn as_os(&self) -> &OsStr {
        OsStr::from_bytes(&self.raw)
    }

    pub fn as_path(&self) -> &Path {
        Path::new(self.as_os())
    }

    pub fn is_dir(&self) -> bool {
        fs::metadata(self.as_path())
            .map(|metadata| metadata.is_dir())
            .unwrap_or(false)
    }

    pub fn is_file(&self) -> bool {
        fs::metadata(self.as_path())
            .map(|metadata| metadata.is_file())
            .unwrap_or(false)
    }

    /// Python `PurePath.suffix`: leading dots are stripped before looking for
    /// the final dot, so `.mp3` has no suffix and `.a.b` ends in `.b`.
    pub fn suffix(&self) -> Vec<u8> {
        let name = self.parts.last().map(Vec::as_slice).unwrap_or(b"");
        let stripped = name.iter().skip_while(|byte| **byte == b'.').count();
        let name = &name[name.len() - stripped..];
        match name.iter().rposition(|byte| *byte == b'.') {
            Some(position) => name[position..].to_vec(),
            None => Vec::new(),
        }
    }

    fn child(&self, name: &[u8]) -> Self {
        let mut parts = self.parts.clone();
        parts.push(name.to_vec());
        let mut raw = Vec::new();
        match self.root {
            Root::Relative => {}
            Root::Absolute => raw.push(b'/'),
            Root::DoubleSlash => raw.extend_from_slice(b"//"),
        }
        for (position, part) in parts.iter().enumerate() {
            if position > 0 {
                raw.push(b'/');
            }
            raw.extend_from_slice(part);
        }
        Self {
            raw,
            root: self.root,
            parts,
        }
    }

    fn join_component(&self, component: &[u8]) -> Self {
        self.child(component)
    }

    /// `sorted(path.rglob("*"))` below this path. Directory symlinks are
    /// yielded but not descended into (Python 3.13+ default).
    pub fn rglob_descendants(&self) -> Vec<PyPath> {
        let mut found = Vec::new();
        self.walk(&mut found);
        found.sort_by(|left, right| left.parts.cmp(&right.parts));
        found
    }

    fn walk(&self, found: &mut Vec<PyPath>) {
        let Ok(read_dir) = fs::read_dir(self.as_path()) else {
            return;
        };
        let mut children: Vec<(Vec<u8>, bool)> = Vec::new();
        for entry in read_dir.flatten() {
            let name = entry.file_name().as_bytes().to_vec();
            let ty = entry.file_type();
            let is_dir = ty.map(|value| value.is_dir()).unwrap_or(false);
            children.push((name, is_dir));
        }
        // The final sort makes this order irrelevant; walking after collecting
        // keeps the recursion independent of readdir order.
        for (name, is_dir) in children {
            let child = self.join_component(&name);
            if is_dir {
                child.walk(found);
            }
            found.push(child);
        }
    }

    /// `Path.expanduser()`: `~` uses HOME (falling back to the passwd entry),
    /// `~user` looks the user up in `/etc/passwd`; unknown names stay literal.
    pub fn expanduser(&self) -> Self {
        if !self.raw.starts_with(b"~") {
            return self.clone();
        }
        let end = self
            .raw
            .iter()
            .position(|byte| *byte == b'/')
            .unwrap_or(self.raw.len());
        let user = &self.raw[1..end];
        let home: Option<Vec<u8>> = if user.is_empty() {
            match env::var_bytes("HOME") {
                Some(value) => Some(value),
                None => current_user_home(),
            }
        } else {
            let Ok(name) = std::str::from_utf8(user) else {
                return self.clone();
            };
            passwd_home_for(name)
        };
        let Some(mut home) = home else {
            return self.clone();
        };
        while home.last() == Some(&b'/') {
            home.pop();
        }
        let mut expanded = home;
        expanded.extend_from_slice(&self.raw[end..]);
        if expanded.is_empty() {
            expanded.push(b'/');
        }
        Self::from_bytes(&expanded)
    }

    pub fn display_os(&self) -> OsString {
        OsString::from_vec(self.raw.clone())
    }
}

fn current_user_home() -> Option<Vec<u8>> {
    let status = fs::read_to_string("/proc/self/status").ok()?;
    let uid = status.lines().find_map(|line| {
        line.strip_prefix("Uid:")
            .and_then(|rest| rest.split_whitespace().next())
    })?;
    passwd_home_for_uid(uid)
}

fn passwd_home_for(name: &str) -> Option<Vec<u8>> {
    let passwd = fs::read("/etc/passwd").ok()?;
    for line in passwd.split(|byte| *byte == b'\n') {
        let fields: Vec<&[u8]> = line.split(|byte| *byte == b':').collect();
        if fields.len() >= 6 && fields[0] == name.as_bytes() {
            return Some(fields[5].to_vec());
        }
    }
    None
}

fn passwd_home_for_uid(uid: &str) -> Option<Vec<u8>> {
    let passwd = fs::read("/etc/passwd").ok()?;
    for line in passwd.split(|byte| *byte == b'\n') {
        let fields: Vec<&[u8]> = line.split(|byte| *byte == b':').collect();
        if fields.len() >= 6 && fields[2] == uid.as_bytes() {
            return Some(fields[5].to_vec());
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalisation_matches_pathlib() {
        let cases: &[(&[u8], &[u8])] = &[
            (b"", b"."),
            (b".", b"."),
            (b"./", b"."),
            (b"./d", b"d"),
            (b"d/", b"d"),
            (b"d//e", b"d/e"),
            (b"a/./b", b"a/b"),
            (b"../x", b"../x"),
            (b"//tmp/x", b"//tmp/x"),
            (b"///tmp", b"/tmp"),
            (b"//", b"//"),
            (b"///", b"/"),
        ];
        for (input, expected) in cases {
            assert_eq!(PyPath::from_bytes(input).as_bytes(), *expected);
        }
    }

    #[test]
    fn suffix_matches_pathlib() {
        let cases: &[(&str, &str)] = &[
            (".mp3", ""),
            ("..", ""),
            ("a.", "."),
            ("a.b", ".b"),
            ("a", ""),
            (".a.b", ".b"),
            ("..a", ""),
        ];
        for (input, expected) in cases {
            assert_eq!(
                PyPath::from_bytes(input.as_bytes()).suffix(),
                expected.as_bytes()
            );
        }
    }
}
