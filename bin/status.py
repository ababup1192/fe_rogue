#!/usr/bin/env python3
"""セッション開始の現状 1 画面。

散らばった記録 (git / .test-logs / スナップショット / 注釈チケット / NOTES.md) を集めて
30 行前後に要約する。何も実行しない・何も変更しない・必ず exit 0。
SessionStart フックから毎回呼ばれるので、出力の短さがそのまま固定費になる。
"""
import glob
import hashlib
import os
import re
import subprocess
import sys
import time

# Windows のコンソール (cp932) でも落ちないように。絵文字は最初から使わない。
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

MAX_LINES = 40


def age(path):
    """更新からの経過を「3分前」「2時間前」「5日前」で返す。古い記録を新しいと誤認させない。"""
    try:
        sec = time.time() - os.path.getmtime(path)
    except OSError:
        return "?"
    if sec < 90:
        return "たった今"
    if sec < 3600:
        return "%d分前" % (sec // 60)
    if sec < 86400:
        return "%d時間前" % (sec // 3600)
    return "%d日前" % (sec // 86400)


def git(*args):
    try:
        out = subprocess.run(
            ["git"] + list(args), capture_output=True, text=True, timeout=10,
            encoding="utf-8", errors="replace")
        return out.stdout.strip() if out.returncode == 0 else ""
    except Exception:
        return ""


def first_line(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                s = line.strip().lstrip("#").strip()
                if s:
                    return s
    except OSError:
        pass
    return ""


def section_git(out):
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    if not branch:
        return
    dirty = git("status", "--porcelain")
    n = len(dirty.splitlines()) if dirty else 0
    out.append("git      ブランチ %s / 変更中 %d ファイル" % (branch, n))
    for line in git("log", "--oneline", "-3").splitlines():
        out.append("  " + line)
    # コミット時のゲートは clone ごとに配線が要る。読むだけの status は知らせるだけ。
    if os.path.isdir(os.path.join("bin", "githooks")) and \
            git("config", "core.hooksPath") != "bin/githooks":
        out.append("  未配線: pre-commit ゲートが効いていません → make hooks")


def section_tests(out):
    logs = sorted(glob.glob(os.path.join(".test-logs", "*.log")))
    logs = [p for p in logs if not os.path.basename(p).startswith("render-")]
    if not logs:
        out.append("テスト   記録なし (make test / make test-par を一度も通していない)")
        return
    out.append("テスト   (最終実行の記録から。回し直してはいない)")
    reds = []
    greens = []
    for p in logs:
        name = os.path.basename(p)[:-4]
        failed = os.path.exists(p[:-4] + ".fail")
        (reds if failed else greens).append("%s(%s)" % (name, age(p)))
    if greens:
        out.append("  OK: " + " ".join(greens[:8]) + (" 他%d" % (len(greens) - 8) if len(greens) > 8 else ""))
    for r in reds:
        out.append("  NG: %s — 詳細は .test-logs/ の同名ログ" % r)
    render_fails = glob.glob(os.path.join(".test-logs", "render-*.fail"))
    for p in render_fails:
        out.append("  NG(render): %s" % os.path.basename(p)[:-5])


def reference_pairs():
    """(名前, reference/SHA256SUMS.txt, gallery/) の組。ゲームリポは自分 1 組、engine リポは templates 全部。"""
    if os.path.isfile(os.path.join("reference", "SHA256SUMS.txt")):
        return [(".", os.path.join("reference", "SHA256SUMS.txt"), "gallery")]
    pairs = []
    for sums in sorted(glob.glob(os.path.join("templates", "*", "reference", "SHA256SUMS.txt"))):
        base = os.path.dirname(os.path.dirname(sums))
        pairs.append((os.path.basename(base), sums, os.path.join(base, "gallery")))
    return pairs


def check_reference(sums, gallery):
    """一致した枚数と食い違い一覧を返す。shasum が無い Windows でも動くよう hashlib で比べる。"""
    expected = {}
    with open(sums, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            parts = line.split(None, 1)
            if len(parts) == 2:
                expected[parts[1].strip()] = parts[0]
    actual = set(os.path.basename(p) for p in glob.glob(os.path.join(gallery, "*.png")))
    bad = sorted(set(expected) - actual) + sorted(actual - set(expected))
    ok = 0
    for name, want in expected.items():
        path = os.path.join(gallery, name)
        if not os.path.isfile(path):
            continue
        h = hashlib.sha256()
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
        if h.hexdigest() == want:
            ok += 1
        else:
            bad.append(name)
    return ok, sorted(set(bad))


def section_reference(out):
    pairs = reference_pairs()
    if not pairs:
        return
    oks = []
    for name, sums, gallery in pairs:
        if not os.path.isdir(gallery):
            continue  # 未生成は「情報なし」。生成してから比べる
        try:
            ok, bad = check_reference(sums, gallery)
        except OSError:
            continue
        if bad:
            out.append("reference NG %s: %s%s (意図した変更なら make reference-update で更新)" % (
                name, " ".join(bad[:4]), " 他%d" % (len(bad) - 4) if len(bad) > 4 else ""))
        else:
            oks.append("%s(%d枚)" % (name, ok))
    if oks:
        out.append("reference OK: " + " ".join(oks))


def section_tickets(out):
    dirs = glob.glob(os.path.join("debug", "annotations", "*")) + \
        glob.glob(os.path.join("templates", "*", "debug", "annotations", "*"))
    dirs = [d for d in dirs if os.path.isdir(d)]
    if not dirs:
        return
    dirs.sort(key=lambda d: os.path.getmtime(d), reverse=True)
    out.append("チケット 注釈 %d 件 (新しい順):" % len(dirs))
    for d in dirs[:3]:
        summary = first_line(os.path.join(d, "README.md"))
        out.append("  %s (%s) %s" % (os.path.basename(d), age(d), summary[:60]))


def section_style(out):
    # engine リポ自身にはルート AGENTS.local.md が無く、素朴に検査すると毎回誤発火する。
    # templates/ の有無でリポ種別を見分ける（reference_pairs() と同じ手）
    if os.path.isdir("templates"):
        return
    hint = "[画風] AGENTS.local.md の「この画面の画風」が未定（無い/仮置きのまま） → 絵を描く前に /style-interview"
    try:
        with open("AGENTS.local.md", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        out.append(hint)
        return
    # 全問おまかせでも聞き取り済みと分かるように、痕跡コメントを節より優先して見る
    if "style-interview" in text:
        return
    # 見出しは「このゲームの画風」等に割れているので前方一致 + 「画風」で緩く拾う
    has_heading = any(
        line.startswith("## この") and "画風" in line for line in text.splitlines())
    # 「最初に決めて、ここに」は templates/game-starter/AGENTS.local.md のプレースホルダ
    # 定型文。節があっても書き足していなければ未記入。あちらの文言を直したらここも直す
    if has_heading and "最初に決めて、ここに" not in text:
        return
    out.append(hint)


def read_engine_dir():
    """このゲームが使う engine の場所。環境変数 ENGINE → local.mk の順で読む。"""
    engine = os.environ.get("ENGINE")
    if engine:
        return engine
    try:
        with open("local.mk", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                m = re.match(r"\s*ENGINE\s*[?:]*=\s*(.+?)\s*$", line)
                if m:
                    return m.group(1)
    except OSError:
        pass
    return None


def section_pack(out):
    """agents-pack の陳腐化検出。AGENTS.md 先頭に刻まれた engine のバージョンと、いま使っている
    engine のバージョン (Makefile の VERSION) を照らす。どちらかが読めなければ黙る (fail-open) —
    status は知らせるだけで、作業を止めない。"""
    if os.path.isdir("templates"):
        return  # engine リポ自身。AGENTS.md は pack の生成物ではない
    try:
        with open("AGENTS.md", encoding="utf-8", errors="replace") as fh:
            head = fh.read(400)
    except OSError:
        return
    m = re.search(r"agents-pack \(engine v([0-9][0-9A-Za-z.\-]*)\)", head)
    if not m:
        return
    stamped = m.group(1)
    engine = read_engine_dir()
    if not engine:
        return
    cur = read_engine_version(engine)
    if cur and cur != stamped:
        out.append("pack     古い (この AGENTS.md は engine v%s / いまの engine は v%s)。"
                   "engine 側で make sync-agents GAME=\"%s\" を再実行"
                   % (stamped, cur, os.getcwd()))


def read_engine_version(engine):
    """engine の Makefile から VERSION := を読む。読めなければ None (fail-open)。"""
    try:
        with open(os.path.join(engine, "Makefile"),
                  encoding="utf-8", errors="replace") as fh:
            return next((m.group(1) for line in fh
                         for m in [re.match(r"VERSION\s*:=\s*(\S+)", line)] if m), None)
    except OSError:
        return None


def section_engine_drift(out):
    """lib の engine バージョンズレ検出。ゲームの flix.toml が指す flix_game_engine のバージョンと、
    いま使っている engine のバージョン (Makefile の VERSION) を照らす。ズレたままだと
    make api や docs が「手元の lib に無い API」を教えてくる (使うと Undefined name)。
    どちらかが読めなければ黙る (fail-open) — status は知らせるだけで、作業を止めない。"""
    if os.path.isdir("templates"):
        return  # engine リポ自身
    try:
        with open("flix.toml", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        return
    m = re.search(
        r'"github:ababup1192/flix_game_engine"\s*=\s*\{[^}]*version\s*=\s*"([0-9][0-9A-Za-z.\-]*)"',
        text)
    if not m:
        return
    pinned = m.group(1)
    engine = read_engine_dir()
    if not engine:
        return
    cur = read_engine_version(engine)
    if cur and cur != pinned:
        out.append("engine   バージョンズレ (このゲームは v%s / いまの engine は v%s)。"
                   "make api や docs は v%s の物なので、無い API を引く恐れ → make engine-upgrade で追随"
                   % (pinned, cur, cur))


def section_notes(out):
    if not os.path.isfile("NOTES.md"):
        out.append("引き継ぎ NOTES.md なし (セッションの終わりに「次やること」を 3 行残すと次が安い)")
        return
    out.append("引き継ぎ NOTES.md (%s):" % age("NOTES.md"))
    shown = 0
    with open("NOTES.md", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            s = line.rstrip()
            if not s.strip():
                continue
            out.append("  " + s[:80])
            shown += 1
            if shown >= 6:
                break


def main():
    here = os.path.basename(os.getcwd())
    out = ["== %s 状態 %s ==" % (here, time.strftime("%m-%d %H:%M"))]
    for section in (section_git, section_tests, section_reference, section_tickets,
                    section_style, section_pack, section_engine_drift, section_notes):
        try:
            section(out)
        except Exception as e:
            out.append("(status: %s 区画で失敗 %s)" % (section.__name__, type(e).__name__))
    if len(out) > MAX_LINES:
        out = out[:MAX_LINES] + ["  … (長すぎるので切った。python3 bin/status.py で全文)"]
    print("\n".join(out))


if __name__ == "__main__":
    main()
    sys.exit(0)
