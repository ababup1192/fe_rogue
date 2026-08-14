#!/usr/bin/env python3
"""構図のシルエット PNG を測る。

絵の下限 (bin/lint-view.py) が「面に階調があるか・矩形だけでないか」を見るのに対し、
こちらは**物がどこに置かれているか**だけを見る。色と質感が乗った絵では構図の欠陥が
見えないので、塊だけを黒く小さく焼いたシルエットを材料にする
(このリポジトリでは make thumb → debug/thumb/hill*.png)。

好みには踏み込まない。出すのは事実だけ:

  NG (終了コード 1) — 数字ではっきり言える壊れ
    center    : 主役の重心が画面のど真ん中 (三分割の線から遠い)
    overlap   : 物どうしの重なりが 1 つも無い (前後関係が生まれない)
    horizon   : 地平線が画面の中央 ±5% にある (空と地面が同じ面積)
    empty     : 画面を縦 3 つに割った帯のどれかに、物が 1 つも置かれていない
                (地面と空だけの帯。9 枚焼いた見本で「下 4 割が無地の土」と言われた所)
    float     : 物の底が地面の天面より上にある (接地していない = 宙に浮いている)
  注意 (終了コード 0。--strict で NG に昇格)
    tangent   : 輪郭が触れるだけで重なっていない組 (くっついて見えて奥行きにならない)
    ladder    : 物の大きさが全部同じくらい (大小の階段が無い)
    sunk      : 物が地面へ深く埋まりすぎ (自分の高さの半分より深い)

材料の並べ方 (このファイル名の作法に合わせて焼く):

  <名前>.png            塊ぜんぶを重ねた 1 枚
  <名前>-<部位>.png     部位ごとに 1 枚ずつ (重なりはここからしか数えられない —
                        1 枚に混ぜると重なった塊が 1 つに融ける)

  部位名 figure は主役として扱う (重心の判定に使う)。
  部位名 ground は地面として扱う (地平線と接地の判定に使い、重なりの組からは外す —
  物が地面に接地しているのは重なりではない)。

  接地は ground がある物だけ測る。次の 2 つは地面に載る物ではないので自動で外す:
  地面のいちばん高い天面より完全に上にある物 (空の雲・太陽) と、画面の下の縁に
  かかっている物 (手前の層。底が画面の外にあるので接地を測れない)。

  python3 bin/lint-composition.py                 # debug/thumb/ を見る
  python3 bin/lint-composition.py path/to/dir     # 別のフォルダを見る
  python3 bin/lint-composition.py --strict        # 「注意」も NG に数える

標準ライブラリだけで動く (Windows / macOS / Linux 共通)。
PNG のデコーダは bin/img-digest.py と同じ作り (zlib+struct、8bit 非インターレースのみ)。
"""

import os
import struct
import sys
import zlib
from collections import deque

for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

DEFAULT_DIR = "debug/thumb"

# 主役として扱う部位名と、地面として扱う部位名。
HERO = "figure"
GROUND = "ground"

# 三分割の線 (縦・横とも)。
THIRDS = (1.0 / 3.0, 2.0 / 3.0)

# 主役の重心がここより中央に近いと NG (design の幅に対する割合)。
CENTER_BAND = 0.06
# 地平線が中央からここより近いと NG。
HORIZON_BAND = 0.05
# 縦 3 つの帯のどれかで、物 (地面を除く) の覆う割合がこれ未満なら NG。
BAND_MIN = 0.06
# 重なりと認めるのに要る画素数 (これ以下は「触れているだけ」= tangent)。
OVERLAP_MIN = 2
# 触れていると見なす距離 (画素)。
TOUCH_DILATE = 1
# いちばん大きい物といちばん小さい物の面積比がこれ未満なら「階段が無い」。
LADDER_MIN = 2.5
# 物の底と地面の天面のすき間がこれを超えたら「浮いている」(画素)。
# 1 画素は縁の丸めで出るので許す。
FLOAT_MAX = 1
# 足の片側の持ち上がりが物の高さのこの割合を超えたら「片側が浮いている」。
OVERHANG_MAX = 0.35
# 地面へのめり込みが物の高さのこの割合を超えたら「埋まりすぎ」。
SUNK_MAX = 0.5

CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


def unfilter(raw, height, bpp, stride):
    """行ごとの前処理 (filter) を戻す。"""
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
        elif filt == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif filt == 4:
            for i in range(bpp):
                line[i] = (line[i] + prev[i]) & 255
            for i in range(bpp, stride):
                a, b, c = line[i - bpp], prev[i], prev[i - bpp]
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                near = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + near) & 255
        prev = line
        rows.append(line)
    return rows


def read_png(path):
    """(幅, 高さ, 行ごとの RGBA バイト列) を返す。未対応形式は ValueError。"""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("PNG ではない")
    pos, idat, palette, alpha = 8, b"", None, None
    width = height = depth = kind = None
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            width, height, depth, kind, _, _, interlace = struct.unpack(">IIBBBBB", body)
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
        raise ValueError("8bit 以外は未対応 (depth={})".format(depth))
    channels = CHANNELS[kind]
    lines = unfilter(zlib.decompress(idat), height, channels, width * channels)

    rows = []
    for line in lines:
        if kind == 6:
            rows.append(bytes(line))
            continue
        out = bytearray(width * 4)
        if kind == 2:
            for x in range(width):
                out[x * 4:x * 4 + 3] = line[x * 3:x * 3 + 3]
                out[x * 4 + 3] = 255
        elif kind == 3:
            for x in range(width):
                index = line[x]
                r, g, b = palette[index] if palette else (0, 0, 0)
                out[x * 4:x * 4 + 4] = (r, g, b,
                                        alpha[index] if alpha and index < len(alpha) else 255)
        elif kind == 0:
            for x in range(width):
                v = line[x]
                out[x * 4:x * 4 + 4] = (v, v, v, 255)
        else:
            for x in range(width):
                v = line[x * 2]
                out[x * 4:x * 4 + 4] = (v, v, v, line[x * 2 + 1])
        rows.append(bytes(out))
    return width, height, rows


def ink_mask(path):
    """(幅, 高さ, 行ごとの bytearray) — 塗られている画素を 1 にした型。

    シルエットは黒 (対象) と白 (背景) の 2 色なので、明るさの真ん中で切る。
    透明な画素は塗られていないものとして扱う。
    """
    width, height, rows = read_png(path)
    mask = []
    for row in rows:
        line = bytearray(width)
        for x in range(width):
            a = row[x * 4 + 3]
            luma = (299 * row[x * 4] + 587 * row[x * 4 + 1] + 114 * row[x * 4 + 2]) // 1000
            line[x] = 1 if (a > 127 and luma < 128) else 0
        mask.append(line)
    return width, height, mask


def area_of(mask):
    return sum(sum(line) for line in mask)


def centroid_of(width, height, mask):
    """(重心 x, 重心 y) を 0〜1 の割合で返す。空なら None。"""
    total = sx = sy = 0
    for y, line in enumerate(mask):
        n = sum(line)
        if not n:
            continue
        total += n
        sy += n * y
        for x in range(width):
            if line[x]:
                sx += x
    if not total:
        return None
    return (sx / total / width, sy / total / height)


def overlap_area(a, b):
    return sum(1 for ya, yb in zip(a, b) for xa, xb in zip(ya, yb) if xa and xb)


def dilated(width, height, mask, radius):
    """mask を radius 画素ぶん太らせた型。触れているかの判定に使う。"""
    out = [bytearray(width) for _ in range(height)]
    for y, line in enumerate(mask):
        for x in range(width):
            if not line[x]:
                continue
            for dy in range(-radius, radius + 1):
                yy = y + dy
                if yy < 0 or yy >= height:
                    continue
                lo = max(0, x - radius)
                hi = min(width, x + radius + 1)
                for xx in range(lo, hi):
                    out[yy][xx] = 1
    return out


def largest_blank(width, height, mask):
    """同じ色の一続きの塊のうち、いちばん大きい物の画素数を返す (4 近傍)。"""
    seen = [bytearray(width) for _ in range(height)]
    best = 0
    for y0 in range(height):
        for x0 in range(width):
            if seen[y0][x0]:
                continue
            value = mask[y0][x0]
            size = 0
            queue = deque([(x0, y0)])
            seen[y0][x0] = 1
            while queue:
                x, y = queue.popleft()
                size += 1
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if 0 <= nx < width and 0 <= ny < height:
                        if not seen[ny][nx] and mask[ny][nx] == value:
                            seen[ny][nx] = 1
                            queue.append((nx, ny))
            best = max(best, size)
    return best


def horizon_of(width, height, mask):
    """地面の型から (空と地面のきわ, 天面の中央値) を 0〜1 の割合で返す。

    きわ = 列ごとの一番上のうち高いほうから 1 割目。段のある地面では天面が 2 つの
    高さを持つので、空が終わる線 (きわ) と地面のならし (中央値) の両方を出す。
    """
    tops = []
    for x in range(width):
        for y in range(height):
            if mask[y][x]:
                tops.append(y)
                break
    if not tops:
        return None
    tops.sort()
    edge = tops[len(tops) // 10] / height
    mid = tops[len(tops) // 2] / height
    return (edge, mid)


def column_edges(width, height, mask):
    """列ごとの (いちばん上の行, いちばん下の行)。塗られていない列は None。"""
    out = []
    for x in range(width):
        top = bottom = None
        for y in range(height):
            if mask[y][x]:
                if top is None:
                    top = y
                bottom = y
        out.append(None if top is None else (top, bottom))
    return out


def contact_of(width, height, mask, ground):
    """物と地面の接し方を測って (足の列数, すき間の最小, すき間の最大, 物の高さ)。

    すき間 = その列で物の底が地面の天面より上にある量 (画素)。正なら下に地面が無い。
    測るのは**足の列だけ** — 物のいちばん下から高さの 1/8 ぶんの帯に底がある列を
    足とみなす。木の葉のように横へ張り出した所まで数えると、張り出しの下は
    いつでも「地面から離れている」ことになり、接地を測れない。帯を広く取ると
    今度は丸い底の裾が「浮いている」ことになるので、帯は狭く取る。

    最小のすき間 = どこか 1 列でも地面に着いているか (正なら丸ごと浮いている)。
    最大のすき間 = 足の片側がどれだけ持ち上がっているか (段の切れ目をまたぐ物で出る)。
    地面の無い列 (空だけの列) は数えない。測れる列が無ければ None。
    """
    obj = column_edges(width, height, mask)
    gnd = column_edges(width, height, ground)
    seen = [(x, e) for x, e in enumerate(obj) if e is not None]
    if not seen:
        return None
    top = min(e[0] for _, e in seen)
    bottom = max(e[1] for _, e in seen)
    tall = bottom - top + 1
    band = max(1, tall // 8)

    gaps = [gnd[x][0] - e[1] for x, e in seen
            if e[1] >= bottom - band and gnd[x] is not None]
    if not gaps:
        return None
    return (len(gaps), min(gaps), max(gaps), tall)


def grounding_kind(width, height, mask, ground):
    """接地を測る対象かどうか。測らないものはその理由を返す。"""
    if any(mask[height - 1]):
        return "画面の下の縁にかかっている (底が画面の外)"
    tops = [e[0] for e in column_edges(width, height, ground) if e is not None]
    bottoms = [e[1] for e in column_edges(width, height, mask) if e is not None]
    if not tops or not bottoms:
        return "地面か物が空 (測れません)"
    if max(bottoms) < min(tops):
        return "地面のいちばん高い天面より上にある (空の物)"
    return None


def near_third(v):
    """三分割の線までの距離 (0〜1)。"""
    return min(abs(v - t) for t in THIRDS)


def collect(directory):
    """{基準名: {部位名: パス}} を集める。部位なし (合成の 1 枚) は "" をキーにする。"""
    groups = {}
    if not os.path.isdir(directory):
        return groups
    for name in sorted(os.listdir(directory)):
        if not name.lower().endswith(".png"):
            continue
        stem = name[:-4]
        base, _, part = stem.partition("-")
        groups.setdefault(base, {})[part] = os.path.join(directory, name)
    return groups


def report(base, files):
    """1 つの構図を測って (行の並び, NG の並び, 注意の並び) を返す。"""
    lines, bad, warn = [], [], []
    composite_path = files.get("")
    if composite_path is None:
        return (["{}: 合成の 1 枚 ({}.png) がありません".format(base, base)],
                ["合成の 1 枚が無い"], [])

    width, height, composite = ink_mask(composite_path)
    lines.append("{}: {}x{} 画素 / 部位 {} 枚".format(
        base, width, height, len(files) - 1))

    parts = {}
    for part, path in files.items():
        if not part:
            continue
        w, h, mask = ink_mask(path)
        if (w, h) != (width, height):
            warn.append("{}: 合成と寸法が違う ({}x{})".format(part, w, h))
            continue
        parts[part] = mask

    # 1. 主役の重心
    hero = parts.get(HERO)
    if hero is None:
        lines.append("  主役: {}-{}.png が無いので測れません".format(base, HERO))
    else:
        spot = centroid_of(width, height, hero)
        if spot is None:
            lines.append("  主役: 1 画素も塗られていません")
        else:
            cx, cy = spot
            lines.append("  主役の重心: x={:.3f} (三分割の線まで {:.3f}) "
                         "y={:.3f} (三分割の線まで {:.3f})".format(
                             cx, near_third(cx), cy, near_third(cy)))
            if abs(cx - 0.5) < CENTER_BAND:
                bad.append("center: 主役の重心が横のど真ん中 (x={:.3f}) — "
                           "三分割の線 (0.333 / 0.667) の近くへ寄せる".format(cx))

    # 2. 重なりと接線
    keys = sorted(k for k in parts if k != GROUND)
    pairs_over, pairs_touch = [], []
    for i, a in enumerate(keys):
        for b in keys[i + 1:]:
            n = overlap_area(parts[a], parts[b])
            if n >= OVERLAP_MIN:
                pairs_over.append((a, b, n))
            else:
                fat = dilated(width, height, parts[a], TOUCH_DILATE)
                if overlap_area(fat, parts[b]) > 0:
                    pairs_touch.append((a, b))
    if pairs_over:
        lines.append("  重なり {} 組: {}".format(
            len(pairs_over),
            "、".join("{}×{} ({}px)".format(a, b, n) for a, b, n in pairs_over)))
    else:
        lines.append("  重なり 0 組")
        bad.append("overlap: 物どうしの重なりが 1 つもありません — "
                   "横に並べただけでは前後関係が出ません")
    if pairs_touch:
        lines.append("  触れているだけ {} 組: {}".format(
            len(pairs_touch), "、".join("{}×{}".format(a, b) for a, b in pairs_touch)))
        warn.append("tangent: {} — 輪郭が触れるだけの組は、"
                    "重なりにも離れにも見えません".format(
                        "、".join("{}×{}".format(a, b) for a, b in pairs_touch)))

    # 3. 地平線
    ground = parts.get(GROUND)
    if ground is None:
        lines.append("  地平線: {}-{}.png が無いので測れません".format(base, GROUND))
    else:
        found = horizon_of(width, height, ground)
        if found is None:
            lines.append("  地平線: 地面が 1 画素も塗られていません")
        else:
            edge, mid = found
            lines.append("  地平線: 空と地面のきわ y={:.3f} (三分割の線まで {:.3f}) / "
                         "天面の中央値 y={:.3f}".format(edge, near_third(edge), mid))
            for label, y in (("空と地面のきわ", edge), ("天面の中央値", mid)):
                if abs(y - 0.5) <= HORIZON_BAND:
                    bad.append("horizon: {}が画面の中央 (y={:.3f}) — "
                               "空と地面が同じ面積になり、どちらが主か読めません".format(label, y))

    # 4. 接地 (物の底が地面の天面と合っているか)
    if ground is not None:
        for part in sorted(k for k in parts if k != GROUND):
            skipped = grounding_kind(width, height, parts[part], ground)
            if skipped is not None:
                lines.append("  接地 {}: 測りません — {}".format(part, skipped))
                continue
            found = contact_of(width, height, parts[part], ground)
            if found is None:
                lines.append("  接地 {}: 地面のある列に重なっていません".format(part))
                continue
            columns, low, high, tall = found
            lines.append("  接地 {}: 足 {} 列 / すき間 {}〜{}px (高さ {}px)".format(
                part, columns, low, high, tall))
            if low > FLOAT_MAX:
                bad.append("float: {} が地面から丸ごと {}px 浮いています — "
                           "足のどの列にも地面が当たっていません".format(part, low))
            elif high > tall * OVERHANG_MAX:
                bad.append("float: {} の足の片側が {}px 持ち上がっています "
                           "(自分の高さ {}px の {:.0f}%) — 底の中心 1 点でなく、"
                           "足の幅の中でいちばん低い天面に底を合わせる".format(
                               part, high, tall, high / float(tall) * 100.0))
            elif -low > tall * SUNK_MAX:
                warn.append("sunk: {} が地面へ {}px 埋まっています "
                            "(自分の高さ {}px の半分より深い)".format(part, -low, tall))

    # 5. 無地の面積
    blank = largest_blank(width, height, composite)
    lines.append("  いちばん大きい一続きの同じ色: {:.1f}% ({} 画素)".format(
        blank / float(width * height) * 100.0, blank))
    props = [m for k, m in parts.items() if k != GROUND]
    if props:
        bands = ("上", "中", "下")
        shares = []
        for b, label in enumerate(bands):
            y0 = height * b // 3
            y1 = height * (b + 1) // 3
            cells = (y1 - y0) * width
            hit = sum(1 for y in range(y0, y1) for x in range(width)
                      if any(m[y][x] for m in props))
            shares.append(hit / float(cells))
            if shares[b] < BAND_MIN:
                bad.append("empty: {}の帯に物がほとんど置かれていません "
                           "({:.1f}%) — 地面か空だけの無地です".format(label, shares[b] * 100.0))
        lines.append("  物の覆う割合 (縦 3 つの帯): {}".format(
            " / ".join("{} {:.1f}%".format(label, s * 100.0)
                       for label, s in zip(bands, shares))))

    # 6. 物の大きさの階段
    sizes = sorted(((area_of(m), k) for k, m in parts.items() if k != GROUND),
                   reverse=True)
    sizes = [(n, k) for n, k in sizes if n > 0]
    if len(sizes) >= 2:
        lines.append("  大きさ: {}".format(
            " > ".join("{} {}px".format(k, n) for n, k in sizes)))
        ratio = sizes[0][0] / float(sizes[-1][0])
        if ratio < LADDER_MIN:
            warn.append("ladder: いちばん大きい物といちばん小さい物の面積比が "
                        "{:.1f} 倍しかありません — 大小の階段がありません".format(ratio))

    return lines, bad, warn


def main(argv):
    strict = "--strict" in argv
    rest = [a for a in argv if not a.startswith("--")]
    directory = rest[0] if rest else DEFAULT_DIR

    groups = collect(directory)
    if not groups:
        print("シルエットが見つかりません: {} (先に make thumb)".format(directory))
        return 1

    bad_total, warn_total = [], []
    for base in sorted(groups):
        lines, bad, warn = report(base, groups[base])
        for line in lines:
            print(line)
        bad_total.extend(bad)
        warn_total.extend(warn)

    for w in warn_total:
        print("注意: {}".format(w))
    if not bad_total:
        print("OK: 構図の壊れはありません（注意 {} 件）".format(len(warn_total)))
        return 1 if (strict and warn_total) else 0

    print("", file=sys.stderr)
    for b in bad_total:
        print("NG: {}".format(b), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
