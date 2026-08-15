#!/usr/bin/env python3
"""読み込みの途中で `bug!` して呼ぶ側から選ぶ機会を奪う書き方を止める検査。

docs/error-handling.md の決まり 2 を機械で裁く。規則は 1 本だけ:

  **`*OrBug` という名前の関数の中を除いて、関数の中で `bug!` を呼んではいけない。**

`*OrBug` は「起動時に loud に止める」を呼ぶ側が選んだラッパなので正しい。
それ以外の場所の `bug!` は、`Result` を返して呼ぶ側に決めさせるべき所で
勝手に落としている疑いがある。

**判定に doc コメントを使わない。** 「この関数は失敗したら panic させる方針」と
書いてあっても正当化にならない (そう書けば何でも通り、決まりが違反を裁けなくなる)。
名前の形だけで決める。

いま残っている `bug!` は下の EXEMPT に理由付きで載せる。理由を 1 行書かないと
載せられない形にしてあり、この一覧がそのまま残りの宿題の一覧になる。

  python3 bin/lint-fallback.py           # ステージした差分の + 行だけ (コミット時と同じ)
  python3 bin/lint-fallback.py --all     # 対象パッケージの src 配下ぜんぶ
  python3 bin/lint-fallback.py a.flix    # 指定ファイルだけ
  python3 bin/lint-fallback.py --self-test

標準ライブラリだけで動く (Windows / macOS / Linux 共通)。
"""

import re
import subprocess
import sys
from pathlib import Path

for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent

# 検査する範囲。examples / templates / test は対象外 (お手本でなく実験台なので)。
SRC_ROOTS = [
    "engine/src",
    "engine_world/src",
    "render_gl/src",
    "engine_tools/src",
]

# 残すと決めた `bug!` の一覧。鍵は "パス::関数名"、値は残す理由 (1 行必須)。
# 行番号でなく関数名で持つのは、上の行が増減しても鍵がずれないため。
#
#   正当 B … プログラマが書いた前提が破れた所。到達不能な分岐・自分が直前に
#            作った値の破れ・Flix の型と *.schema.json の食い違い
#   正当 C … アセット・起動要件が無い/壊れている所。遊ぶ前に必ず出るので
#            リリース前に確実に気づける。fail-open で「絵が出ない音が鳴らない
#            まま完成したことにする」方が悪い
EXEMPT = {
    # ── 正当 B: 前提が破れた ────────────────────────────────
    "engine_world/src/Fx.flix::curveIntegral":
        "正当 B: flicker / pulse は速度カーブに使えないと FxDoc.parse が先に弾く到達不能な分岐",
    "engine_world/src/Render.flix::atCenter":
        "正当 B: Poly は at がそのまま中心なので呼び出し規約違反 (呼ぶ側のコードの誤り)",
    "engine_world/src/Render.flix::scaled":
        "正当 B: onLeaf が Clipped を剥がすので Clipped はここへ届かない到達不能な分岐",
    "engine_world/src/Render.flix::raiseZ":
        "正当 B: onLeaf が Clipped を剥がすので Clipped はここへ届かない到達不能な分岐",
    "engine_world/src/Render.flix::toDrawables":
        "正当 B: Poly は Drawable にならず draw が PolygonRenderCmd へ振り分ける — 届いたら振り分けの誤り",
    "engine_world/src/Render.flix::spriteDrawable":
        "正当 B: region atlas は未対応で呼ぶ側が regionRect=None を渡す規約 (未実装の明示)",
    "engine_world/src/CatalogContainer.flix::loadWithCheck":
        "正当 B: Flix の型と *.schema.json の食い違いはコード側の誤り",
    "engine_world/src/HitDoc.flix::checkGaps":
        "正当 A の一部: loadOrBug からしか呼ばれない下請けで、止める判断は loadOrBug が済ませている",
    "render_gl/src/Shader.flix::compileShader":
        "正当 B: 同梱の GLSL がコンパイルできないのはコード側の誤り",
    "render_gl/src/Shader.flix::createShaderProgram":
        "正当 B: 同梱の GLSL がリンクできないのはコード側の誤り",
    "render_gl/src/Font.flix::bakeFontCpu":
        "正当 B: 全グリフが焼き込みサイズに収まらないのはフォント設定の誤りで、字が黙って欠ける方が悪い",
    "render_gl/src/LwjglLayer.flix::withLwjgl":
        "正当 C: GLFW / OpenAL の初期化に失敗した先に描く物も鳴らす物も無い (起動要件)",
    # ── 正当 C: アセットが無い・壊れているので起動時に止める ──
    "render_gl/src/Audio.flix::loadOggToALBuffer":
        "正当 C: 同梱の OGG が壊れているのはビルドの誤り。リリース前に確実に気づける方を選ぶ",
    "render_gl/src/Audio.flix::loadWavToALBuffer":
        "正当 C: 同梱の WAV が壊れているのはビルドの誤り。リリース前に確実に気づける方を選ぶ",
    "render_gl/src/Texture.flix::loadTexture":
        "正当 C: 同梱の画像が読めないのはビルドの誤り。リリース前に確実に気づける方を選ぶ",
    "engine/src/render/drawable/Sprite.flix::toDrawable":
        "正当 C: 未登録テクスチャは配線漏れ。黙って透明になるより止める方が気づける",
    "render_gl/src/LwjglLayer.flix::withProject":
        "正当 C: project.json は起動時の必須入力 (決まり 1 の loadOrBug 相当。名前が *OrBug でないのが宿題)",
}

BUG = re.compile(r"\bbug!")
DEF = re.compile(r"^\s*(?:pub\s+)?def\s+([a-zA-Z][A-Za-z0-9_]*)")
# 文字列リテラルの中の bug! は呼び出しではない (メッセージ本文・テストの期待値)。
STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"')


def in_scope(path):
    p = path.replace("\\", "/")
    if not p.endswith(".flix"):
        return False
    return any(p.startswith(root + "/") for root in SRC_ROOTS)


# ---------------------------------------------------------------- Flix を読む

def strip_comments(line):
    """`//` から後ろを落とす。文字列リテラルの中の // は落とさない。"""
    out, i, quote = [], 0, False
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                out.append(line[i:i + 2])
                i += 2
                continue
            if ch == '"':
                quote = False
            out.append(ch)
        else:
            if ch == '"':
                quote = True
                out.append(ch)
            elif ch == "/" and line[i + 1:i + 2] == "/":
                break
            else:
                out.append(ch)
        i += 1
    return "".join(out)


class Hit:
    def __init__(self, path, lineno, func, excerpt):
        self.path, self.lineno, self.func, self.excerpt = path, lineno, func, excerpt

    @property
    def key(self):
        return f"{self.path}::{self.func}"


def scan(path, lines):
    """(行番号, 囲んでいる関数名) で `bug!` の呼び出しを拾う。

    囲む def はインデントの深さで決める。Java の匿名クラス (`new ...I { def invoke ... }`)
    のように def は入れ子になるので、最後に見た def を覚えるだけでは、入れ子から
    出た後の行まで内側の def の物として数えてしまう。"""
    hits, stack = [], []
    for lineno, raw in enumerate(lines, start=1):
        code = strip_comments(raw)
        if not code.strip():
            continue
        indent = len(code) - len(code.lstrip())
        m = DEF.match(code)
        if m:
            while stack and stack[-1][0] >= indent:
                stack.pop()
            stack.append((indent, m.group(1)))
        elif BUG.search(STRING.sub('""', code)):
            while stack and stack[-1][0] >= indent:
                stack.pop()
        if BUG.search(STRING.sub('""', code)):
            func = stack[-1][1] if stack else "?"
            hits.append(Hit(path, lineno, func, code.strip()[:78]))
    return hits


def violations(hits):
    """`*OrBug` の中でも EXEMPT でもない `bug!` だけを残す。"""
    return [h for h in hits if not h.func.endswith("OrBug") and h.key not in EXEMPT]


# ---------------------------------------------------------------- 入力の口

def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args],
                          capture_output=True, text=True, check=True).stdout


def read_file(path):
    full = Path(path)
    if not full.is_file():
        full = ROOT / path
    if not full.is_file():
        return None
    return full.read_text(encoding="utf-8", errors="replace").splitlines()


def file_hits(paths):
    hits = []
    for p in paths:
        rel = p.replace("\\", "/")
        lines = read_file(rel)
        if lines is None:
            continue
        hits.extend(scan(rel, lines))
    return hits


def all_paths():
    # git に入っていない新しいファイルも見る。コミット時は staged 経路が拾うが、
    # 手で make lint-fallback を打つ人は「まだ add していない書きかけ」を見たい。
    tracked = git("ls-files", "-z").split("\0")
    untracked = git("ls-files", "-z", "-o", "--exclude-standard").split("\0")
    return sorted({p for p in tracked + untracked if p and in_scope(p)})


def staged_hits():
    """新しく書いた行だけを見る。関数名を知るためにステージ後の全文を読み、
    差分で足された行番号と突き合わせる (差分の + 行だけでは囲む def が見えない)。"""
    diff = git("diff", "--cached", "-U0", "--diff-filter=ACMR")
    added = {}
    path, lineno = None, 0
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            path = line[6:]
            continue
        if line.startswith("@@"):
            m = re.search(r"\+(\d+)", line)
            lineno = int(m.group(1)) if m else 0
            continue
        if path and in_scope(path) and line.startswith("+") and not line.startswith("+++"):
            added.setdefault(path, set()).add(lineno)
            lineno += 1
    hits = []
    for p, linenos in added.items():
        body = subprocess.run(["git", "-C", str(ROOT), "show", f":{p}"],
                              capture_output=True, text=True)
        if body.returncode != 0:
            continue
        hits.extend(h for h in scan(p, body.stdout.splitlines())
                    if h.lineno in linenos)
    return hits


# ---------------------------------------------------------------- 出力

def report(bad, total, show_exempt, stale=()):
    if show_exempt:
        for key in sorted(EXEMPT):
            print(f"除外: {key} — {EXEMPT[key]}")
    if stale:
        for key in stale:
            print(f"  {key} は EXEMPT に載っていますが、そこに bug! はもうありません")
        print(f"[lint-fallback] 古い除外 {len(stale)} 件。"
              "宿題の一覧として読めなくなるので EXEMPT から消してください")
        return 1
    if not bad:
        print(f"[lint-fallback] OK (bug! {total} 件を検査 / 除外 {len(EXEMPT)} 件)")
        return 0
    for h in bad:
        print(f"  {h.path}:{h.lineno}: {h.func} の中で bug! を呼んでいます")
        print(f"      {h.excerpt}")
    print(f"[lint-fallback] 決まり 2 違反 {len(bad)} 件 (docs/error-handling.md)。"
          "\n  読み込みなら load* にして Err を返し、止めると決めた所なら"
          " *OrBug という名前のラッパへ移してください。"
          "\n  どうしても残すなら bin/lint-fallback.py の EXEMPT へ"
          " \"パス::関数名\" と理由 1 行を書いてください")
    return 1


# ---------------------------------------------------------------- 自己検査

SAMPLE = """
mod Demo {
    pub def loadThing(path: String): Result[String, String] = Ok(path)

    /// 失敗したら bug! で止める方針です (この doc コメントは正当化にならない)
    pub def getThing(path: String): String =
        match loadThing(path) {
            case Ok(v)  => v
            case Err(_) => bug!("getThing: ${path}")
        }

    pub def loadThingOrBug(path: String): String =
        match loadThing(path) {
            case Ok(v)  => v
            case Err(e) => bug!("thing: ${e}")
        }

    // ここは bug! と書いてあるだけのコメント
    pub def quiet(): String = "bug! と書いた文字列"
}
"""


def self_test():
    hits = scan("x.flix", SAMPLE.splitlines())
    funcs = sorted(h.func for h in hits)
    assert funcs == ["getThing", "loadThingOrBug"], funcs
    bad = violations(hits)
    assert [h.func for h in bad] == ["getThing"], bad
    assert strip_comments('let s = "a // b" // c') == 'let s = "a // b" '
    assert in_scope("engine/src/App.flix")
    assert not in_scope("engine/test/TestApp.flix")
    assert not in_scope("templates/x/src/Game.flix")
    assert not in_scope("examples/x/src/Game.flix")
    for key in EXEMPT:
        assert "::" in key and EXEMPT[key].strip(), key
    print(f"[lint-fallback] self-test OK (除外 {len(EXEMPT)} 件はすべて理由付き)")
    return 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    files = [a for a in argv if not a.startswith("--")]
    stale = ()
    if files:
        hits = file_hits(files)
        show_exempt = False
    elif "--all" in argv:
        hits = file_hits(all_paths())
        show_exempt = True
        # 全量のときだけ、消えた bug! の除外が残っていないかも見る
        # (差分やファイル指定では全体が見えないので判定できない)
        live = {h.key for h in hits}
        stale = sorted(set(EXEMPT) - live)
    else:
        hits = staged_hits()
        show_exempt = False
    return report(violations(hits), len(hits), show_exempt, stale)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
