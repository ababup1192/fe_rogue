#!/usr/bin/env python3
"""作業の区切り（Claude Code の Stop / SubagentStop hook）で Flix を型検査する。

かつては保存のたび（PostToolUse）に .claude/hooks/after-flix-edit.py が走っていたが、
サブエージェントを並列に走らせると保存が秒間何度も届き、常駐 (JVM) が増殖して
機械が重くなった (2026-08-13 実測: load 183・空きメモリ 69MB・JVM 12 個 = 7.3GB が
アイドルで眠っていた)。加えて、保存のたびだと「編集の途中」の型エラーまで拾ってしまい、
ノイズがエージェントの文脈に流れ込んでいた。

引き金を「作業の区切り」へ移し、次の段でノイズを削る:

1. `stop_hook_active` が真なら何もしない — 直前の Stop hook のブロックで
   もう継続中という意味なので、ここで再びブロックすると止まれなくなる
2. **このセッションが触っていないパッケージは検査そのものをしない** —
   作業ツリーは複数エージェントが並行で汚すので、他セッションが編集中の
   （赤くて当然の）パッケージまで拾うと、無関係な赤で他人のターンを止めて
   しまう。「触った」の印は .claude/hooks/after-flix-touch.py
   （PostToolUse、検査はせず印を置くだけの軽い hook）が付ける
3. 前回この hook が検査した時点（内容のハッシュで判定）から変わっていない
   パッケージは飛ばす — 何も変わっていなければ検査しても結果は同じ
4. 差分が丸ごとコメント・空行だけなら型検査は無意味なので飛ばす

会話が止まる直前に、このセッションが触った .flix を持つパッケージだけを集めて
常駐 (bin/checkd) へ CHECK を投げる。NG が出れば decision:block (exit 2) で
Claude に差し戻す — 「緑と自己申告したが実は赤」を防ぐのが検査を残す理由。
一度ブロックした後、同じ内容のまま再び Stop が来ても、ハッシュが変わって
いなければ検査済み扱いで飛ばす（`stop_hook_active` のチェックと合わせて
二重に無限ループを防ぐ）。

低レベルの通信・起動予約・エラー整形は after-flix-edit.py の実装を共有する
（この hook は「いつ・どのパッケージを」の判断が仕事で、常駐との話し方は
1 か所にしか持たない）。

exit 2 で stderr が Claude に返る。ペイロードの形・git の出力が予想と違っても、
すべて無音の exit 0 にする（フックの都合で作業を壊さないのが最優先。
after-flix-edit.py の edited_path() と同じ作法）。
"""

import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.realpath(__file__))


def _load_shared():
    """after-flix-edit.py を「常駐との話し方」の共有ライブラリとして読む。

    settings.json の hook 登録からは外れたが、find_pkg/ask/state_dir/
    too_busy/reserve_daemon/first_error_block/load_prescriptions はここでも
    要る。二重に持つと常駐のプロトコルが 2 か所でズレる恐れがあるので、
    ファイルは残したまま import で使い回す。
    """
    path = os.path.join(HERE, "after-flix-edit.py")
    spec = importlib.util.spec_from_file_location("after_flix_edit", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def project_root():
    return os.environ.get("CLAUDE_PROJECT_DIR") or os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.realpath(__file__))))


def git(root, *args, timeout=15):
    """git コマンドを走らせ (成功可否, stdout テキスト) を返す。失敗は例外を投げない。"""
    try:
        proc = subprocess.run(
            ["git", "-C", root, *args],
            capture_output=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return False, ""
    if proc.returncode not in (0, 1):  # git diff は差分ありで 1 を返すことがある
        return False, ""
    return True, proc.stdout.decode("utf-8", "replace")


def changed_flix_files(root):
    """作業ツリーで変わっている .flix の絶対パス一覧 (追跡分 + 未追跡分)。"""
    files = set()
    ok, out = git(root, "diff", "--name-only", "HEAD", "--", "*.flix")
    if ok:
        files.update(out.splitlines())
    ok, out = git(root, "ls-files", "--others", "--exclude-standard", "--", "*.flix")
    if ok:
        files.update(out.splitlines())
    return sorted({os.path.join(root, f) for f in files if f})


def group_by_pkg(afe, files):
    groups = {}
    for f in files:
        pkg = afe.find_pkg(f)
        if pkg:
            groups.setdefault(pkg, []).append(f)
    return groups


def touched_by_session(afe, pkg, session_id):
    """このセッションが after-flix-touch.py で印を付けたパッケージか。

    session_id が取れない（ペイロードが読めない・古い Claude Code 等）場合は
    「触ったか分からない」ではなく確実側 (= 触っていない) とみなす。他人の赤で
    止めない方が、自分の赤を見逃すより安全 (フックの都合で作業を壊さない)。
    """
    if not session_id:
        return False
    marker = os.path.join(afe.state_dir(pkg),
                           f"touched-{hashlib.sha1(session_id.encode('utf-8')).hexdigest()[:16]}")
    return os.path.isfile(marker)


COMMENT_ONLY_PREFIXES = (
    "diff --git", "index ", "@@", "new file mode", "deleted file mode",
    "similarity index", "rename from", "rename to", "old mode", "new mode",
)


def _is_prose(text):
    """コメント行または空行なら True (bin/lint-jargon.py の prose_lines と同じ判定基準)。"""
    t = text.strip()
    return t == "" or t.startswith("//")


def pkg_diff_signature_and_prose(root, pkg, files):
    """(署名文字列, 差分がコメント・空行だけか) を返す。

    署名は「今のパッケージの状態」を表す文字列で、前回と同じなら検査を省ける
    (内容ハッシュ方式。mtime より単純で、保存し直しただけの空振りにも強い)。
    """
    tracked = [f for f in files if os.path.isfile(f)]
    rels = [os.path.relpath(f, root) for f in files]
    ok, diff_text = git(root, "diff", "-U0", "HEAD", "--", *rels) if rels else (True, "")
    if not ok:
        return None, False  # 差分が読めない → 検査は必要 (安全側) だが署名も作れない

    prose = True
    for line in diff_text.splitlines():
        if line.startswith(("+++", "---")) or line.startswith(COMMENT_ONLY_PREFIXES):
            continue
        if line.startswith("+") or line.startswith("-"):
            if not _is_prose(line[1:]):
                prose = False

    h = hashlib.sha1()
    h.update(diff_text.encode("utf-8", "replace"))
    # git diff は追跡ファイルしか見ない。未追跡の新規ファイルは中身をそのまま
    # 署名と「コメントだけ判定」の両方に足す。
    untracked_ok, untracked_out = git(root, "ls-files", "--others",
                                      "--exclude-standard", "--", *rels) if rels else (True, "")
    untracked = set(untracked_out.splitlines()) if untracked_ok else set()
    for rel in sorted(untracked):
        p = os.path.join(root, rel)
        try:
            with open(p, "rb") as fh:
                body = fh.read()
        except OSError:
            prose = False
            continue
        h.update(b"\x00" + rel.encode("utf-8", "replace") + b"\x00" + body)
        for line in body.decode("utf-8", "replace").splitlines():
            if not _is_prose(line):
                prose = False
    return h.hexdigest(), prose


def stop_state_path(afe, pkg):
    return os.path.join(afe.state_dir(pkg), "stop-hash")


def read_stop_state(afe, pkg):
    try:
        with open(stop_state_path(afe, pkg), encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return None


def write_stop_state(afe, pkg, sig):
    try:
        os.makedirs(afe.state_dir(pkg), exist_ok=True)
        with open(stop_state_path(afe, pkg), "w", encoding="utf-8") as f:
            f.write(sig)
    except OSError:
        pass


def check_pkg(afe, pkg):
    """常駐と話して (code, out) を返す。話せなければ None (起動だけ予約する)。"""
    try:
        afe.ask(pkg, "PING", timeout=0.5)
    except (OSError, ValueError):
        afe.reserve_daemon(pkg)
        return None
    try:
        return afe.ask(pkg, "CHECK", timeout=30)
    except (OSError, ValueError):
        return None


def run_hook():
    t0 = time.time()
    payload = {}
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        pass  # 形が読めなくても続行する (session_id が空扱いになり、下で全部スキップされる)
    if not isinstance(payload, dict):
        payload = {}

    if payload.get("stop_hook_active") is True:
        # 直前の Stop hook のブロックで、もう継続ターンに入っている。ここで再び
        # ブロックすると、直せない種類の型エラー（他セッションが編集中で赤い等）
        # のときに永久に止まれなくなる。1 回ブロックしたら黙って引く。
        return 0
    session_id = payload.get("session_id")
    if not isinstance(session_id, str) or not session_id:
        session_id = None

    root = project_root()
    if not root or not os.path.isdir(os.path.join(root, ".git")):
        return 0

    afe = _load_shared()
    files = changed_flix_files(root)
    if not files:
        return 0

    failures = []
    for pkg, pkg_files in group_by_pkg(afe, files).items():
        if not touched_by_session(afe, pkg, session_id):
            continue  # 他セッション/エージェントが編集中のパッケージ。検査すらしない
        sig, prose_only = pkg_diff_signature_and_prose(root, pkg, pkg_files)
        if sig is None:
            continue  # 差分が読めない → 無理に検査しない (フックの都合で作業を壊さない)
        if sig == read_stop_state(afe, pkg):
            continue  # 前回検査した時点から変わっていない
        if prose_only:
            write_stop_state(afe, pkg, sig)
            continue  # コメント・空行だけの差分は型検査の対象にならない
        result = check_pkg(afe, pkg)
        if result is None:
            continue  # 常駐が温まっていない。起動だけ予約し、次の区切りで効く
        code, out = result
        if code < 0:
            continue  # 常駐が「素の CLI で確かめて」と言っている。ここでは待たない
        write_stop_state(afe, pkg, sig)  # 検査は実施した (緑・赤いずれも記録)
        if code == 0:
            continue
        block = afe.first_error_block(out)
        tip = next((tp for key, tp in afe.load_prescriptions(pkg) if key in block), None)
        msg = f"# after-flix-work: {os.path.basename(pkg)} で型検査 NG\n{block}"
        if tip:
            msg += f"\n処方箋: {tip} (詳細は /compile-fix)"
        failures.append(msg)

    if not failures:
        return 0
    print(f"\n\n".join(failures) + f"\n\n(計 {time.time() - t0:.1f}s)", file=sys.stderr)
    return 2


def main():
    for stream in (sys.stdin, sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            try:
                stream.reconfigure(encoding="utf-8", errors="replace")
            except (OSError, ValueError):
                pass
    try:
        return run_hook()
    except Exception:
        # フックの不具合で作業を止めない。どんな想定外も無音で降りる。
        return 0


if __name__ == "__main__":
    sys.exit(main())
