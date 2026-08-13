#!/usr/bin/env python3
"""エンジンの公開 API に `Float32` が出ていないかを検査する。

規則は 1 本だけ:

  **engine / engine_world / engine_tools の pub 面（型・関数・eff の op）に
  `Float32` を出さない。Float32 は GL / OpenAL / STB の境界の内側だけ。**

Flix のデフォルトの小数は Float64 で、Float32 のリテラルには `f32` サフィックスが要る。
pub 面に Float32 が混ざっていると、ゲームを書く側は型が合わないコンパイルエラーで
初めてそれに気づき、`f32` を足して再コンパイルする往復を強いられる。
境界の内側（`render_gl` の GL 呼び出しなど）は検査の対象外で、そこは Float32 のままでよい。

判定は `bin/gen-api-digest.py` の宣言抽出をそのまま借りる。二重管理しないためと、
`pub type alias GradVertex = { ..., alpha = Float32 }` のような複数行の宣言や、
`pub` の付かない eff の op（`pub eff Audio { def setVolume(...) }`）を
自前の正規表現で解き直さないため。

残すと決めた Float32 は下の EXEMPT に理由付きで載せる。理由を 1 行書かないと
載せられない形にしてあり、この一覧がそのまま残りの宿題の一覧になる。

  python3 bin/lint-f32.py            # pub 面ぜんぶを検査
  python3 bin/lint-f32.py --check    # 同じ (make check-docs-sync 等から呼ぶとき用)
  python3 bin/lint-f32.py --self-test

標準ライブラリだけで動く (Windows / macOS / Linux 共通)。
"""

import importlib.util
import re
import sys
from pathlib import Path

for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent

# 残すと決めた Float32 の一覧。鍵は "モジュール名.宣言名"、値は残す理由 (1 行必須)。
# 行番号でなくモジュールと名前で持つのは、上の行が増減しても鍵がずれないため。
EXEMPT = {
    "RenderUtil.f32":
        "Float64 → Float32 の変換そのもの。GL の uniform へ渡す境界の入り口で、"
        "ここが Float32 を返さないと境界の内側が書けない",
}


def load_digest_module():
    """bin/gen-api-digest.py を読み込む。ファイル名にハイフンが入っていて
    `import` では書けないので importlib で読む。"""
    path = ROOT / "bin" / "gen-api-digest.py"
    spec = importlib.util.spec_from_file_location("gen_api_digest", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


DIGEST = load_digest_module()

F32 = re.compile(r"\bFloat32\b")
DEF_NAME = re.compile(r"^pub\s+def\s+([A-Za-z][A-Za-z0-9_]*)")
TYPE_NAME = re.compile(r"^pub\s+(?:enum|type\s+alias)\s+([A-Za-z][A-Za-z0-9_]*)")
EFF_OP_NAME = re.compile(
    r"^pub\s+eff\s+([A-Za-z][A-Za-z0-9_]*)\s*\{\s*def\s+([A-Za-z][A-Za-z0-9_]*)"
)
EFF_NAME = re.compile(r"^pub\s+eff\s+([A-Za-z][A-Za-z0-9_]*)")


def decl_name(decl):
    """宣言 1 行から名前を取る。eff の op は "Audio.setVolume" の形で返す。"""
    m = EFF_OP_NAME.match(decl)
    if m:
        return "{}.{}".format(m.group(1), m.group(2))
    for pattern in (DEF_NAME, TYPE_NAME, EFF_NAME):
        m = pattern.match(decl)
        if m:
            return m.group(1)
    return "?"


class Hit:
    def __init__(self, path, mod, name, decl):
        self.path, self.mod, self.name, self.decl = path, mod, name, decl

    @property
    def key(self):
        return "{}.{}".format(self.mod, self.name)


def scan_source(path, rel):
    hits = []
    for mod, decls in DIGEST.scan_file(path).items():
        for _doc, decl in decls:
            if F32.search(decl):
                hits.append(Hit(rel, mod, decl_name(decl), decl))
    return hits


def all_hits():
    hits = []
    for _pkg_name, pkg_root in DIGEST.PACKAGES:
        root = ROOT / pkg_root
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.flix")):
            hits.extend(scan_source(path, path.relative_to(ROOT).as_posix()))
    return hits


def report(hits):
    for key in sorted(EXEMPT):
        print(f"除外: {key} — {EXEMPT[key]}")
    bad = [h for h in hits if h.key not in EXEMPT]
    live = {h.key for h in hits}
    stale = sorted(set(EXEMPT) - live)
    if stale:
        for key in stale:
            print(f"  {key} は EXEMPT に載っていますが、そこに Float32 はもうありません")
        print(f"[lint-f32] 古い除外 {len(stale)} 件。"
              "宿題の一覧として読めなくなるので EXEMPT から消してください")
        return 1
    if not bad:
        print(f"[lint-f32] OK (pub 面の Float32 {len(hits)} 件 / 除外 {len(EXEMPT)} 件)")
        return 0
    for h in bad:
        print(f"  {h.path}: {h.mod}.{h.name} の pub 面に Float32 があります")
        print(f"      {h.decl[:110]}")
    print(f"[lint-f32] pub 面の Float32 {len(bad)} 件。"
          "\n  ゲームを書く側は Float64 と Int32 だけで済むのが決まりです。"
          "型を Float64 にして、Float32 への変換は GL / OpenAL / STB を呼ぶ手前まで下げてください"
          "\n  どうしても残すなら bin/lint-f32.py の EXEMPT へ"
          " \"モジュール名.宣言名\" と理由 1 行を書いてください")
    return 1


# ---------------------------------------------------------------- 自己検査

SAMPLE = """
mod Demo {
    /// GL へ渡す値
    pub type alias GradVertex = {
        at = Vec2.Vec2,
        alpha = Float32
    }

    pub def clean(v: Float64): Float64 = v

    pub eff Audio {
        /// 音量
        def setVolume(name: String, volume: Float32): Unit
        def stopAudio(name: String): Unit
    }

    // Float32 とコメントに書いただけ
    pub def quiet(): String = "Float32"
}
"""


def self_test():
    tmp = ROOT / "build" / "lint-f32-self-test.flix"
    tmp.parent.mkdir(parents=True, exist_ok=True)
    tmp.write_text(SAMPLE, encoding="utf-8")
    try:
        hits = scan_source(tmp, "self-test.flix")
    finally:
        tmp.unlink()
    keys = sorted(h.key for h in hits)
    assert keys == ["Demo.Audio.setVolume", "Demo.GradVertex"], keys
    for key in EXEMPT:
        assert "." in key and EXEMPT[key].strip(), key
    print(f"[lint-f32] self-test OK "
          f"(複数行の type alias と eff の op を拾う / 除外 {len(EXEMPT)} 件はすべて理由付き)")
    return 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    return report(all_hits())


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
