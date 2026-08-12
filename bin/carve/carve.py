#!/usr/bin/env python3
"""3 面図から立体を彫り出し、3D で動かして 4 方向へ描き直す (標準ライブラリのみ)。

    python3 bin/carve/carve.py 三面図.png --id 名前 --size 32x48\n\n実行したディレクトリの assets/chars/ と gallery/ に書き出す。

**絵は描かない。** やるのは「供給された 3 枚から立体を作り、その立体を動かす」だけ。

なぜ立体に戻すのか:

- 2D のまま脚をずらすと、正面では動いて見えても横向きでは動かない。
  向きごとに別々の細工が要り、必ずどこかで食い違う
- 立体で腕を前後に振れば、**横向きでは前後の動き・正面では手前の腕が体に重なる**、
  という辻褄の合った見え方が 4 方向ぶん同時に出る

作り方は**空間の彫り出し (visual hull)**。ある高さの断面は、正面図が決める
「横の広がり」と、横図が決める「奥行きの広がり」の掛け合わせ。3 枚の
シルエットが同時に満たす所だけを残す。

こうすると、動かさない限り**投影は元の絵とまったく同じ**になる。
元の絵を 1 画素も描き換えないまま、動きだけを立体で作れる。
"""

import argparse
import importlib.util
import json
import os
import sys
from collections import Counter, deque

# ---------------------------------------------------------------- 体型のつまみ
#
# **絵ごとの調整はここだけ。** 残りの仕組みは下絵を選ばない。
# 別のキャラで崩れたら、コードでなくこの値を疑う。--profile で JSON からも
# 差し替えられる (書いたキーだけ上書き)。

PROFILE = {
    "feetShare": 0.18,    # 立ち位置の中心に使う、足元の高さの割合
    "headRatio": 0.32,    # 上からこの割合までが頭 (曲げない)
    "hipRatio": 0.60,     # 上からこの割合より下が脚
    "coreTrimPct": 10,    # 胴の左右端を決める刈り込み (%)。この外側が腕
    "tubeMargin": 1,      # 腕・脚の筒の太さ = 正面の幅の半分 + これ
    "toneStep": 32,       # 持ち物の持ち主を色で照合するときの色の丸め幅
    "tool": "auto",       # "none" = 持ち物なし (スカートの裾などの誤検出を抑える)
    "reach": 3,           # 腕と脚の先端が前後へ動く量 (ボクセル)
    "liftAt": 0.7,        # 引く側の足を持ち上げ始める深さ (0=腰, 1=足先)
    "crumbLimit": 4,      # 動きが生む欠片を掃く上限 (px)
}

HERE = os.path.dirname(os.path.abspath(__file__))
for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


adopt = _load("adopt", os.path.join(HERE, "adopt.py"))
render = _load("render", os.path.join(HERE, "render.py"))
gifs = _load("gifs", os.path.join(HERE, "gifs.py"))


# ---------------------------------------------------------------- 位置合わせ


def stance_center(cells, size, share=None):
    """立ち位置の中心。**外接枠でなく足元**で決める。

    外接枠の中心で合わせると、手に持った道具がはみ出している側へ体が寄る。
    面ごとに道具の出方が違うので、面ごとに違う量ずれて、彫った立体が食い違う。
    足元は道具の影響を受けない。
    """
    share = PROFILE["feetShare"] if share is None else share
    ys = [y for _, y in cells]
    bottom = max(ys)
    floor = bottom - int((bottom - min(ys)) * share)
    feet = [x for x, y in cells if y >= floor]
    if not feet:
        feet = [x for x, _ in cells]
    feet.sort()
    return (feet[0] + feet[-1]) / 2


def align(views, size):
    """3 面を**まとめて**位置合わせする。

    面ごとに合わせると、接地の行が 1px ずれたまま彫ることになり、
    正面の腰と横の腰が別の高さで交わって、描き直したとき絵がずれる。
    合わせるのは 2 つ: 接地の行をそろえる / 立ち位置の中心を枠の中央へ。
    """
    width, height = size
    floor = max(max(y for _, y in cells) for cells in views.values())
    out = {}
    for name, cells in views.items():
        dy = (height - 2) - floor          # 下辺に 1px 空ける
        # 背面は後で鏡映(x → width-1-x)されるため、中央 width/2 に置くと
        # 鏡映後に 1px ずれる。鏡映して初めて他ビューと重なる位置に置く
        target = (width - 1) - width / 2 if name == "back" else width / 2
        dx = round(target - stance_center(cells, size))
        moved = {}
        for (x, y), color in cells.items():
            pos = (x + dx, y + dy)
            if 0 <= pos[0] < width and 0 <= pos[1] < height:
                moved[pos] = color
        out[name] = moved
    return out


# ---------------------------------------------------------------- 彫り出し


def carve(front, side, back, size):
    """3 枚のシルエットが同時に満たす所だけを残す。

    断面は「正面が決める横幅」×「横が決める奥行き」。粗いが、**投影は元の絵に
    一致する**ので、動かさない限り絵は変わらない。
    """
    width, height = size
    rows_front, rows_side, rows_back = {}, {}, {}
    for (x, y) in front:
        rows_front.setdefault(y, set()).add(x)
    for (z, y) in side:
        rows_side.setdefault(y, set()).add(z)
    for (x, y) in back:
        rows_back.setdefault(y, set()).add(width - 1 - x)   # 背面は左右が逆

    voxels = {}
    for y in range(height):
        xs = rows_front.get(y, set())
        zs = rows_side.get(y, set())
        if not xs or not zs:
            continue
        back_xs = rows_back.get(y)
        for x in xs:
            # 背面にも有る x だけ残す。片方にしか無い所は持ち物のはみ出し
            if back_xs and x not in back_xs and len(back_xs) > 2:
                pass                     # 消さない (道具は正面にしか無いことがある)
            for z in zs:
                voxels[(x, y, z)] = None
    return voxels


def _runs(values):
    """昇順の値の列を、連続する区間 [始, 終] の列にまとめる。"""
    out = []
    for v in values:
        if out and v == out[-1][1] + 1:
            out[-1][1] = v
        else:
            out.append([v, v])
    return out


def slim(parts, front, side, size):
    """腕と持ち物の奥行きを絞り、幽霊の体積を消す。

    彫り出しは「正面の横幅 × 横の奥行き」の掛け算なので、横図の持ち物や
    体の奥行きが**反対側の腕にも**掛かり、腕が体と同じ厚みの板になる。
    止まっていれば板は真後ろに隠れて見えないが、振った瞬間に分離して
    2 本目の腕に見える。

    - 腕は「正面の幅と同じくらいの太さの筒」に絞る (奥行きは体の中心)
    - 横図で体の帯からはみ出た奥行き (持ち物) は、正面の色と照らして
      合う側の腕にだけ残す
    - 脚と胴からも持ち物の奥行きは外す。脚どうしの重なりは絞らない —
      左右の脚は同じ見た目なので、重なりが動いても違いは写らない
    """
    by_row = {}
    for (z, y) in side:
        by_row.setdefault(y, []).append(z)
    axis = sorted(z for (z, _) in side)[len(side) // 2]   # 体の奥行きの軸
    body_span, tool_cols = {}, {}
    for y, zs in by_row.items():
        runs = _runs(sorted(zs))
        body = min(runs, key=lambda r:
                   0 if r[0] <= axis <= r[1] else min(abs(r[0] - axis),
                                                      abs(r[1] - axis)))
        body_span[y] = (body[0], body[1])
        tool_cols[y] = {z for r in runs if r is not body
                        for z in range(r[0], r[1] + 1)}

    # 持ち物はどちらの腕の物か。はみ出た奥行きの色と、腕の正面の色を照らす
    step = PROFILE["toneStep"]
    tone = lambda c: (c[0] // step, c[1] // step, c[2] // step)
    tool_tones = Counter(tone(side[(z, y)])
                         for y, cols in tool_cols.items() for z in cols)
    holder = None
    if tool_tones and PROFILE["tool"] != "none":
        def kinship(arm):
            return sum(tool_tones.get(tone(front[(x, y)]), 0)
                       for (x, y, _) in parts.get(arm, {}) if (x, y) in front)
        holder = max(("armL", "armR"), key=kinship)

    kept = {}
    for name, cells in parts.items():
        limb = name.startswith(("arm", "leg"))
        width_of = {}
        if limb:
            for (x, y, _) in cells:
                width_of.setdefault(y, set()).add(x)
        out = {}
        for (x, y, z), color in cells.items():
            if z in tool_cols.get(y, ()):
                if name == holder:
                    out[(x, y, z)] = color
                continue
            if limb:
                lo, hi = body_span.get(y, (z, z))
                half = max(1, len(width_of[y]) // 2 + PROFILE["tubeMargin"])
                if abs(z - (lo + hi) / 2) > half:
                    continue
            out[(x, y, z)] = color
        kept[name] = out

    # 絞りで横図のシルエットに穴が開いたら (ブーツのつま先など、正面の幅より
    # 奥行きが長い所)、絞る前の実体を戻す。戻す先は **1 つの部位だけ** —
    # 全部位へ戻すと板の複製が復活し、動いた瞬間にダブって写る
    have_s = set()
    for cells in kept.values():
        for (x, y, z) in cells:
            have_s.add((z, y))
    for (z, y) in side:
        if (z, y) in have_s:
            continue
        donors = [(name, [p for p in cells if p[1] == y and p[2] == z])
                  for name, cells in parts.items()]
        donors = [(name, hit) for name, hit in donors if hit]
        if not donors:
            continue
        def closeness(entry):
            name, _ = entry
            near = [abs(zz - z) for (_, yy, zz) in kept[name] if yy == y]
            return min(near) if near else 999
        name, hit = min(donors, key=closeness)
        for pos in hit:
            kept[name][pos] = parts[name][pos]
        have_s.add((z, y))

    # 正面のシルエットの穴も同じく、元の持ち主 1 部位へ戻す
    have_f = set()
    for cells in kept.values():
        for (x, y, z) in cells:
            have_f.add((x, y))
    for name, cells in parts.items():
        for (x, y, z), color in cells.items():
            if (x, y) not in have_f:
                kept[name][(x, y, z)] = color
                have_f.add((x, y))
    return kept, holder


# ---------------------------------------------------------------- 部位分け


def split_parts(voxels, size):
    """体を頭・胴・腕・脚に分ける。**高さと左右の位置だけ**で決める。

    正確な骨格は要らない。振るのは腕と脚だけで、そこが分かれば足りる。
    """
    width, height = size
    ys = [y for _, y, _ in voxels]
    top, bottom = min(ys), max(ys)
    span = bottom - top
    head_line = top + int(span * PROFILE["headRatio"])   # ここから上が頭
    hip_line = top + int(span * PROFILE["hipRatio"])     # ここから下が脚
    # 胴の左右の端。腕はその外側
    core = [x for (x, y, _) in voxels if head_line < y < hip_line]
    core.sort()
    trim = len(core) * PROFILE["coreTrimPct"] // 100
    inner = core[trim], core[-trim - 1]
    center = (inner[0] + inner[1]) / 2
    parts = {}
    for (x, y, z), color in voxels.items():
        if y <= head_line:
            name = "head"
        elif y >= hip_line:
            name = "legL" if x >= center else "legR"
        elif x < inner[0] + 1:
            name = "armR"
        elif x > inner[1] - 1:
            name = "armL"
        else:
            name = "torso"
        parts.setdefault(name, {})[(x, y, z)] = color
    # 腰より下でも、腕からつながって垂れている物 (手先・持ち物) は腕のまま。
    # 高さの直線だけで切ると、道具の下半分が脚に化けて腕と逆へ振れる。
    # x の帯を出ない範囲でしか辿らない。腰の行は左右に密につながっていて、
    # 無条件に辿ると脚まで腕に飲み込むため
    for arm, in_band in (("armR", lambda x: x < inner[0] + 1),
                         ("armL", lambda x: x > inner[1] - 1)):
        frontier = list(parts.get(arm, {}))
        while frontier:
            x, y, z = frontier.pop()
            for pos in ((x + 1, y, z), (x - 1, y, z), (x, y + 1, z),
                        (x, y - 1, z), (x, y, z + 1), (x, y, z - 1)):
                if not in_band(pos[0]):
                    continue
                for leg in ("legL", "legR"):
                    if pos in parts.get(leg, {}):
                        parts[arm][pos] = parts[leg].pop(pos)
                        frontier.append(pos)
    return parts, {"top": top, "bottom": bottom, "head": head_line,
                   "hip": hip_line, "center": center}


# ---------------------------------------------------------------- 動き
#
# コマごとに、腕と脚を**前後 (z) へ振る**量と、体の沈みを持つ。
# 前後へ振るので、横向きでは歩幅として・正面では手前の腕が体に重なる形で出る。

MOTIONS = {
    "walk": (("walk_l", -1, 1), ("idle", 0, 0), ("walk_r", 1, 1)),
}


def swing(parts, marks, phase, dip, reach=None, rise=True):
    """腕と脚を振り、体を沈める。

    振りは付け根 0・先端 reach の割合。付け根から同じ量だけ動かすと、
    胴との継ぎ目が切れる。先端ほど大きく動かす。

    **沈みは足まで下ろさない。** 全身を同じだけ下げると、接地の行が
    コマごとに変わり、タイルに乗せたとき床へめり込んで見える。
    接地している足は動かさず、腰から上だけを沈める (脚が縮む = 膝が曲がる)。
    """
    reach = PROFILE["reach"] if reach is None else reach
    out = {}
    bottom = marks["bottom"]
    head, hip = marks["head"], marks["hip"]
    for name, cells in parts.items():
        for (x, y, z), color in cells.items():
            dz = 0
            dy = dip
            if name.startswith("leg"):
                deep = (y - hip) / max(1, bottom - hip)
                # 足元ほど沈みを効かせない。軸足は床に置いたまま
                dy = round(dip * (1 - deep))
                if phase:
                    side = 1 if name.endswith("L") else -1
                    dz = round(reach * deep) * phase * side
                    # 前へ出る足を持ち上げる。前後 (奥行き) の動きは正面から
                    # 見えないので、上下で「歩いている」を 4 方向へ届ける
                    if side * phase > 0:
                        if deep > PROFILE["liftAt"]:
                            dy -= 1
                        if deep > 0.92:
                            dy -= 1                  # つま先はもう 1px 浮く
            elif name.startswith("arm"):
                if y > hip:
                    # 手より下 (持ち物) は手と同じ振り幅で 1 本の棒として動く。
                    # 沈みは接地へ向けて弱め、道具の先が床を割らないようにする
                    deep = 1.0
                    low = (y - hip) / max(1, bottom - hip)
                    dy = round(dip * (1 - low))
                else:
                    deep = (y - head) / max(1, hip - head)
                if phase:
                    side = -1 if name.endswith("L") else 1
                    dz = round(reach * deep) * phase * side
                    # 前へ振れる腕は手先が持ち上がる。上下は 4 方向全部で見える。
                    # 道具を持つ腕は上げない — 幅 1px の柄の途中に段差が入ると
                    # 道具の頭が泳ぐ
                    if rise and phase * side > 0 and deep > 0.6:
                        dy -= 1
            out[(x, y + dy, z + dz)] = color
    return out


# ---------------------------------------------------------------- 描き直す

VIEWS = (("front", 0), ("right", 90), ("back", 180), ("left", 270))


def _screen(view, x, y, z, width):
    """ボクセル位置を、その向きの画面座標と奥行きへ写す。"""
    if view == "front":
        return (x, y), z
    if view == "right":
        return (z, y), width - 1 - x
    if view == "back":
        return (width - 1 - x, y), -z
    return (width - 1 - z, y), x


def _img_x(view, sx, width):
    """画面 x を元図の x へ戻す。左向きだけ横図の鏡映を見ている。"""
    return width - 1 - sx if view == "left" else sx


def face_owners(parts, size):
    """止まった姿で「各向きの各画素を、どの部位が見せているか」を確定する。

    色はボクセルに埋め込まない。1 ボクセル 1 色では 4 方向の色を同時に
    満たせない (左右で色が食い違っていた) ため、描き直すたびに元図から引く。
    その照合に使う所有権の地図を、動かす前に 1 回だけ作る。
    """
    width, _ = size
    owner = {view: {} for view, _ in VIEWS}
    best = {view: {} for view, _ in VIEWS}
    for name, cells in parts.items():
        for (x, y, z) in cells:
            for view, _ in VIEWS:
                key, depth = _screen(view, x, y, z, width)
                if key not in best[view] or depth > best[view][key]:
                    best[view][key] = depth
                    owner[view][key] = name
    return owner


def dress(moved, view, owner, imgs, size):
    """動かした立体を 1 方向へ落とし、色を元図から着せる。

    moved は部位ごとの {今の位置: 出身位置}。色の優先順:
    (1) 出身画素がこの向きでこの部位の物なら、元図のその色 —
        動いた部位の表面は「元の絵がそのままずれた物」になる
    (2) この向きでこの部位が見せている、近くの行の色 —
        めくれて現れた面は、同じ部位の見えている所から続きを借りる
    (3) 正面図の自分の色 — この向きで一度も見えない部位 (奥の腕) の控え。
        彫り出しが正面図の列からしか作らないので、必ず在る
    """
    width, height = size
    img = imgs[view]
    screen = {}
    for name, cells in moved.items():
        for (x, y, z), origin in cells.items():
            key, depth = _screen(view, x, y, z, width)
            if key not in screen or depth > screen[key][0]:
                screen[key] = (depth, name, origin)
    out = {}
    for (sx, y), (_, name, (x0, y0, z0)) in screen.items():
        if not (0 <= sx < width and 0 <= y < height):
            continue
        okey, _ = _screen(view, x0, y0, z0, width)
        color = None
        if owner[view].get(okey) == name:
            color = img.get((_img_x(view, okey[0], width), okey[1]))
        if color is None:
            color = _kin_color(owner[view], img, view, name, okey, width)
        if color is None:
            color = imgs["front"].get((x0, y0))
        out[(sx, y)] = color if color else (0, 0, 0)
    return out


def _kin_color(owned, img, view, name, okey, width):
    """同じ向きでその部位が見せている画素のうち、近い物の色を借りる。"""
    sx0, y0 = okey
    for dy in (0, -1, 1, -2, 2, -3, 3):
        row = [sx for (sx, y), who in owned.items()
               if y == y0 + dy and who == name
               and img.get((_img_x(view, sx, width), y)) is not None]
        if row:
            sx = min(row, key=lambda v: abs(v - sx0))
            return img.get((_img_x(view, sx, width), y0 + dy))
    return None


def _groups(cells):
    """つながった塊に分ける。輪郭の対角つなぎは切らない (8 近傍)。"""
    unseen = set(cells)
    groups = []
    while unseen:
        todo = deque([unseen.pop()])
        grp = set()
        while todo:
            x, y = todo.popleft()
            grp.add((x, y))
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    q = (x + dx, y + dy)
                    if q in unseen:
                        unseen.remove(q)
                        todo.append(q)
        groups.append(grp)
    groups.sort(key=len, reverse=True)
    return groups


def _crumbs(cells):
    """本体 (最大の塊) 以外の塊を返す。"""
    return _groups(cells)[1:]


def components(cells):
    return [len(g) for g in _groups(cells)]


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("image")
    parser.add_argument("--id", default="carved")
    parser.add_argument("--size", default="32x48")
    parser.add_argument("--colors", type=int, default=16)
    parser.add_argument("--reach", type=int, default=None,
                        help="腕と脚の先端が前後へ動く量 (省略時は PROFILE)")
    parser.add_argument("--profile", default=None,
                        help="体型のつまみを上書きする JSON (書いたキーだけ)")
    args = parser.parse_args(argv)
    if args.profile:
        with open(args.profile, encoding="utf-8") as handle:
            PROFILE.update(json.load(handle))
    if args.reach is None:
        args.reach = PROFILE["reach"]

    root = os.getcwd()
    size = tuple(int(v) for v in args.size.lower().split("x"))
    img = adopt.png_read.open_image(args.image)
    mask = adopt.backdrop_mask(img)
    spans = adopt.spans_of(img, mask)
    print(f"切り分け {len(spans)} 体")
    names = ("front", "right", "back")
    views = {}
    for name, span in zip(names, spans):
        box = adopt.bounds_of(img, span, mask)
        views[name] = adopt.resample(img, box, size, mask)
    # 位置合わせは**色を減らす前・彫る前**に、3 面まとめて 1 回だけ
    views = align(views, size)
    views = adopt.reduce_colors(views, args.colors)
    for name, cells in views.items():
        ys = [y for _, y in cells]
        print(f"  {name:6} 接地 {max(ys)}  立ち位置の中心 "
              f"{stance_center(cells, size):.1f}")

    voxels = carve(views["front"], views["right"], views["back"], size)
    print(f"彫り出した立体 {len(voxels)} ボクセル")
    parts, marks = split_parts(voxels, size)
    parts, holder = slim(parts, views["front"], views["right"], size)
    total = sum(len(cells) for cells in parts.values())
    print(f"奥行きを絞って {total} ボクセル  持ち物は {holder or '無し'}")
    print("部位 " + " ".join(f"{k}:{len(v)}" for k, v in sorted(parts.items())))
    imgs = {"front": views["front"], "right": views["right"],
            "back": views["back"], "left": views["right"]}
    owner = face_owners(parts, size)
    # 動かさない投影は、色まで含めて元の絵と一致するはず。左は右の鏡映のはず
    rest = {name: {pos: pos for pos in cells} for name, cells in parts.items()}
    idle_shot = {view: dress(rest, view, owner, imgs, size)
                 for view, _ in VIEWS}
    for name in ("front", "right", "back"):
        shot = idle_shot[name]
        same = sum(1 for pos, c in views[name].items() if shot.get(pos) == c)
        gap = len(set(views[name]) ^ set(shot))
        print(f"  {name:6} 投影の一致 {same}/{len(views[name])}  ずれ {gap}px")
    mirror = {(size[0] - 1 - x, y): c
              for (x, y), c in idle_shot["right"].items()}
    left = idle_shot["left"]
    off = len(set(mirror) ^ set(left))
    tint = sum(1 for pos in mirror if pos in left and left[pos] != mirror[pos])
    print(f"  left   右の鏡映と 位置ずれ {off}px  色違い {tint}px")

    out_dir = os.path.join(root, "gallery", args.id)
    os.makedirs(out_dir, exist_ok=True)
    frames = {}
    todo = [(m, pose, phase, dip) for m, seq in MOTIONS.items()
            for pose, phase, dip in seq]
    for m, pose, phase, dip in todo:
        if ("front", pose) in frames:
            continue                     # idle は表をまたいで共通
        moved = {name: swing({name: {pos: pos for pos in cells}},
                             marks, phase, dip, args.reach,
                             rise=(name != holder))
                 for name, cells in parts.items()}
        for view, yaw in VIEWS:
            cells = dress(moved, view, owner, imgs, size)
            if phase:
                # せん断の丸め境界は対角にしかつながらない 1px の欠片を生む。
                # 動きで生まれた新参だけ掃く。元絵由来の浮き画素は idle にも
                # 居るので残り、止まった投影の一致は崩れない
                still = frames.get((view, "idle"), idle_shot[view])
                for chunk in _crumbs(cells):
                    if (len(chunk) <= PROFILE["crumbLimit"]
                            and not any(p in still for p in chunk)):
                        for p in chunk:
                            del cells[p]
            frames[(view, pose)] = cells
            adopt.save_png(os.path.join(out_dir, f"{view}-{pose}.png"),
                           cells, size)
    poses = []
    for _, p, _, _ in todo:
        if p not in poses:
            poses.append(p)
    for view, _ in VIEWS:
        parts_count = [len(components(frames[(view, p)])) for p in poses]
        moved = len(frames[(view, "idle")].keys()
                    ^ frames[(view, "walk_l")].keys())
        print(f"  {view:6} 塊 {parts_count}  コマ間で動く画素 {moved}")

    palette, legend, table = {}, {}, {}
    chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    every = Counter()
    for cells in frames.values():
        every.update(cells.values())
    for index, (color, _) in enumerate(every.most_common(len(chars))):
        key = f"c{index:02d}"
        palette[key] = "#%02x%02x%02x" % color
        legend[chars[index]] = key
        table[color] = chars[index]
    sprites = {}
    for view, _ in VIEWS:
        made = {}
        for pose in poses:
            cells = frames[(view, pose)]
            made[pose] = ["".join(table.get(cells.get((x, y)), ".")
                                  for x in range(size[0]))
                          for y in range(size[1])]
        sprites[f"{args.id}_{view}"] = {
            "anchor": {"x": size[0] // 2, "y": size[1] - 1}, "frames": made}
    doc = {"version": 1, "entityId": args.id,
           "note": "3 面図から彫り出した立体を 3D で振り、4 方向へ描き直した。"
                   "bin/carve.py の生成物",
           "palette": palette, "legend": legend, "sprites": sprites}
    path = os.path.join(root, "assets", "chars", f"{args.id}.sprite.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(doc, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    reels = {"walk": ("idle", "walk_l", "idle", "walk_r")}
    for m, order in reels.items():
        strips = []
        for index, pose in enumerate(order):
            png_path = os.path.join(out_dir, f"_strip-{m}{index}.png")
            rows = []
            for y in range(size[1]):
                line = []
                for view, _ in VIEWS:
                    cells = frames[(view, pose)]
                    for x in range(size[0]):
                        color = cells.get((x, y))
                        line.append(color + (255,) if color else (0, 0, 0, 0))
                rows.append(line)
            with open(png_path, "wb") as handle:
                handle.write(render.png_of(size[0] * len(VIEWS), size[1], rows))
            strips.append(png_path)
        with open(os.path.join(out_dir, f"{m}.gif"), "wb") as handle:
            handle.write(gifs.from_pngs(strips, shrink=1))
        for png_path in strips:
            os.remove(png_path)
    print(os.path.relpath(path, root))
    print(os.path.relpath(out_dir, root))
    return 0


if __name__ == "__main__":
    sys.exit(main())
