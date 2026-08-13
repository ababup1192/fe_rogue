#!/usr/bin/env python3
"""独自の比喩語(このリポジトリでしか通じない言い回し)が新しく入るのを止める検査。

独自語は人が読めないだけでなく、**同じ物が別の字で書かれ、1 つの字が
いくつもの意味を持つ**ので、人も AI も grep で辿れなくなる。それを新規ぶんだけ
止めるのがこの lint。

  python3 bin/lint-jargon.py            # ステージした差分の + 行だけ (コミット時と同じ)
  python3 bin/lint-jargon.py --all      # 追跡ファイル全部 (手で確かめたい人向け)
  python3 bin/lint-jargon.py a.md b.py  # 指定ファイルだけ
  python3 bin/lint-jargon.py --all --show-warn   # 注意 (warn) の中身も並べる
  python3 bin/lint-jargon.py --self-test

語のリストは下の WORDS が正。1 語 = (語, 見つけ方, 言い換え, English, 段階) で、
English は将来この repo を英語化するときの対訳辞書としても使う。

誤検知を避けるための絞り:

  1. 見るのはコメントとドキュメントだけ。Flix は // ///、Elm は -- と {-| -}、
     JSON は "//" "note" "help" "label"、Python は # と docstring、
     Makefile は # と @echo、md は本文(コードブロックは除く)。
     **ゲームのセリフ・UI 文言(文字列リテラル)は対象外** — 最大の誤検知源はここ
  2. 単字でなく語形で当てる(WORDS の「見つけ方」の正規表現)
  3. 2 段階。error だけがコミットを止める。warn は 1 行知らせるだけ
  4. 行末に `jargon-ok: 理由` があればその行は飛ばす

見えない物 (この lint の限界):
  - ステージ差分では前後の行が見えないので、md のコードブロックの中や
    Python の docstring の途中かどうかは判別できない。その分は検査しない
    (見逃す側を選ぶ。--all では前後を読むので正しく判別する)

標準ライブラリだけで動く (Windows / macOS / Linux 共通)。
"""

import json
import re
import subprocess
import sys
from pathlib import Path

for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
# この lint 自身は語で埋まっているので検査しない。
SKIP_PATHS = {"bin/lint-jargon.py"}

# (語, 見つけ方, 言い換え, English, 段階)
#
#   error … コミットを止める。一対一の英語が無い純粋な比喩。ここは 10〜15 語に絞る
#           (多すぎると --no-verify が常用されて仕組みごと死ぬ)
#   warn  … 1 行知らせるだけ。多義の一般語で、文脈しだいでは正しい
#
# 見つけ方は単字でなく語形で書く。`倒` ではなく「既定へ倒す」の形だけを見る、のように
# 誤検知しない幅まで絞る。None は「語をそのまま探す」。
WORDS = [
    # ── 止める(error) ────────────────────────────────────
    ("関所", None, "ゲート", "gate", "error"),
    ("祝福", None, "期待値の更新 / 正解として登録する",
     "bless (approve as expected)", "error"),
    ("打ちかけ", r"打ちかけ|打ち掛け", "下書き", "draft", "error"),
    ("持ち場", None, "責務 / 担当範囲", "responsibility", "error"),
    ("台帳", None, "レジストリ / 一覧表", "registry", "error"),
    ("暗幕", None, "暗くするオーバーレイ", "darkness overlay", "error"),
    ("器", r"(?<![一-龥])器[はをがにへので]", "コンテナ", "container", "error"),
    ("素通り", None, "スキップする / 何もせず通す", "pass through / no-op", "error"),
    ("札", r"(?<![一-龥])札(?![幌])", "ボタン / カード / ラベル",
     "button / card / label", "error"),
    ("正本", None, "source of truth / 元データ", "source of truth", "error"),
    ("取り置き", None, "キャッシュ", "cache", "error"),
    ("焼き置き", None, "事前生成したデータ", "prebaked data", "error"),
    # ── 知らせるだけ(warn) ───────────────────────────────
    ("帯", r"(?<![一-龥])帯(?![電び])", "z-index の範囲 / 走査線 / 階調ステップ",
     "z range / scanline / gradient step", "warn"),
    ("段", r"(?<![一-龥])段(?![階])", "段階 / レベル / 行", "step / level / row", "warn"),
    ("窓", r"(?<![一-龥])窓(?![口])", "ウィンドウ / パネル / 範囲",
     "window / panel / range", "warn"),
    ("畳む", r"畳(?:む|み|ん|め)", "1 つにまとめる / 折り返す",
     "fold / collapse / wrap", "warn"),
    ("寄せる", r"寄せ(?:る|て|た|ら|ず)", "そろえる / 移す / 近づける",
     "align / move to / approximate", "warn"),
    ("拍", r"(?<![一-龥])拍(?![手車])", "ビート / 拍子", "beat", "warn"),
    ("効く", r"効[くきけ]", "反映される / 有効になる", "take effect", "warn"),
    ("倒す", r"(既定|空|None|false|fail-open)[^。]{0,12}へ?倒",
     "既定へ落とす / フォールバック", "fall back", "warn"),
    ("口", r"の口|読み口|差し口|受け口|窓口", "入口 / API / 差し替え点",
     "entry point / API / hook", "warn"),
    ("印", r"(?<![一-龥])印(?![刷象鑑税])", "目印 / フラグ / マーカー",
     "marker / flag", "warn"),
    ("粒", r"(?<![一-龥])粒(?![子])", "粒子 / 細かさ", "particle / granularity", "warn"),
    ("縁", r"(?<![一-龥])縁(?![側起])", "ふち / 輪郭線", "edge / outline", "warn"),
    ("芯", None, "中心 / 中核", "core / center", "warn"),
    ("敷く", r"敷[くきけ]", "敷き詰める / 下に置く", "tile / lay under", "warn"),
    ("色票", None, "パレット / 配色表", "palette", "warn"),
    ("升目", None, "マス / グリッドのセル", "grid cell", "warn"),
    ("方言", None, "独自の書き方 / 拡張スキーマ", "dialect (schema variant)", "warn"),
    ("台本", None, "シナリオ / 手順書", "script / scenario", "warn"),
    ("黙って", r"黙[っり]", "何も知らせずに / エラーを出さずに", "silently", "warn"),
]

ESCAPE = re.compile(r"jargon-ok\s*[:：]")

JSON_DOC_KEYS = ("//", "note", "help", "label", "comment", "desc", "description")

SUFFIX_KIND = {
    ".md": "md", ".flix": "flix", ".elm": "elm", ".json": "json", ".py": "py",
}


def kind_of(path):
    name = path.replace("\\", "/").rsplit("/", 1)[-1]
    if name == "Makefile" or name.endswith(".mk"):
        return "make"
    for suffix, kind in SUFFIX_KIND.items():
        if name.endswith(suffix):
            return kind
    return None


# ---------------------------------------------------------------- 語を組み立てる

class Rule:
    def __init__(self, word, pattern, better, english, stage):
        self.word = word
        self.regex = re.compile(pattern if pattern else re.escape(word))
        self.better = better
        self.english = english
        self.stage = stage


def load_rules(words=None):
    return [Rule(*w) for w in (words if words is not None else WORDS)]


# ------------------------------------------------ コメント・文章だけ取り出す

STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"')


def _after(line, marker):
    body = STRING.sub('""', line)
    i = body.find(marker)
    return line[i:] if i >= 0 else None


def _json_doc_values(line):
    out = []
    for key in JSON_DOC_KEYS:
        for m in re.finditer(r'"%s"\s*:\s*"((?:[^"\\]|\\.)*)"' % re.escape(key), line):
            out.append(m.group(1))
    return " ".join(out)


def _json_walk(node, out):
    if isinstance(node, dict):
        for k, v in node.items():
            if k in JSON_DOC_KEYS and isinstance(v, str):
                out.append(v)
            else:
                _json_walk(v, out)
    elif isinstance(node, list):
        for v in node:
            _json_walk(v, out)


INLINE_CODE = re.compile(r"`[^`]*`")


def prose_lines(kind, lines, whole_file):
    """(行番号, 見る文字列) を返す。whole_file=False は差分の + 行 (前後が見えない)。"""
    out = []
    fence = False       # md のコードブロック
    block = False       # Elm の {- -} / Python の docstring
    quote = None
    for i, line in enumerate(lines, start=1):
        text = None
        if kind == "md":
            if whole_file and re.match(r"\s*(```|~~~)", line):
                fence = not fence
                continue
            if not fence:
                text = INLINE_CODE.sub("", line)
        elif kind == "flix":
            text = _after(line, "//")
        elif kind == "elm":
            if whole_file:
                if block:
                    text = line
                    if "-}" in line:
                        block = False
                elif "{-" in line:
                    text = line
                    block = "-}" not in line
            if text is None:
                text = _after(line, "--")
        elif kind == "json":
            text = _json_doc_values(line)
        elif kind == "py":
            if whole_file:
                for q in ('"""', "'''"):
                    if quote == q and q in line:
                        quote = None
                        text = line
                        break
                    if quote is None and line.count(q) == 1:
                        quote = q
                        text = line
                        break
                else:
                    if quote:
                        text = line
            if text is None:
                text = _after(line, "#")
        elif kind == "make":
            text = _after(line, "#")
            if text is None:
                text = " ".join(re.findall(r'@?echo\s+"([^"]*)"', line))
        if text:
            out.append((i, text))
    return out


# ---------------------------------------------------------------- 検査本体

class Hit:
    def __init__(self, path, lineno, rule, excerpt):
        self.path, self.lineno, self.rule, self.excerpt = path, lineno, rule, excerpt


def check(path, kind, lines, rules, whole_file):
    hits = []
    for lineno, text in prose_lines(kind, lines, whole_file):
        if ESCAPE.search(text):
            continue
        for rule in rules:
            if rule.regex.search(text):
                hits.append(Hit(path, lineno, rule, text.strip()[:70]))
    return hits


def check_json_file(path, body, rules):
    """JSON は全体を読めるなら構造で歩く (行 regex より確実)。"""
    try:
        doc = json.loads(body)
    except ValueError:
        return None
    values = []
    _json_walk(doc, values)
    hits = []
    for value in values:
        if ESCAPE.search(value):
            continue
        for rule in rules:
            if rule.regex.search(value):
                hits.append(Hit(path, 0, rule, value.strip()[:70]))
    return hits


# ---------------------------------------------------------------- 入力の口

def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args],
                          capture_output=True, text=True, check=True).stdout


def staged_hits(rules):
    diff = git("diff", "--cached", "-U0", "--diff-filter=ACMR")
    hits, path, kind, lineno, pending = [], None, None, 0, []
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            path = line[6:]
            kind = None if path in SKIP_PATHS else kind_of(path)
            continue
        if line.startswith("@@"):
            m = re.search(r"\+(\d+)", line)
            lineno = int(m.group(1)) if m else 0
            continue
        if kind and line.startswith("+") and not line.startswith("+++"):
            pending.append((path, kind, lineno, line[1:]))
            lineno += 1
    for path, kind, lineno, body in pending:
        for _, text in prose_lines(kind, [body], False):
            if ESCAPE.search(text):
                continue
            for rule in rules:
                if rule.regex.search(text):
                    hits.append(Hit(path, lineno, rule, text.strip()[:70]))
    return hits


def all_paths():
    out = git("ls-files", "-z")
    return [p for p in out.split("\0") if p and p not in SKIP_PATHS and kind_of(p)]


def file_hits(paths, rules):
    hits = []
    for p in paths:
        full = Path(p)
        if not full.is_file():
            full = ROOT / p
        if not full.is_file():
            continue
        kind = kind_of(p)
        if kind is None or p in SKIP_PATHS:
            continue
        body = full.read_text(encoding="utf-8", errors="replace")
        if kind == "json":
            structured = check_json_file(p, body, rules)
            if structured is not None:
                hits.extend(structured)
                continue
        hits.extend(check(p, kind, body.splitlines(), rules, True))
    return hits


# ---------------------------------------------------------------- 出力

def report(hits, rules, show_warn=False):
    errors = [h for h in hits if h.rule.stage == "error"]
    warns = [h for h in hits if h.rule.stage == "warn"]
    for h in errors + (warns if show_warn else []):
        where = f"{h.path}:{h.lineno}" if h.lineno else h.path
        mark = "注意 " if h.rule.stage == "warn" else ""
        print(f"  {mark}{where}: 「{h.rule.word}」→ {h.rule.better} ({h.rule.english})")
        print(f"      {h.excerpt}")
    if errors:
        print(f"[lint-jargon] 独自語 {len(errors)} 件。上の言い換えへ直すか、"
              "本当に必要なら行末に jargon-ok: 理由 を書いてください")
    if warns:
        by_word = {}
        for h in warns:
            by_word.setdefault(h.rule.word, []).append(h)
        top = sorted(by_word.items(), key=lambda kv: -len(kv[1]))[:8]
        summary = " / ".join(f"{w}×{len(v)}" for w, v in top)
        print(f"[lint-jargon] 注意 {len(warns)} 件 (止めません): {summary}")
    if not hits:
        print(f"[lint-jargon] OK ({len(rules)} 語で検査)")
    return 1 if errors else 0


# ---------------------------------------------------------------- 自己検査

SELF_TEST_WORDS = [
    ("関所", None, "ゲート", "gate", "error"),
    ("倒す", r"(既定|空)[^。]{0,12}へ?倒", "既定へ落とす", "fall back", "warn"),
]


def self_test():
    rules = load_rules(SELF_TEST_WORDS)
    assert len(rules) == 2, rules
    assert rules[0].stage == "error" and rules[1].stage == "warn"
    assert rules[1].regex.search("既定へ倒す")
    assert not rules[1].regex.search("敵を倒す")

    def hits(kind, line, whole=False):
        return check("x", kind, [line], rules, whole)

    assert hits("flix", "// 関所で止める")
    assert not hits("flix", 'let msg = "関所を通っておくれ"')
    assert not hits("flix", "let name = \"関所\" // ok")
    assert hits("md", "コミットの関所で止める")
    assert not hits("md", "`関所` は使わない")
    assert hits("py", "# 関所を通す")
    assert hits("elm", "-- 関所のあたり")
    assert hits("json", '{"note": "関所で止める"}')
    assert not hits("json", '{"text": "関所を通っておくれ"}')
    assert hits("make", '\t@echo "  make x   関所の検査"')
    assert not hits("flix", "// 関所で止める  jargon-ok: 説明のため")
    assert not hits("md", "```")

    real = load_rules()
    assert len(real) == len(WORDS)
    stopped = [r for r in real if r.stage == "error"]
    # 止める語が増えすぎると --no-verify が常用されて仕組みごと死ぬ
    assert len(stopped) <= 15, len(stopped)
    assert not any(r.regex.search("武器を持つ") for r in stopped)
    assert not any(r.regex.search("改札を抜ける") for r in stopped)
    print(f"[lint-jargon] self-test OK ({len(stopped)} 語で止め、"
          f"{len(real) - len(stopped)} 語で知らせる)")
    return 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    rules = load_rules()
    files = [a for a in argv if not a.startswith("--")]
    if files:
        hits = file_hits(files, rules)
    elif "--all" in argv:
        hits = file_hits(all_paths(), rules)
    else:
        hits = staged_hits(rules)
    return report(hits, rules, show_warn="--show-warn" in argv)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
