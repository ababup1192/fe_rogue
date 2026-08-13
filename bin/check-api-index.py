#!/usr/bin/env python3
"""pub def を持つモジュールが索引 (docs/*-module-index.md) に載っているかを検査する。

pub def を足したときの索引の追記は人任せで漏れる。漏れると「既にある関数」を
AI が見つけられず、再発明や見落としが起きる。人の記憶より前に機械が声を出す。

検査は 2 方向:
  1. engine/src・engine_world/src の pub def を持つモジュールが、対応する索引に
     モジュール名で載っているか（索引はモジュール単位の 1 行紹介なので粒度を合わせる）
  2. 索引が「Mod.関数」の形で挙げている関数が、ソースに pub def として実在するか
     （索引だけ残って実体が消える「幽霊参照」を防ぐ）

  python3 bin/check-api-index.py

標準ライブラリだけで動く（Windows / macOS / Linux 共通）。
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# (ソースの根, 索引ファイル) の対応。索引の粒度はどちらもモジュール単位。
TARGETS = [
    ("engine/src", "docs/engine-module-index.md"),
    ("engine_world/src", "docs/module-index.md"),
]

# 索引に載せないモジュール。黙って除外はしない — 理由を書き、実行時に件数を見せる。
EXEMPT = {
    "BootFontData": "生成物（make boot-font）。索引は BootFont の行が案内する",
}

# legacy/ 配下は新規ゲームに使わせない凍結層。索引には MapResource / Resource の
# 行があり「新規は使うな」と案内済みなので、配下の下請け codec まで行を求めない。
SKIP_DIRS = {"legacy"}

MOD_DECL = re.compile(r"^mod ([A-Za-z][A-Za-z0-9]*(?:\.[A-Za-z][A-Za-z0-9]*)*)", re.M)
PUB_DEF = re.compile(r"^\s*pub def ([a-zA-Z][A-Za-z0-9_]*)", re.M)
# 索引が関数を指す形は「Mod.func」（func は小文字始まり）。大文字始まりは型・ケース参照。
DOC_FUNC_REF = re.compile(r"\b([A-Z][A-Za-z0-9]*)\.([a-z][A-Za-z0-9]*)\b")
# 「App.flix」のようなファイル名参照を関数参照と誤認しないための拡張子。
FILE_EXTS = {"flix", "json", "md", "png", "py", "sh"}


def strip_comments(src: str) -> str:
    """コメント行に書かれた mod 名・pub def を拾わない。"""
    return "\n".join(
        ln for ln in src.splitlines() if not ln.lstrip().startswith("//")
    )


def scan_package(src_root: Path):
    """{トップレベルモジュール名: pub def 名の集合} を返す。"""
    mods = {}
    for path in sorted(src_root.rglob("*.flix")):
        if SKIP_DIRS.intersection(p.name for p in path.parents):
            continue
        try:
            body = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
        except OSError:
            continue
        decls = MOD_DECL.findall(body)
        if not decls:
            continue
        # 1 ファイル複数 mod でも、索引の粒度（トップレベル名）にまとめて数える。
        top = decls[0].split(".")[0]
        defs = set(PUB_DEF.findall(body))
        if defs:
            mods.setdefault(top, set()).update(defs)
    return mods


def word_in(name: str, text: str) -> bool:
    return re.search(r"\b" + re.escape(name) + r"\b", text) is not None


def main():
    problems = []
    exempted = []
    all_defs = {}  # モジュール名 → pub def 集合（全パッケージ横断・幽霊参照の照合用）

    scanned = []
    for src_rel, doc_rel in TARGETS:
        mods = scan_package(ROOT / src_rel)
        for name, defs in mods.items():
            all_defs.setdefault(name, set()).update(defs)
        scanned.append((src_rel, doc_rel, mods))

    # 幽霊参照の照合には描き出し側 (engine_tools) の pub def も混ぜる。
    # 索引が HeadlessRender 等を案内しており、実在確認だけはここでもできるため。
    for name, defs in scan_package(ROOT / "engine_tools/src").items():
        all_defs.setdefault(name, set()).update(defs)

    for src_rel, doc_rel, mods in scanned:
        doc_path = ROOT / doc_rel
        try:
            doc = doc_path.read_text(encoding="utf-8")
        except OSError:
            print("読めません: {}".format(doc_rel), file=sys.stderr)
            return 1

        # 1. モジュールが索引に載っているか。
        for name in sorted(mods):
            if name in EXEMPT:
                exempted.append((name, EXEMPT[name]))
                continue
            if not word_in(name, doc):
                problems.append(
                    "{}: モジュール {}（{} 配下・pub def {} 本）が載っていません".format(
                        doc_rel, name, src_rel, len(mods[name])
                    )
                )

        # 2. 索引の「Mod.関数」参照が実在するか。
        for mod_name, func in sorted(set(DOC_FUNC_REF.findall(doc))):
            if func in FILE_EXTS:
                continue
            if mod_name not in all_defs:
                continue  # 標準ライブラリや別リポのモジュールは照合しない
            if func not in all_defs[mod_name]:
                problems.append(
                    "{}: {}.{} は pub def に見つかりません（改名か削除の可能性）".format(
                        doc_rel, mod_name, func
                    )
                )

    for name, reason in exempted:
        print("除外: {} — {}".format(name, reason))

    if not problems:
        print("OK: 索引とソースの pub def はそろっています（除外 {} 件）".format(len(exempted)))
        return 0

    for p in problems:
        print(p, file=sys.stderr)
    print("", file=sys.stderr)
    print(
        "モジュールを足したら docs/module-index.md（engine_world）か\n"
        "docs/engine-module-index.md（engine）に 1 行足してください。\n"
        "内部専用なら bin/check-api-index.py の EXEMPT に理由付きで載せてください。",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
