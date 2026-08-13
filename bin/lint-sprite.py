#!/usr/bin/env python3
"""ドット絵 (*.sprite.json) の絵としての質を検査するゲート。

lint-palette が「色が解けるか」を見るのに対し、こちらは画素の並びを見る。
規則はドット絵の実務で広く共有されている物の機械化:
  NG (終了コード 1) — 形式の壊れ。誤検知がほぼ無い
    structure : rows が矩形 / legend に無い文字 / コマ間の大きさ不一致 /
                anchor が格子の外 / 空のコマ / コマの丸ごとコピペ
    orphan    : 周り 4 方向すべて透明の浮いた 1 画素
  注意 (終了コード 0。--strict で NG に昇格) — 閾値に依存する美学の規則
    jaggy     : 輪郭の階段のラン長が 長,1,長 と乱れる (例 3,1,3)
    banding   : ある色が輪郭の内側 1px の縁取りとしてしか使われていない
    corner    : 1px 線の角に画素が L 字に 2 重になっている
    silhouette: 枠に対して絵がスカスカ / 細長すぎる
    palette   : 1 スプライトの色数が上限超え / 色どうしが近すぎる (ΔE)
                (色数は少数パレットの画風向けの目安。色ランプ+ディザの
                 高精細一枚絵では超えて良い — 気になるなら --strict で)

塗り率 90% 以上のコマは「テクスチャ」(全面ディザ・タイル) と見なし、
形の規則 (orphan/jaggy/banding/corner/silhouette) を掛けない。
それでも残る意図的な例外は、スプライト (またはファイルのトップレベル) に
  "lint-sprite": "対象外(jaggy, banding) — 遠景の山肌はギザギザが画風"
と理由付きで書く (括弧を省くと全規則が対象外)。黙って除外はしない。

  python3 bin/lint-sprite.py                  # templates/ を全部見る
  python3 bin/lint-sprite.py a.sprite.json    # 指定ファイルだけ見る
  python3 bin/lint-sprite.py --strict         # 「注意」も NG に数える
  python3 bin/lint-sprite.py --self-test      # 内蔵の最小例で自分自身を検査

標準ライブラリだけで動く (Windows / macOS / Linux 共通)。
"""

import importlib.util
import json
import os
import re
import sys
from collections import deque

# Windows のコンソール (cp932 等) でも日本語メッセージで落とさない。
for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

EXCLUDED_DIRS = {"build", "lib", ".git", "gallery", ".devbox", "node_modules"}
GAME_ROOTS = ("templates",)

# legend に無い文字のうち、透明として認める物。それ以外は typo と見なす
# (エンジンは fail-open で無言で透明にするため、ゲートが代わりに声を出す)。
TRANSPARENT_CHARS = {".", " "}

RULES = ("structure", "orphan", "palette", "jaggy", "banding", "corner", "silhouette")

MAX_COLORS = 12          # 1 スプライトの色数上限 (legend の値の異なり数)
MAX_COLORS_BIG = 16      # 32px を超える大物 (建物・細長い物) は少し緩める
BIG_SIDE = 32
TEXTURE_FILL = 0.90      # これ以上塗られたコマはテクスチャ扱い
MIN_ORPHAN_CELLS = 4     # これ未満の極小スプライト (粒など) は orphan を見ない
JAGGY_MIN_COUNT = 3      # 1 コマにこれ以上の乱れで注意
BANDING_MIN_RUN = 8      # 縁取り専用色がこの画素数以上で注意
SILHOUETTE_MIN_OCC = 0.20
DELTA_E_MIN = 5.0


def load_lint_palette():
    """色の判定と解決は lint-palette.py の物を借りる (二重実装しない)。"""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lint-palette.py")
    try:
        spec = importlib.util.spec_from_file_location("lint_palette", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    except Exception:
        return None


LP = load_lint_palette()


def read_json(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


# ---------------------------------------------------------------- 色 (ΔE)


def hex_of_value(value):
    """色として読める値から "#rrggbb" を取り出す。hsv/rgb 表記は対象外。"""
    if LP is None:
        return None
    if isinstance(value, str) and LP.is_hex_color(value):
        body = value[1:] if value.startswith("#") else value
        return "#" + body.lower()
    if isinstance(value, dict):
        for key in LP.COLOR_WRAP_KEYS:
            if key in value:
                found = hex_of_value(value[key])
                if found:
                    return found
    return None


def hex_map_of(obj):
    if not isinstance(obj, dict):
        return {}
    found = {}
    for name, value in obj.items():
        got = hex_of_value(value)
        if got:
            found[name] = got
    nested = obj.get("colors")
    if isinstance(nested, dict):
        for name, value in nested.items():
            got = hex_of_value(value)
            if got:
                found[name] = got
    return found


def color_hexes_of(game_dir, json_paths, doc):
    """legend の値 → "#rrggbb"。解けない値は含めない (lint-palette の縄張り)。"""
    names = {}
    for rel in json_paths:
        if rel.endswith(".theme.json"):
            names.update(hex_map_of(read_json(os.path.join(game_dir, rel))))
    ref = doc.get("paletteFile")
    if isinstance(ref, str):
        names.update(hex_map_of(read_json(os.path.join(game_dir, ref))))
    names.update(hex_map_of(doc.get("palette")))

    legend = doc.get("legend")
    resolved = {}
    if isinstance(legend, dict):
        for char, value in legend.items():
            if not isinstance(value, str):
                continue
            direct = hex_of_value(value)
            if direct:
                resolved[value] = direct
                continue
            name = value[1:] if value.startswith("@") else value
            if name in names:
                resolved[value] = names[name]
    return resolved


def lab_of(hex_color):
    r, g, b = (int(hex_color[i : i + 2], 16) / 255.0 for i in (1, 3, 5))

    def lin(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = lin(r), lin(g), lin(b)
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883

    def f(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116

    fx, fy, fz = f(x), f(y), f(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def delta_e(hex_a, hex_b):
    la, lb = lab_of(hex_a), lab_of(hex_b)
    return sum((p - q) ** 2 for p, q in zip(la, lb)) ** 0.5


# ---------------------------------------------------------------- 格子の下ごしらえ


def grid_of(rows, legend):
    """rows → {(x, y): 色キー}。返り値は (格子, 幅, 高さ, 不正文字の集合)。"""
    height = len(rows)
    width = len(rows[0]) if rows else 0
    cells = {}
    unknown = set()
    for y, row in enumerate(rows):
        for x, char in enumerate(row):
            if char in legend:
                cells[(x, y)] = legend[char]
            elif char not in TRANSPARENT_CHARS:
                unknown.add(char)
    return cells, width, height, unknown


def neighbors4(x, y):
    return ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1))


def neighbors8(x, y):
    return tuple(
        (x + dx, y + dy)
        for dx in (-1, 0, 1)
        for dy in (-1, 0, 1)
        if (dx, dy) != (0, 0)
    )


def bbox_of(cells):
    xs = [x for x, _ in cells]
    ys = [y for _, y in cells]
    return min(xs), min(ys), max(xs), max(ys)


def dist_from_edge(cells):
    """各画素の「透明 (格子外含む) からの距離」。輪郭 = 1、その内側 = 2 …"""
    dist = {}
    queue = deque()
    for x, y in cells:
        if any(n not in cells for n in neighbors4(x, y)):
            dist[(x, y)] = 1
            queue.append((x, y))
    while queue:
        x, y = queue.popleft()
        for n in neighbors4(x, y):
            if n in cells and n not in dist:
                dist[n] = dist[(x, y)] + 1
                queue.append(n)
    return dist


# ---------------------------------------------------------------- 各規則


def orphan_cells(cells):
    """周り 8 方向すべて透明の画素。斜めで繋がる点線・鎖は浮いていない扱い。"""
    if len(cells) < MIN_ORPHAN_CELLS:
        return []
    return sorted(
        (x, y) for x, y in cells if all(n not in cells for n in neighbors8(x, y))
    )


def contour_profiles(cells, width, height):
    """上下左右 4 方向から見た輪郭の高さ列。透明の切れ目で列を分ける。"""
    profiles = []
    for outer, inner, limit_o, limit_i, flip in (
        ("x", "y", width, height, False),   # 上から
        ("x", "y", width, height, True),    # 下から
        ("y", "x", height, width, False),   # 左から
        ("y", "x", height, width, True),    # 右から
    ):
        sequence = []
        for o in range(limit_o):
            hits = [i for i in range(limit_i) if ((o, i) if outer == "x" else (i, o)) in cells]
            if hits:
                sequence.append(max(hits) if flip else min(hits))
            else:
                sequence.append(None)
        profiles.append(sequence)
    return profiles


def jaggy_count(cells, width, height):
    """輪郭の階段で 長,1,長 (段差 ±1・同方向) と乱れている箇所を数える。"""
    count = 0
    for sequence in contour_profiles(cells, width, height):
        chunk = []
        chunks = [chunk]
        for value in sequence:
            if value is None:
                chunk = []
                chunks.append(chunk)
            else:
                chunk.append(value)
        for values in chunks:
            runs = []
            for value in values:
                if runs and runs[-1][0] == value:
                    runs[-1][1] += 1
                else:
                    runs.append([value, 1])
            for i in range(1, len(runs) - 1):
                step_in = runs[i][0] - runs[i - 1][0]
                step_out = runs[i + 1][0] - runs[i][0]
                if (
                    runs[i][1] == 1
                    and runs[i - 1][1] >= 2
                    and runs[i + 1][1] >= 2
                    and step_in == step_out
                    and abs(step_in) == 1
                ):
                    count += 1
    return count


def banding_keys(cells):
    """輪郭の内側 1px の縁取りとしてしか使われていない色 (banding の疑い)。"""
    if len(set(cells.values())) < 3:
        return []
    dist = dist_from_edge(cells)
    suspects = []
    for key in sorted(set(cells.values())):
        spots = [p for p, k in cells.items() if k == key]
        if len(spots) < BANDING_MIN_RUN:
            continue
        if any(dist[p] != 2 for p in spots):
            continue
        x0, y0, x1, y1 = bbox_of(spots)
        if x1 - x0 >= 2 and y1 - y0 >= 2:
            suspects.append(key)
    return suspects


def corner_double_spots(cells):
    """1px の斜め線の段が 1 画素重なって太って見える箇所 (xx / .xx の稲妻)。

    箱の直角の角は正当なので見ない。段の重なりだけを拾う。
    """

    def same(p, key):
        return cells.get(p) == key

    spots = set()
    for (x, y), key in cells.items():
        for dy in (1, -1):
            if (
                same((x + 1, y), key)
                and same((x + 1, y + dy), key)
                and same((x + 2, y + dy), key)
                and not same((x, y + dy), key)
                and not same((x + 2, y), key)
                and not same((x, y - dy), key)
                and not same((x + 1, y - dy), key)
                and not same((x + 1, y + 2 * dy), key)
                and not same((x + 2, y + 2 * dy), key)
            ):
                spots.add((x + 1, y))
        for dx in (1, -1):
            if (
                same((x, y + 1), key)
                and same((x + dx, y + 1), key)
                and same((x + dx, y + 2), key)
                and not same((x + dx, y), key)
                and not same((x, y + 2), key)
                and not same((x - dx, y), key)
                and not same((x - dx, y + 1), key)
                and not same((x + 2 * dx, y + 1), key)
                and not same((x + 2 * dx, y + 2), key)
            ):
                spots.add((x, y + 1))
    return sorted(spots)


def silhouette_notes(cells, width, height):
    x0, y0, x1, y1 = bbox_of(cells)
    box_w, box_h = x1 - x0 + 1, y1 - y0 + 1
    notes = []
    occupancy = len(cells) / (box_w * box_h)
    if occupancy < SILHOUETTE_MIN_OCC:
        notes.append(f"シルエットがスカスカ (枠 {box_w}x{box_h} の {occupancy:.0%})")
    # 格子の端から端まで届く物はタイルの縁や細長い物であって、細くて当たり前。
    spans = box_w == width or box_h == height
    if not spans and min(box_w, box_h) <= 2 and max(box_w, box_h) >= 8:
        notes.append(f"シルエットが細長すぎる ({box_w}x{box_h})")
    return notes


# ---------------------------------------------------------------- 除外記法


def exempt_of(value):
    """"対象外(規則, ...) — 理由" を (規則の集合, 理由) に読む。読めなければ None。"""
    if not isinstance(value, str) or "対象外" not in value:
        return None
    match = re.search(r"対象外\s*(?:\(([^)]*)\))?", value)
    listed = match.group(1) if match else None
    if listed:
        rules = {r.strip() for r in listed.replace("、", ",").split(",") if r.strip()}
    else:
        rules = set(RULES)
    _, _, tail = value.partition("対象外")
    tail = re.sub(r"^\s*\([^)]*\)", "", tail)
    reason = tail.lstrip(" —-–:").strip() or "（理由が書かれていません）"
    return rules, reason


# ---------------------------------------------------------------- 1 Doc の検査


def check_doc(doc, legend_hexes):
    """(NG の列, 注意の列, 除外の列, スプライト数) を返す。行頭にパスは付けない。"""
    problems = []
    warnings = []
    excluded = []

    legend = doc.get("legend")
    legend = legend if isinstance(legend, dict) else {}
    sprites = doc.get("sprites")
    sprites = sprites if isinstance(sprites, dict) else {}

    doc_exempt = exempt_of(doc.get("lint-sprite"))
    if doc_exempt:
        excluded.append((None, doc_exempt[1]))

    if legend_hexes is not None and len(legend_hexes) >= 2:
        names = sorted(legend_hexes)
        for i, name_a in enumerate(names):
            for name_b in names[i + 1 :]:
                de = delta_e(legend_hexes[name_a], legend_hexes[name_b])
                if de < DELTA_E_MIN and not (doc_exempt and "palette" in doc_exempt[0]):
                    warnings.append(
                        f"色 \"{name_a}\" ({legend_hexes[name_a]}) と \"{name_b}\""
                        f" ({legend_hexes[name_b]}) が近すぎる (ΔE {de:.1f})"
                    )

    sprite_count = 0
    for name in sorted(sprites):
        if name.startswith("//"):
            continue
        spec = sprites[name]
        if not isinstance(spec, dict) or not isinstance(spec.get("frames"), dict):
            problems.append(f"{name}: frames が無い (スプライトは {{frames, anchor}} の形)")
            continue
        sprite_count += 1

        exempt_rules = set()
        reason_source = exempt_of(spec.get("lint-sprite"))
        if reason_source:
            exempt_rules = reason_source[0]
            excluded.append((name, reason_source[1]))
        if doc_exempt:
            exempt_rules |= doc_exempt[0]

        def report(rule, is_problem, text):
            if rule in exempt_rules:
                return
            (problems if is_problem else warnings).append(text)

        frames = spec["frames"]
        sizes = {}
        used_keys = set()
        seen_frames = {}
        for frame_name in sorted(frames):
            rows = frames[frame_name]
            where = f"{name}/{frame_name}"
            if not isinstance(rows, list) or not all(isinstance(r, str) for r in rows):
                report("structure", True, f"{where}: rows が文字列の配列でない")
                continue
            if not rows or len({len(r) for r in rows}) > 1:
                report("structure", True, f"{where}: rows が矩形でない (行の長さが不揃い)")
                continue
            cells, width, height, unknown = grid_of(rows, legend)
            if unknown:
                shown = " ".join(f"'{c}'" for c in sorted(unknown))
                report("structure", True, f"{where}: legend に無い文字 {shown} (typo なら透明として消えている)")
            if not cells:
                report("structure", True, f"{where}: 絵が空 (不透明な画素が 1 つも無い)")
                continue
            sizes[frame_name] = (width, height)
            used_keys |= set(cells.values())
            key = tuple(rows)
            if key in seen_frames:
                report("structure", True, f"{name}: コマ \"{seen_frames[key]}\" と \"{frame_name}\" が完全に同じ (コピペ?)")
            else:
                seen_frames[key] = frame_name

            texture = len(cells) / (width * height) >= TEXTURE_FILL
            if texture:
                continue
            for x, y in orphan_cells(cells):
                report("orphan", True, f"{where}: ({x},{y}) に浮いた 1 画素 (周り 8 方向すべて透明)")
            count = jaggy_count(cells, width, height)
            if count >= JAGGY_MIN_COUNT:
                report("jaggy", False, f"{where}: 輪郭の階段が {count} 箇所で乱れている (長,1,長 のラン)")
            for key_name in banding_keys(cells):
                report("banding", False, f"{where}: 色 \"{key_name}\" が輪郭の内側 1px の縁取りとしてしか使われていない (banding の疑い)")
            spots = corner_double_spots(cells)
            if spots:
                x, y = spots[0]
                report("corner", False, f"{where}: 1px 線の角が {len(spots)} 箇所で 2 重 (最初は ({x},{y}) 付近)")
            for note in silhouette_notes(cells, width, height):
                report("silhouette", False, f"{where}: {note}")

        if len(set(sizes.values())) > 1:
            shown = ", ".join(f"{n}={w}x{h}" for n, (w, h) in sorted(sizes.items()))
            report("structure", True, f"{name}: コマの大きさが不揃い ({shown})")
        elif sizes:
            width, height = next(iter(sizes.values()))
            anchor = spec.get("anchor")
            if isinstance(anchor, dict):
                ax, ay = anchor.get("x", 0), anchor.get("y", 0)
                if not (0 <= ax < width and 0 <= ay < height):
                    report("structure", True, f"{name}: anchor ({ax},{ay}) が格子 {width}x{height} の外")
        big = sizes and max(max(w, h) for w, h in sizes.values()) > BIG_SIDE
        cap = MAX_COLORS_BIG if big else MAX_COLORS
        if len(used_keys) > cap:
            report("palette", False, f"{name}: 色数 {len(used_keys)} が目安 {cap} を超えている (少数パレットの画風なら色を束ねる。色ランプ+ディザの画風なら気にしなくてよい)")

    return problems, warnings, excluded, sprite_count


# ---------------------------------------------------------------- 走査


def game_dirs(root):
    dirs = []
    for group in GAME_ROOTS:
        group_dir = os.path.join(root, group)
        if not os.path.isdir(group_dir):
            continue
        for name in sorted(os.listdir(group_dir)):
            rel = f"{group}/{name}"
            if not os.path.isdir(os.path.join(root, rel)):
                continue
            dirs.append(rel)
    if not dirs and os.path.isdir(os.path.join(root, "assets")):
        dirs.append(".")
    return dirs


def walk_json(game_dir):
    found = []
    for current, dir_names, files in os.walk(game_dir):
        dir_names[:] = sorted(d for d in dir_names if d not in EXCLUDED_DIRS)
        for name in sorted(files):
            if name.endswith(".json"):
                found.append(os.path.relpath(os.path.join(current, name), game_dir))
    return sorted(found)


def game_dir_of(path):
    """個別指定されたファイルの色票を探す起点 (assets/ の親、無ければ同じ場所)。"""
    parent = os.path.dirname(os.path.abspath(path))
    if os.path.basename(parent) == "assets":
        return os.path.dirname(parent)
    return parent


def gather_targets(argv_paths, root):
    """(表示パス, 実パス, 色票の起点) の列。"""
    targets = []
    if argv_paths:
        for path in argv_paths:
            targets.append((path, path, game_dir_of(path)))
        return targets
    for game in game_dirs(root):
        game_dir = os.path.join(root, game)
        for rel in walk_json(game_dir):
            if rel.endswith(".sprite.json"):
                targets.append((f"{game}/{rel}", os.path.join(game_dir, rel), game_dir))
    return targets


def run(argv_paths, strict):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    problems = []
    warnings = []
    excluded = []
    doc_count = 0
    sprite_count = 0

    if LP is None:
        warnings.append("注意: lint-palette.py が読めないため色の近さ (ΔE) は検査していない")

    for shown, path, game_dir in gather_targets(argv_paths, root):
        doc = read_json(path)
        if not isinstance(doc, dict):
            problems.append(f"{shown}: JSON として読めない")
            continue
        doc_count += 1
        hexes = color_hexes_of(game_dir, walk_json(game_dir), doc) if LP else None
        got_p, got_w, got_e, got_n = check_doc(doc, hexes)
        problems.extend(f"{shown}: {line}" for line in got_p)
        warnings.extend(f"注意: {shown}: {line}" for line in got_w)
        excluded.extend(
            f"除外: {shown}" + (f"/{sprite}" if sprite else "") + f" — {reason}"
            for sprite, reason in got_e
        )
        sprite_count += got_n

    for line in excluded:
        print(line)
    if strict:
        problems.extend(warnings)
        warnings = []
    for line in warnings:
        print(line)
    if problems:
        for line in problems:
            print(line, file=sys.stderr)
        print(
            f"NG: {len(problems)} 件 (sprite Doc {doc_count} 件・スプライト {sprite_count} 個を検査)",
            file=sys.stderr,
        )
        return 1
    print(
        f"OK: sprite Doc {doc_count} 件・スプライト {sprite_count} 個を検査"
        f" (注意 {len(warnings)} 件・除外 {len(excluded)} 件)"
    )
    return 0


# ---------------------------------------------------------------- 自己検査


def self_test():
    """各規則につき「検出する例」と「しない例」の最小ペアで自分自身を確かめる。"""
    legend = {"i": "ink", "s": "skin", "c": "cloth", "h": "hair", "g": "glow"}

    def doc_of(sprite_body, extra=None):
        doc = {"version": 1, "legend": legend, "sprites": {"hero": sprite_body}}
        if extra:
            doc.update(extra)
        return doc

    good = doc_of(
        {
            "frames": {
                "idle": ["..ii..", ".issi.", ".issi.", ".icci.", ".icci.", "..ii.."],
                "walk": ["..ii..", ".issi.", ".issi.", ".icci.", "iicc..", "..ii.."],
            },
            "anchor": {"x": 2, "y": 5},
        }
    )

    cases = [
        ("良い例は素通し", good, [], []),
        (
            "非矩形",
            doc_of({"frames": {"idle": ["ii", "i"]}}),
            ["矩形でない"],
            [],
        ),
        (
            "legend 外の文字",
            doc_of({"frames": {"idle": ["iii", "iiZ"]}}),
            ["legend に無い文字 'Z'"],
            [],
        ),
        (
            "空のコマ",
            doc_of({"frames": {"idle": ["..", ".."]}}),
            ["絵が空"],
            [],
        ),
        (
            "コマのコピペ",
            doc_of({"frames": {"idle": ["ii", "ii"], "walk": ["ii", "ii"]}}),
            ["完全に同じ"],
            [],
        ),
        (
            "コマの大きさ不揃い",
            doc_of({"frames": {"idle": ["ii", "ii"], "walk": ["iii", "iii"]}}),
            ["大きさが不揃い"],
            [],
        ),
        (
            "anchor が格子の外",
            doc_of({"frames": {"idle": ["ii", "ii"]}, "anchor": {"x": 5, "y": 0}}),
            ["格子 2x2 の外"],
            [],
        ),
        (
            "浮いた 1 画素",
            doc_of({"frames": {"idle": ["ii...", "ii..s", ".....", "....."]}}),
            ["浮いた 1 画素"],
            [],
        ),
        (
            "全面ディザはテクスチャ扱い",
            doc_of({"frames": {"idle": ["isis", "sisi", "isis", "sisi"]}}),
            [],
            [],
        ),
        (
            "階段の乱れ (3,1,3)",
            doc_of(
                {
                    "frames": {
                        "idle": [
                            "iii............",
                            "iiii...........",
                            "iiiiiii........",
                            "iiiiiiii.......",
                            "iiiiiiiiiii....",
                            "iiiiiiiiiiii...",
                            "iiiiiiiiiiiiiii",
                        ]
                    }
                }
            ),
            [],
            ["階段"],
        ),
        (
            "縁取り専用色 (banding)",
            doc_of(
                {
                    "frames": {
                        "idle": [
                            "...........",
                            "..iiiiiii..",
                            ".iggggggsi.",
                            ".igcccccsi.",
                            ".igcccccsi.",
                            ".igcccccsi.",
                            ".igssssssi.",
                            "..iiiiiii..",
                            "...........",
                        ]
                    }
                }
            ),
            [],
            ["banding の疑い"],
        ),
        (
            "1px 線の角の 2 重",
            doc_of(
                {
                    "frames": {
                        "idle": [
                            "......",
                            ".ii...",
                            "..ii..",
                            "......",
                        ]
                    }
                }
            ),
            [],
            ["2 重"],
        ),
        (
            "スカスカのシルエット",
            doc_of(
                {
                    "frames": {
                        "idle": [
                            "i.........",
                            "..........",
                            "..........",
                            "..........",
                            ".........i",
                        ]
                    }
                }
            ),
            [],
            ["スカスカ"],
        ),
        (
            "色数の超過は注意どまり",
            {
                "version": 1,
                "legend": {c: "c" + c for c in "abcdefghijklm"},
                "sprites": {"hero": {"frames": {"idle": ["abcdefghijklm"]}}},
            },
            [],
            ["色数"],
        ),
        (
            "除外記法 (規則指定)",
            doc_of(
                {
                    "frames": {"idle": ["ii...", "ii..s", ".....", "....."]},
                    "lint-sprite": "対象外(orphan) — 火の粉は浮かせたい",
                }
            ),
            [],
            [],
        ),
        (
            "除外記法 (全規則・ファイル単位)",
            doc_of(
                {"frames": {"idle": ["ii", "i"]}},
                extra={"lint-sprite": "対象外 — 移行中の下書き"},
            ),
            [],
            [],
        ),
    ]

    failures = []
    for title, doc, want_ng, want_warn in cases:
        got_p, got_w, _, _ = check_doc(doc, None)
        for needle in want_ng:
            if not any(needle in line for line in got_p):
                failures.append(f"{title}: NG に「{needle}」が出ない (実際: {got_p})")
        for needle in want_warn:
            if not any(needle in line for line in got_w):
                failures.append(f"{title}: 注意に「{needle}」が出ない (実際: {got_w})")
        if not want_ng and got_p:
            failures.append(f"{title}: NG が出ないはずが {got_p}")
        if not want_warn and got_w and "除外" not in title and "テクスチャ" not in title:
            failures.append(f"{title}: 注意が出ないはずが {got_w}")

    if delta_e("#000000", "#ffffff") < 90:
        failures.append("ΔE: 黒と白が近すぎる判定になっている")
    if delta_e("#804030", "#814131") > DELTA_E_MIN:
        failures.append("ΔE: ほぼ同じ 2 色が遠い判定になっている")

    if failures:
        for line in failures:
            print(line, file=sys.stderr)
        print(f"self-test NG: {len(failures)} 件", file=sys.stderr)
        return 1
    print(f"self-test OK: {len(cases)} 例")
    return 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    strict = "--strict" in argv
    paths = [a for a in argv if not a.startswith("--")]
    return run(paths, strict)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
