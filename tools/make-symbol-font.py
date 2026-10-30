#!/usr/bin/env python3
import os
import re
import struct

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(REPO, "system", "vyntaris-logo-symbolic.svg")
TARGET = os.path.join(REPO, "system", "fonts", "VyntarisSymbols.ttf")
LOGO = 0x10F000
EM = 1000
ASCENT, DESCENT = 800, -200
FAMILY = "Vyntaris Symbols"


def contours():
    with open(SOURCE) as f:
        d = re.search(r' d="([^"]+)"', f.read()).group(1)
    scale = EM / 24
    # The picture's y runs down, a font's up, so each outline is turned round to stay clockwise.
    return [[(round(float(x) * scale), round(ASCENT - float(y) * scale))
             for x, y in re.findall(r"(-?[\d.]+) (-?[\d.]+)", part)][::-1]
            for part in d.split("M")[1:]]


def glyph(shapes):
    points = [p for shape in shapes for p in shape]
    xs, ys = [p[0] for p in points], [p[1] for p in points]
    box = (min(xs), min(ys), max(xs), max(ys))
    data = struct.pack(">5h", len(shapes), *box)
    end = -1
    for shape in shapes:
        end += len(shape)
        data += struct.pack(">H", end)
    data += struct.pack(">H", 0) + b"\x01" * len(points)
    for axis in (xs, ys):
        last = 0
        for v in axis:
            data += struct.pack(">h", v - last)
            last = v
    return data + b"\0" * (-len(data) % 4), box, len(points)


def name_table():
    names = {1: FAMILY, 2: "Regular", 3: FAMILY, 4: FAMILY, 5: "Version 1.0", 6: FAMILY.replace(" ", "")}
    records, text = b"", b""
    for key, value in names.items():
        raw = value.encode("utf-16-be")
        records += struct.pack(">6H", 3, 1, 0x409, key, len(raw), len(text))
        text += raw
    return struct.pack(">3H", 0, len(names), 6 + len(records)) + records + text


def checksum(data):
    data += b"\0" * (-len(data) % 4)
    return sum(struct.unpack(f">{len(data) // 4}I", data)) & 0xFFFFFFFF


def main():
    shapes = contours()
    outline, box, count = glyph(shapes)
    tables = {
        "OS/2": struct.pack(">HhHHH10hh", 4, EM, 400, 5, 0, *([0] * 10), 0)
            + bytes([2, 0, 0, 9, 0, 0, 0, 0, 0, 0])
            + struct.pack(">4I4sHHHhhhHHIIhhHHH", 0, 0, 0, 0, b"VYNT", 0x40, 0xFFFF, 0xFFFF,
                          ASCENT, DESCENT, 0, ASCENT, -DESCENT, 0, 0, 0, 0, 0, 0, 0),
        "cmap": struct.pack(">HHHHI", 0, 1, 3, 10, 12) + struct.pack(">HHIIIIII", 12, 0, 28, 0, 1, LOGO, LOGO, 1),
        "glyf": outline,
        "head": struct.pack(">IIIIHHQQ4hHHhhh", 0x00010000, 0x00010000, 0, 0x5F0F3CF5, 0x000B, EM, 0, 0, *box, 0, 8, 2, 1, 0),
        "hhea": struct.pack(">I3hH3h3h4hhH", 0x00010000, ASCENT, DESCENT, 0, EM, 0, box[0], box[2], 1, 0, 0, 0, 0, 0, 0, 0, 2),
        "hmtx": struct.pack(">HhHh", EM, 0, EM, box[0]),
        "loca": struct.pack(">3I", 0, 0, len(outline)),
        "maxp": struct.pack(">I13H", 0x00010000, 2, count, len(shapes), 0, 0, 2, 0, 0, 0, 0, 0, 0, 0) + struct.pack(">H", 0),
        "name": name_table(),
        "post": struct.pack(">IIhhIIIII", 0x00030000, 0, 0, 0, 1, 0, 0, 0, 0),
    }
    power = max(p for p in range(8) if 2 ** p <= len(tables))
    font = struct.pack(">IHHHH", 0x00010000, len(tables), 16 * 2 ** power, power, 16 * (len(tables) - 2 ** power))
    offset = len(font) + 16 * len(tables)
    body = b""
    for tag in sorted(tables):
        data = tables[tag]
        font += struct.pack(">4sIII", tag.encode(), checksum(data), offset + len(body), len(data))
        body += data + b"\0" * (-len(data) % 4)
    font += body
    # head's checkSumAdjustment makes the whole file add up to a fixed number.
    at = offset + sum(len(tables[t]) + (-len(tables[t]) % 4) for t in sorted(tables) if t < "head") + 8
    font = font[:at] + struct.pack(">I", (0xB1B0AFBA - checksum(font)) & 0xFFFFFFFF) + font[at + 4:]
    os.makedirs(os.path.dirname(TARGET), exist_ok=True)
    with open(TARGET, "wb") as f:
        f.write(font)
    print(TARGET)


if __name__ == "__main__":
    main()
