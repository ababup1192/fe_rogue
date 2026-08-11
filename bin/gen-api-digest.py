#!/usr/bin/env python3
"""engine 系パッケージの pub API を 1 枚のダイジェストにまとめる。

AI エージェントが「この関数、型はどんな形だっけ」を調べるたびにソースを grep して
丸読みすると、トークンも時間も食う。pub def / pub enum / pub type alias の宣言だけを
機械的に抜き出して 1 ファイルに畳んでおけば、まずそこを読むだけで済む。

  python3 bin/gen-api-digest.py            # docs/api-digest.md を書く
  python3 bin/gen-api-digest.py --check    # 生成し直しても差分が無いか検査する（書かない）

対象は engine/src・engine_world/src・engine_tools/src の *.flix。
pub def のシグネチャは本体開始の `=` 直前までを 1 行に畳む（本体そのものは載せない）。
pub enum・pub type alias は宣言全体（case 行・フィールドも含む）を 1 行に畳む。

標準ライブラリだけで動く（Windows / macOS / Linux 共通。sed 等の外部コマンドを使わない）。
"""

import datetime
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INDEX_PATH = ROOT / "docs" / "api-digest.md"
DIGEST_DIR = ROOT / "docs" / "api-digest"

# 「いつの engine の姿か」を先頭に刻む (古い写しを最新と信じて誤推測しないため)。
# 日付は内容が変わった時だけ進める — 毎回進めると --check の差分ゼロ検査が壊れる。
VERSION_RE = re.compile(r"^VERSION\s*:=\s*(\S+)", re.M)
STAMP_DATE_RE = re.compile(r"生成: \d{4}-\d{2}-\d{2}")


def engine_version():
    try:
        m = VERSION_RE.search((ROOT / "Makefile").read_text(encoding="utf-8"))
        return m.group(1) if m else "?"
    except OSError:
        return "?"


def stamp_line():
    return "<!-- engine v{} / 生成: {} -->\n".format(
        engine_version(), datetime.date.today().isoformat()
    )


def dateless(text):
    """スタンプの日付だけを均した本文を返す (差分比較は日付を見ない)。"""
    return STAMP_DATE_RE.sub("生成: 0000-00-00", text)

# (パッケージ表示名, ソース根)。表示順はこの並びのまま使う。
PACKAGES = [
    ("engine", "engine/src"),
    ("engine_world", "engine_world/src"),
    ("engine_tools", "engine_tools/src"),
]

MOD_RE = re.compile(r"^mod\s+([A-Za-z][A-Za-z0-9_.]*)\s*\{")

PACKAGE_BANNER = (
    "<!-- 生成物: bin/gen-api-digest.py が作る。手で編集しない（make api-digest で作り直す） -->\n"
)

INDEX_HEADER = """\
<!-- 生成物: bin/gen-api-digest.py が作る。手で編集しない（make api-digest で作り直す） -->

# API ダイジェスト

engine / engine_world / engine_tools が公開している `pub def` / `pub enum` /
`pub type alias` の一覧。**API の型・引数を調べる時は、ソースを grep する前に
まずここを読む。** 実装や WhyNot コメントまでは載っていないので、シグネチャだけで
足りないときにだけ元ファイルを開く。

パッケージごとに分けている（1 ファイルが大きくなりすぎると、それ自体を読むのが
grep 代わりの重い作業になってしまうため）。調べたいモジュールがどのパッケージに
あるか分からないときは [engine-module-index.md](engine-module-index.md) /
[module-index.md](module-index.md) を先に引く。

"""


def scannable(line: str) -> str:
    """文字列リテラルの外にある `//` 以降（行コメント）を落とした行を返す。

    括弧の深さ数えと `=` 判定を、コメント中の記号に惑わされずに行うための下ごしらえ。
    """
    out = []
    in_str = False
    skip = False
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if skip:
            skip = False
            out.append(c)
            i += 1
            continue
        if in_str:
            out.append(c)
            if c == "\\":
                skip = True
            elif c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < n and line[i + 1] == "/":
            break
        out.append(c)
        i += 1
    return "".join(out)


def collapse(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def extract_def_signature(lines, start_idx):
    """`pub def` の宣言を、本体開始の `=` 直前まで 1 行に畳んで返す。"""
    depth = 0
    parts = []
    i = start_idx
    limit = min(len(lines), start_idx + 60)
    while i < limit:
        raw = scannable(lines[i])
        buf = []
        in_str = False
        skip = False
        stop = False
        k = 0
        n = len(raw)
        while k < n:
            c = raw[k]
            if skip:
                skip = False
                buf.append(c)
                k += 1
                continue
            if in_str:
                buf.append(c)
                if c == "\\":
                    skip = True
                elif c == '"':
                    in_str = False
                k += 1
                continue
            if c == '"':
                in_str = True
                buf.append(c)
                k += 1
                continue
            if c in "([{":
                depth += 1
                buf.append(c)
                k += 1
                continue
            if c in ")]}":
                depth -= 1
                buf.append(c)
                k += 1
                continue
            if c == "=" and depth == 0:
                prev = raw[k - 1] if k > 0 else ""
                nxt = raw[k + 1] if k + 1 < n else ""
                # ==, !=, <=, >=, => は本体開始の代入ではないので飛ばす。
                # prev/nxt が空文字（行頭・行末）の場合は `'' in s` が常に True になる
                # Python の罠があるので、空でないときだけ集合に照合する。
                prev_is_op = prev != "" and prev in "=!<>~"
                nxt_is_op = nxt != "" and nxt in "=>"
                if not prev_is_op and not nxt_is_op:
                    stop = True
                    break
            buf.append(c)
            k += 1
        parts.append("".join(buf))
        if stop:
            break
        i += 1
    return collapse(" ".join(p.strip() for p in parts if p.strip())), i


def extract_block(lines, start_idx):
    """`pub enum` / `pub type alias` の宣言全体を、括弧の深さが 0 に戻るまで拾う。

    enum は case 行、type alias はフィールドの中身まで、丸ごと 1 行に畳んで返す
    （関数と違い、宣言そのものが型の形なので途中で切らない）。
    """
    depth = 0
    parts = []
    i = start_idx
    limit = min(len(lines), start_idx + 200)
    while i < limit:
        raw = scannable(lines[i])
        parts.append(raw)
        in_str = False
        skip = False
        for c in raw:
            if skip:
                skip = False
                continue
            if in_str:
                if c == "\\":
                    skip = True
                elif c == '"':
                    in_str = False
                continue
            if c == '"':
                in_str = True
                continue
            if c in "([{":
                depth += 1
            elif c in ")]}":
                depth -= 1
        i += 1
        if depth <= 0:
            break
    return collapse(" ".join(p.strip() for p in parts if p.strip())), i


def scan_file(path: Path):
    """ファイル 1 本から {mod名: [(doc, decl), ...]} を、出現順を保って返す。"""
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.split("\n")

    mod_of_line = [None] * len(lines)
    depth = 0
    mod_stack = []  # (name, depth_after_open)
    for idx, line in enumerate(lines):
        raw = scannable(line)
        in_str = False
        skip = False
        for c in raw:
            if skip:
                skip = False
                continue
            if in_str:
                if c == "\\":
                    skip = True
                elif c == '"':
                    in_str = False
                continue
            if c == '"':
                in_str = True
                continue
            if c in "([{":
                depth += 1
            elif c in ")]}":
                depth -= 1
        while mod_stack and depth < mod_stack[-1][1]:
            mod_stack.pop()
        m = MOD_RE.match(line.strip())
        if m:
            mod_stack.append((m.group(1), depth))
        mod_of_line[idx] = mod_stack[-1][0] if mod_stack else None

    result = {}  # mod名 -> [(doc_or_None, decl_text)]
    pending_doc = None
    i = 0
    while i < len(lines):
        stripped = lines[i].strip()
        if stripped.startswith("///"):
            if pending_doc is None:
                pending_doc = stripped[3:].strip()
            i += 1
            continue
        if stripped.startswith("pub def "):
            sig, end = extract_def_signature(lines, i)
            mod = mod_of_line[i]
            if mod is not None:
                result.setdefault(mod, []).append((pending_doc, sig))
            pending_doc = None
            i += 1
            continue
        if stripped.startswith("pub enum ") or stripped.startswith("pub type alias "):
            decl, end = extract_block(lines, i)
            mod = mod_of_line[i]
            if mod is not None:
                result.setdefault(mod, []).append((pending_doc, decl))
            pending_doc = None
            i += 1
            continue
        pending_doc = None
        i += 1
    return result


def build_package_digest(pkg_name, pkg_root):
    """1 パッケージ分の Markdown 本文と、モジュール数・宣言数を返す。"""
    root = ROOT / pkg_root
    lines = [PACKAGE_BANNER.rstrip("\n")]
    lines.append("")
    lines.append("# API ダイジェスト — {}".format(pkg_name))
    lines.append("")
    lines.append(
        "`{}` 配下の `pub def` / `pub enum` / `pub type alias` の一覧。"
        "索引は [api-digest.md](../api-digest.md)。".format(pkg_root)
    )

    # ファイル単位で走査し、モジュール名 -> (ファイル相対パス, 宣言リスト) に集約。
    # 1 ファイルに複数 mod があってもモジュール単位の見出しに分ける。
    modules = {}  # mod名 -> (rel_path, [(doc, decl)])
    if root.is_dir():
        for path in sorted(root.rglob("*.flix")):
            rel = path.relative_to(ROOT).as_posix()
            for mod, decls in scan_file(path).items():
                bucket = modules.setdefault(mod, (rel, []))
                bucket[1].extend(decls)

    decl_count = 0
    for mod in sorted(modules):
        rel, decls = modules[mod]
        if not decls:
            continue
        lines.append("")
        lines.append("## {} — `{}`".format(mod, rel))
        for doc, decl in decls:
            decl_count += 1
            if doc:
                lines.append("- {}".format(doc))
                lines.append("  `{}`".format(decl))
            else:
                lines.append("- `{}`".format(decl))
    lines.append("")
    return "\n".join(lines), len(modules), decl_count


def build_index(stats):
    lines = [INDEX_HEADER.rstrip("\n")]
    lines.append("| パッケージ | モジュール数 | 宣言数 | ファイル |")
    lines.append("|---|---|---|---|")
    for pkg_name, mod_count, decl_count in stats:
        lines.append(
            "| {0} | {1} | {2} | [api-digest/{0}.md](api-digest/{0}.md) |".format(
                pkg_name, mod_count, decl_count
            )
        )
    lines.append("")
    return "\n".join(lines)


def main(argv):
    check = "--check" in argv
    stamp = stamp_line().rstrip("\n")
    targets = []  # (path, content)
    stats = []
    for pkg_name, pkg_root in PACKAGES:
        content, mod_count, decl_count = build_package_digest(pkg_name, pkg_root)
        targets.append((DIGEST_DIR / "{}.md".format(pkg_name), content))
        stats.append((pkg_name, mod_count, decl_count))
    targets.append((INDEX_PATH, build_index(stats)))
    targets = [(path, stamp + "\n" + content) for path, content in targets]

    if check:
        ok = True
        for path, content in targets:
            current = path.read_text(encoding="utf-8") if path.exists() else None
            if current is None or dateless(current) != dateless(content):
                ok = False
                print(
                    "[gen-api-digest] NG: {} がソースとずれています。"
                    " make api-digest で作り直してください".format(
                        path.relative_to(ROOT)
                    ),
                    file=sys.stderr,
                )
        if ok:
            print("OK: docs/api-digest.md / docs/api-digest/*.md は最新です")
            return 0
        return 1

    DIGEST_DIR.mkdir(parents=True, exist_ok=True)
    for path, content in targets:
        path.parent.mkdir(parents=True, exist_ok=True)
        current = path.read_text(encoding="utf-8") if path.exists() else None
        if current is not None and dateless(current) == dateless(content):
            continue  # 内容が同じなら日付も進めない (git の空騒ぎを作らない)
        path.write_text(content, encoding="utf-8")
        print("[gen-api-digest] wrote {}".format(path.relative_to(ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
