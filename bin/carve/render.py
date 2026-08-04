#!/usr/bin/env python3
"""sprite.json の文字格子を PNG に描く (標準ライブラリのみ)。

  python3 bin/render.py                 # assets/ 配下を全部 gallery/ へ
  python3 bin/render.py a.sprite.json   # 指定ファイルだけ

色は Doc 直下の inline "palette" (名前 → "#rrggbb") で解く。
拡大率は絵の大きさで自動 (48px 以下 = 8 倍、それ以上 = 4 倍)。
"""

import json
import os
import struct
import sys
import zlib

# Windows のコンソール (cp932 等) でも日本語メッセージで落とさない。
for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

TRANSPARENT_CHARS = {".", " "}


def png_of(width, height, rows_rgba):
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    raw = b"".join(
        b"\x00" + b"".join(struct.pack("4B", *px) for px in row) for row in rows_rgba
    )
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def rgba_of(value):
    body = value[1:] if value.startswith("#") else value
    return tuple(int(body[i : i + 2], 16) for i in (0, 2, 4)) + (255,)


def hex_of(value):
    if isinstance(value, str):
        body = value[1:] if value.startswith("#") else value
        if len(body) == 6 and all(c in "0123456789abcdefABCDEF" for c in body):
            return "#" + body.lower()
    if isinstance(value, dict):
        for key in ("hex", "color", "value"):
            if key in value:
                found = hex_of(value[key])
                if found:
                    return found
    return None


def render_doc(path, out_dir):
    with open(path, encoding="utf-8") as handle:
        doc = json.load(handle)
    palette = {
        name: hex_of(value)
        for name, value in (doc.get("palette") or {}).items()
        if hex_of(value)
    }
    legend = {}
    for char, value in (doc.get("legend") or {}).items():
        direct = hex_of(value)
        name = value[1:] if isinstance(value, str) and value.startswith("@") else value
        resolved = direct or palette.get(name)
        if resolved:
            legend[char] = rgba_of(resolved)

    base = os.path.basename(path).replace(".sprite.json", "")
    written = []
    for sprite_name, spec in (doc.get("sprites") or {}).items():
        if sprite_name.startswith("//") or not isinstance(spec, dict):
            continue
        for frame_name, rows in (spec.get("frames") or {}).items():
            width = max((len(r) for r in rows), default=0)
            height = len(rows)
            if not width or not height:
                continue
            scale = 8 if max(width, height) <= 48 else 4
            rgba_rows = []
            for row in rows:
                line = []
                for x in range(width):
                    char = row[x] if x < len(row) else "."
                    line.extend([legend.get(char, (0, 0, 0, 0))] * scale)
                rgba_rows.extend([line] * scale)
            out = os.path.join(out_dir, f"{base}__{sprite_name}__{frame_name}.png")
            with open(out, "wb") as handle:
                handle.write(png_of(width * scale, height * scale, rgba_rows))
            written.append(out)
    return written


def main(argv):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "gallery")
    os.makedirs(out_dir, exist_ok=True)
    targets = argv or sorted(
        os.path.join(current, name)
        for current, _, files in os.walk(os.path.join(root, "assets"))
        for name in files
        if name.endswith(".sprite.json")
    )
    count = 0
    for path in targets:
        for out in render_doc(path, out_dir):
            print(os.path.relpath(out, root))
            count += 1
    print(f"{count} 枚を書き出した")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
