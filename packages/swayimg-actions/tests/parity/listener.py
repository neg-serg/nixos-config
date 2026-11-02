#!/usr/bin/env python3
"""Record every connection to a Unix socket, one block per connection.

Usage: listener.py <socket-path> <output-path> [idle-seconds]

The harness starts this before each swayimg-actions run and waits for it after
the run; the process exits once the socket has been idle for the timeout. Each
accepted connection is recorded as "---\\n" followed by the exact bytes the
client wrote, with unbuffered writes so a later SIGTERM cannot lose data.
"""

import os
import socket
import sys

path = sys.argv[1]
output = sys.argv[2]
timeout = float(sys.argv[3]) if len(sys.argv) > 3 else 0.2

try:
    os.unlink(path)
except FileNotFoundError:
    pass

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(path)
server.listen(8)
server.settimeout(timeout)

fd = os.open(output, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o644)
try:
    while True:
        try:
            connection, _ = server.accept()
        except socket.timeout:
            break
        chunks = []
        while True:
            data = connection.recv(65536)
            if not data:
                break
            chunks.append(data)
        connection.close()
        os.write(fd, b"---\n" + b"".join(chunks))
finally:
    os.close(fd)
    server.close()
