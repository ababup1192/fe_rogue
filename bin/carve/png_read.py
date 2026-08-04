#!/usr/bin/env python3
"""PNG を読む (標準ライブラリのみ)。RGBA 以外の形式も受ける。

    python3 bin/png_read.py 絵.png     # 大きさ・形式・色数を出す

外から来る絵は形式がまちまち。8bit RGBA だけを想定していると、
色票つき (color type 3) や RGB (2) でそのまま落ちる。
"""

import os
import struct
import sys
import zlib

for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}
_RAW = [False]      # _decode が生の行を返すか (open_image のときだけ True)


def _unfilter(raw, width, height, bpp, stride):
    """行ごとの前処理を戻す。

    filter 0 と 2 は行まるごと処理できるので、1 画素ずつの繰り返しを避ける。
    大きな絵 (1900x800 など) を素直に 1 画素ずつ回すと分単位で待たされる。
    """
    rows, prev, pos = [], bytearray(stride), 0
    for _ in range(height):
        filt = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if filt == 0:
            pass
        elif filt == 2:
            line = bytearray((a + b) & 255 for a, b in zip(line, prev))
        elif filt == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif filt == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif filt == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif filt == 4:
            # 局所変数に束ねる。属性参照と添字計算が内側で効いてくる
            for i in range(bpp):
                line[i] = (line[i] + prev[i]) & 255
            for i in range(bpp, stride):
                a = line[i - bpp]
                b = prev[i]
                c = prev[i - bpp]
                p = a + b - c
                pa = p - a if p >= a else a - p
                pb = p - b if p >= b else b - p
                pc = p - c if p >= c else c - p
                if pa <= pb and pa <= pc:
                    near = a
                elif pb <= pc:
                    near = b
                else:
                    near = c
                line[i] = (line[i] + near) & 255
        prev = line
        rows.append(line)
    return rows


class Image:
    """展開した行をそのまま持ち、必要な画素だけ取り出す。

    1881x836 を全部タプルにすると 150 万個の生成になり、そこで数分待つ。
    拡大された絵は等倍へ落として使うので、**全画素をタプルにする必要が無い**。
    """

    def __init__(self, width, height, channels, lines, palette, alpha):
        self.width, self.height = width, height
        self.channels, self.lines = channels, lines
        self.palette, self.alpha = palette, alpha

    def at(self, x, y):
        line = self.lines[y]
        c = self.channels
        if c == 4:
            return tuple(line[x * 4:x * 4 + 4])
        if c == 3:
            return tuple(line[x * 3:x * 3 + 3]) + (255,)
        if self.palette is not None:
            index = line[x]
            a = (self.alpha[index]
                 if self.alpha and index < len(self.alpha) else 255)
            return self.palette[index] + (a,)
        if c == 2:
            return (line[x * 2],) * 3 + (line[x * 2 + 1],)
        return (line[x],) * 3 + (255,)


def open_image(path):
    """展開だけして Image を返す。全画素をタプルにしない。"""
    _RAW[0] = True
    try:
        width, height, channels, lines, palette, alpha = _decode(path)
    finally:
        _RAW[0] = False
    return Image(width, height, channels, lines, palette, alpha)


def _decode(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"PNG ではない: {path}")
    pos, idat, palette, alpha = 8, b"", None, None
    width = height = depth = kind = None
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            width, height, depth, kind, _, _, interlace = struct.unpack(
                ">IIBBBBB", body)
            if interlace:
                raise ValueError("インターレース PNG は未対応")
        elif tag == b"PLTE":
            palette = [tuple(body[i:i + 3]) for i in range(0, len(body), 3)]
        elif tag == b"tRNS":
            alpha = body
        elif tag == b"IDAT":
            idat += body
        pos += 12 + length
    if depth != 8:
        raise ValueError(f"8bit 以外は未対応 (depth={depth})")
    channels = CHANNELS[kind]
    stride = width * channels
    lines = _unfilter(zlib.decompress(idat), width, height, channels, stride)
    if _RAW[0]:
        return width, height, channels, lines, palette, alpha
    rows = []
    for line in lines:
        if kind == 6:
            view = memoryview(line)
            out = [tuple(view[x * 4:x * 4 + 4]) for x in range(width)]
        elif kind == 2:
            out = [tuple(line[x * 3:x * 3 + 3]) + (255,) for x in range(width)]
        elif kind == 3:
            out = []
            for index in line[:width]:
                color = palette[index] if palette else (0, 0, 0)
                a = alpha[index] if alpha and index < len(alpha) else 255
                out.append(color + (a,))
        elif kind == 0:
            out = [(v, v, v, 255) for v in line[:width]]
        else:
            out = [(line[x * 2], line[x * 2], line[x * 2], line[x * 2 + 1])
                   for x in range(width)]
        rows.append(out)
    return width, height, rows


def read(path):
    """(幅, 高さ, 行ごとの (r,g,b,a) の並び) を返す。小さい絵向け。"""
    return _decode(path)


def main(argv):
    for path in argv:
        width, height, rows = read(path)
        solid = [(x, y) for y in range(height) for x in range(width)
                 if rows[y][x][3] > 8]
        colors = {rows[y][x][:3] for x, y in solid}
        xs = [x for x, _ in solid]
        ys = [y for _, y in solid]
        print(f"{os.path.basename(path)}: {width}x{height}  "
              f"中身 {max(xs) - min(xs) + 1}x{max(ys) - min(ys) + 1}  "
              f"{len(colors)} 色")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
