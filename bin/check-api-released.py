#!/usr/bin/env python3
"""api-digest に載っているのに、リリース済みの版には入っていない宣言を挙げる。

なぜ要るか（2026-08-14 に実際に起きたこと）:

  docs/api-digest は**作業ツリーの src/ から**作る。だから、まだリリースしていない
  変更を足した直後は「digest には載っているが、ゲームが引く fpkg には無い」宣言が
  できる。ゲーム側は flix.toml で `version = "0.24.0"` を固定して GitHub Release の
  fpkg を引くので、digest を信じて書いた `Depth.bands` / `PxSpriteDoc.Loop` が
  コンパイルで落ちた。落ちた側は原因が分からないので自前実装に逃げる。

  つまり `make api` は「この関数はある」と嘘をつける。嘘をつけること自体は digest を
  作業ツリーから作る以上どうしようもないので、**嘘を見えるようにする**のがこの検査。

やり方は git のタグとの突き合わせだけ:

  リリース = `make release` が打つ v<VERSION> のタグ（release-guard が未コミットを
  拒むので、タグの中身 = 配った fpkg の中身）。作業ツリーの pub 宣言のうち、
  v<VERSION> のソースに無い名前を「未リリース」として挙げる。

  python3 bin/check-api-released.py           # 未リリースの宣言を一覧する
  python3 bin/check-api-released.py <語>      # その語に当たる宣言だけ見る（make api が使う）

タグが取れないとき（浅い clone など）は何も言わずに 0 で終わる — 検査が無い環境で
ビルドを止めない（fail-open）。digest 本体は作業ツリーの姿のままで、この検査の
結果を混ぜない（混ぜると --check の差分ゼロ検査が環境で揺れる）。
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PKGS = ("engine", "engine_world", "engine_tools")
VERSION_RE = re.compile(r"^VERSION\s*:=\s*(\S+)", re.M)

# pub 宣言の名前だけを拾う（gen-api-digest.py と同じ範囲: def / enum / type alias / eff）。
DECL_RE = re.compile(
    r"^\s*pub\s+(?:def|eff|enum|type\s+alias)\s+([A-Za-z_][A-Za-z0-9_]*)", re.M
)
MOD_RE = re.compile(r"^mod\s+([A-Za-z_][A-Za-z0-9_.]*)\s*\{")


def version():
    m = VERSION_RE.search((ROOT / "Makefile").read_text(encoding="utf-8"))
    return m.group(1) if m else None


def git(*args):
    return subprocess.run(
        ["git", "-C", str(ROOT), *args],
        capture_output=True, text=True, check=True,
    ).stdout


def declarations_in_tree():
    """作業ツリーの (モジュール, 名前) の集合。モジュールは `mod X {` の直近の物。"""
    found = {}
    for pkg in PKGS:
        for path in sorted((ROOT / pkg / "src").rglob("*.flix")):
            text = path.read_text(encoding="utf-8", errors="replace")
            for mod, names in per_module(text):
                found.setdefault(mod, set()).update(names)
    return found


def per_module(text):
    """`mod <名前> {` ごとに、その中の pub 宣言の名前を返す。"""
    chunks = re.split(r"^mod\s+([A-Za-z_][A-Za-z0-9_.]*)\s*\{", text, flags=re.M)
    out = []
    for i in range(1, len(chunks), 2):
        out.append((chunks[i], set(DECL_RE.findall(chunks[i + 1]))))
    return out


def declarations_in_release(tag):
    """タグ tag のソースの (モジュール → 名前) の表。タグが無ければ None。

    `make api` は「1 行で速く引く」入口なので、ここは git を 1 回しか呼ばない。
    git grep で「mod の行」と「pub 宣言の行」だけをタグから直接引き、
    ファイルと行番号の順に歩いて、どの宣言がどの mod の中かを組み直す。
    """
    pattern = (
        r"^(mod[[:space:]]+[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*\{"
        r"|[[:space:]]*pub[[:space:]]+(def|eff|enum|type[[:space:]]+alias)[[:space:]])"
    )
    paths = [f"{p}/src" for p in PKGS]
    try:
        hits = git("grep", "-n", "-E", pattern, tag, "--", *paths)
    except subprocess.CalledProcessError as e:
        # 1 = 当たり無し（タグはある）。それ以外はタグが引けない環境。
        return {} if e.returncode == 1 else None

    rows = []
    for line in hits.splitlines():
        # 形は `<tag>:<path>:<lineno>:<本文>`。パスにも本文にも `:` は出るので分割は 3 回だけ。
        parts = line.split(":", 3)
        if len(parts) < 4 or not parts[1].endswith(".flix"):
            continue
        rows.append((parts[1], int(parts[2]), parts[3]))

    found = {}
    current = None
    seen_path = None
    for path, _lineno, text in sorted(rows, key=lambda r: (r[0], r[1])):
        if path != seen_path:
            seen_path = path
            current = None  # mod はファイルをまたがない
        mod = MOD_RE.match(text)
        if mod:
            current = mod.group(1)
            found.setdefault(current, set())
            continue
        decl = DECL_RE.match(text)
        if decl and current is not None:
            found[current].add(decl.group(1))
    return found


def main():
    needle = sys.argv[1].lower() if len(sys.argv) > 1 else None
    v = version()
    if v is None:
        return 0
    tag = f"v{v}"
    released = declarations_in_release(tag)
    if released is None:
        return 0  # タグが引けない環境では黙る

    rows = []
    for mod, names in sorted(declarations_in_tree().items()):
        missing = sorted(names - released.get(mod, set()))
        for name in missing:
            if needle is None or needle in name.lower() or needle in mod.lower():
                rows.append(f"{mod}.{name}")

    if not rows:
        return 0
    if needle is None:
        print(f"[api] 未リリース（{tag} の fpkg に無い。ゲームから引くとコンパイルで落ちる）:")
    else:
        print(f"[api] 注意: 次は未リリース。{tag} の fpkg には無いのでゲームからは引けない:")
    for row in rows:
        print(f"  {row}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
