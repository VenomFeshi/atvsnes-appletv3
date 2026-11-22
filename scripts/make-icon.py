"""Write a 284x161 PNG tile using only the Python standard library."""

import struct
import sys
import zlib


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(
        ">I", zlib.crc32(kind + data)
    )


S = ("11111", "10000", "10000", "11111", "00001", "00001", "11111")
N = ("10001", "11001", "11001", "10101", "10011", "10011", "10001")
E = ("11111", "10000", "10000", "11110", "10000", "10000", "11111")
letters = ["0".join(row) for row in zip(S, N, E, S)]


def pixel(x, y):
    edge_x, edge_y = min(x, 283 - x), min(y, 160 - y)
    if edge_x == 0 or edge_y == 0 or (
        edge_x < 12 and edge_y < 12 and (12 - edge_x) ** 2 + (12 - edge_y) ** 2 > 121
    ):
        return b"\x00\x00\x00\x00"
    if 50 <= x < 234 and 52 <= y < 108 and letters[(y - 52) // 8][(x - 50) // 8] == "1":
        return b"\xf7\xf4\xff\xff"
    return bytes((36 + y // 6, 30, 77 + y // 5, 255))


raw = b"".join(b"\x00" + b"".join(pixel(x, y) for x in range(284)) for y in range(161))
with open(sys.argv[1], "wb") as output:
    output.write(b"\x89PNG\r\n\x1a\n")
    output.write(chunk(b"IHDR", struct.pack(">IIBBBBB", 284, 161, 8, 6, 0, 0, 0)))
    output.write(chunk(b"IDAT", zlib.compress(raw, 9)))
    output.write(chunk(b"IEND", b""))
