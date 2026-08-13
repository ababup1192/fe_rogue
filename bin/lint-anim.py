#!/usr/bin/env python3
"""コマ列と 4 方向のそろい方を機械で確かめる (標準ライブラリのみ)。

  python3 bin/lint-anim.py                    # assets/ 配下を全部
  python3 bin/lint-anim.py a.sprite.json      # 指定ファイルだけ
  python3 bin/lint-anim.py --strict           # 注意も NG に上げる
  python3 bin/lint-anim.py --self-test        # この lint 自身の検査

見るのは「1 枚の絵の質」ではなく **絵と絵の関係**:

  コマ列 (idle / walk_0 / walk_1 …)
    - コマ間で入れ替わる画素が多すぎないか (ポッピング)
    - 面積が保たれているか (体積保存)
    - 接地が保たれているか・上下動が大きすぎないか
    - 輪を閉じたとき (最後 → 最初) も同じ上限に収まるか
    - コマごとに色が湧いていないか

  4 方向 (同じキャラの front / side / back …)
    - 接地行・頭頂・足元の中心がそろっているか
    - 横向きの幅が正面の 0.6〜0.85 倍か
    - 前と後のシルエットが重なるか (IoU ≥ 0.90)
    - 全方向で同じ色を使っているか

除外は sprite.json に書く:
  "lint-anim": "対象外(pop) — 変身するので前後のコマが別物でよい"
"""

import json
import os
import sys

for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

TRANSPARENT = {".", " "}

# --- 閾値 (16〜48px 級。64px 級なら px 系を 2 倍に) -------------------------
MAX_POP_SHARE = 0.45      # コマ間で入れ替わってよい画素の割合
MAX_AREA_DRIFT = 0.20     # コマ間の面積の変動
MAX_BOB = 2               # 歩きの上下動 (px)
MIN_SIDE_RATIO = 0.60     # 横向きの幅 / 正面の幅
MAX_SIDE_RATIO = 0.85
MIN_BACK_IOU = 0.90       # 前と後のシルエットの重なり
FOOT_TOLERANCE = 1        # 接地行のずれ (px)

RULES = ("pop", "area", "ground", "bob", "loop", "palette", "view")

# 方向を表す語尾。基の名前が同じ物どうしを 1 組として見る。
DIRECTIONS = {
    "front": "front", "south": "front", "down": "front",
    "back": "back", "north": "back", "up": "back",
    "side": "side", "east": "side", "right": "side",
    "west": "side_w", "left": "side_w",
}


def mask_of(rows):
    return {
        (x, y)
        for y, row in enumerate(rows)
        for x, char in enumerate(row)
        if char not in TRANSPARENT
    }


def colors_of(rows):
    return {c for row in rows for c in row if c not in TRANSPARENT}


def bottom_of(mask):
    return max((y for _, y in mask), default=None)


def top_of(mask):
    return min((y for _, y in mask), default=None)


def width_of(mask):
    xs = [x for x, _ in mask]
    return (max(xs) - min(xs) + 1) if xs else 0


def foot_center(mask):
    bottom = bottom_of(mask)
    xs = [x for x, y in mask if y == bottom]
    return sum(xs) / len(xs) if xs else None


def _grid(rows):
    return {
        (x, y): char
        for y, row in enumerate(rows)
        for x, char in enumerate(row)
        if char not in TRANSPARENT
    }


def change_share(a_rows, b_rows, slack=2):
    """入れ替わった画素の割合。

    体を 1px 上下させる歩きの上下動だけで全画素がずれるので、
    ±slack の平行移動でいちばん重なる置き方に合わせてから数える。
    「動いた量」ではなく「**平行移動では説明できない変化**」を見る。
    """
    a, b = _grid(a_rows), _grid(b_rows)
    if not a and not b:
        return 0.0
    best = 1.0
    for dy in range(-slack, slack + 1):
        for dx in range(-slack, slack + 1):
            shifted = {(x + dx, y + dy): c for (x, y), c in b.items()}
            span = set(a) | set(shifted)
            changed = sum(1 for p in span if a.get(p) != shifted.get(p))
            best = min(best, changed / max(1, len(span)))
    return best


def excluded_rules(text):
    if not isinstance(text, str) or "対象外" not in text:
        return set()
    head = text.split("対象外", 1)[1]
    inside = head.split("(", 1)[1].split(")", 1)[0] if "(" in head else ""
    return {r.strip() for r in inside.replace("、", ",").split(",") if r.strip()}


def split_direction(name):
    """'walker_side' → ('walker', 'side')。方向語尾が無ければ (name, None)。"""
    if "_" in name:
        base, tail = name.rsplit("_", 1)
        if tail.lower() in DIRECTIONS:
            return base, DIRECTIONS[tail.lower()]
    return name, None


def check_frames(sprite_name, frames, skip):
    """コマ列の不変量。frames: [(コマ名, rows)] を並び順で。"""
    notes = []
    if len(frames) < 2:
        return notes
    masks = [(n, mask_of(r)) for n, r in frames]
    base_area = len(masks[0][1])

    for (na, ra), (nb, rb) in zip(frames, frames[1:]):
        if "pop" not in skip:
            share = change_share(ra, rb)
            if share > MAX_POP_SHARE:
                notes.append(
                    f"{sprite_name}: {na} → {nb} でシルエットの {share:.0%} が入れ替わる "
                    f"(上限 {MAX_POP_SHARE:.0%}) — 別の絵に見えて画面がちらつく"
                )
    if "loop" not in skip and len(frames) > 2:
        share = change_share(frames[-1][1], frames[0][1])
        if share > MAX_POP_SHARE:
            notes.append(
                f"{sprite_name}: 輪が閉じていない ({frames[-1][0]} → {frames[0][0]} で "
                f"{share:.0%} 入れ替わる) — 繰り返した瞬間に飛ぶ"
            )
    for name, mask in masks[1:]:
        if "area" not in skip and base_area:
            drift = abs(len(mask) - base_area) / base_area
            if drift > MAX_AREA_DRIFT:
                notes.append(
                    f"{sprite_name}: コマ {name} の面積が {drift:+.0%} ずれる "
                    f"(上限 ±{MAX_AREA_DRIFT:.0%}) — 曲げても体の太さは変わらない"
                )
    bottoms = [(n, bottom_of(m)) for n, m in masks if m]
    if bottoms:
        if "ground" not in skip:
            floor = max(b for _, b in bottoms)
            for name, b in bottoms:
                if floor - b > FOOT_TOLERANCE:
                    notes.append(
                        f"{sprite_name}: コマ {name} で足が {floor - b}px 浮いている "
                        f"— 両足が同時に浮くのは跳躍だけ"
                    )
        if "bob" not in skip:
            tops = [top_of(m) for _, m in masks if m]
            swing = max(tops) - min(tops)
            if swing > MAX_BOB:
                notes.append(
                    f"{sprite_name}: 頭の上下動が {swing}px (上限 {MAX_BOB}px) — 跳ねて見える"
                )
    if "palette" not in skip:
        base_colors = colors_of(frames[0][1])
        for name, rows in frames[1:]:
            extra = colors_of(rows) - base_colors
            if extra:
                notes.append(
                    f"{sprite_name}: コマ {name} だけに色 {sorted(extra)} が湧いている "
                    "— コマごとに色を足さない"
                )
    return notes


def check_views(base, views, skip):
    """同じキャラの方向どうしの不変量。views: {方向: rows}"""
    notes = []
    if "view" in skip or len(views) < 2:
        return notes
    masks = {d: mask_of(r) for d, r in views.items() if mask_of(r)}
    if len(masks) < 2:
        return notes
    bottoms = {d: bottom_of(m) for d, m in masks.items()}
    if max(bottoms.values()) != min(bottoms.values()):
        notes.append(
            f"{base}: 方向で接地行が違う {bottoms} — 全方向で足の裏を同じ行にそろえる"
        )
    tops = {d: top_of(m) for d, m in masks.items()}
    if max(tops.values()) - min(tops.values()) > 1:
        notes.append(f"{base}: 方向で頭の高さが違う {tops} (許容 1px) — 別人に見える")
    centers = {d: foot_center(m) for d, m in masks.items()}
    if max(centers.values()) - min(centers.values()) > 1:
        notes.append(
            f"{base}: 方向で足元の中心がずれている — 向きを変えた瞬間に体が滑る"
        )
    if "front" in masks and "side" in masks:
        ratio = width_of(masks["side"]) / max(1, width_of(masks["front"]))
        if not (MIN_SIDE_RATIO <= ratio <= MAX_SIDE_RATIO):
            notes.append(
                f"{base}: 横向きの幅が正面の {ratio:.2f} 倍 "
                f"(目安 {MIN_SIDE_RATIO}〜{MAX_SIDE_RATIO}) — "
                + ("細すぎて貧相" if ratio < MIN_SIDE_RATIO else "太すぎて別人")
            )
    if "front" in masks and "back" in masks:
        a, b = masks["front"], masks["back"]
        iou = len(a & b) / max(1, len(a | b))
        if iou < MIN_BACK_IOU:
            notes.append(
                f"{base}: 前と後のシルエットの重なりが {iou:.2f} "
                f"(下限 {MIN_BACK_IOU}) — 背面は正面の外形を流用し、顔と髪だけ描き替える"
            )
    if "side" in views and "side_w" in views:
        east = mask_of(views["side"])
        west = {(w - 1 - x, y) for x, y in mask_of(views["side_w"])
                for w in [max(len(r) for r in views["side_w"])]}
        if east and west:
            iou = len(east & west) / max(1, len(east | west))
            if iou < MIN_BACK_IOU:
                notes.append(
                    f"{base}: 左右が反転になっていない (重なり {iou:.2f})。"
                    "非対称の持ち物があるなら意図的 — 除外記法で書く"
                )
    base_colors = None
    for d, rows in sorted(views.items()):
        cs = colors_of(rows)
        if base_colors is None:
            base_colors = cs
        elif cs - base_colors:
            notes.append(
                f"{base}: 方向 {d} だけに色 {sorted(cs - base_colors)} がある "
                "— 色票は全方向で同じにする"
            )
    return notes


def sequences(spec):
    """コマを「連番の並び」ごとに分ける。

    `walk_0` `walk_1` は 1 つの動き。`idle` `hit` `lit` `heart_empty` のような
    番号の無いコマは**別々の状態**であって動きの続きではない。
    一緒くたに比べると「点灯したランプは色が湧いている」のような的外れな指摘が出る。
    """
    names = [n for n in spec.get("frames", {}) if not n.startswith("//")]
    groups = {}
    for name in names:
        head = name.rstrip("0123456789")
        digits = name[len(head):]
        if not digits:
            continue
        groups.setdefault(head.rstrip("_"), []).append((int(digits), name))
    return {
        base: [n for _, n in sorted(items)]
        for base, items in groups.items()
        if len(items) >= 2
    }


def check_doc(path):
    with open(path, encoding="utf-8") as handle:
        doc = json.load(handle)
    file_skip = excluded_rules(doc.get("lint-anim", ""))
    notes = []
    groups = {}
    for name, spec in (doc.get("sprites") or {}).items():
        if name.startswith("//") or not isinstance(spec, dict):
            continue
        skip = file_skip | excluded_rules(spec.get("lint-anim", ""))
        frames = spec.get("frames") or {}
        for seq, order in sorted(sequences(spec).items()):
            label = name if seq in ("", name) else f"{name}.{seq}"
            notes.extend(check_frames(label, [(n, frames[n]) for n in order], skip))
        base, direction = split_direction(name)
        first = next((n for n in frames if not n.startswith("//")), None)
        if direction and first:
            groups.setdefault(base, {})[direction] = frames[first]
            groups[base].setdefault("__skip", set()).update(skip)
    for base, views in groups.items():
        skip = views.pop("__skip", set())
        notes.extend(check_views(base, views, skip))
    return notes


def _self_test():
    ok = []

    def case(name, fn, needle=None):
        notes = fn()
        hit = any(needle in n for n in notes) if needle else not notes
        ok.append(("OK  " if hit else "NG  ") + name + ("" if hit else f": {notes}"))

    solid = ["." * 8] * 2 + ["..oooo.."] * 4 + ["..o..o.."] * 2
    moved = ["." * 8] * 2 + ["..oooo.."] * 4 + [".o...o.."] * 2
    other = ["oooooooo"] * 8

    case("普通のコマ", lambda: check_frames("s", [("a", solid), ("b", moved)], set()))
    case(
        "入れ替わりすぎ",
        lambda: check_frames("s", [("a", solid), ("b", other)], set()),
        "入れ替わる",
    )
    case(
        "除外が効く",
        lambda: check_frames("s", [("a", solid), ("b", other)], {"pop", "area", "ground", "bob", "palette"}),
    )
    floating = ["." * 8] * 2 + ["..oooo.."] * 4 + ["." * 8] * 2
    case(
        "足が浮く",
        lambda: check_frames("s", [("a", solid), ("b", floating)], {"pop", "area", "bob"}),
        "浮いている",
    )
    case(
        "色が湧く",
        lambda: check_frames(
            "s", [("a", solid), ("b", [r.replace("o", "x", 1) for r in solid])],
            {"pop", "area", "ground", "bob"},
        ),
        "湧いている",
    )
    front = ["..oooo.."] * 6 + ["..o..o.."] * 2
    thin = ["...oo..."] * 6 + ["...o.o.."] * 2
    case("正面と横", lambda: check_views("c", {"front": front, "side": thin}, set()))
    case(
        "横が太すぎ",
        lambda: check_views("c", {"front": front, "side": front}, set()),
        "太すぎ",
    )
    case(
        "接地がずれる",
        lambda: check_views(
            "c", {"front": front, "side": ["...oo..."] * 6 + ["........"] * 2}, set()
        ),
        "接地行が違う",
    )
    back = ["..oooo.."] * 6 + ["..o..o.."] * 2
    case("前と後が重なる", lambda: check_views("c", {"front": front, "back": back}, set()))

    for line in ok:
        print(line)
    bad = [x for x in ok if x.startswith("NG")]
    print(f"\n{len(ok) - len(bad)}/{len(ok)} 件 OK")
    return 1 if bad else 0


GAME_ROOTS = ("templates",)
EXCLUDED_DIRS = {".git", "build", "lib", ".devbox", "gallery", "reference", "target"}


def discover(root):
    """templates/ 配下、無ければ自分の assets/ を見る。

    エンジンのリポでもゲーム 1 本のリポでも同じ 1 ファイルで動かすため。
    """
    bases = []
    for group in GAME_ROOTS:
        group_dir = os.path.join(root, group)
        if not os.path.isdir(group_dir):
            continue
        for name in sorted(os.listdir(group_dir)):
            rel = f"{group}/{name}"
            if not os.path.isdir(os.path.join(root, rel)):
                continue
            bases.append(os.path.join(root, rel))
    if not bases:
        bases = [root]
    found = []
    for base in bases:
        for current, dir_names, files in os.walk(base):
            dir_names[:] = sorted(d for d in dir_names if d not in EXCLUDED_DIRS)
            found.extend(
                os.path.join(current, n) for n in sorted(files)
                if n.endswith(".sprite.json")
            )
    return sorted(found)


def main(argv):
    if "--self-test" in argv:
        return _self_test()
    strict = "--strict" in argv
    targets = [a for a in argv if not a.startswith("--")]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if not targets:
        targets = discover(root)
    total = 0
    for path in targets:
        notes = check_doc(path)
        if notes:
            print(f"\n{os.path.relpath(path, root)}")
            for note in notes:
                print(f"  {'NG' if strict else '注意'}: {note}")
            total += len(notes)
    label = "NG" if strict else "注意"
    print(f"\n{len(targets)} ファイル / {label} {total} 件")
    return 1 if (strict and total) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
