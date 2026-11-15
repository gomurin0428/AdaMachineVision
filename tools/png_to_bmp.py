#!/usr/bin/env python3
"""png_to_bmp.py IN.png OUT.bmp

Writes a PNG as a 24-bit BMP, with the Python standard library only.
tools/fetch_real_images.sh uses it for the images whose pixels must be
the same on every platform (the barcode photographs): the installed
converters differ (sips, on macOS, changes some grey levels by one and
writes no BMP for some PNGs with a palette).

Supported: every colour type and bit depth of PNG (grey, RGB, palette,
with or without alpha), not interlaced. Samples of 16 bits keep their
high byte, grey levels of 1, 2 and 4 bits are spread over 0 .. 255, and
transparency (an alpha channel, or the alpha values of a palette) is
flattened on white. The pixels are otherwise those of the file: no
colour profile or gamma is applied."""
import struct
import sys
import zlib

CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}
DEPTHS = {0: (1, 2, 4, 8, 16), 2: (8, 16), 3: (1, 2, 4, 8), 4: (8, 16),
          6: (8, 16)}


def chunks(png):
    if png[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("not a PNG")
    pos = 8
    while pos + 12 <= len(png):
        n, kind = struct.unpack_from(">I4s", png, pos)
        body = png[pos + 8:pos + 8 + n]
        if len(body) != n or pos + 12 + n > len(png) or \
                zlib.crc32(png[pos + 4:pos + 8 + n]) & 0xFFFFFFFF != \
                struct.unpack_from(">I", png, pos + 8 + n)[0]:
            raise SystemExit("PNG: damaged chunk")
        yield kind, body
        if kind == b"IEND":
            return
        pos += 12 + n
    raise SystemExit("PNG: no end")


def unfilter(raw, height, stride, bpp):
    """The rows of the image, each a bytearray of stride bytes."""
    if len(raw) != height * (stride + 1):
        raise SystemExit("PNG: wrong amount of image data")
    rows, prior, pos = [], bytearray(stride), 0
    for _ in range(height):
        f = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += stride + 1
        if f == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prior[i]) & 255
        elif f == 3:
            for i in range(min(bpp, stride)):
                line[i] = (line[i] + prior[i] // 2) & 255
            for i in range(bpp, stride):
                line[i] = (line[i] + (line[i - bpp] + prior[i]) // 2) & 255
        elif f == 4:
            for i in range(min(bpp, stride)):
                line[i] = (line[i] + prior[i]) & 255
            for i in range(bpp, stride):
                a, b, c = line[i - bpp], prior[i], prior[i - bpp]
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                if pa <= pb and pa <= pc:
                    line[i] = (line[i] + a) & 255
                elif pb <= pc:
                    line[i] = (line[i] + b) & 255
                else:
                    line[i] = (line[i] + c) & 255
        elif f != 0:
            raise SystemExit("PNG: bad filter %d" % f)
        rows.append(line)
        prior = line
    return rows


def samples(line, width, depth):
    """The first width samples of a row of samples of depth bits."""
    if depth == 8:
        return line[:width]
    if depth == 16:
        return line[0:2 * width:2]
    out = bytearray(width)
    mask, per = (1 << depth) - 1, 8 // depth
    for x in range(width):
        shift = 8 - depth * (x % per + 1)
        out[x] = (line[x // per] >> shift) & mask
    return out


def on_white(value, alpha):
    return (value * alpha + 255 * (255 - alpha) + 127) // 255


def bgr_rows(png):
    header, palette, alphas, idat = None, None, b"", bytearray()
    for kind, body in chunks(png):
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"PLTE":
            palette = body
        elif kind == b"tRNS":
            alphas = body
        elif kind == b"IDAT":
            idat += body
    if header is None:
        raise SystemExit("PNG: no header")
    width, height, depth, colour, _, _, interlace = header
    if colour not in CHANNELS or depth not in DEPTHS[colour]:
        raise SystemExit("PNG: bad colour type or bit depth")
    if interlace != 0:
        raise SystemExit("PNG: interlaced images are not supported")
    if width == 0 or height == 0:
        raise SystemExit("PNG: empty image")
    channels = CHANNELS[colour]
    stride = (width * channels * depth + 7) // 8
    bpp = max(1, channels * depth // 8)
    rows = unfilter(zlib.decompress(bytes(idat)), height, stride, bpp)

    if colour == 3:
        if palette is None or len(palette) % 3 != 0:
            raise SystemExit("PNG: no palette")
        table = []
        for i in range(len(palette) // 3):
            alpha = alphas[i] if i < len(alphas) else 255
            r, g, b = palette[3 * i:3 * i + 3]
            table.append(bytes((on_white(b, alpha), on_white(g, alpha),
                                on_white(r, alpha))))
    elif colour == 0:
        top = (1 << min(depth, 8)) - 1
        table = [bytes((255 * v // top,) * 3) for v in range(top + 1)]

    step = depth // 8 if depth >= 8 else 1
    for line in rows:
        if colour in (0, 3):
            try:
                yield b"".join(table[v] for v in samples(line, width, depth))
            except IndexError:
                raise SystemExit("PNG: colour outside the palette")
            continue
        # One byte for each sample: the high byte of 16 bits.
        s = line[0::step]
        out = bytearray(3 * width)
        if colour == 2:
            out[0::3], out[1::3], out[2::3] = s[2::3], s[1::3], s[0::3]
        elif colour == 4:
            grey = bytes(on_white(s[2 * x], s[2 * x + 1])
                         for x in range(width))
            out[0::3], out[1::3], out[2::3] = grey, grey, grey
        else:
            for x in range(width):
                alpha = s[4 * x + 3]
                out[3 * x] = on_white(s[4 * x + 2], alpha)
                out[3 * x + 1] = on_white(s[4 * x + 1], alpha)
                out[3 * x + 2] = on_white(s[4 * x], alpha)
        yield bytes(out)


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    with open(sys.argv[1], "rb") as f:
        png = f.read()
    rows = list(bgr_rows(png))
    width, height = len(rows[0]) // 3, len(rows)
    pad = b"\0" * (-3 * width % 4)
    size = (3 * width + len(pad)) * height
    with open(sys.argv[2], "wb") as f:
        f.write(b"BM" + struct.pack("<IHHI", 54 + size, 0, 0, 54))
        f.write(struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24, 0,
                            size, 2835, 2835, 0, 0))
        for row in reversed(rows):
            f.write(row + pad)


if __name__ == "__main__":
    main()
