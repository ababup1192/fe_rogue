#!/usr/bin/env python3
"""bin/checkd（常駐）との話し方 — after-flix-work.py が使う共有ライブラリ。

以前はこのファイル自身が Claude Code の PostToolUse hook として、保存の
たびに常駐へ CHECK を送っていた。サブエージェントを並列に走らせると保存が
秒間何度も届いて常駐が増殖したため、引き金は .claude/hooks/after-flix-work.py
（Stop / SubagentStop hook）へ移した。常駐との通信プロトコル（find_pkg /
ask / state_dir / too_busy / reserve_daemon / first_error_block /
load_prescriptions）は 1 か所にしか持たない方針で、ここへ残して import で
使い回している。settings.json には直接は登録されていない。

単体でも `python3 after-flix-edit.py < ペイロード` として、1 ファイル分の
PostToolUse 形ペイロードを与えれば従来どおり動く（デバッグ・移行期の比較用）。

exit 2 で stderr が Claude に返る（作業自体は止めない）。緑・冷・想定外の
失敗はすべて無音の exit 0。フックの都合で作業を壊さないことを最優先する。
"""

import hashlib
import json
import os
import re
import socket
import subprocess
import sys
import time

ANSI = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]|\x1b\][^\x07]*\x07|\x1b[=>]")


def load_prescriptions(pkg):
    """エラー → 処方箋の対応表を bin/explain-error から借りる (実体は 1 か所)。

    make check の要約と同じ表を使う。見つからない・読めない時は空 (処方箋なしで
    エラー本文だけ出す) — フックの都合で作業を止めない。
    """
    import importlib.machinery
    import importlib.util

    root = os.environ.get("CLAUDE_PROJECT_DIR") or os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
    for base in (pkg, root):
        cand = os.path.join(base, "bin", "explain-error")
        if not os.path.isfile(cand):
            continue
        try:
            loader = importlib.machinery.SourceFileLoader("explain_error", cand)
            spec = importlib.util.spec_from_loader("explain_error", loader)
            mod = importlib.util.module_from_spec(spec)
            loader.exec_module(mod)
            return mod.PRESCRIPTIONS
        except Exception:
            continue  # 壊れた候補は飛ばして次 (root 側) を試す
    return []


def state_dir(pkg):
    h = hashlib.sha1(pkg.encode("utf-8")).hexdigest()[:16]
    return os.path.join(os.path.expanduser("~/.cache/flix-checkd"), h)


def ask(pkg, command, timeout):
    """常駐へ 1 コマンド送り (終了コード, 出力) を返す。話せなければ例外。"""
    with open(os.path.join(state_dir(pkg), "port"), encoding="utf-8") as f:
        port = int(f.read().strip())
    s = socket.create_connection(("127.0.0.1", port), timeout=timeout)
    s.settimeout(timeout)
    try:
        s.sendall(command.encode("utf-8") + b"\n")
        buf = b""
        while b"\n" not in buf:
            c = s.recv(65536)
            if not c:
                raise ConnectionError("no header")
            buf += c
        header, body = buf.split(b"\n", 1)
        _tag, code, length = header.split()
        code, length = int(code), int(length)
        while len(body) < length:
            c = s.recv(65536)
            if not c:
                raise ConnectionError("truncated")
            body += c
        return code, body.decode("utf-8", "replace")
    finally:
        s.close()


def find_pkg(path):
    """編集ファイルから flix.toml まで遡ってパッケージの根を探す。"""
    d = os.path.dirname(os.path.realpath(path))
    for _ in range(8):
        if os.path.isfile(os.path.join(d, "flix.toml")):
            return d
        nd = os.path.dirname(d)
        if nd == d:
            return None
        d = nd
    return None


def find_checkd(pkg):
    root = os.environ.get("CLAUDE_PROJECT_DIR") or os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
    for base in (pkg, root):
        cand = os.path.join(base, "bin", "checkd")
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    return None


def load_checkd(pkg):
    """bin/checkd を読み込んで返す。読めなければ None。

    常駐の数の上限とプロセスの生存判定は checkd 側にしか持たない
    (2 か所に置くと、機械を変えたとき片方だけ古い値が残る)。
    """
    import importlib.machinery
    import importlib.util

    path = find_checkd(pkg)
    if not path:
        return None
    try:
        loader = importlib.machinery.SourceFileLoader("checkd_mod", path)
        spec = importlib.util.spec_from_loader("checkd_mod", loader)
        mod = importlib.util.module_from_spec(spec)
        loader.exec_module(mod)
        return mod
    except Exception:
        return None


def read_pid(sd):
    try:
        with open(os.path.join(sd, "pid"), encoding="utf-8") as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return None


def pid_alive(pkg):
    """そのパッケージの常駐が生きているか。落ちた常駐も pid ファイルを残すので、
    ファイルの有無ではなくプロセスの存在で確かめる
    (Windows の os.kill は相手を止めてしまうので checkd.pid_alive に任せる)。"""
    pid = read_pid(state_dir(pkg))
    if pid is None:
        return False
    checkd = load_checkd(pkg)
    if not checkd:
        return False  # 判定できない → 「居ない」に倒す (歯止めは too_busy が別に持つ)
    return checkd.pid_alive(pid)


def live_daemons(checkd):
    """今生きている常駐の数。"""
    root = os.path.expanduser("~/.cache/flix-checkd")
    try:
        names = os.listdir(root)
    except OSError:
        return 0
    live = 0
    for name in names:
        pid = read_pid(os.path.join(root, name))
        if pid is not None and checkd.pid_alive(pid):
            live += 1
    return live


def too_busy(pkg):
    """起動予約を見送る条件。JVM 1 つで 1 コア食うので、無条件に増やすと機械が死ぬ。

    サブエージェントを並列に走らせると、1 パッケージへ数十件の保存が数秒で届く。
    予約は「次の保存から効けばよい」おまけなので、混んでいる間は諦める方が速い。
    """
    stamp = os.path.join(state_dir(pkg), "reserved")
    try:
        if time.time() - os.path.getmtime(stamp) < 90:
            return True
    except OSError:
        pass
    try:
        if os.getloadavg()[0] > (os.cpu_count() or 4):
            return True
    except (OSError, AttributeError):
        pass
    # 常駐は JVM を抱えたまま眠り続ける。パッケージの数だけ増やすと機械の
    # メモリが尽きるので、生きている数で上限を切る (上限は機械の大きさから
    # checkd.memory_budget() が決める)。
    checkd = load_checkd(pkg)
    if not checkd:
        return True  # checkd が読めない機械では起動を頼まない (素の CLI で足りる)
    if live_daemons(checkd) >= checkd.MAX_DAEMONS:
        return True
    try:
        os.makedirs(os.path.dirname(stamp), exist_ok=True)
        open(stamp, "w").close()
    except OSError:
        pass
    return False


def reserve_daemon(pkg):
    """裏で `checkd <pkg>` を完全に切り離して起動する。次の保存から温で効く。

    結果は待たない・出力も拾わない。失敗しても無音（起動予約はおまけの善意で、
    フック本体の責務ではない）。
    """
    checkd = find_checkd(pkg)
    if not checkd or too_busy(pkg):
        return
    kwargs = {}
    if os.name == "nt":
        kwargs["creationflags"] = (subprocess.CREATE_NEW_PROCESS_GROUP
                                   | subprocess.CREATE_NO_WINDOW)
    else:
        kwargs["start_new_session"] = True
    try:
        subprocess.Popen(
            [sys.executable, checkd, pkg], cwd=pkg,
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, **kwargs)
    except OSError:
        pass


def first_error_block(text):
    """Flix の出力から最初のエラーブロックだけ抜く (次の '-- ' 見出しか 15 行まで)。"""
    lines = ANSI.sub("", text).splitlines()
    start = next((i for i, l in enumerate(lines) if l.startswith("-- ")), None)
    if start is None:
        return "\n".join(lines[-10:]).rstrip()
    block = [lines[start]]
    for l in lines[start + 1:]:
        if l.startswith("-- ") or len(block) >= 15:
            break
        block.append(l)
    return "\n".join(block).rstrip()


def edited_path(payload):
    """編集されたファイルのパスをペイロードから拾う。

    Claude Code は tool_input.file_path に入れるが、Codex 等のペイロード形は
    確定していないので、ありそうなキーを順に試す。どれも無ければ空文字を返して
    呼び元が黙って降りる (フックの都合で作業を壊さない)。
    """
    ti = payload.get("tool_input") or {}
    tr = payload.get("tool_response") or {}
    for cand in (ti.get("file_path"), ti.get("path"),
                 tr.get("file_path"), tr.get("path"),
                 payload.get("file_path"), payload.get("path")):
        if isinstance(cand, str) and cand:
            return cand
    return ""


def run_hook():
    t0 = time.time()
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0
    path = edited_path(payload)
    if not path.endswith(".flix"):
        return 0
    pkg = find_pkg(path)
    if not pkg:
        return 0
    try:
        ask(pkg, "PING", timeout=0.5)
    except (OSError, ValueError):
        reserve_daemon(pkg)
        return 0
    try:
        code, out = ask(pkg, "CHECK", timeout=30)
    except (OSError, ValueError):
        return 0
    if code < 0:
        # 常駐が「素の CLI で確かめて」と言っている。フックで CLI を回すと
        # 保存のたびに数十秒待たせるので、ここでは黙って降りる。
        return 0
    if code == 0:
        return 0
    block = first_error_block(out)
    tip = next((t for key, t in load_prescriptions(pkg) if key in block), None)
    msg = (f"# after-flix-edit: {os.path.basename(pkg)} で型検査 NG "
           f"(先頭 1 件, {time.time() - t0:.1f}s)\n{block}")
    if tip:
        msg += f"\n処方箋: {tip} (詳細は /compile-fix)"
    print(msg, file=sys.stderr)
    return 2


def main():
    # Windows の既定はロケール依存の文字コードで、日本語の出力で化ける・落ちる
    # ので UTF-8 に固定する。
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
