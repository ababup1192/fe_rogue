#!/usr/bin/env python3
"""ドット絵 (*.sprite.json) の legend の意味色キーが Studio から解けるか検査するゲート。

Studio (flix_ge_studio) の SpriteColors が legend の値を実色に解く道は 3 本しかない:
  (a) プロジェクト内の *.theme.json のトップレベル (または "colors" の下) の名前
  (b) sprite Doc の "paletteFile" が指す JSON のキー
  (c) sprite Doc 直下の inline "palette" のキー
値そのものが色表記 ("#rrggbb") なら表引き無しで解ける。
どれにも当たらない名前は Studio が仮色で塗るので、編集画面と実機で配色が食い違う。

使い方: python3 bin/lint-palette.py [ルート]   (既定のルートはこのファイルの親の親)
解けない名前が 1 つでもあれば 1 行ずつ挙げて終了コード 1。
"""

import json
import os
import sys

# Studio の FileIndex.excludedDirs と同じ。build/ は数十万ファイルに膨れるので降りない。
EXCLUDED_DIRS = {"build", "lib", ".git", "gallery", ".devbox", "node_modules"}

# 色 1 つを object に包んで書く欄の名前 (Studio の colorWrapKeys と同じ)。
COLOR_WRAP_KEYS = ("hex", "color", "value")

GAME_ROOTS = ("templates",)


def is_hex_color(text):
    """"#rrggbb" / "rrggbb" (大文字可) か。Studio の normalizeHex と同じ判定。"""
    body = text[1:] if text.startswith("#") else text
    return len(body) == 6 and all(c in "0123456789abcdefABCDEF" for c in body)


def is_floats3(value):
    return (
        isinstance(value, list)
        and len(value) == 3
        and all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in value)
    )


def is_color(value):
    """色として読める値か (Studio の colorHexOf と同じ方言: 文字列 / hsv / rgb / 包み)。"""
    if isinstance(value, str):
        return is_hex_color(value)
    if isinstance(value, dict):
        has_hsv, has_rgb = "hsv" in value, "rgb" in value
        if has_hsv and not has_rgb:
            return is_floats3(value["hsv"])
        if has_rgb and not has_hsv:
            return is_floats3(value["rgb"])
        return any(k in value and is_color(value[k]) for k in COLOR_WRAP_KEYS)
    return False


def read_json(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def walk_json(game_dir):
    """game_dir 配下の .json を game_dir 相対で集める (除外ディレクトリには降りない)。"""
    found = []
    for current, dirs, files in os.walk(game_dir):
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDED_DIRS)
        for name in sorted(files):
            if name.endswith(".json"):
                found.append(os.path.relpath(os.path.join(current, name), game_dir))
    return sorted(found)


def color_names_of(obj):
    """object の直下と "colors" の下から、色として読める名前を集める。"""
    if not isinstance(obj, dict):
        return set()
    names = {name for name, value in obj.items() if is_color(value)}
    nested = obj.get("colors")
    if isinstance(nested, dict):
        names |= {name for name, value in nested.items() if is_color(value)}
    return names


def theme_names_of(game_dir, json_paths):
    """プロジェクト内の全 *.theme.json が宣言している色名。"""
    names = set()
    for rel in json_paths:
        if rel.endswith(".theme.json"):
            names |= color_names_of(read_json(os.path.join(game_dir, rel)))
    return names


def palette_names_of(game_dir, doc):
    """sprite Doc の paletteFile (プロジェクト直下起点) と inline palette の色名。"""
    names = set()
    ref = doc.get("paletteFile")
    if isinstance(ref, str):
        names |= color_names_of(read_json(os.path.join(game_dir, ref)))
    names |= color_names_of(doc.get("palette"))
    return names


def unresolved_of(doc, names):
    """(legend の文字, 値) のうち解けない物。値が色表記ならそのまま解ける。"""
    legend = doc.get("legend")
    if not isinstance(legend, dict):
        return []
    bad = []
    for char, value in sorted(legend.items()):
        if not isinstance(value, str):
            continue
        if is_hex_color(value):
            continue
        name = value[1:] if value.startswith("@") else value
        if name not in names:
            bad.append((char, value))
    return bad


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
    # 生成されたゲームには templates/ が無い。空を返すと
    # 「検査したが問題なし」と見分けが付かず、ゲートが何も言わずに通してしまう。
    if not dirs and os.path.isdir(os.path.join(root, "assets")):
        dirs.append(".")
    return dirs


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    problems = []
    doc_count = 0
    key_count = 0

    for game in game_dirs(root):
        game_dir = os.path.join(root, game)
        json_paths = walk_json(game_dir)
        sprite_paths = [p for p in json_paths if p.endswith(".sprite.json")]
        if not sprite_paths:
            continue
        themes = theme_names_of(game_dir, json_paths)
        for rel in sprite_paths:
            doc = read_json(os.path.join(game_dir, rel))
            if not isinstance(doc, dict):
                problems.append(f"{game}/{rel}: JSON として読めない")
                continue
            doc_count += 1
            legend = doc.get("legend")
            if isinstance(legend, dict):
                key_count += len(legend)
            names = themes | palette_names_of(game_dir, doc)
            for char, value in unresolved_of(doc, names):
                problems.append(
                    f"{game}/{rel}: legend '{char}' の \"{value}\" がどの色票にも無い"
                    " (*.theme.json のトップレベル / paletteFile / inline palette)"
                )

    if problems:
        for line in problems:
            print(line)
        print(f"NG: {len(problems)} 個の意味色キーが解けない (sprite Doc {doc_count} 件を検査)")
        return 1
    print(f"OK: sprite Doc {doc_count} 件・legend {key_count} キーすべて色票で解ける")
    return 0


if __name__ == "__main__":
    sys.exit(main())
