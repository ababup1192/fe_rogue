#!/usr/bin/env python3
"""工程の絵を 4 方向 × 3 コマの一覧に並べる (標準ライブラリのみ)。

    python3 bin/sheet.py 2_陰影

1 枚ずつ見ても方向のそろいは分からない。並べて初めて、背の高さ・接地・
色が方向で割れていないかが読める。
"""
import importlib.util, os, struct, sys, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
_s = importlib.util.spec_from_file_location("render", os.path.join(HERE, "render.py"))
render = importlib.util.module_from_spec(_s); _s.loader.exec_module(render)

VIEWS = ("front", "east", "back", "west")
FRAMES = ("idle", "walk_0", "walk_1", "walk_2", "walk_3",
          "swing_0", "swing_1", "swing_2",
          "jump_0", "jump_1", "jump_2")
BACK = (30, 30, 34, 255)


def read_png(path):
    data = open(path, "rb").read()
    pos, w, h, idat = 8, None, None, b""
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        if kind == b"IHDR":
            w, h = struct.unpack(">II", data[pos + 8:pos + 16])
        elif kind == b"IDAT":
            idat += data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
    raw = zlib.decompress(idat)
    stride, rows, prev, i = w * 4, [], bytearray(w * 4), 0
    for _ in range(h):
        filt = raw[i]; i += 1
        line = bytearray(raw[i:i + stride]); i += stride
        for x in range(stride):
            a = line[x - 4] if x >= 4 else 0
            b = prev[x]
            c = prev[x - 4] if x >= 4 else 0
            if filt == 1: line[x] = (line[x] + a) & 255
            elif filt == 2: line[x] = (line[x] + b) & 255
            elif filt == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif filt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc
                                      else (b if pb <= pc else c))) & 255
        prev = line
        rows.append([tuple(line[x * 4:x * 4 + 4]) for x in range(w)])
    return w, h, rows


def main(argv):
    stage = argv[0] if argv else "2_陰影"
    root = os.path.dirname(HERE)
    out = []
    for body in sorted(os.listdir(os.path.join(root, "gallery"))):
        home = os.path.join(root, "gallery", body, stage)
        if not os.path.isdir(home):
            continue
        tiles = [read_png(os.path.join(home, f"{v}_{f}.png"))
                 for v in VIEWS for f in FRAMES]
        tw = max(t[0] for t in tiles); th = max(t[1] for t in tiles)
        cols = len(FRAMES) * len(VIEWS)
        canvas = [[BACK] * (tw * cols) for _ in range(th)]
        for i, (w, h, px) in enumerate(tiles):
            ox = i * tw + (tw - w) // 2
            oy = th - h
            for y in range(h):
                for x in range(w):
                    if px[y][x][3]:
                        canvas[oy + y][ox + x] = px[y][x]
        path = os.path.join(root, "gallery", f"_一覧_{body}_{stage}.png")
        with open(path, "wb") as handle:
            handle.write(render.png_of(tw * cols, th, canvas))
        out.append(os.path.relpath(path, root))
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
