//! Minimal NumPy `.npy` reader/writer for float32 arrays.
//!
//! The index files are plain `.npy` v1 files: a magic header describing
//! ``<f4`` in C order plus the raw little-endian payload. Writing the exact
//! same layout keeps the index readable by the Python payload and by numpy, and
//! reading accepts v1/v2 headers and big-endian or float64 files so a
//! hand-written or older cache entry is still usable (numpy would cast it).

use std::fs;
use std::io;
use std::path::Path;

const MAGIC: &[u8] = b"\x93NUMPY";

/// A decoded float32 array; `data` is in C order.
#[derive(Clone, Debug, PartialEq)]
pub struct NpyArray {
    pub shape: Vec<usize>,
    pub data: Vec<f32>,
}

impl NpyArray {
    pub fn len(&self) -> usize {
        self.data.len()
    }

    pub fn is_empty(&self) -> bool {
        self.data.is_empty()
    }
}

fn invalid(message: impl Into<String>) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message.into())
}

/// Read a float32 `.npy` file (v1/v2), accepting `<f4`, `>f4`, `<f8`, `>f8`.
pub fn read_f32(path: &Path) -> io::Result<NpyArray> {
    let bytes = fs::read(path)?;
    if bytes.len() < 10 || &bytes[..6] != MAGIC {
        return Err(invalid("not a .npy file"));
    }
    let major = bytes[6];
    let (header_start, header_len) = match major {
        1 => (10, u16::from_le_bytes([bytes[8], bytes[9]]) as usize),
        2 | 3 => {
            if bytes.len() < 12 {
                return Err(invalid("truncated .npy header"));
            }
            (
                12,
                u32::from_le_bytes([bytes[8], bytes[9], bytes[10], bytes[11]]) as usize,
            )
        }
        other => return Err(invalid(format!("unsupported .npy version {other}"))),
    };
    if bytes.len() < header_start + header_len {
        return Err(invalid("truncated .npy header"));
    }
    let header = std::str::from_utf8(&bytes[header_start..header_start + header_len])
        .map_err(|_| invalid("non-UTF-8 .npy header"))?;

    let descr = field_value(header, "descr")
        .and_then(quoted)
        .ok_or_else(|| invalid("missing or invalid .npy descr"))?;
    let fortran = field_value(header, "fortran_order").unwrap_or("");
    if !fortran.trim_start().starts_with("False") {
        return Err(invalid(
            "only C-order .npy arrays are supported (fortran_order=False)",
        ));
    }
    let shape = parse_shape(header)?;
    let count: usize = shape.iter().product();
    let (element_size, little_endian, is_f64) = match descr {
        "<f4" | "|f4" => (4usize, true, false),
        ">f4" => (4, false, false),
        "<f8" | "|f8" => (8, true, true),
        ">f8" => (8, false, true),
        other => return Err(invalid(format!("unsupported .npy dtype {other:?}"))),
    };
    let payload = &bytes[header_start + header_len..];
    if payload.len() != count * element_size {
        return Err(invalid(format!(
            "truncated .npy payload ({} bytes, expected {})",
            payload.len(),
            count * element_size
        )));
    }

    let mut data = Vec::with_capacity(count);
    for chunk in payload.chunks_exact(element_size) {
        if is_f64 {
            let bytes: [u8; 8] = chunk.try_into().expect("chunks_exact(8)");
            let value = if little_endian {
                f64::from_le_bytes(bytes)
            } else {
                f64::from_be_bytes(bytes)
            };
            data.push(value as f32);
        } else {
            let bytes: [u8; 4] = chunk.try_into().expect("chunks_exact(4)");
            data.push(if little_endian {
                f32::from_le_bytes(bytes)
            } else {
                f32::from_be_bytes(bytes)
            });
        }
    }
    Ok(NpyArray { shape, data })
}

/// Write a float32 `.npy` file in C order, using the same v1 header numpy emits.
pub fn write_f32(path: &Path, shape: &[usize], data: &[f32]) -> io::Result<()> {
    let count: usize = shape.iter().product();
    if count != data.len() {
        return Err(invalid(format!(
            "shape {:?} needs {count} values, got {}",
            shape,
            data.len()
        )));
    }

    let mut shape_text = String::from("(");
    for (i, dim) in shape.iter().enumerate() {
        if i > 0 {
            shape_text.push_str(", ");
        }
        shape_text.push_str(&dim.to_string());
    }
    if shape.len() == 1 {
        shape_text.push(',');
    }
    shape_text.push(')');

    let dict = format!("{{'descr': '<f4', 'fortran_order': False, 'shape': {shape_text}, }}");
    // numpy pads the header with spaces so that the 10-byte prefix plus the
    // header is a multiple of 64, and the header always ends with a newline.
    let dict = dict.into_bytes();
    let pad = (64 - ((10 + dict.len() + 1) % 64)) % 64;
    let header_len = dict.len() + pad + 1;
    if header_len > u16::MAX as usize {
        return Err(invalid("npy header too large for version 1"));
    }

    let mut out = Vec::with_capacity(10 + header_len + data.len() * 4);
    out.extend_from_slice(MAGIC);
    out.push(1);
    out.push(0);
    out.extend_from_slice(&(header_len as u16).to_le_bytes());
    out.extend_from_slice(&dict);
    out.extend(std::iter::repeat_n(b' ', pad));
    out.push(b'\n');
    for value in data {
        out.extend_from_slice(&value.to_le_bytes());
    }
    fs::write(path, out)
}

/// Locate `'key':` in the header dict and return the text after the colon.
fn field_value<'a>(header: &'a str, key: &str) -> Option<&'a str> {
    for quote in ['\'', '"'] {
        let pattern = format!("{quote}{key}{quote}");
        if let Some(position) = header.find(&pattern) {
            let rest = header[position + pattern.len()..].trim_start();
            if let Some(rest) = rest.strip_prefix(':') {
                return Some(rest.trim_start());
            }
        }
    }
    None
}

/// Parse a Python/JSON quoted string starting at `text`.
fn quoted(text: &str) -> Option<&str> {
    let quote = text.chars().next()?;
    if quote != '\'' && quote != '"' {
        return None;
    }
    let rest = &text[quote.len_utf8()..];
    let end = rest.find(quote)?;
    Some(&rest[..end])
}

/// Parse `(3, 16)` / `(768,)` / `()` from the header dict.
fn parse_shape(header: &str) -> io::Result<Vec<usize>> {
    let text = field_value(header, "shape").ok_or_else(|| invalid("missing .npy shape"))?;
    let text = text
        .strip_prefix('(')
        .ok_or_else(|| invalid("invalid .npy shape"))?;
    let end = text
        .find(')')
        .ok_or_else(|| invalid("invalid .npy shape"))?;
    let mut shape = Vec::new();
    for part in text[..end].split(',') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }
        shape.push(
            part.parse::<usize>()
                .map_err(|_| invalid("invalid .npy shape dimension"))?,
        );
    }
    Ok(shape)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn round_trips_2d() {
        let dir = crate::fsutil::TempDir::new("npy-roundtrip").unwrap();
        let path = dir.path().join("vectors.npy");
        let data: Vec<f32> = (0..12).map(|i| i as f32 * 0.5 - 3.0).collect();
        write_f32(&path, &[3, 4], &data).unwrap();
        let array = read_f32(&path).unwrap();
        assert_eq!(array.shape, vec![3, 4]);
        assert_eq!(array.data, data);

        // The header layout must match numpy's 64-byte alignment rule.
        let raw = fs::read(&path).unwrap();
        assert_eq!(&raw[..6], MAGIC);
        assert_eq!((raw[6], raw[7]), (1, 0));
        let header_len = u16::from_le_bytes([raw[8], raw[9]]) as usize;
        assert_eq!((10 + header_len) % 64, 0);
        assert_eq!(raw[10 + header_len - 1], b'\n');
        let header = std::str::from_utf8(&raw[10..10 + header_len]).unwrap();
        assert!(header.contains("'descr': '<f4'"));
        assert!(header.contains("'fortran_order': False"));
        assert!(header.contains("'shape': (3, 4)"));
    }

    #[test]
    fn round_trips_1d_and_empty() {
        let dir = crate::fsutil::TempDir::new("npy-1d").unwrap();
        let path = dir.path().join("center.npy");
        write_f32(&path, &[768], &vec![0.25; 768]).unwrap();
        let array = read_f32(&path).unwrap();
        assert_eq!(array.shape, vec![768]);
        assert_eq!(array.data.len(), 768);

        let empty = dir.path().join("empty.npy");
        write_f32(&empty, &[0, 4], &[]).unwrap();
        let array = read_f32(&empty).unwrap();
        assert_eq!(array.shape, vec![0, 4]);
        assert!(array.data.is_empty());
    }

    #[test]
    fn reads_float64_and_big_endian() {
        let dir = crate::fsutil::TempDir::new("npy-f8").unwrap();
        let path = dir.path().join("f8.npy");
        // Hand-written little-endian float64 array, shape (2,).
        let mut header = b"{'descr': '<f8', 'fortran_order': False, 'shape': (2,), }".to_vec();
        let pad = (64 - ((10 + header.len() + 1) % 64)) % 64;
        header.extend(std::iter::repeat_n(b' ', pad));
        header.push(b'\n');
        let mut raw = Vec::new();
        raw.extend_from_slice(MAGIC);
        raw.extend_from_slice(&[1, 0]);
        raw.extend_from_slice(&(header.len() as u16).to_le_bytes());
        raw.extend_from_slice(&header);
        for value in [1.5f64, -2.25] {
            raw.extend_from_slice(&value.to_le_bytes());
        }
        fs::write(&path, raw).unwrap();
        let array = read_f32(&path).unwrap();
        assert_eq!(array.shape, vec![2]);
        assert_eq!(array.data, vec![1.5, -2.25]);

        let big = dir.path().join("big.npy");
        let mut header = b"{'descr': '>f4', 'fortran_order': False, 'shape': (1,), }".to_vec();
        let pad = (64 - ((10 + header.len() + 1) % 64)) % 64;
        header.extend(std::iter::repeat_n(b' ', pad));
        header.push(b'\n');
        let mut raw = Vec::new();
        raw.extend_from_slice(MAGIC);
        raw.extend_from_slice(&[1, 0]);
        raw.extend_from_slice(&(header.len() as u16).to_le_bytes());
        raw.extend_from_slice(&header);
        raw.extend_from_slice(&0.5f32.to_be_bytes());
        fs::write(&big, raw).unwrap();
        assert_eq!(read_f32(&big).unwrap().data, vec![0.5]);
    }

    #[test]
    fn reads_v2_header() {
        let dir = crate::fsutil::TempDir::new("npy-v2").unwrap();
        let path = dir.path().join("v2.npy");
        let mut header = b"{'descr': '<f4', 'fortran_order': False, 'shape': (1, 2), }".to_vec();
        let pad = (64 - ((12 + header.len() + 1) % 64)) % 64;
        header.extend(std::iter::repeat_n(b' ', pad));
        header.push(b'\n');
        let mut raw = Vec::new();
        raw.extend_from_slice(MAGIC);
        raw.extend_from_slice(&[2, 0]);
        raw.extend_from_slice(&(header.len() as u32).to_le_bytes());
        raw.extend_from_slice(&header);
        for value in [1.0f32, 2.0] {
            raw.extend_from_slice(&value.to_le_bytes());
        }
        fs::write(&path, raw).unwrap();
        let array = read_f32(&path).unwrap();
        assert_eq!(array.shape, vec![1, 2]);
        assert_eq!(array.data, vec![1.0, 2.0]);
    }

    #[test]
    fn rejects_truncated_payload() {
        let dir = crate::fsutil::TempDir::new("npy-bad").unwrap();
        let path = dir.path().join("bad.npy");
        write_f32(&path, &[2], &[1.0, 2.0]).unwrap();
        let mut raw = fs::read(&path).unwrap();
        raw.truncate(raw.len() - 4);
        fs::write(&path, raw).unwrap();
        assert!(read_f32(&path).is_err());
    }
}
