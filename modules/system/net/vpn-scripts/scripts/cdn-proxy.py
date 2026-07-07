#!/usr/bin/env python3
"""CDN on-demand proxy: caches packages on first access through SOCKS5."""
import socket, threading, subprocess, os, time

CACHE = "/tmp/cdn-cache"
PROXY = "socks5://127.0.0.1:10808"  # works with curl --socks5-hostname
CDN_HOST = "cdn.example.com"
os.makedirs(CACHE, exist_ok=True)


def fetch(url, dest):
    for attempt in range(3):
        try:
            subprocess.run(
                [
                    "curl",
                    "-s",
                    "--max-time",
                    "120",
                    "--socks5-hostname",
                    "127.0.0.1:10808",
                    url,
                    "-o",
                    dest,
                ],
                check=True,
                timeout=130,
            )
            return True
        except Exception as e:
            print(f"  retry {attempt+1}: {e}")
            time.sleep(2)
    return False


def handle(client):
    data = None
    try:
        data = client.recv(16384)
        lines = data.decode(errors="ignore").split("\r\n")
        parts = lines[0].split(" ")
        if len(parts) < 2:
            client.close()
            return
        method, path = parts[0], parts[1]

        # Cache key and file
        cache_key = path.replace("/", "_").replace("?", "_")
        cache_path = os.path.join(CACHE, cache_key)

        # Serve from cache if available
        if os.path.exists(cache_path):
            with open(cache_path, "rb") as f:
                body = f.read()
            client.send(
                f"HTTP/1.1 200 OK\r\nContent-Length: {len(body)}\r\n\r\n".encode()
                + body
            )
            client.close()
            return

        # Download from CDN
        url = f"https://{CDN_HOST}{path}"
        print(f"FETCH: {path.split('/')[-1][:60]}")
        if fetch(url, cache_path):
            with open(cache_path, "rb") as f:
                body = f.read()
            client.send(
                f"HTTP/1.1 200 OK\r\nContent-Length: {len(body)}\r\n\r\n".encode()
                + body
            )
            print(f"  OK: {len(body)} bytes")
        else:
            client.send(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
    except Exception as e:
        print(f"ERROR: {e}")
        if data and b"HTTP/" in data:
            try:
                client.send(b"HTTP/1.1 500\r\n\r\n")
            except:
                pass
    finally:
        try:
            client.close()
        except:
            pass


print(f"CDN proxy: 0.0.0.0:19996 -> {CDN_HOST} via SOCKS5")
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("0.0.0.0", 19996))
s.listen(200)
for _ in range(10):
    threading.Thread(
        target=lambda: [handle(c) for c in iter(lambda: s.accept(), None)],
        daemon=True,
    ).start()
print("Ready (10 threads)")
threading.Event().wait()
