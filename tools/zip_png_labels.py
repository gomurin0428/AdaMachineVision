#!/usr/bin/env python3
"""zip_png_labels.py ENTRY OUT.pgm

Turns an object mask stored as a colour PNG inside a zip member (the raw
bytes of the member's local entry, as tools/fetch_real_images.sh saves
them) into a label image: a 16-bit PGM (maxval 65535) whose pixel is 0 on
the background and K >= 1 on the K-th object.

The masks of BBBC039 give each nucleus a colour, the same colour being
used again for nuclei that do not touch; an object is therefore a
connected set (8-connectivity) of pixels of one colour that is not black.
Objects are numbered in raster order of their first pixel. Prints the
number of objects.

Supported: 8-bit RGB or RGBA PNG (colour types 2 and 6), not interlaced,
the five standard row filters. The zip member is checked by its CRC
(tools/zip_tiff_to_pgm.py)."""
import os
import struct
import sys
import zlib
from collections import deque

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from zip_tiff_to_pgm import member_data  # noqa: E402


def png_pixels(png):
    if png[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("not a PNG")
    pos, idat, header = 8, bytearray(), None
    while pos < len(png):
        n, kind = struct.unpack_from(">I4s", png, pos)
        body = png[pos + 8:pos + 8 + n]
        if zlib.crc32(png[pos + 4:pos + 8 + n]) & 0xFFFFFFFF != \
                struct.unpack_from(">I", png, pos + 8 + n)[0]:
            raise SystemExit("PNG: chunk CRC mismatch")
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
        pos += 12 + n
    width, height, depth, colour, _, _, interlace = header
    if depth != 8 or colour not in (2, 6) or interlace != 0:
        raise SystemExit("PNG: only 8-bit RGB or RGBA, not interlaced")
    bpp = 3 if colour == 2 else 4
    raw = zlib.decompress(bytes(idat))
    stride = width * bpp
    rows, prior = [], bytearray(stride)
    for y in range(height):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prior[i]
            c = prior[i - bpp] if i >= bpp else 0
            if f == 1:
                line[i] = (line[i] + a) & 255
            elif f == 2:
                line[i] = (line[i] + b) & 255
            elif f == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 255
            elif f != 0:
                raise SystemExit("PNG: bad filter %d" % f)
        rows.append(bytes(line))
        prior = line
    colours = [[tuple(r[x * bpp:x * bpp + 3]) for x in range(width)]
               for r in rows]
    return width, height, colours


def labels(width, height, colours):
    out = [[0] * width for _ in range(height)]
    count = 0
    for y in range(height):
        for x in range(width):
            c = colours[y][x]
            if c == (0, 0, 0) or out[y][x]:
                continue
            count += 1
            out[y][x] = count
            queue = deque([(x, y)])
            while queue:
                px, py = queue.popleft()
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        qx, qy = px + dx, py + dy
                        if 0 <= qx < width and 0 <= qy < height \
                                and not out[qy][qx] and colours[qy][qx] == c:
                            out[qy][qx] = count
                            queue.append((qx, qy))
    return count, out


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    width, height, colours = png_pixels(
        member_data(open(sys.argv[1], "rb").read()))
    count, out = labels(width, height, colours)
    if count > 65535:
        raise SystemExit("too many objects")
    with open(sys.argv[2], "wb") as f:
        f.write(b"P5\n%d %d\n65535\n" % (width, height))
        for row in out:
            f.write(struct.pack(">%dH" % width, *row))
    print(count)


if __name__ == "__main__":
    main()
