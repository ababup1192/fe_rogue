#!/usr/bin/env python3
"""Flix ファイルを書いた直後に型検査する（Claude Code の PostToolUse hook）。

bin/checkd が温めている常駐へ CHECK を送るだけの薄い入口。常駐が温まって
いなければ黙って降りる（保存のたびに数十秒のコンパイルを待たせない）。
その代わり、裏で常駐の立ち上げだけ予約して、次の保存から効くようにする。

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

# エラー文中のキー → 平易な 1 行の処方箋。上から順に最初に当たった 1 件だけ出す。
# 具体的なエラー番号を先、言い回しだけの広いキーを後に置く。
PRESCRIPTIONS = [
    ("Expected ',' before '='",
     "予約語をレコードのフィールド名に使っている疑い (spawn/run/project 等)。別名へ逃がす"),
    ("E5252",
     "レコードは Eq/Order を持てない。比較したい値は名前付き 1 フィールド enum で包む"),
    ("E6217",
     "checked_ecast は不要。dispatch を単一の match に束ねる"),
    ("E3138",
     "定義が見つからない。ファイル移動で test 側だけ取り残されていないか"),
    ("E5410",
     "同名モジュールを別ファイルで開き直している。モジュールの再オープンは不可"),
    ("Non-exhaustive",
     "enum の全ケースを網羅していない。足りない case か case _ を足す"),
    ("Expected Float32",
     "浮動小数点リテラルに f32 サフィックスが要る (1.0 は Float64)"),
    ("Unable to unify",
     "型が合っていない。f32 サフィックス忘れ・Int32/Int64 の混在・エフェクト注釈の不足をまず疑う"),
    ("Unexpected type",
     "型が合っていない。f32 サフィックス忘れ・Int32/Int64 の混在をまず疑う"),
    ("Unresolved type",
     "Java の import は関数の中でなくモジュール直下に置く。例外型の ## 前置きは外す"),
    ("Undefined name",
     "名前の打ち間違いか、モジュール名の付け忘れ (Module.name)。docs/module-index.md で正しい名を引く"),
    ("Unexpected token",
     "予約語 (handler/do/run/spawn/region/project 等) を識別子に使っていないか"),
]


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


def reserve_daemon(pkg):
    """裏で `checkd <pkg>` を完全に切り離して起動する。次の保存から温で効く。

    結果は待たない・出力も拾わない。失敗しても無音（起動予約はおまけの善意で、
    フック本体の責務ではない）。
    """
    checkd = find_checkd(pkg)
    if not checkd:
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


def run_hook():
    t0 = time.time()
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0
    path = (payload.get("tool_input") or {}).get("file_path") or ""
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
    tip = next((t for key, t in PRESCRIPTIONS if key in block), None)
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
