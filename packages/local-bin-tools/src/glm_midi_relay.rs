//! glm-midi-relay — one-way MIDI relay to the dockur Windows VM.
//!
//! Topology constraint: the VM shares the host IP (192.168.0.10 via pasta), so
//! bidirectional UDP (RTP-MIDI) handshakes die on the host → VM reply path. The
//! only reliable host → VM channel is a connection the VM *initiates* (outbound
//! TCP through passt works and replies flow back).
//!
//! Design:
//! - the VM-side bridge (`oem/glm-midi-bridge.ps1`) connects OUT to `:9003`;
//! - local `glm-midi` connects to `127.0.0.1:9004` and writes one raw MIDI packet;
//! - this relay forwards each local packet into the current VM connection.
//!
//! `GLM_RELAY_LOG=/path` records every forwarded packet (timestamp, peer, hex).
//! Port of `packages/local-bin/bin/glm-midi-relay`.

use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

const VM_PORT: u16 = 9003;
const LOCAL_PORT: u16 = 9004;
/// One 3-byte CC message per connection (status, controller, value).
const MESSAGE_LEN: usize = 3;

fn ports() -> (u16, u16) {
    let read = |name: &str, fallback: u16| {
        std::env::var(name)
            .ok()
            .and_then(|value| value.trim().parse().ok())
            .unwrap_or(fallback)
    };
    (
        read("GLM_RELAY_VM_PORT", VM_PORT),
        read("GLM_RELAY_LOCAL_PORT", LOCAL_PORT),
    )
}

/// Read exactly one MIDI packet, tolerating senders that write byte by byte.
fn read_message(stream: &mut TcpStream) -> Vec<u8> {
    let mut data = Vec::with_capacity(MESSAGE_LEN);
    let mut chunk = [0u8; MESSAGE_LEN];
    while data.len() < MESSAGE_LEN {
        match stream.read(&mut chunk[..MESSAGE_LEN - data.len()]) {
            Ok(0) => break,
            Ok(read) => data.extend_from_slice(&chunk[..read]),
            Err(_) => break,
        }
    }
    data
}

fn main() -> std::process::ExitCode {
    let (vm_port, local_port) = ports();
    // Bind both sockets before starting any thread, so a failed bind exits
    // cleanly instead of leaving a half-started relay behind.
    let vm_listener = match TcpListener::bind(("0.0.0.0", vm_port)) {
        Ok(listener) => listener,
        Err(exc) => {
            eprintln!("glm-midi-relay: bind 0.0.0.0:{vm_port} failed: {exc}");
            return std::process::ExitCode::from(1);
        }
    };
    let local_listener = match TcpListener::bind(("127.0.0.1", local_port)) {
        Ok(listener) => listener,
        Err(exc) => {
            eprintln!("glm-midi-relay: bind 127.0.0.1:{local_port} failed: {exc}");
            return std::process::ExitCode::from(1);
        }
    };

    let vm: Arc<Mutex<Option<TcpStream>>> = Arc::new(Mutex::new(None));
    {
        let vm = Arc::clone(&vm);
        std::thread::spawn(move || {
            for stream in vm_listener.incoming().flatten() {
                // A new VM connection replaces the previous one.
                *vm.lock().expect("vm") = Some(stream);
            }
        });
    }

    let log_path = std::env::var("GLM_RELAY_LOG").unwrap_or_default();
    for stream in local_listener.incoming().flatten() {
        let mut stream = stream;
        // Python logged `repr(getpeername())`, i.e. a tuple: keep the same shape
        // so existing log greps keep working.
        let peer = stream
            .peer_addr()
            .map(|address| format!("('{}', {})", address.ip(), address.port()))
            .unwrap_or_else(|_| "()".to_string());
        let data = read_message(&mut stream);
        if data.is_empty() {
            continue;
        }
        if !log_path.is_empty() {
            let stamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|delta| delta.as_secs_f64())
                .unwrap_or(0.0);
            let hex: String = data.iter().map(|byte| format!("{byte:02x}")).collect();
            use std::io::Write as _;
            if let Ok(mut file) = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(&log_path)
            {
                let _ = writeln!(file, "{stamp:.3} from={peer} msg={hex}");
            }
        }
        let mut guard = vm.lock().expect("vm");
        let Some(target) = guard.as_mut() else {
            continue; // no VM bridge connected yet — drop the packet
        };
        if target.write_all(&data).is_err() {
            *guard = None;
        }
    }
    std::process::ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::Shutdown;

    #[test]
    fn byte_by_byte_senders_still_deliver_a_whole_message() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).expect("listener");
        let address = listener.local_addr().expect("address");
        let sender = std::thread::spawn(move || {
            let mut stream = TcpStream::connect(address).expect("connect");
            for byte in [0xB0u8, 0x07, 0x40] {
                stream.write_all(&[byte]).expect("write");
                std::thread::sleep(std::time::Duration::from_millis(5));
            }
            stream.shutdown(Shutdown::Write).ok();
        });
        let (mut stream, _) = listener.accept().expect("accept");
        let message = read_message(&mut stream);
        sender.join().expect("sender");
        assert_eq!(message, vec![0xB0, 0x07, 0x40]);
    }

    #[test]
    fn short_sends_are_not_padded() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).expect("listener");
        let address = listener.local_addr().expect("address");
        let sender = std::thread::spawn(move || {
            let mut stream = TcpStream::connect(address).expect("connect");
            stream.write_all(&[0x90, 0x40]).expect("write");
            stream.shutdown(Shutdown::Write).ok();
        });
        let (mut stream, _) = listener.accept().expect("accept");
        let message = read_message(&mut stream);
        sender.join().expect("sender");
        assert_eq!(message, vec![0x90, 0x40]);
    }
}
