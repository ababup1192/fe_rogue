#!/usr/bin/env python3
"""ドット絵 (*.sprite.json) を目視用の PNG に描き出す (シルエット・明度・背景の明暗)。

lint-sprite の `silhouette` ルール (充填率と縦横比の検査) とは別物 —
こちらは目視用の PNG を書き出す。

  python3 bin/sil-png.py --mode sil   # 全 legend を黒 1 色に潰す   → gallery/sil/
  python3 bin/sil-png.py --mode gray  # 明度だけのグレーにする      → gallery/gray/
  python3 bin/sil-png.py --mode bg    # 明背景と暗背景に並べて置く  → gallery/bg/
  python3 bin/sil-png.py --mode sil a.sprite.json   # 指定ファイルだけ

引数を省くと lint-sprite と同じ範囲 (templates/ 配下、生成されたゲームでは assets/)。
何が分かるか:
  sil  — 単色に潰しても何者か読めるか (読めなければ形が弱い)
  gray — 色を外してもパーツが分離して読めるか (色相だけに頼っていないか)
  bg   — 明るい所と暗い所の両方で輪郭が消えないか

元の Doc は書き換えない (色の差し替えはメモリの上だけ)。書き出し先の gallery/ は
git 管理外なので、人に見せる絵は docs/gallery/ へ選んで写す。
標準ライブラリだけで動く (Windows / macOS / Linux 共通)。
"""

import argparse
import importlib.util
import math
import os
import struct
import sys
import zlib

# Windows のコンソール (cp932 等) でも日本語メッセージで落とさない。
for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

SIL_INK = (0x1A, 0x1A, 0x1A, 255)
SIL_BG = (255, 255, 255, 255)
BG_LIGHT = (0xE8, 0xE8, 0xE8, 255)
BG_DARK = (0x20, 0x20, 0x20, 255)
BG_GAP = 2        # 並べた 2 枚の間の隙間 (拡大前のセル数)
SMALL_SIDE = 48   # これ以下は 8 倍、超えたら 4 倍に拡大する


def load_lint_sprite():
    """Doc の探し方と legend の色解決は lint-sprite.py の物を借りる (二重実装しない)。"""
    path = os.path.join(HERE, "lint-sprite.py")
    spec = importlib.util.spec_from_file_location("lint_sprite", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


LS = load_lint_sprite()


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


def rgba_of(hex_color):
    return tuple(int(hex_color[i : i + 2], 16) for i in (1, 3, 5)) + (255,)


def rgba_of_floats(values):
    return tuple(max(0, min(255, round(v * 255))) for v in values) + (255,)


def rgba_of_hsv(h, s, v):
    """Color.hsv (engine/src/core/Color.flix) と同じ変換。h は 1 周 = 1.0。"""
    h6 = (h - math.floor(h)) * 6.0
    f = h6 - math.floor(h6)
    p, q, u = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    return rgba_of_floats(
        (v, u, p) if h6 < 1 else
        (q, v, p) if h6 < 2 else
        (p, v, u) if h6 < 3 else
        (p, q, v) if h6 < 4 else
        (u, p, v) if h6 < 5 else
        (v, p, q)
    )


def rgba_of_value(value):
    """色 1 値 → RGBA。読めなければ None。

    lint-sprite の hex_of_value は "#rrggbb" しか解かない (色の近さの検査は
    hex で書かれた色だけを縄張りにしている)。ここは実際の絵を描き出すので、
    生成された色票が使う {"rgb": [...]} / {"hsv": [...]} も読む。
    """
    found = LS.hex_of_value(value)
    if found:
        return rgba_of(found)
    if isinstance(value, dict):
        if LS.LP.is_floats3(value.get("rgb")) and "hsv" not in value:
            return rgba_of_floats(value["rgb"])
        if LS.LP.is_floats3(value.get("hsv")) and "rgb" not in value:
            return rgba_of_hsv(*value["hsv"])
        for key in LS.LP.COLOR_WRAP_KEYS:
            if key in value:
                nested = rgba_of_value(value[key])
                if nested:
                    return nested
    return None


def color_map_of(obj):
    """object の直下と "colors" の下から 名前 → RGBA を集める。"""
    if not isinstance(obj, dict):
        return {}
    found = {}
    for source in (obj, obj.get("colors")):
        if not isinstance(source, dict):
            continue
        for name, value in source.items():
            got = rgba_of_value(value)
            if got:
                found[name] = got
    return found


def legend_colors_of(game_dir, doc):
    """legend の 文字 → RGBA。色票で解けない文字は透明のまま (lint-palette の縄張り)。"""
    names = {}
    for rel in LS.walk_json(game_dir):
        if rel.endswith(".theme.json"):
            names.update(color_map_of(LS.read_json(os.path.join(game_dir, rel))))
    ref = doc.get("paletteFile")
    if isinstance(ref, str):
        names.update(color_map_of(LS.read_json(os.path.join(game_dir, ref))))
    names.update(color_map_of(doc.get("palette")))

    legend = doc.get("legend")
    legend = legend if isinstance(legend, dict) else {}
    colors = {}
    for char, value in legend.items():
        direct = rgba_of_value(value)
        if direct:
            colors[char] = direct
            continue
        if isinstance(value, str):
            name = value[1:] if value.startswith("@") else value
            if name in names:
                colors[char] = names[name]
    return colors


def to_gray(px):
    y = round(0.299 * px[0] + 0.587 * px[1] + 0.114 * px[2])
    return (y, y, y, px[3])


def frame_pixels(rows, legend, background):
    """rows を RGBA の 2 次元列へ (legend に無い文字 = background)。"""
    width = max((len(r) for r in rows), default=0)
    grid = []
    for row in rows:
        line = []
        for x in range(width):
            char = row[x] if x < len(row) else "."
            line.append(legend.get(char, background))
        grid.append(line)
    return width, len(rows), grid


def scale_up(width, height, grid):
    scale = 8 if max(width, height) <= SMALL_SIDE else 4
    out = []
    for row in grid:
        line = []
        for px in row:
            line.extend([px] * scale)
        out.extend([line] * scale)
    return width * scale, height * scale, out


def build_frame(mode, rows, legend):
    if mode == "sil":
        return frame_pixels(rows, {char: SIL_INK for char in legend}, SIL_BG)
    if mode == "gray":
        gray = {char: to_gray(px) for char, px in legend.items()}
        return frame_pixels(rows, gray, (0, 0, 0, 0))
    width, height, light = frame_pixels(rows, legend, BG_LIGHT)
    _, _, dark = frame_pixels(rows, legend, BG_DARK)
    gap = [(0, 0, 0, 0)] * BG_GAP
    joined = [light[y] + gap + dark[y] for y in range(height)]
    return width * 2 + BG_GAP, height, joined


def base_name_of(shown):
    """書き出しファイルの頭。ゲームが違えば同じ名前の Doc があるので潰さない。"""
    stem = shown[: -len(".sprite.json")] if shown.endswith(".sprite.json") else shown
    stem = os.path.relpath(os.path.abspath(stem), ROOT)
    return stem.replace(os.sep, "__").replace("..", "_")


def process_doc(shown, path, game_dir, mode, out_dir):
    doc = LS.read_json(path)
    if not isinstance(doc, dict):
        print(f"読めない: {shown}", file=sys.stderr)
        return []
    legend = legend_colors_of(game_dir, doc)
    base = base_name_of(shown)
    sprites = doc.get("sprites")
    sprites = sprites if isinstance(sprites, dict) else {}
    written = []
    for sprite_name in sorted(sprites):
        spec = sprites[sprite_name]
        if sprite_name.startswith("//") or not isinstance(spec, dict):
            continue
        frames = spec.get("frames")
        frames = frames if isinstance(frames, dict) else {}
        for frame_name in sorted(frames):
            rows = frames[frame_name]
            if not isinstance(rows, list) or not rows:
                continue
            if not all(isinstance(r, str) for r in rows):
                continue
            if not max((len(r) for r in rows), default=0):
                continue
            width, height, grid = build_frame(mode, rows, legend)
            width, height, grid = scale_up(width, height, grid)
            out = os.path.join(out_dir, f"{base}__{sprite_name}__{frame_name}.png")
            with open(out, "wb") as handle:
                handle.write(png_of(width, height, grid))
            written.append(out)
    return written


def main(argv):
    parser = argparse.ArgumentParser(description="ドット絵を目視用の PNG に描き出す")
    parser.add_argument("--mode", choices=("sil", "gray", "bg"), required=True)
    parser.add_argument("files", nargs="*")
    args = parser.parse_args(argv)

    out_dir = os.path.join(ROOT, "gallery", args.mode)
    os.makedirs(out_dir, exist_ok=True)
    count = 0
    for shown, path, game_dir in LS.gather_targets(args.files, ROOT):
        for out in process_doc(shown, path, game_dir, args.mode, out_dir):
            print(os.path.relpath(out, ROOT))
            count += 1
    print(f"{count} 枚を書き出した ({args.mode})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
