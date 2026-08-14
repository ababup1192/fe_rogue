#!/usr/bin/env python3
"""焼いた PNG を測って「画風の軸がズレていないか」を言う。

描き手 (hand) は 3 本ある:

  coarse  ファミコンのような絵 (画素で描く・色数を絞る)
  fine    スーファミのような絵 (画素で描く・色数は多め)
  smooth  ピクセル感を感じさせない絵 (画素の目を見せない)

人が目で見て出した失敗 —「fine がドット絵に見えない」「楕円が目立つ」
「fine と smooth の差がほぼ無い」— は、どれも画像から数値で測れる。
1 枚 20〜30 分かけて焼いた絵を人が開くより前に、機械がここで声を出す。

  python3 bin/lint-style.py --hand fine --unit 1 debug/style/fine-*.png
  python3 bin/lint-style.py --hand coarse debug/style/coarse-*.png
  python3 bin/lint-style.py --compare debug/style/fine-a.png debug/style/smooth-a.png
  python3 bin/lint-style.py --strict ...      # 「注意」も NG に数える

--hand を省くとファイル名から当てる (coarse/famicom, fine/sfc, smooth/nopixel)。
--unit を省くと 1..8 から自動で見つける。

測る物 (定義は下の各関数の doc に書く):

  中間色の割合   隣の色との段が小さい (<=12) 画素が全体の何 % か。
                 ドット絵なら数 %、なめらかな絵なら数十 %。fine と smooth を分ける主指標。
  格子適合率     輪郭の段 (縦横の色の切り替わり) が unit の倍数に乗っている割合を
                 偶然当たる分で割り戻した値。ベクター調の曲線だと崩れる。
  楕円で説明できる面
                 大きい面のうち、best-fit 楕円との重なり (IoU) が 0.85 以上の物の面積割合。
                 「塊が楕円の重ね合わせでできている」の正体。
  色数           全体の色数と、画面の 90% を覆うのに要る色数 (べた面がいくつあるか)。
  隣の色の段の分布
                 隣り合って違う色の組を段の大きさで 4 つに分ける。
                 33+ に寄れば「段になっている」= パレットで塗った絵。
                 1-4 に寄れば「連続している」= なめらかな絵。

標準ライブラリだけで動く (Windows / macOS / Linux 共通)。
PNG のデコーダは bin/img-digest.py と同じ作り (zlib+struct、8bit 非インターレースのみ)。
"""

import math
import os
import struct
import sys
import zlib
from collections import deque

for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}

# 段の大きさの区切り (max チャンネル差)。この値より下は「中間色」と数える。
SOFT_STEP = 12
STEP_EDGES = (4, 12, 32)
STEP_LABELS = ("1-4", "5-12", "13-32", "33+")

# 格子の自動判定で試す unit の上限。
MAX_UNIT = 8
# 正規化した格子適合率がこれ未満なら「格子に乗っていない」= unit 1 と見なす。
GRID_FOUND = 0.35

# 楕円で説明できる面: best-fit 楕円との IoU がこれ以上なら「楕円」。
ELLIPSE_IOU = 0.85
# 面として数える最小面積 (画面比) と、数える面の上限。
REGION_MIN = 0.0015
REGION_CAP = 60
# 面を切り出すときの色の粗さ (なめらかな絵でも面が取れるように丸める)。
REGION_QUANT = 32

BLOCK_NAMES = [
    ["左上", "上", "右上"],
    ["左", "中央", "右"],
    ["左下", "下", "右下"],
]

# --- しきい値 ------------------------------------------------------------
# debug/bakeoff/ の 9 枚で較正した (人が「合格」と言った B-1-famicom が通り、
# 「ドット絵に見えない」と言った B-2-sfc が落ちる所に線を引いた)。
#   中間色:  B-1 4.9% / C-1 5.0% / A-1 21.3% || B-2 72.0% / C-2 56.6% / A-2 50.3%
#   格子:    B-1 u2 で 0.98 / C-1 0.62 / A-1 0.32 || sfc・nopixel は全部 0.0〜0.02
#   90% 色:  B-1 15 / C-1 10 / A-1 46 || B-2 5197 / B-3 8005
HANDS = {
    # 名前: (中間色の注意/NG, 格子の注意/NG, 90% 色数の注意/NG, 全色数の注意/NG)
    "coarse": {
        "aa_warn": 12.0, "aa_bad": 25.0,
        "grid_warn": 0.80, "grid_bad": 0.50,
        "cover_warn": 32, "cover_bad": 128,
        "colors_warn": 96, "colors_bad": 512,
    },
    "fine": {
        "aa_warn": 15.0, "aa_bad": 25.0,
        "grid_warn": 0.80, "grid_bad": 0.50,
        "cover_warn": 96, "cover_bad": 512,
        "colors_warn": 320, "colors_bad": 2048,
    },
}
# smooth は逆向き (乗りすぎ・少なすぎを注意する)。NG は出さない — なめらかな絵の
# 「やりすぎ」は壊れではないので、判断は人に残す。
SMOOTH = {
    "aa_min": 30.0,        # これ未満なら「なめらかさが足りない」
    "grid_max": 0.50,      # これ以上なら「格子に乗りすぎ (ドット絵に寄っている)」
    "colors_min": 512,     # これ未満なら「色数が少なすぎる」
}
# 楕円で説明できる面がこの割合を超えたら注意 (どの hand でも)。
ELLIPSE_WARN = 5.0

# --compare で「差がほぼ無い」と言う線。
SAME_AA = 10.0          # 中間色の差 (ポイント)
SAME_COLOR_RATIO = 1.6  # 色数の比

HAND_HINTS = {
    "coarse": (".claude/skills/retro-pixel（色の予算・タイルと材質）"),
    "fine": (".claude/skills/retro-pixel（色の予算・ディザ）"),
    "smooth": (".claude/skills/smooth-render（グラデ・ぼかし・banding）"),
}


# --- PNG デコーダ (bin/img-digest.py と同じ作り) -------------------------

def unfilter(raw, height, bpp, stride):
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


def read_png(path):
    """(幅, 高さ, 行ごとの RGBA バイト列) を返す。未対応形式は ValueError。"""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("PNG ではない")
    pos, idat, palette, alpha = 8, b"", None, None
    width = height = depth = kind = None
    while pos + 8 <= len(data):
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
                a = alpha[index] if alpha and index < len(alpha) else 255
                out[x * 4:x * 4 + 4] = (r, g, b, a)
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


def to_pixels(width, rows):
    """行ごとの RGBA バイト列を、RGB の組の 2 次元配列へ。"""
    return [[tuple(r[x * 4:x * 4 + 3]) for x in range(width)] for r in rows]


# --- 指標 -----------------------------------------------------------------

def scan(P, w, h):
    """1 パスで数える: 色ごとの画素数 / 中間色の画素数 / 段の分布 / 明度の 3 段。

    中間色 = 4 近傍のどれかとの段 (max チャンネル差) が 1..SOFT_STEP に収まる画素。
    ベタ面の内側 (段 0) でも、はっきりした輪郭 (段 33+) でもない画素のこと。
    """
    counts = {}
    soft_pixels = 0
    steps = [0, 0, 0, 0]
    luma3 = [0, 0, 0]
    luma_sum = 0
    for y in range(h):
        row = P[y]
        below = P[y + 1] if y + 1 < h else None
        for x in range(w):
            p = row[x]
            counts[p] = counts.get(p, 0) + 1
            v = (299 * p[0] + 587 * p[1] + 114 * p[2]) // 1000
            luma_sum += v
            luma3[0 if v < 85 else (1 if v < 171 else 2)] += 1

            soft = False
            # 右と下だけ数えれば、隣り合う組を 1 回ずつ数えられる。
            for q in ((row[x + 1] if x + 1 < w else None),
                      (below[x] if below is not None else None)):
                if q is None or q == p:
                    continue
                d = max(abs(p[0] - q[0]), abs(p[1] - q[1]), abs(p[2] - q[2]))
                if d <= STEP_EDGES[0]:
                    steps[0] += 1
                elif d <= STEP_EDGES[1]:
                    steps[1] += 1
                elif d <= STEP_EDGES[2]:
                    steps[2] += 1
                else:
                    steps[3] += 1
                if d <= SOFT_STEP:
                    soft = True
            # 中間色は左と上も見る (段の分布は数えない)。
            if not soft:
                for q in ((row[x - 1] if x > 0 else None),
                          (P[y - 1][x] if y > 0 else None)):
                    if q is None or q == p:
                        continue
                    d = max(abs(p[0] - q[0]), abs(p[1] - q[1]), abs(p[2] - q[2]))
                    if d <= SOFT_STEP:
                        soft = True
                        break
            if soft:
                soft_pixels += 1
    total = w * h
    return {
        "colors": counts,
        "aa": 100.0 * soft_pixels / total,
        "steps": steps,
        "luma3": [100.0 * n / total for n in luma3],
        "luma": luma_sum / total,
    }


def grid_fit(P, w, h, unit):
    """輪郭の段が unit の倍数に乗っている生の割合 (0..1)。"""
    if unit <= 1:
        return 1.0
    on = off = 0
    for y in range(h):
        row = P[y]
        for x in range(1, w):
            if row[x] != row[x - 1]:
                if x % unit:
                    off += 1
                else:
                    on += 1
    for y in range(1, h):
        row, prev = P[y], P[y - 1]
        hit = y % unit == 0
        for x in range(w):
            if row[x] != prev[x]:
                if hit:
                    on += 1
                else:
                    off += 1
    return on / (on + off) if on + off else 1.0


def grid_score(P, w, h, unit):
    """格子適合率を「偶然当たる分」で割り戻した値 (0..1)。

    切り替わりの位置がでたらめでも 1/unit は当たってしまうので、そこを 0 に置く。
    1.0 なら段が完全に unit の倍数に乗っている = 画素の目がある。
    """
    if unit <= 1:
        return None
    raw = grid_fit(P, w, h, unit)
    chance = 1.0 / unit
    return max(0.0, (raw - chance) / (1.0 - chance))


def find_unit(P, w, h):
    """1..MAX_UNIT で一番よく乗る unit を探す。乗っていなければ 1。"""
    best, best_score = 1, 0.0
    for u in range(2, MAX_UNIT + 1):
        s = grid_score(P, w, h, u)
        # 大きい unit は小さい unit の倍数を兼ねるので、同点なら小さい方を採る。
        if s is not None and s > best_score + 0.02:
            best, best_score = u, s
    return (best, best_score) if best_score >= GRID_FOUND else (1, best_score)


def quantize(P, step=REGION_QUANT):
    return [[((p[0] // step) * step + step // 2,
              (p[1] // step) * step + step // 2,
              (p[2] // step) * step + step // 2) for p in row] for row in P]


def find_regions(Q, w, h, min_area, cap=REGION_CAP):
    """同じ (丸めた) 色でつながった面を、大きい順に cap 個まで。"""
    seen = [bytearray(w) for _ in range(h)]
    out = []
    for y0 in range(h):
        for x0 in range(w):
            if seen[y0][x0]:
                continue
            col = Q[y0][x0]
            seen[y0][x0] = 1
            dq = deque([(x0, y0)])
            cells = []
            while dq:
                x, y = dq.popleft()
                cells.append((x, y))
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] \
                            and Q[ny][nx] == col:
                        seen[ny][nx] = 1
                        dq.append((nx, ny))
            if len(cells) >= min_area:
                out.append((len(cells), col, cells))
    out.sort(key=lambda t: -t[0])
    return out[:cap]


def ellipse_iou(cells):
    """面と、同じ重心・同じ広がりの楕円との重なり具合 (0..1)。

    2 次モーメントから楕円の向きと半径を出し、面の画素のうち何個が楕円の中に
    入るかを数える。1.0 に近いほど「これは楕円そのもの」。
    """
    n = len(cells)
    mx = sum(c[0] for c in cells) / n
    my = sum(c[1] for c in cells) / n
    sxx = sum((c[0] - mx) ** 2 for c in cells) / n
    syy = sum((c[1] - my) ** 2 for c in cells) / n
    sxy = sum((c[0] - mx) * (c[1] - my) for c in cells) / n
    tr = sxx + syy
    det = sxx * syy - sxy * sxy
    if det <= 1e-9:
        return 0.0
    disc = math.sqrt(max(tr * tr / 4 - det, 0.0))
    l1, l2 = tr / 2 + disc, tr / 2 - disc
    if l2 <= 1e-9:
        return 0.0
    a, b = 2 * math.sqrt(l1), 2 * math.sqrt(l2)
    th = 0.5 * math.atan2(2 * sxy, sxx - syy)
    ct, st = math.cos(th), math.sin(th)
    inside = 0
    for x, y in cells:
        dx, dy = x - mx, y - my
        u = (dx * ct + dy * st) / a
        v = (-dx * st + dy * ct) / b
        if u * u + v * v <= 1.0:
            inside += 1
    union = n + math.pi * a * b - inside
    return inside / union if union > 0 else 0.0


def where(cells, w, h):
    mx = sum(c[0] for c in cells) / len(cells)
    my = sum(c[1] for c in cells) / len(cells)
    return BLOCK_NAMES[min(int(my * 3 // h), 2)][min(int(mx * 3 // w), 2)]


def cover_count(counts, total, share=0.90):
    """画面の share を覆うのに要る色数。べた面がいくつあるかの目安。"""
    acc = n = 0
    for c in sorted(counts.values(), reverse=True):
        acc += c
        n += 1
        if acc >= share * total:
            break
    return n


def measure(path, unit=None, with_regions=True):
    """1 枚を測って辞書で返す。img-digest.py もこの関数を呼ぶ。"""
    w, h, rows = read_png(path)
    P = to_pixels(w, rows)
    s = scan(P, w, h)
    total = w * h
    if unit is None:
        unit, _ = find_unit(P, w, h)
        auto = True
    else:
        auto = False
    st = {
        "path": path,
        "width": w, "height": h,
        "unit": unit, "unit_auto": auto,
        "grid": grid_score(P, w, h, unit),
        "aa": s["aa"],
        "steps": [100.0 * n / (sum(s["steps"]) or 1) for n in s["steps"]],
        "colors": len(s["colors"]),
        "colors_per_kpx": 1000.0 * len(s["colors"]) / total,
        "cover90": cover_count(s["colors"], total),
        "luma": s["luma"],
        "luma3": s["luma3"],
        "ellipse": 0.0,
        "regions": [],
    }
    if with_regions:
        Q = quantize(P)
        regs = find_regions(Q, w, h, max(48, int(REGION_MIN * total)))
        ell = 0
        big = []
        for area, col, cells in regs:
            iou = ellipse_iou(cells)
            if iou >= ELLIPSE_IOU:
                ell += area
            big.append((100.0 * area / total, col, where(cells, w, h), iou))
        st["ellipse"] = 100.0 * ell / total
        st["regions"] = big
        st["region_area"] = sum(r[0] for r in big)
    return st


# --- 報告 -----------------------------------------------------------------

def guess_hand(path):
    name = os.path.basename(path).lower()
    for hand, words in (("coarse", ("coarse", "famicom", "nes")),
                        ("fine", ("fine", "sfc", "snes")),
                        ("smooth", ("smooth", "nopixel", "vector"))):
        if any(word in name for word in words):
            return hand
    return None


def hexcolor(rgb):
    return "#%02x%02x%02x" % tuple(rgb)


def describe(st, show_regions=False):
    lines = []
    unit = "unit={}{}".format(st["unit"], "(自動)" if st["unit_auto"] else "")
    grid = "—" if st["grid"] is None else "{:.0f}%".format(100 * st["grid"])
    lines.append("{}  {}x{}  {}".format(
        os.path.basename(st["path"]), st["width"], st["height"], unit))
    lines.append("  中間色 {:.1f}%   格子適合 {}   楕円で説明できる面 {:.1f}%".format(
        st["aa"], grid, st["ellipse"]))
    lines.append("  色数 {} (画面の 90% を覆う色 {})   平均輝度 {:.0f}".format(
        st["colors"], st["cover90"], st["luma"]))
    lines.append("  隣の色の段: " + "  ".join(
        "{}:{:.0f}%".format(lbl, v) for lbl, v in zip(STEP_LABELS, st["steps"])))
    lines.append("  明度 3 段: 暗 {:.0f}% / 中 {:.0f}% / 明 {:.0f}%".format(*st["luma3"]))
    if show_regions and st["regions"]:
        top = st["regions"][:5]
        lines.append("  大きい面: " + "  ".join(
            "{} {:.0f}%@{}".format(hexcolor(c), a, pos) for a, c, pos, _ in top))
    return lines


def judge(st, hand):
    """(NG の並び, 注意の並び) を返す。"""
    bad, warn = [], []
    name = os.path.basename(st["path"])
    grid = st["grid"]
    if hand in HANDS:
        t = HANDS[hand]
        if st["aa"] > t["aa_bad"]:
            bad.append("{}: 中間色が {:.1f}% — ドット絵になっていません "
                       "(輪郭がなめらかに溶けている。{} 系は {:.0f}% 以下)".format(
                           name, st["aa"], hand, t["aa_warn"]))
        elif st["aa"] > t["aa_warn"]:
            warn.append("{}: 中間色が {:.1f}% と多め (境目がぼけ始めている)".format(
                name, st["aa"]))
        if grid is None:
            warn.append("{}: 画素の目が見つかりません (unit=1) — "
                        "出力を等倍で焼いているか、段が格子に乗っていません".format(name))
        elif grid < t["grid_bad"]:
            bad.append("{}: 格子適合 {:.0f}% (unit={}) — 輪郭の段が画素の目に"
                       "乗っていません (ベクター調の曲線)".format(
                           name, 100 * grid, st["unit"]))
        elif grid < t["grid_warn"]:
            warn.append("{}: 格子適合 {:.0f}% (unit={}) と甘い".format(
                name, 100 * grid, st["unit"]))
        if st["cover90"] > t["cover_bad"]:
            bad.append("{}: 画面の 90% を覆うのに {} 色 — パレットで塗っていません "
                       "({} 系は {} 色まで)".format(
                           name, st["cover90"], hand, t["cover_warn"]))
        elif st["cover90"] > t["cover_warn"]:
            warn.append("{}: 画面の 90% を覆うのに {} 色 (色を絞れていない)".format(
                name, st["cover90"]))
        if st["colors"] > t["colors_bad"]:
            bad.append("{}: 全体の色数 {} — {} 系の色の予算 ({} 色) から桁で"
                       "外れています".format(name, st["colors"], hand, t["colors_warn"]))
        elif st["colors"] > t["colors_warn"]:
            warn.append("{}: 全体の色数 {} — {} 系の目安は {} 色".format(
                name, st["colors"], hand, t["colors_warn"]))
        # 楕円の判定は画素で描く 2 本だけ。なめらかな絵では面を色で丸めて切り出す
        # ので、取れる面がそもそも本物の塊ではない (数字は出すが判定しない)。
        if st["ellipse"] >= ELLIPSE_WARN:
            warn.append("{}: 画面の {:.1f}% が楕円そのものの面 — 塊を楕円の"
                        "重ね合わせで作っています (目立ちます)".format(
                            name, st["ellipse"]))
    elif hand == "smooth":
        if st["aa"] < SMOOTH["aa_min"]:
            warn.append("{}: 中間色が {:.1f}% しかない — なめらかさが出ていません "
                        "(段で塗っている)".format(name, st["aa"]))
        if grid is not None and grid >= SMOOTH["grid_max"]:
            warn.append("{}: 格子適合 {:.0f}% (unit={}) — 画素の目が見えています "
                        "(ドット絵側へ寄っている)".format(name, 100 * grid, st["unit"]))
        if st["colors"] < SMOOTH["colors_min"]:
            warn.append("{}: 色数 {} と少なすぎ — 面が段になって見えます (banding)".format(
                name, st["colors"]))
    return bad, warn


def compare(a, b, hand_a, hand_b):
    """2 枚の差を出す。「fine と smooth の差がほぼ無い」を機械に言わせる所。"""
    lines = ["{} <-> {} の差".format(
        os.path.basename(a["path"]), os.path.basename(b["path"]))]
    d_aa = b["aa"] - a["aa"]
    # 色数は絵の大きさに比例して増えるので、1000 画素あたりに直してから比べる
    # (fine 768x480 と smooth 1024x640 のように寸法が違う 2 枚を並べるため)。
    ratio = (b["colors_per_kpx"] + 0.01) / (a["colors_per_kpx"] + 0.01)
    lines.append("  中間色 {:.1f}% -> {:.1f}% (差 {:+.1f} ポイント)".format(
        a["aa"], b["aa"], d_aa))
    lines.append("  色数 {} -> {}   1000 画素あたり {:.1f} -> {:.1f} ({:.2f} 倍)"
                 "   90% を覆う色 {} -> {}".format(
                     a["colors"], b["colors"],
                     a["colors_per_kpx"], b["colors_per_kpx"], ratio,
                     a["cover90"], b["cover90"]))
    ga = "—" if a["grid"] is None else "{:.0f}%".format(100 * a["grid"])
    gb = "—" if b["grid"] is None else "{:.0f}%".format(100 * b["grid"])
    lines.append("  格子適合 {} (unit={}) -> {} (unit={})".format(
        ga, a["unit"], gb, b["unit"]))
    lines.append("  楕円で説明できる面 {:.1f}% -> {:.1f}%".format(
        a["ellipse"], b["ellipse"]))
    lines.append("  明度 3 段 暗/中/明 {:.0f}/{:.0f}/{:.0f} -> {:.0f}/{:.0f}/{:.0f}".format(
        *(a["luma3"] + b["luma3"])))

    bad = []
    same_aa = abs(d_aa) < SAME_AA
    same_color = (1.0 / SAME_COLOR_RATIO) < ratio < SAME_COLOR_RATIO
    if hand_a and hand_b and hand_a != hand_b and same_aa and same_color:
        bad.append("{} と {} の差がほぼありません "
                   "(中間色の差 {:+.1f} ポイント・色数 {:.2f} 倍) — "
                   "描き手を分けた意味が絵に出ていません".format(
                       hand_a, hand_b, d_aa, ratio))
    return lines, bad


def main(argv):
    strict = "--strict" in argv
    do_compare = "--compare" in argv
    show_regions = "--regions" in argv
    hand = None
    unit = None
    files = []
    i = 0
    args = [a for a in argv if a not in ("--strict", "--compare", "--regions")]
    while i < len(args):
        a = args[i]
        if a == "--hand" and i + 1 < len(args):
            hand = args[i + 1]
            i += 2
            continue
        if a == "--unit" and i + 1 < len(args):
            try:
                unit = int(args[i + 1])
            except ValueError:
                print("--unit には数を渡してください: {}".format(args[i + 1]))
                return 1
            i += 2
            continue
        if a.startswith("--"):
            print("知らないオプション: {}".format(a))
            return 1
        files.append(a)
        i += 1

    if not files:
        print(__doc__.strip().splitlines()[0])
        print("使い方: python3 bin/lint-style.py --hand fine --unit 2 debug/style/*.png")
        print("        python3 bin/lint-style.py --compare a.png b.png")
        return 1
    if hand is not None and hand not in ("coarse", "fine", "smooth"):
        print("--hand は coarse / fine / smooth のどれか: {}".format(hand))
        return 1
    if do_compare and len(files) != 2:
        print("--compare は PNG を 2 枚だけ渡してください")
        return 1

    stats, hands = [], []
    for path in files:
        if not os.path.isfile(path):
            print("見つからない: {}".format(path))
            return 1
        try:
            st = measure(path, unit)
        except ValueError as e:
            print("測れない: {} ({})".format(path, e))
            return 1
        stats.append(st)
        hands.append(hand or guess_hand(path))

    bad_total, warn_total = [], []
    if do_compare:
        lines, bad = compare(stats[0], stats[1], hands[0], hands[1])
        for st in stats:
            for line in describe(st, show_regions):
                print(line)
        for line in lines:
            print(line)
        bad_total.extend(bad)
    else:
        for st, hd in zip(stats, hands):
            for line in describe(st, show_regions):
                print(line)
            if hd is None:
                warn_total.append("{}: 描き手が分かりません — --hand を渡すと判定します"
                                  .format(os.path.basename(st["path"])))
                continue
            b, w = judge(st, hd)
            bad_total.extend(b)
            warn_total.extend(w)

    for w in warn_total:
        print("注意: {}".format(w))
    if not bad_total:
        print("OK: 画風の軸ズレはありません（注意 {} 件）".format(len(warn_total)))
        return 1 if (strict and warn_total) else 0

    print("", file=sys.stderr)
    for b in bad_total:
        print("NG: {}".format(b), file=sys.stderr)
    tips = sorted({HAND_HINTS[h] for h in hands if h in HAND_HINTS})
    if tips:
        print("", file=sys.stderr)
        print("手つきの在り処: " + " / ".join(tips), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
