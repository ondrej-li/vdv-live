#!/usr/bin/env python3
"""Rewrite a PNG with only the chunks an App Store upload will accept.

App Store Connect refuses an asset whose dimensions are in fact correct with
"File dimensions are invalid", because its validator counts any metadata chunk as
a reason to reject the file. `sips`, Preview exports and ImageIO all write an
`eXIf` chunk, so an image that opened and saved cleanly can still be refused.

This keeps the compressed image data verbatim - same pixels, same size, same
colour type - and drops every ancillary chunk with it. Nothing is re-encoded.

    python3 tools/strip-png-metadata.py icon.png [more.png ...]

Prints the chunks it kept for each file. Exits non-zero if the PNG cannot be read
or if it carries an alpha channel, which App Store artwork must not.
"""

import struct
import sys
import zlib

# The only chunks a bare PNG needs. Everything else is metadata.
KEEP = {b"IHDR", b"PLTE", b"IDAT", b"IEND", b"tRNS"}

ALPHA_COLOUR_TYPES = {4, 6}


def chunk(kind, payload):
    checksum = zlib.crc32(kind + payload) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", checksum)


def strip(path):
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")

    ihdr = None
    idat = bytearray()
    dropped = []
    offset = 8
    while offset < len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        if kind == b"IHDR":
            ihdr = payload
        elif kind == b"IDAT":
            idat += payload
        elif kind not in KEEP:
            dropped.append(kind.decode("ascii", "replace"))
        offset += 12 + length
        if kind == b"IEND":
            break

    if ihdr is None or not idat:
        raise ValueError(f"{path}: no image data")

    width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", ihdr)
    if colour in ALPHA_COLOUR_TYPES:
        raise ValueError(f"{path}: {width}x{height} has an alpha channel")
    if interlace:
        raise ValueError(f"{path}: interlaced")

    zlib.decompress(bytes(idat))  # the stream has to be whole before it is moved
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n")
        handle.write(chunk(b"IHDR", ihdr))
        handle.write(chunk(b"IDAT", bytes(idat)))
        handle.write(chunk(b"IEND", b""))
    return width, height, depth, colour, dropped


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    status = 0
    for path in sys.argv[1:]:
        try:
            width, height, depth, colour, dropped = strip(path)
        except (ValueError, OSError) as error:
            print(f"  {error}")
            status = 1
            continue
        dropped_text = ", ".join(dropped) if dropped else "none"
        print(f"{path}: {width}x{height} depth={depth} colour={colour}, dropped {dropped_text}")
    return status


if __name__ == "__main__":
    sys.exit(main())
