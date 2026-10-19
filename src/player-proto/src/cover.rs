//! Album art extraction straight from the file.
//!
//! MPD's `albumart`/`readpicture` answer in `binarylimit` chunks (8 KiB by default) and stall
//! instead of returning the next chunk, which makes them useless for a single-shot fetch. The
//! library lives on disk, so the FLAC PICTURE block (and ID3v2 APIC for MP3) is parsed directly:
//! one open() instead of a socket round trip per 8 KiB.

use std::fs::File;
use std::io::{Read, Seek, SeekFrom};

/// Returns the embedded picture bytes, if the file carries one.
pub fn embedded_picture(path: &str) -> Option<Vec<u8>> {
    let mut file = File::open(path).ok()?;
    let mut magic = [0u8; 4];
    file.read_exact(&mut magic).ok()?;
    if &magic == b"fLaC" {
        flac_picture(&mut file)
    } else if &magic[..3] == b"ID3" {
        id3_picture(&mut file)
    } else {
        None
    }
}

fn read_u32_be<R: Read>(r: &mut R) -> Option<u32> {
    let mut b = [0u8; 4];
    r.read_exact(&mut b).ok()?;
    Some(u32::from_be_bytes(b))
}

/// FLAC: a sequence of metadata blocks, the last one flagged by the top bit of the header.
fn flac_picture<R: Read + Seek>(r: &mut R) -> Option<Vec<u8>> {
    loop {
        let mut header = [0u8; 4];
        r.read_exact(&mut header).ok()?;
        let last = header[0] & 0x80 != 0;
        let block_type = header[0] & 0x7f;
        let len = ((header[1] as u32) << 16) | ((header[2] as u32) << 8) | header[3] as u32;
        if block_type == 6 {
            // PICTURE: type, mime len + mime, desc len + desc, w, h, depth, colors, data len
            let mut block = vec![0u8; len as usize];
            r.read_exact(&mut block).ok()?;
            let mut cur = std::io::Cursor::new(block);
            let _picture_type = read_u32_be(&mut cur)?;
            let mime_len = read_u32_be(&mut cur)? as usize;
            cur.seek(SeekFrom::Current(mime_len as i64)).ok()?;
            let desc_len = read_u32_be(&mut cur)? as usize;
            cur.seek(SeekFrom::Current(desc_len as i64)).ok()?;
            for _ in 0..4 {
                let _ = read_u32_be(&mut cur)?;
            }
            let data_len = read_u32_be(&mut cur)? as usize;
            let start = cur.position() as usize;
            let inner = cur.into_inner();
            if start + data_len <= inner.len() {
                return Some(inner[start..start + data_len].to_vec());
            }
            return None;
        }
        r.seek(SeekFrom::Current(len as i64)).ok()?;
        if last {
            return None;
        }
    }
}

/// ID3v2: walk the frames of the first tag looking for an APIC frame.
fn id3_picture<R: Read + Seek>(r: &mut R) -> Option<Vec<u8>> {
    let mut header = [0u8; 10];
    r.read_exact(&mut header).ok()?;
    let size = ((header[6] as u32 & 0x7f) << 21)
        | ((header[7] as u32 & 0x7f) << 14)
        | ((header[8] as u32 & 0x7f) << 7)
        | (header[9] as u32 & 0x7f);
    let mut tag = vec![0u8; size as usize];
    r.read_exact(&mut tag).ok()?;
    let mut pos = 0usize;
    while pos + 10 <= tag.len() {
        let id = &tag[pos..pos + 4];
        if !id
            .iter()
            .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit())
        {
            break;
        }
        let frame_size =
            u32::from_be_bytes([tag[pos + 4], tag[pos + 5], tag[pos + 6], tag[pos + 7]]) as usize;
        let body = &tag[pos + 10..(pos + 10 + frame_size).min(tag.len())];
        if id == b"APIC" && body.len() > 4 {
            // encoding, mime (nul terminated), picture type, description (nul), data
            let mime_end = body[1..].iter().position(|&b| b == 0).map(|i| i + 1)?;
            let mut p = mime_end + 1;
            p += 1; // picture type
            let enc = body[0];
            let desc_end = if enc == 1 || enc == 2 {
                let mut i = p;
                while i + 1 < body.len() {
                    if body[i] == 0 && body[i + 1] == 0 {
                        i += 2;
                        break;
                    }
                    i += 2;
                }
                i
            } else {
                body[p..].iter().position(|&b| b == 0).map(|i| i + p + 1)?
            };
            let data = &body[desc_end..];
            if data.len() > 16 {
                return Some(data.to_vec());
            }
        }
        pos += 10 + frame_size;
    }
    None
}
