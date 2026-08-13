#!/usr/bin/env python3
"""ui.json の text が「折り返し宣言の漏れ」ではみ出さないかを機械で確かめる (標準ライブラリのみ)。

  python3 bin/lint-ui-overflow.py                 # templates/ の *.ui.json を全部
  python3 bin/lint-ui-overflow.py a.ui.json       # 指定ファイルだけ
  python3 bin/lint-ui-overflow.py --strict        # 注意も NG に上げる
  python3 bin/lint-ui-overflow.py --self-test     # この lint 自身の検査

見るのは **構造** だけ (フォントの実寸は読まない — 実行時に流し込まれる文字は静的に測れない):

  固定幅の枠に入った text ウィジェットが wrap も fit も宣言していない → 注意。
  長い文言が来た瞬間に枠からはみ出す形になっている、という宣言漏れの検出。

「固定幅」の判定 (誤爆より見逃す側を選ぶ):
  - text ノード自身か、その親をたどった先に width が数値 (px) のノードがある → 固定幅
  - 途中の "grow" は素通しして更に上を見る (grow の実寸は親で決まるため)
  - width 未指定・"auto" に当たったらそこで打ち切り → 対象外
    (auto は中身の実寸から枠が決まる auto-size で、構造上はみ出せない)

宣言と認める物 (パーサの正 engine_world/src/UiDoc.flix と同じ読み方):
  - "wrap": "auto" か正の数値 (px)。**真偽値の wrap はコンテナの flex wrap で別物** — 数えない
  - "fit": true

見えない物 (この lint の限界):
  - コードから直組みした Text (ui.json を経由しない直呼び) は見えない。
    そちらは Text.measure での採寸 (visual-dict の作法) と目視でカバーする
  - "instance" で別ファイルを合成するノードは対象外 (合成は UiDoc が唯一のパーサで、
    Python 側では追わない)。参照先のファイル自体は個別に検査される
  - RichText 経路 (UiDialog 本文) は maxWidth 必須の別配線なので対象外

除外は該当ノード (またはファイルの最上位) に理由付きで書く。黙って除外はしない:
  "lint-ui": "対象外 — スコア表示は桁固定"
"""

import json
import os
import sys

for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

LIMITS_NOTE = (
    "※ この lint は ui.json の構造だけを見る。コードから直組みした Text と"
    " instance 参照ノードは見えない (詳細は bin/lint-ui-overflow.py の冒頭)"
)


def is_excluded(node):
    """"lint-ui": "対象外 — 理由" が書いてあるか。理由の無い文字列では除外しない。"""
    text = node.get("lint-ui")
    return isinstance(text, str) and "対象外" in text


def width_kind(node):
    """width の種類: "px" (数値) / "grow" / "auto" (未指定・"auto"・読めない形)。"""
    value = node.get("width")
    if isinstance(value, bool):
        return "auto"
    if isinstance(value, (int, float)):
        return "px"
    if value == "grow":
        return "grow"
    return "auto"


def has_wrap_decl(node):
    """text の折り返し宣言があるか。真偽値の wrap は flex wrap (別物) なので数えない。"""
    wrap = node.get("wrap")
    if isinstance(wrap, str) and wrap == "auto":
        return True
    if not isinstance(wrap, bool) and isinstance(wrap, (int, float)) and wrap > 0:
        return True
    return node.get("fit") is True


def fixed_width_of(self_node, ancestors):
    """text の枠を決める固定幅。固定でなければ None。

    自分の width が px ならそれ。auto/grow なら枠は親で決まるので親をたどる:
    px で確定、grow は更に上へ、auto (auto-size = 中身で枠が決まる) で打ち切り対象外。
    """
    if width_kind(self_node) == "px":
        return self_node.get("width")
    for node in ancestors:
        kind = width_kind(node)
        if kind == "px":
            return node.get("width")
        if kind == "auto":
            return None
        # "grow" は親の寸法で決まるので更に上を見る
    return None


def resolve_use(templates, node):
    """"use" のテンプレ値の上にノード値を重ねる (ノード勝ち。UiDoc.resolveTemplate と同じ)。"""
    tmap = templates.get(node.get("use"))
    if not isinstance(tmap, dict):
        return node
    merged = dict(tmap)
    merged.update(node)
    return merged


def walk(templates, node, path, ancestors, notes, stats):
    if not isinstance(node, dict):
        return
    if "instance" in node:
        stats["instances"] += 1
        return
    merged = resolve_use(templates, node)
    name = merged.get("name") if isinstance(merged.get("name"), str) else "(無名)"
    here = f"{path}/{name}" if path else name
    if is_excluded(merged):
        return
    if merged.get("widget") == "text" and not has_wrap_decl(merged):
        width = fixed_width_of(merged, ancestors)
        if width is not None:
            notes.append(
                f"{here}: 固定幅 {width:g}px の枠内の text が wrap も fit も宣言していない "
                "— 長い文言が来るとはみ出す。折るなら \"wrap\": \"auto\"、"
                "意図的な 1 行固定なら \"lint-ui\": \"対象外 — 理由\" を書く"
            )
    children = merged.get("children")
    if isinstance(children, list):
        for child in children:
            walk(templates, child, here, [merged] + ancestors, notes, stats)


def check_doc(doc, stats):
    """パース済み ui.json 1 つ分の注意一覧。"""
    notes = []
    if not isinstance(doc, dict) or is_excluded(doc):
        return notes
    templates = doc.get("templates")
    if not isinstance(templates, dict):
        templates = {}
    walk(templates, doc.get("root"), "", [], notes, stats)
    return notes


def check_file(path, stats):
    try:
        with open(path, encoding="utf-8") as handle:
            doc = json.load(handle)
    except (OSError, json.JSONDecodeError) as err:
        return [f"(読めない JSON: {err})"]
    return check_doc(doc, stats)


def _self_test():
    ok = []

    def case(name, doc, needle=None):
        notes = check_doc(doc, {"instances": 0})
        hit = any(needle in n for n in notes) if needle else not notes
        ok.append(("OK  " if hit else "NG  ") + name + ("" if hit else f": {notes}"))

    def rooted(root):
        return {"version": 1, "root": root}

    text = {"name": "label", "widget": "text", "text": "ながいながい文言"}

    case(
        "固定幅パネル内の宣言なし text は注意",
        rooted({"name": "panel", "width": 120, "children": [dict(text)]}),
        "宣言していない",
    )
    case(
        "wrap: \"auto\" 宣言があれば合格",
        rooted({"name": "panel", "width": 120,
                "children": [dict(text, wrap="auto")]}),
    )
    case(
        "wrap: 数値(px) 宣言があれば合格",
        rooted({"name": "panel", "width": 120,
                "children": [dict(text, wrap=96)]}),
    )
    case(
        "fit: true 宣言があれば合格",
        rooted({"name": "panel", "width": 120,
                "children": [dict(text, fit=True)]}),
    )
    case(
        "真偽値 wrap は flex wrap で別物 — 宣言と数えず注意",
        rooted({"name": "panel", "width": 120,
                "children": [dict(text, wrap=True)]}),
        "宣言していない",
    )
    case(
        "auto-size の枠 (width 未指定) は構造上はみ出せないので対象外",
        rooted({"name": "panel", "children": [dict(text)]}),
    )
    case(
        "grow は素通しして更に上の固定幅を見る",
        rooted({"name": "outer", "width": 200,
                "children": [{"name": "inner", "width": "grow",
                              "children": [dict(text)]}]}),
        "固定幅 200px",
    )
    case(
        "grow の上が auto なら見逃す側を選んで対象外",
        rooted({"name": "outer",
                "children": [{"name": "inner", "width": "grow",
                              "children": [dict(text)]}]}),
    )
    case(
        "text 自身の固定幅も枠として見る",
        rooted({"name": "panel", "children": [dict(text, width=80)]}),
        "固定幅 80px",
    )
    case(
        "理由付き lint-ui 宣言で除外できる",
        rooted({"name": "panel", "width": 120,
                "children": [dict(text, **{"lint-ui": "対象外 — スコア表示は桁固定"})]}),
    )
    case(
        "instance ノードは対象外 (UiDoc が唯一のパーサ)",
        rooted({"name": "panel", "width": 120,
                "children": [{"name": "sub", "instance": "assets/ui/sub.ui.json"}]}),
    )
    case(
        "use テンプレの width もノードに重ねて見る",
        {"version": 1,
         "templates": {"fixed": {"width": 150}},
         "root": {"name": "panel", "use": "fixed", "children": [dict(text)]}},
        "固定幅 150px",
    )

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
                if n.endswith(".ui.json")
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
    stats = {"instances": 0}
    for path in targets:
        notes = check_file(path, stats)
        if notes:
            print(f"\n{os.path.relpath(path, root)}")
            for note in notes:
                print(f"  {'NG' if strict else '注意'}: {note}")
            total += len(notes)
    label = "NG" if strict else "注意"
    print(f"\n{len(targets)} ファイル / {label} {total} 件")
    if stats["instances"]:
        print(f"(instance 参照ノード {stats['instances']} 件は対象外)")
    print(LIMITS_NOTE)
    return 1 if (strict and total) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
