#!/usr/bin/env python3
"""外から来た絵を取り込んで、4 方向 × 歩き 3 コマに仕立てる (標準ライブラリのみ)。

    python3 bin/adopt.py 三面図.png --id mechanic

**絵は描かない。** やるのは次だけ:

1. 拡大されている絵から**元の格子**を割り出し、等倍へ戻す
2. 立ち絵を向きごとに切り分ける (透明な縦の帯で区切る)
3. 足元と対称軸で位置を合わせ、決めた枠へ収める
4. 横向きを反転して左右をそろえる
5. **脚の区画を見つけて左右にずらし、体を 1px 浮かせて**歩き 3 コマを作る
6. 色数・浮き画素・接地・左右のそろいを検査して数値で出す
7. sprite.json と実寸の確認画像、ツクール規格のシートを書き出す

元の絵の画素は**1 つも描き換えない**。ずらすだけ。
"""

import argparse
import importlib.util
import json
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


png_read = _load("png_read", os.path.join(HERE, "png_read.py"))
render = _load("render", os.path.join(HERE, "render.py"))
gifs = _load("gifs", os.path.join(HERE, "gifs.py"))

ALPHA = 8          # これ以下は透明とみなす


def looks_light(color):
    """市松の背景に使われがちな、明るくて彩度の無い色か。"""
    r, g, b, a = color
    if a <= ALPHA:
        return True
    return r > 224 and g > 224 and b > 224 and max(r, g, b) - min(r, g, b) < 12


def backdrop_mask(img, coarse=2):
    """背景を**縁からの塗りつぶし**で決める。

    色だけで決めてはいけない。市松の白 (254,254,254) と白目 (255,255,255) は
    区別できず、色で切ると**目の白が消える**。実際それで目が黒い塊になった。
    外から繋がっている背景色だけが背景。

    背景色は明るい市松とは限らない (緑ベタの下絵が来た)。縁でいちばん
    多い色も背景とみなす。図柄の中の同じ色は縁と繋がらないので消えない。
    """
    votes = Counter()
    for x in range(0, img.width, coarse):
        for y in (0, img.height - 1):
            votes[quantize(img.at(x, y)[:3])] += 1
    for y in range(0, img.height, coarse):
        for x in (0, img.width - 1):
            votes[quantize(img.at(x, y)[:3])] += 1
    edge_tone = votes.most_common(1)[0][0]
    # 明るい背景 (市松) では従来の判定だけを使う。縁の色 ±40 まで広げると、
    # 絵の縁の中間グレーまで背景に食われ、輪郭が 1px 変わってしまう
    if looks_light(edge_tone + (255,)):
        def is_backdrop(color):
            return looks_light(color)
    else:
        def is_backdrop(color):
            if looks_light(color):
                return True
            return all(abs(c - e) <= 40 for c, e in zip(color[:3], edge_tone))

    wide = (img.width + coarse - 1) // coarse
    tall = (img.height + coarse - 1) // coarse
    light = []
    for gy in range(tall):
        y = min(img.height - 1, gy * coarse)
        light.append([is_backdrop(img.at(min(img.width - 1, gx * coarse), y))
                      for gx in range(wide)])
    seen = [[False] * wide for _ in range(tall)]
    stack = []
    for gx in range(wide):
        for gy in (0, tall - 1):
            if light[gy][gx]:
                stack.append((gx, gy))
    for gy in range(tall):
        for gx in (0, wide - 1):
            if light[gy][gx]:
                stack.append((gx, gy))
    while stack:
        gx, gy = stack.pop()
        if seen[gy][gx]:
            continue
        seen[gy][gx] = True
        for nx, ny in ((gx - 1, gy), (gx + 1, gy), (gx, gy - 1), (gx, gy + 1)):
            if 0 <= nx < wide and 0 <= ny < tall and not seen[ny][nx] \
                    and light[ny][nx]:
                stack.append((nx, ny))
    return seen, coarse


def quantize(color, step=24):
    """補間で散った色を丸める。**丸めてから多数決を取る**のが肝。

    拡大の補間が入った絵は、面の中でも 1 画素ごとに色が違う。丸めずに
    多数決を取ると、どの色も 1 票ずつになって背景に負ける。
    """
    if color is None:
        return None
    return tuple((v // step) * step + step // 2 for v in color)


def solid_at(img, x, y, mask=None):
    color = img.at(x, y)
    if color[3] <= ALPHA:
        return None
    if mask is not None:
        seen, coarse = mask
        if seen[min(len(seen) - 1, y // coarse)][
                min(len(seen[0]) - 1, x // coarse)]:
            return None
        return color[:3]
    return None if looks_light(color) else color[:3]


def spans_of(img, mask=None, step=4, least=40):
    """絵のある縦の帯を探す。ここで 3 面図を 1 体ずつに切り分ける。"""
    cols = [x for x in range(img.width)
            if any(solid_at(img, x, y, mask) for y in range(0, img.height, step))]
    if not cols:
        return []
    spans, start, prev = [], cols[0], cols[0]
    for x in cols[1:]:
        if x != prev + 1:
            spans.append((start, prev))
            start = x
        prev = x
    spans.append((start, prev))
    return [s for s in spans if s[1] - s[0] >= least]


def bounds_of(img, span, mask=None, step=3):
    x0, x1 = span
    ys = [y for y in range(img.height)
          if any(solid_at(img, x, y, mask) for x in range(x0, x1 + 1, step))]
    return x0, x1, min(ys), max(ys)


def _points(low, high, most):
    """low..high から最大 most 点を等間隔で選ぶ。"""
    span = high - low
    if span <= most:
        return range(low, high)
    return [low + span * i // most for i in range(most)]


def resample(img, box, size, mask=None, step=24):
    """外接枠を、決めた大きさの升へ面で落とす。各升は丸めた色の多数決。

    補間も平均も取らない。平均を取ると縁に中間色が出て、ドット絵でなくなる。
    """
    x0, x1, y0, y1 = box
    width, height = size
    out = {}
    for gy in range(height):
        for gx in range(width):
            sx0 = x0 + (x1 - x0 + 1) * gx // width
            sx1 = max(sx0 + 1, x0 + (x1 - x0 + 1) * (gx + 1) // width)
            sy0 = y0 + (y1 - y0 + 1) * gy // height
            sy1 = max(sy0 + 1, y0 + (y1 - y0 + 1) * (gy + 1) // height)
            # 升の中は最大 8x8 点だけ見る。全画素なめると 1 体で 30 万回になり、
            # 3 体で分単位の待ちになる。多数決の答えは 8x8 でほぼ変わらない
            xs = _points(sx0, sx1, 8)
            ys = _points(sy0, sy1, 8)
            seen = Counter()
            for y in ys:
                for x in xs:
                    seen[quantize(solid_at(img, x, y, mask), step)] += 1
            color, _ = seen.most_common(1)[0]
            if color is not None:
                out[(gx, gy)] = color
    # 黒い背景は、絵の黒い輪郭と色では区別できない (どちらもほぼ 0,0,0)。
    # 輪郭が背景として食われ、スカートの裾とソックスの間のような
    # 輪郭 1 本だけの行が抜けて、絵が千切れる。色で救えないぶんは形で救う:
    # **上下か左右を絵に挟まれた、暗い空の升**だけ輪郭として埋め戻す。
    # 明るい背景ではそもそも暗くないので発火しない
    patch = {}
    for gy in range(height):
        for gx in range(width):
            if (gx, gy) in out:
                continue
            pinched = (((gx, gy - 1) in out and (gx, gy + 1) in out)
                       or ((gx - 1, gy) in out and (gx + 1, gy) in out))
            if not pinched:
                continue
            sx0 = x0 + (x1 - x0 + 1) * gx // width
            sx1 = max(sx0 + 1, x0 + (x1 - x0 + 1) * (gx + 1) // width)
            sy0 = y0 + (y1 - y0 + 1) * gy // height
            sy1 = max(sy0 + 1, y0 + (y1 - y0 + 1) * (gy + 1) // height)
            dark = Counter()
            total = 0
            for y in _points(sy0, sy1, 8):
                for x in _points(sx0, sx1, 8):
                    c = img.at(x, y)
                    if c[3] > ALPHA:
                        total += 1
                        if max(c[:3]) < 64:
                            dark[quantize(c[:3], step)] += 1
            if total and sum(dark.values()) >= total * 0.6:
                patch[(gx, gy)] = dark.most_common(1)[0][0]
    out.update(patch)
    return out


def reduce_colors(pieces, limit):
    """色数を上限まで落とす。**多い色と、他から遠い色の両方**を残す。

    多い順だけで選ぶと、白目のように「画素は少ないが他のどの色とも遠い色」が
    真っ先に潰れて、目が黒い塊になる。頻度 × 既に残した色からの距離、で選ぶ。
    """
    counts = Counter()
    for cells in pieces.values():
        counts.update(cells.values())
    if len(counts) <= limit:
        return pieces
    keep = [counts.most_common(1)[0][0]]
    rest = [c for c in counts if c not in keep]
    while len(keep) < limit and rest:
        best, score = None, -1.0
        for color in rest:
            far = min(sum((a - b) ** 2 for a, b in zip(color, k)) for k in keep)
            value = counts[color] * (far ** 0.5)
            if value > score:
                score, best = value, color
        keep.append(best)
        rest.remove(best)
    table = {}
    for color in counts:
        table[color] = color if color in keep else min(
            keep, key=lambda k: sum((a - b) ** 2 for a, b in zip(color, k)))
    return {name: {pos: table[c] for pos, c in cells.items()}
            for name, cells in pieces.items()}


def cells_of(grid, span):
    left, right = span
    out = {}
    for y, line in enumerate(grid):
        for x in range(left, right + 1):
            if line[x][3] > ALPHA:
                out[(x - left, y)] = line[x][:3]
    return out


def place(cells, size):
    """足元を下辺に、左右は絵の中心に合わせて枠へ収める。"""
    width, height = size
    xs = [x for x, _ in cells]
    ys = [y for _, y in cells]
    dx = width // 2 - (min(xs) + max(xs) + 1) // 2
    # 下辺に 1px 空ける。沈むコマがそこへ落ちる
    dy = height - 2 - max(ys)
    out = {}
    for (x, y), color in cells.items():
        pos = (x + dx, y + dy)
        if 0 <= pos[0] < width and 0 <= pos[1] < height:
            out[pos] = color
    return out


def leg_band(cells, size):
    """脚の区画を探す。

    条件は 3 つ。**下の方にあり・中央で割れていて・その割れ目が続いている**。
    「左右に割れている行」だけで探すと、手に持った道具まで脚と見なして
    引きちぎることになる (レンチを持った絵で実際に起きた)。
    """
    width, height = size
    ys = [y for _, y in cells]
    top, bottom = min(ys), max(ys)
    floor = top + int((bottom - top) * 0.62)      # 下 4 割だけ見る
    center = width / 2
    rows = {}
    for (x, y), _ in cells.items():
        rows.setdefault(y, []).append(x)
    band = []
    for y in range(bottom, floor - 1, -1):
        xs = sorted(rows.get(y, []))
        near = [x for x in xs if abs(x - center) <= width * 0.28]
        holes = [i for i in range(len(near) - 1) if near[i + 1] - near[i] > 1]
        if not holes:
            if band:
                break
            continue
        band.append(y)
    return sorted(band)


# 動きの表。コマごとに「脚の位相」と「体の沈み」を持つ。
# 位相 0 が立ち。±1 で左右の脚が入れ替わる。
MOTIONS = {
    "walk": (("walk_l", -1, 1), ("idle", 0, 0), ("walk_r", 1, 1)),
}


def shear_legs(cells, band, size, phase, swing, dip):
    """脚を**付け根から足先へ向かって少しずつ**ずらす。

    脚全体を同じ量だけ動かすと、腰との継ぎ目で必ず千切れる。
    付け根 0・足先 swing の斜めのずらし (せん断) にすると、隣り合う行の差が
    1px 以内に収まり、繋がったまま歩幅が出る。

    体の沈みは**下方向**。上へ持ち上げると、頭のてっぺんが枠から出て 1px 欠ける。
    """
    if not band:
        return {(x, y + dip): c for (x, y), c in cells.items()
                if y + dip < size[1]}
    width = size[0]
    center = width / 2
    top, bottom = band[0], band[-1]
    span = max(1, bottom - top)
    out = {}
    for (x, y), color in cells.items():
        if phase and y >= top and abs(x - center) <= width * 0.30:
            deep = (y - top) / span                  # 付け根 0 → 足先 1
            side = 1 if x >= center else -1
            shift = round(swing * deep) * phase * side
            # 後ろへ引く側の足だけ 1px 上げる。両方上げると跳ねて見える
            lift = 1 if (side * phase < 0 and deep > 0.7) else 0
            pos = (x + shift, y + dip - lift)
        else:
            pos = (x, y + dip)
        if 0 <= pos[0] < size[0] and 0 <= pos[1] < size[1]:
            out[pos] = color
    return out


def motion_frames(cells, size, motion="walk", swing=2, dip=1):
    """動きの表からコマを作る。**元の絵の画素は描き換えない** — ずらすだけ。"""
    band = leg_band(cells, size)
    made = {}
    for name, phase, sink in MOTIONS[motion]:
        frame = shear_legs(cells, band, size, phase, swing, sink * dip)
        if len(components(frame)) > 1:
            # 千切れたら歩幅を 1 段狭めて作り直す。振りを捨てない
            frame = shear_legs(cells, band, size, phase, max(1, swing - 1),
                               sink * dip)
        made[name] = frame
    return made


def components(cells):
    """つながりの数。1 つでなければどこかが千切れている。"""
    unseen = set(cells)
    sizes = []
    while unseen:
        todo = [unseen.pop()]
        size = 0
        while todo:
            x, y = todo.pop()
            size += 1
            for q in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if q in unseen:
                    unseen.remove(q)
                    todo.append(q)
        sizes.append(size)
    return sorted(sizes, reverse=True)


def check(name, cells, size):
    """検査。数値で出す。"""
    xs = [x for x, _ in cells]
    ys = [y for _, y in cells]
    colors = Counter(cells.values())
    holes = 0
    for (x, y) in cells:
        near = sum(1 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                   if (x + dx, y + dy) in cells)
        if near <= 1:
            holes += 1
    return {
        "幅": max(xs) - min(xs) + 1, "高さ": max(ys) - min(ys) + 1,
        "接地": size[1] - 1 - max(ys), "色数": len(colors),
        "浮き画素": holes, "画素": len(cells),
    }


def save_png(path, cells, size, scale=1, background=None):
    width, height = size
    rows = []
    for y in range(height):
        line = []
        for x in range(width):
            color = cells.get((x, y))
            value = (color + (255,)) if color else (background or (0, 0, 0, 0))
            line.extend([value] * scale)
        rows.extend([line] * scale)
    with open(path, "wb") as handle:
        handle.write(render.png_of(width * scale, height * scale, rows))


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("image")
    parser.add_argument("--id", default="adopted")
    parser.add_argument("--size", default="",
                        help="出す枠 (例 32x48)。省略すると 32x48")
    parser.add_argument("--order", default="front,right,back",
                        help="左から並んでいる向き")
    parser.add_argument("--swing", type=int, default=2,
                        help="足先の振り幅 (px)。付け根は 0 で、そこへ向かって減る")
    parser.add_argument("--colors", type=int, default=24, help="色数の上限")
    args = parser.parse_args(argv)

    root = os.path.dirname(HERE)
    img = png_read.open_image(args.image)
    mask = backdrop_mask(img)
    spans = spans_of(img, mask)
    order = args.order.split(",")
    print(f"切り分け {len(spans)} 体: " +
          " ".join(f"{a}..{b}" for a, b in spans))
    if len(spans) != len(order):
        print(f"警告: 向きの指定は {len(order)} 個だが、絵は {len(spans)} 体ある")
    size = tuple(int(v) for v in args.size.lower().split("x")) if args.size \
        else (32, 48)
    pieces = {}
    for name, span in zip(order, spans):
        box = bounds_of(img, span, mask)
        print(f"  {name:6} 元の外接枠 {box[1]-box[0]+1} x {box[3]-box[2]+1} px")
        pieces[name] = resample(img, box, size, mask)
    if "right" in pieces and "left" not in pieces:
        source = pieces["right"]
        wide = max(x for x, _ in source)
        pieces["left"] = {(wide - x, y): c for (x, y), c in source.items()}
        print("左向きは右向きを反転して作った")
    pieces = reduce_colors(pieces, args.colors)

    print(f"枠 {size[0]} x {size[1]}  色 {args.colors} まで")

    out_dir = os.path.join(root, "gallery", args.id)
    os.makedirs(out_dir, exist_ok=True)
    frames, palette_names = {}, {}
    for view, cells in pieces.items():
        stand = place(cells, size)
        made = motion_frames(stand, size, swing=args.swing)
        for pose, frame in made.items():
            frames[(view, pose)] = frame
            save_png(os.path.join(out_dir, f"{view}-{pose}.png"), frame, size)
        found = check(view, stand, size)
        print(f"  {view:6} " + "  ".join(f"{k} {v}" for k, v in found.items()))

    # 4 方向で色票を 1 枚にまとめる
    every = Counter()
    for cells in frames.values():
        every.update(cells.values())
    palette, legend = {}, {}
    chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    for index, (color, _) in enumerate(every.most_common()):
        if index >= len(chars):
            break
        key = f"c{index:02d}"
        palette[key] = "#%02x%02x%02x" % color
        legend[chars[index]] = key
        palette_names[color] = chars[index]
    print(f"色票 {len(palette)} 色 (4 方向ぶんを 1 枚に統合)")

    sprites = {}
    for view in pieces:
        made = {}
        for pose in ("walk_l", "idle", "walk_r"):
            cells = frames[(view, pose)]
            made[pose] = ["".join(palette_names.get(cells.get((x, y)), ".")
                                  for x in range(size[0]))
                          for y in range(size[1])]
        sprites[f"{args.id}_{view}"] = {
            "anchor": {"x": size[0] // 2, "y": size[1] - 1}, "frames": made}

    doc = {"version": 1, "entityId": args.id,
           "note": f"{os.path.basename(args.image)} を取り込み。"
                   "歩きは脚をずらして生成。元の画素は描き換えていない",
           "palette": palette, "legend": legend, "sprites": sprites}
    path = os.path.join(root, "assets", "chars", f"{args.id}.sprite.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(doc, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    # 実寸 1/2/3 倍
    for pose in ("idle",):
        strip = []
        for k in (1, 2, 3):
            strip.append(k)
    view_order = [v for v in ("front", "right", "back", "left") if v in pieces]
    for k in (1, 2, 4):
        rows_out = []
        for y in range(size[1] * k):
            rows_out.append([(113, 137, 139, 255)] * (size[0] * len(view_order) * k))
        for index, view in enumerate(view_order):
            for (x, y), color in frames[(view, "idle")].items():
                for dy in range(k):
                    for dx in range(k):
                        rows_out[y * k + dy][(index * size[0] + x) * k + dx] = \
                            color + (255,)
        with open(os.path.join(out_dir, f"_4方向-{k}x.png"), "wb") as handle:
            handle.write(render.png_of(size[0] * len(view_order) * k,
                                       size[1] * k, rows_out))

    # 歩きの GIF (4 方向を横に)
    strips = []
    for index, pose in enumerate(("idle", "walk_l", "idle", "walk_r")):
        path_png = os.path.join(out_dir, f"_strip-{index}.png")
        rows_out = []
        for y in range(size[1]):
            line = []
            for view in view_order:
                cells = frames[(view, pose)]
                for x in range(size[0]):
                    color = cells.get((x, y))
                    line.append(color + (255,) if color else (0, 0, 0, 0))
            rows_out.append(line)
        with open(path_png, "wb") as handle:
            handle.write(render.png_of(size[0] * len(view_order), size[1],
                                       rows_out))
        strips.append(path_png)
    with open(os.path.join(out_dir, "walk.gif"), "wb") as handle:
        handle.write(gifs.from_pngs(strips, shrink=1))
    for path_png in strips:
        os.remove(path_png)

    print(os.path.relpath(os.path.join(root, "assets", "chars",
                                       f"{args.id}.sprite.json"), root))
    print(os.path.relpath(out_dir, root))
    return 0


if __name__ == "__main__":
    sys.exit(main())
