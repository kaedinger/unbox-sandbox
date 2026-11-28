#!/usr/bin/env python3
# Draws the icon (stdlib only): a ">_" prompt over a sand dune on a dark rounded
# square. Drawn on a 128-unit grid, rendered at any size (default 128):
#   python3 unraid/make-icon.py > unraid/icon.png
#   python3 unraid/make-icon.py 1024 > unraid/icon-1024.png
import math, struct, sys, zlib

N = int(sys.argv[1]) if len(sys.argv) > 1 else 128   # output size
S = 4 if N <= 256 else 2           # supersampling factor
W = N * S
F = W / 128                        # supersampled pixels per grid unit
BG, SAND, FG = (38, 44, 56), (217, 119, 87), (245, 245, 245)  # SAND: terracotta
P = 0.85                           # prompt scale
AX, AY = 101, 27                   # asterisk centre


def inside_rounded(x, y, r=26 * F):
    cx = min(max(x, r), W - r)
    cy = min(max(y, r), W - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return ((px - ax - t * dx) ** 2 + (py - ay - t * dy) ** 2) ** 0.5


def color(x, y):
    if not inside_rounded(x, y):
        return None
    u, v = x / F, y / F
    # asterisk in the top right corner: six plain round-capped strokes
    for k in range(6):
        a = math.pi / 6 + k * math.pi / 3
        if seg_dist(u, v, AX, AY, AX + 12 * math.cos(a), AY + 12 * math.sin(a)) <= 3.4:
            return SAND
    # ">" chevron and "_" cursor, scaled by P around (60, 58)
    pu, pv = 60 + (u - 60) / P, 58 + (v - 58) / P
    if min(seg_dist(pu, pv, 30, 34, 58, 56), seg_dist(pu, pv, 58, 56, 30, 78)) <= 7:
        return FG
    if 66 <= pu <= 98 and 71 <= pv <= 81:
        return FG
    # dune along the bottom
    dune = 100 - 8 * math.sin((u - 10) / 128 * 3.6)
    if v >= dune:
        return SAND
    return BG


rows = []
for oy in range(N):
    row = bytearray([0])
    for ox in range(N):
        acc = [0, 0, 0, 0]
        for sy in range(S):
            for sx in range(S):
                c = color(ox * S + sx, oy * S + sy)
                if c:
                    acc[0] += c[0]; acc[1] += c[1]; acc[2] += c[2]; acc[3] += 255
        n = S * S
        a = acc[3] // n
        if a:
            k = acc[3] // 255
            row += bytes([acc[0] // k, acc[1] // k, acc[2] // k, a])
        else:
            row += bytes(4)
    rows.append(bytes(row))


def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))


png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", N, N, 8, 6, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
       + chunk(b"IEND", b""))
sys.stdout.buffer.write(png)
