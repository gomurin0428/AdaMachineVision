#!/usr/bin/env python3
"""Converts one member of a zip archive, fetched alone as its local file
entry (the local header followed by the deflated data; a byte range of the
archive), from a 16-bit grey TIFF to a binary 16-bit PGM (P5) that AMV
reads. Used by tools/fetch_real_images.sh for the BBBC006 images, which
are LZW-compressed TIFFs inside large zip archives.

    zip_tiff_to_pgm.py ENTRY OUT.pgm MAXVAL

The PGM's maxval is MAXVAL (fixed for a series, so that AMV's conversion
to 8 bits, round (V * 255 / MAXVAL), applies the same gain to every image
of it); a sample above MAXVAL is an error. Handles what these files use:
a deflated or stored member, a little or big endian TIFF, 16 bits per
sample, one sample per pixel, strips, no compression or LZW, no predictor.
Python standard library only.
"""

import struct
import sys
import zlib


def member_data(entry):
    """The data of a zip member given as its local entry: the local header,
    the compressed data and, when bit 3 of the flags is set (sizes and CRC
    after the data), the data descriptor (with or without its signature)."""
    if entry[:4] != b"PK\x03\x04":
        raise SystemExit("not a zip local file entry")
    flags, method = struct.unpack_from("<HH", entry, 6)
    crc, csize, usize = struct.unpack_from("<III", entry, 14)
    nl, el = struct.unpack_from("<HH", entry, 26)
    start = 30 + nl + el
    if flags & 8:
        crc, csize, usize = struct.unpack_from("<III", entry, len(entry) - 12)
        size = len(entry) - start - 12
        if entry[len(entry) - 16:len(entry) - 12] == b"PK\x07\x08":
            size -= 4
        if size != csize:
            raise SystemExit("zip member: the data descriptor does not fit")
    body = entry[start:start + csize]
    if method == 8:
        data = zlib.decompress(body, -15)
    elif method == 0:
        data = body
    else:
        raise SystemExit("unsupported zip method %d" % method)
    if len(data) != usize or zlib.crc32(data) & 0xFFFFFFFF != crc:
        raise SystemExit("zip member: size or CRC mismatch")
    return data


def lzw_decode(data, expected):
    """TIFF LZW: codes most significant bit first, 9 to 12 bits, Clear 256,
    EndOfInformation 257, the width growing one code early. Stops at
    EndOfInformation or once the strip's expected bytes are out (as
    libtiff does: some writers end a strip without EndOfInformation)."""
    out = bytearray()
    table = [bytes([i]) for i in range(256)] + [b"", b""]
    width = 9
    bit = 0
    total = len(data) * 8
    prev = None
    while bit + width <= total and len(out) < expected:
        byte = bit >> 3
        chunk = int.from_bytes(data[byte:byte + 3].ljust(3, b"\0"), "big")
        code = (chunk >> (24 - width - (bit & 7))) & ((1 << width) - 1)
        bit += width
        if code == 256:
            table = table[:258]
            width = 9
            prev = None
            continue
        if code == 257:
            break
        if prev is None:
            entry = table[code]
        elif code < len(table):
            entry = table[code]
            table.append(prev + entry[:1])
        elif code == len(table):
            entry = prev + prev[:1]
            table.append(entry)
        else:
            raise SystemExit("LZW: bad code %d" % code)
        out += entry
        prev = entry
        if len(table) + 1 >= (1 << width) and width < 12:
            width += 1
    return bytes(out)


def tiff_samples(t):
    order = {b"II": "<", b"MM": ">"}.get(t[:2])
    if order is None:
        raise SystemExit("not a TIFF")
    ifd, = struct.unpack_from(order + "I", t, 4)
    count, = struct.unpack_from(order + "H", t, ifd)
    tags = {}
    for i in range(count):
        tag, typ, n, _ = struct.unpack_from(order + "HHII", t,
                                            ifd + 2 + 12 * i)
        size = {3: 2, 4: 4}.get(typ)
        if size is None:
            continue
        fmt = order + ("H" if typ == 3 else "I")
        at = ifd + 2 + 12 * i + 8
        if n * size > 4:
            at, = struct.unpack_from(order + "I", t, at)
        tags[tag] = [struct.unpack_from(fmt, t, at + k * size)[0]
                     for k in range(n)]
    width, height = tags[256][0], tags[257][0]
    if tags.get(258, [1])[0] != 16 or tags.get(277, [1])[0] != 1:
        raise SystemExit("not a 16-bit grey TIFF")
    if tags.get(317, [1])[0] != 1:
        raise SystemExit("TIFF predictor not supported")
    compression = tags.get(259, [1])[0]
    rows = tags.get(278, [height])[0]
    raw = bytearray()
    for k, (off, n) in enumerate(zip(tags[273], tags[279])):
        strip = t[off:off + n]
        expected = width * 2 * min(rows, height - k * rows)
        if compression == 5:
            raw += lzw_decode(strip, expected)[:expected]
        elif compression == 1:
            raw += strip
        else:
            raise SystemExit("TIFF compression %d not supported" % compression)
    need = width * height * 2
    if len(raw) < need:
        raise SystemExit("TIFF: too few samples")
    samples = struct.unpack(order + "%dH" % (width * height),
                            bytes(raw[:need]))
    return width, height, samples


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    entry = open(sys.argv[1], "rb").read()
    maxval = int(sys.argv[3])
    width, height, samples = tiff_samples(member_data(entry))
    top = max(samples)
    if top > maxval:
        raise SystemExit("sample %d above the maxval %d" % (top, maxval))
    with open(sys.argv[2], "wb") as f:
        f.write(b"P5\n%d %d\n%d\n" % (width, height, maxval))
        f.write(struct.pack(">%dH" % len(samples), *samples))


if __name__ == "__main__":
    main()
