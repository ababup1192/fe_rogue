#!/usr/bin/env python3
"""carve の突き合わせに使う見本を作る (go/compare.d/carve.sh から呼ばれる)。

    python3 go/compare.d/carve-fixture.py <書き出し先>

carve / adopt の入力になる 3 面図 (3 体を横に並べた PNG) と、gifs / sheet が
読む工程のコマ、render が読む sprite.json を作る。**リポの中には置かない** —
書き出し先は compare.sh が作った使い捨ての場所。
"""
import os
import struct
import sys
import zlib

SKIN = (226, 178, 140, 255)
SKIN2 = (198, 150, 112, 255)
SHIRT = (72, 104, 168, 255)
SHIRT2 = (52, 78, 132, 255)
PANTS = (60, 60, 72, 255)
BOOT = (40, 32, 28, 255)
HAIR = (92, 60, 40, 255)
TOOL = (198, 60, 48, 255)
EYE = (255, 255, 255, 255)

VIEWS = ("front", "east", "back", "west")
FRAMES = ("idle", "walk_0", "walk_1", "walk_2", "walk_3",
          "swing_0", "swing_1", "swing_2", "jump_0", "jump_1", "jump_2")


def png_of(w, h, px):
    raw = b"".join(b"\x00" + b"".join(struct.pack("4B", *px[y][x]) for x in range(w))
                   for y in range(h))

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(data)


def rect(px, x0, y0, x1, y1, color):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if 0 <= y < len(px) and 0 <= x < len(px[0]):
                px[y][x] = color


def disc(px, cx, cy, r, color):
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                if 0 <= y < len(px) and 0 <= x < len(px[0]):
                    px[y][x] = color


def figure(px, ox, oy, w, h, view, tool, extra):
    """1 体を描く。view は front / side / back。"""
    cx = ox + w // 2
    head_r = max(4, w // 5)
    head_cy = oy + head_r + 2
    disc(px, cx, head_cy, head_r, SKIN)
    rect(px, cx - head_r, head_cy - head_r, cx + head_r, head_cy - head_r + 2, HAIR)
    if view == "front":
        px[head_cy][cx - head_r // 2] = EYE
        px[head_cy][cx + head_r // 2] = EYE
    elif view == "side":
        px[head_cy][cx + head_r // 2] = EYE
    else:
        rect(px, cx - head_r, head_cy - head_r, cx + head_r, head_cy + 1, HAIR)
    body_top = head_cy + head_r
    hip = oy + int(h * 0.62)
    body_w = w // 3 if view != "side" else w // 3 - 2
    rect(px, cx - body_w, body_top, cx + body_w, hip, SHIRT if view != "back" else SHIRT2)
    if extra:
        rect(px, cx - body_w, body_top + 3, cx + body_w, body_top + 5, SHIRT2)
    arm_w = max(2, w // 10)
    if view == "side":
        rect(px, cx - arm_w, body_top + 2, cx + arm_w, hip - 4, SKIN2)
    else:
        rect(px, cx - body_w - arm_w - 1, body_top + 1, cx - body_w - 1, hip - 3, SKIN)
        rect(px, cx + body_w + 1, body_top + 1, cx + body_w + arm_w + 1, hip - 3, SKIN)
    leg_w = max(2, w // 8)
    foot = oy + h - 1
    if view == "side":
        rect(px, cx - leg_w, hip, cx + leg_w, foot - 3, PANTS)
        rect(px, cx - leg_w - 2, foot - 3, cx + leg_w + 8, foot, BOOT)
    else:
        rect(px, cx - body_w, hip, cx - body_w + 2 * leg_w, foot - 3, PANTS)
        rect(px, cx + body_w - 2 * leg_w, hip, cx + body_w, foot - 3, PANTS)
        rect(px, cx - body_w, foot - 3, cx - body_w + 2 * leg_w, foot, BOOT)
        rect(px, cx + body_w - 2 * leg_w, foot - 3, cx + body_w, foot, BOOT)
    if tool:
        if view == "side":
            rect(px, cx + arm_w + 1, hip - 12, cx + arm_w + 2, hip + 6, TOOL)
        elif view == "front":
            rect(px, cx + body_w + arm_w + 2, hip - 12, cx + body_w + arm_w + 3, hip + 6, TOOL)
        else:
            rect(px, cx - body_w - arm_w - 3, hip - 12, cx - body_w - arm_w - 2, hip + 6, TOOL)


def sheet_of(kind):
    """3 面図を 1 枚に。left-right 非対称 (持ち物) と背景の明暗を変えて 3 通り。"""
    if kind == "plain":
        gap, fw, fh, bg = 14, 72, 100, (255, 255, 255, 255)
        tool, extra = False, False
    elif kind == "green":
        gap, fw, fh, bg = 16, 78, 116, (58, 122, 62, 255)
        tool, extra = True, True
    else:
        gap, fw, fh, bg = 23, 96, 160, (250, 250, 252, 255)
        tool, extra = True, True
    w, h = 4 * gap + 3 * fw, fh + 12
    px = [[bg for _ in range(w)] for _ in range(h)]
    for i, view in enumerate(("front", "side", "back")):
        figure(px, gap + i * (fw + gap), h - fh - 4, fw, fh, view, tool, extra)
    return png_of(w, h, px)


def tile_of(seed, w, h):
    """工程のコマ 1 枚。大きさをまちまちにして、並べる側の中央寄せを試す。"""
    px = [[(0, 0, 0, 0) for _ in range(w)] for _ in range(h)]
    rect(px, 2, h // 3, w - 3, h - 2, (60 + seed * 7 % 180, 90, 140, 255))
    disc(px, w // 2, h // 4, max(2, h // 6), (220, 190 - seed * 3 % 60, 120, 255))
    px[h - 1][0] = (255, 255, 255, 255)
    return png_of(w, h, px)


ODD_DOC = """{
  "version": 1,
  "palette": {"skin": {"hex": "#E2B28C"}, "ink": "#101018",
              "bad": {"value": "nope"}, "up": "AABBCC"},
  "legend": {"a": "@skin", "b": "ink", "c": "#ff0000", "d": "missing",
             "e": {"color": "#0f0f0f"}, "\\u3042": "up"},
  "sprites": {
    "//note": {"frames": {"x": ["aa"]}},
    "hero": {"anchor": {"x": 1, "y": 2},
      "frames": {"idle": ["ab.c", "de", "\\u3042\\u3042\\u3042\\u3042", ""],
                 "long": ["abcde"]}},
    "big": {"frames": {"k": ["abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"]}}
  }
}
"""


def main(argv):
    root = argv[0]
    for kind in ("plain", "green", "tall"):
        write(os.path.join(root, "views", kind + ".png"), sheet_of(kind))
    write(os.path.join(root, "prof.json"),
          b'{"reach": 4, "tool": "none", "headRatio": 0.28, '
          b'"crumbLimit": 6, "toneStep": 16}\n')
    write(os.path.join(root, "odd.sprite.json"), ODD_DOC.encode("utf-8"))
    sizes = ((32, 48), (24, 32), (40, 40))
    seed = 0
    for body in ("勇者", "slime"):
        for stage in ("1_線画", "2_陰影"):
            for view in VIEWS:
                for frame in FRAMES:
                    seed += 1
                    w, h = sizes[seed % len(sizes)]
                    write(os.path.join(root, "stage", "gallery", body, stage,
                                       "%s_%s.png" % (view, frame)),
                          tile_of(seed, w, h))
    write(os.path.join(root, "stage", "gallery", "欠け", "1_線画", "front_idle.png"),
          tile_of(1, 32, 48))
    write(os.path.join(root, "stage", "gallery", "ただのファイル"), b"")
    print(root)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
