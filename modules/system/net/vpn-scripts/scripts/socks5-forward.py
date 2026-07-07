#!/usr/bin/env python3
"""Minimal SOCKS5 proxy (CONNECT only). Optionally chains to upstream SOCKS5."""
import argparse
import asyncio
import base64
import socket
import struct
import sys

SOCKS_VERSION = 5


async def socks5_connect(reader, writer, addr, port, atyp=3):
    buf = struct.pack("!BBBB", SOCKS_VERSION, 1, 0, atyp)
    if atyp == 1:
        buf += socket.inet_aton(addr)
    elif atyp == 3:
        encoded = addr.encode() if isinstance(addr, str) else addr
        buf += struct.pack("!B", len(encoded)) + encoded
    elif atyp == 4:
        buf += socket.inet_pton(socket.AF_INET6, addr)
    buf += struct.pack("!H", port)
    writer.write(buf)
    await writer.drain()

    ver, rep = struct.unpack("!BB", await reader.readexactly(2))
    if rep != 0:
        raise ConnectionError(f"Upstream SOCKS5 returned error {rep}")
    await reader.readexactly(1)
    atyp_resp = struct.unpack("!B", await reader.readexactly(1))[0]
    if atyp_resp == 1:
        await reader.readexactly(4)
    elif atyp_resp == 3:
        n = (await reader.readexactly(1))[0]
        await reader.readexactly(n)
    elif atyp_resp == 4:
        await reader.readexactly(16)
    await reader.readexactly(2)


async def socks5_auth(reader, writer, user, passw):
    ulen = len(user)
    plen = len(passw)
    auth_msg = (
        struct.pack("!BB", 1, ulen)
        + user.encode()
        + struct.pack("!B", plen)
        + passw.encode()
    )
    writer.write(auth_msg)
    await writer.drain()

    ver, status = struct.unpack("!BB", await reader.readexactly(2))
    if status != 0:
        raise ConnectionError("Upstream SOCKS5 authentication failed")


async def upstream_connect(
    upstream_host, upstream_port, upstream_auth, target_addr, target_port
):
    ureader, uwriter = await asyncio.open_connection(
        upstream_host, upstream_port
    )

    methods = b"\x00" if not upstream_auth else b"\x00\x02"
    uwriter.write(struct.pack("!BB", SOCKS_VERSION, len(methods)) + methods)
    await uwriter.drain()

    ver, method = struct.unpack("!BB", await ureader.readexactly(2))
    if ver != SOCKS_VERSION:
        raise ConnectionError(f"Bad SOCKS version from upstream: {ver}")

    if method == 2:
        if not upstream_auth:
            raise ConnectionError("Upstream requires auth but none provided")
        await socks5_auth(ureader, uwriter, upstream_auth[0], upstream_auth[1])
    elif method == 0:
        pass
    else:
        raise ConnectionError(f"Upstream rejected auth methods: {method}")

    await socks5_connect(ureader, uwriter, target_addr, target_port, 3)

    return ureader, uwriter


async def relay(reader, writer, label):
    try:
        while True:
            data = await reader.read(8192)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except (ConnectionError, asyncio.IncompleteReadError, OSError):
        pass
    finally:
        try:
            writer.close()
        except OSError:
            pass


class Socks5Handler:
    def __init__(self, upstream=None, upstream_auth=None):
        self.upstream = upstream
        self.upstream_auth = upstream_auth

    async def handle(self, reader, writer):
        try:
            ver, nmethods = struct.unpack("!BB", await reader.readexactly(2))
            await reader.readexactly(nmethods)
        except (asyncio.IncompleteReadError, OSError):
            writer.close()
            return

        writer.write(struct.pack("!BB", SOCKS_VERSION, 0))
        await writer.drain()

        try:
            ver, cmd, rsv, atyp = struct.unpack(
                "!BBBB", await reader.readexactly(4)
            )
        except (asyncio.IncompleteReadError, OSError):
            writer.close()
            return

        if cmd != 1:
            writer.write(
                struct.pack("!BBBB", SOCKS_VERSION, 7, 0, 1)
                + socket.inet_aton("0.0.0.0")
                + struct.pack("!H", 0)
            )
            await writer.drain()
            writer.close()
            return

        if atyp == 1:
            addr = socket.inet_ntoa(await reader.readexactly(4))
        elif atyp == 3:
            length = (await reader.readexactly(1))[0]
            addr = (await reader.readexactly(length)).decode()
        elif atyp == 4:
            addr = socket.inet_ntop(
                socket.AF_INET6, await reader.readexactly(16)
            )
        else:
            writer.close()
            return

        port = struct.unpack("!H", await reader.readexactly(2))[0]

        try:
            if self.upstream:
                remote_reader, remote_writer = await upstream_connect(
                    self.upstream[0],
                    self.upstream[1],
                    self.upstream_auth,
                    addr,
                    port,
                )
            else:
                remote_reader, remote_writer = await asyncio.open_connection(
                    addr, port
                )
        except (ConnectionError, OSError, socket.gaierror) as e:
            writer.write(
                struct.pack("!BBBB", SOCKS_VERSION, 1, 0, 1)
                + socket.inet_aton("0.0.0.0")
                + struct.pack("!H", 0)
            )
            await writer.drain()
            writer.close()
            return

        bind_ip = socket.inet_aton(remote_writer.get_extra_info("sockname")[0])
        bind_port = remote_writer.get_extra_info("sockname")[1]
        writer.write(
            struct.pack("!BBBB", SOCKS_VERSION, 0, 0, 1)
            + bind_ip
            + struct.pack("!H", bind_port)
        )
        await writer.drain()

        await asyncio.gather(
            relay(reader, remote_writer, "up"),
            relay(remote_reader, writer, "down"),
        )


async def main(
    host="127.0.0.1", port=10809, upstream=None, upstream_auth=None
):
    handler = Socks5Handler(upstream=upstream, upstream_auth=upstream_auth)
    server = await asyncio.start_server(handler.handle, host, port)
    upstream_str = (
        f" -> {upstream[0]}:{upstream[1]}" if upstream else " (direct)"
    )
    print(f"SOCKS5 proxy: {host}:{port}{upstream_str}")
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=10810)
    p.add_argument("--upstream", help="SOCKS5 upstream host:port")
    p.add_argument("--upstream-auth", help="SOCKS5 upstream user:pass")
    args = p.parse_args()

    upstream = None
    upstream_auth = None
    if args.upstream:
        parts = args.upstream.rsplit(":", 1)
        upstream = (parts[0], int(parts[1]))
    if args.upstream_auth:
        upstream_auth = tuple(args.upstream_auth.split(":", 1))

    asyncio.run(main(args.host, args.port, upstream, upstream_auth))
