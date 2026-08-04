#!/usr/bin/env python3
"""コマの PNG を並べて、動く GIF にする (標準ライブラリのみ)。

    python3 bin/gifs.py                # gallery/ の各工程から歩きの GIF を作る

止まった絵を並べても、コマ間の飛びや接地のずれは分からない。動かして初めて読める。
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_s = importlib.util.spec_from_file_location("sheet", os.path.join(HERE, "sheet.py"))
sheet = importlib.util.module_from_spec(_s)
_s.loader.exec_module(sheet)

# 動きごとのコマの並び。歩きは接地→中間→接地(逆)→中間の 4 コマ
CYCLES = {
    "歩き": ("walk_0", "walk_1", "walk_2", "walk_3"),
    "振り": ("idle", "swing_0", "swing_1", "swing_2", "idle"),
    "跳ぶ": ("idle", "jump_0", "jump_1", "jump_2", "idle"),
}
DELAY = 14                                     # 1 コマの長さ (1/100 秒)


def _bits(codes, width_start, clear, end):
    """LZW の符号をビット列に詰める。辞書を伸ばさず、幅が上がる前に clear を打つ。

    圧縮しないぶん大きいが、符号化が 1 通りに決まるので壊れようがない。
    """
    out = bytearray()
    acc = acc_bits = 0
    width = width_start

    def push(code):
        nonlocal acc, acc_bits
        acc |= code << acc_bits
        acc_bits += width
        while acc_bits >= 8:
            out.append(acc & 0xFF)
            acc >>= 8
            acc_bits -= 8

    push(clear)
    since = 0
    for code in codes:
        push(code)
        since += 1
        if since >= 250:          # 復号側の辞書が幅を上げる前に区切り直す
            push(clear)
            since = 0
    push(end)
    if acc_bits:
        out.append(acc & 0xFF)
    return bytes(out)


def gif_of(width, height, frames, palette, delay=DELAY, transparent=0):
    """frames は「画素の番号の並び」の列。palette は (r,g,b) の並び (最大 256)。"""
    table = bytearray()
    for i in range(256):
        table.extend(palette[i] if i < len(palette) else (0, 0, 0))
    out = bytearray(b"GIF89a")
    out += bytes([width & 255, width >> 8, height & 255, height >> 8, 0xF7, 0, 0])
    out += table
    out += b"\x21\xFF\x0BNETSCAPE2.0\x03\x01\x00\x00\x00"   # 無限に繰り返す
    for pixels in frames:
        out += bytes([0x21, 0xF9, 4, 0b00001001, delay & 255, delay >> 8,
                      transparent, 0])
        out += bytes([0x2C, 0, 0, 0, 0, width & 255, width >> 8,
                      height & 255, height >> 8, 0])
        out += bytes([8])
        data = _bits(pixels, 9, 256, 257)
        for i in range(0, len(data), 255):
            chunk = data[i:i + 255]
            out += bytes([len(chunk)]) + chunk
        out += b"\x00"
    out += b"\x3B"
    return bytes(out)


def from_pngs(paths, shrink=1):
    """PNG を読んで、色を番号に振り直した GIF を作る。番号 0 は透明。

    shrink は工程の絵の拡大率。**等倍に戻してから**焼く — 拡大したまま焼くと、
    同じ絵なのに何十倍にも膨らむ。見るときの拡大は表示側の仕事。
    """
    read = []
    for path in paths:
        w, h, rows = sheet.read_png(path)
        if shrink > 1:
            rows = [[rows[y][x] for x in range(0, w, shrink)]
                    for y in range(0, h, shrink)]
            w, h = len(rows[0]), len(rows)
        read.append((w, h, rows))
    w = max(r[0] for r in read)
    h = max(r[1] for r in read)
    palette = [(0, 0, 0)]
    index = {}
    frames = []
    for pw, ph, rows in read:
        ox, oy = (w - pw) // 2, h - ph
        flat = []
        for y in range(h):
            for x in range(w):
                px = (0, 0, 0, 0)
                sy, sx = y - oy, x - ox
                if 0 <= sy < ph and 0 <= sx < pw:
                    px = rows[sy][sx]
                if px[3] == 0:
                    flat.append(0)
                    continue
                key = px[:3]
                if key not in index:
                    index[key] = len(palette)
                    palette.append(key)
                flat.append(index[key])
        frames.append(flat)
    return gif_of(w, h, frames, palette)


def main(argv):
    root = os.path.dirname(HERE)
    shrink = int(argv[0]) if argv else 6
    only = argv[1:]        # 工程を指定すると、その工程だけ焼く
    made = []
    for body in sorted(os.listdir(os.path.join(root, "gallery"))):
        home = os.path.join(root, "gallery", body)
        if not os.path.isdir(home):
            continue
        for stage in sorted(os.listdir(home)):
            if only and stage not in only:
                continue
            for view in sheet.VIEWS:
              for move, cycle in CYCLES.items():
                paths = [os.path.join(home, stage, f"{view}_{f}.png") for f in cycle]
                if not all(os.path.exists(p) for p in paths):
                    continue
                out = os.path.join(root, "gallery",
                                   f"{move}_{body}_{stage}_{view}.gif")
                with open(out, "wb") as handle:
                    handle.write(from_pngs(paths, shrink))
                made.append(os.path.relpath(out, root))
    print("\n".join(made))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
