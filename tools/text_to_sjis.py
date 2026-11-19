#!/usr/bin/env python3
"""text_to_sjis.py IN.txt OUT.sjis

Writes a text in UTF-8 as the same text in Shift JIS, with the Python
standard library only. tools/fetch_real_images.sh uses it for the texts
of the QR Code images: the code reader reports the bytes of a symbol as
they are encoded, and some symbols hold their text in Shift JIS.

The codec is shift_jis (JIS X 0201 and JIS X 0208), or cp932 for a text
with characters that only that extension has. OUT is not written, and
is removed if it is there, where the text cannot be written in either,
or where its bytes would be those of IN (a text in ASCII)."""
import os
import sys


def shift_jis(text):
    for codec in ("shift_jis", "cp932"):
        try:
            return text.encode(codec)
        except UnicodeEncodeError:
            pass
    return None


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    with open(sys.argv[1], "rb") as source:
        data = source.read()
    try:
        coded = shift_jis(data.decode("utf-8"))
    except UnicodeDecodeError:
        raise SystemExit(sys.argv[1] + ": not UTF-8")
    if coded is None or coded == data:
        if os.path.exists(sys.argv[2]):
            os.remove(sys.argv[2])
        return
    with open(sys.argv[2], "wb") as target:
        target.write(coded)


main()
