#!/usr/bin/env python3
"""Keep location and other personal metadata out of the photo fixtures.

    photo-privacy.py check PATH...   exit 1 if any JPEG carries GPS, XMP, or IPTC data
    photo-privacy.py strip PATH...   remove that metadata in place, without re-encoding

PATH is a JPEG or a directory searched recursively. Stripping keeps only the EXIF orientation
flag, which phone photos need to display upright, and drops every other EXIF field, XMP, IPTC,
comments, and MPF. The image data is not touched, so pixels are identical.

Standard library only, so it runs anywhere `verify.sh` does.
"""

import struct
import sys
from pathlib import Path

SOI = b"\xff\xd8"
SOS = 0xDA
APP1, APP13, COM = 0xE1, 0xED, 0xFE
ORIENTATION_TAG, GPS_TAG = 0x0112, 0x8825


def segments(data):
    """Yield (marker, start, end) for each segment before the image data; the last one runs to EOF."""
    if data[:2] != SOI:
        raise ValueError("not a JPEG")
    i = 2
    while i < len(data):
        while data[i] == 0xFF and data[i + 1] == 0xFF:  # fill bytes
            i += 1
        if data[i] != 0xFF:
            raise ValueError(f"bad marker at offset {i}")
        marker = data[i + 1]
        if marker == SOS:
            yield marker, i, len(data)
            return
        end = i + 2 + struct.unpack(">H", data[i + 2 : i + 4])[0]
        yield marker, i, end
        i = end


def exif_info(payload):
    """Read the orientation and whether a GPS block exists from an Exif APP1 payload (after the length)."""
    tiff = payload[6:]
    order = {b"II": "<", b"MM": ">"}.get(tiff[:2])
    if order is None:
        return None, False
    ifd = struct.unpack(order + "I", tiff[4:8])[0]
    count = struct.unpack(order + "H", tiff[ifd : ifd + 2])[0]
    orientation, has_gps = None, False
    for n in range(count):
        entry = ifd + 2 + 12 * n
        tag, kind, _, value = struct.unpack(order + "HHIH", tiff[entry : entry + 10])
        if tag == ORIENTATION_TAG and kind == 3:
            orientation = value
        elif tag == GPS_TAG:
            has_gps = True
    return orientation, has_gps


def inspect(data):
    """Return (orientation, problems) for a JPEG's bytes."""
    orientation, problems = None, []
    for marker, start, end in segments(data):
        payload = data[start + 4 : end]
        if marker == APP1 and payload.startswith(b"Exif\x00\x00"):
            orientation, has_gps = exif_info(payload)
            if has_gps:
                problems.append("GPS location")
        elif marker == APP1:
            problems.append("XMP")
        elif marker == APP13:
            problems.append("IPTC")
    return orientation, problems


def orientation_only_exif(orientation):
    tiff = b"MM\x00\x2a\x00\x00\x00\x08" + struct.pack(">H", 1)
    tiff += struct.pack(">HHIHH", ORIENTATION_TAG, 3, 1, orientation, 0) + b"\x00\x00\x00\x00"
    payload = b"Exif\x00\x00" + tiff
    return b"\xff\xe1" + struct.pack(">H", len(payload) + 2) + payload


def strip(data):
    orientation, _ = inspect(data)
    kept, has_jfif = [], False
    for marker, start, end in segments(data):
        payload = data[start + 4 : end]
        if marker == SOS:
            tail = data[start:]
        elif marker in (APP1, APP13, COM) or payload.startswith(b"MPF\x00"):
            continue
        else:
            has_jfif = has_jfif or payload.startswith(b"JFIF")
            kept.append(data[start:end])
    exif = orientation_only_exif(orientation) if orientation else b""
    # JFIF, when present, must come first; EXIF goes right after it.
    head = kept[:1] if has_jfif else []
    return SOI + b"".join(head) + exif + b"".join(kept[len(head) :]) + tail


def jpegs(paths):
    for path in map(Path, paths):
        if path.is_dir():
            yield from sorted(p for p in path.rglob("*") if p.suffix.lower() in (".jpg", ".jpeg"))
        elif path.suffix.lower() in (".jpg", ".jpeg"):
            yield path


def main(argv):
    if len(argv) < 3 or argv[1] not in ("check", "strip"):
        print(__doc__)
        return 2
    command, failed = argv[1], False
    for path in jpegs(argv[2:]):
        data = path.read_bytes()
        _, problems = inspect(data)
        if command == "check" and problems:
            print(f"{path}: contains {', '.join(problems)}; run scripts/photo-privacy.py strip")
            failed = True
        elif command == "strip":
            cleaned = strip(data)
            if cleaned != data:
                path.write_bytes(cleaned)
                print(f"stripped {path}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
