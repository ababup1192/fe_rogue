#!/usr/bin/env python3
"""このセッションが .flix を編集したパッケージへ印だけ残す（PostToolUse hook）。

after-flix-work.py（Stop / SubagentStop hook）は「作業ツリーで汚れている
パッケージ全部」を見る。複数エージェントが並行で走っていると、他のセッションが
編集中の（赤くて当然の）パッケージまで拾ってしまい、無関係な赤で他人のターンを
止めることになる。ここでは検査を一切せず（常駐へ CHECK は送らない）、
「session_id がこのパッケージの .flix を書いた」という印を
~/.cache/flix-checkd/<パッケージのハッシュ>/touched-<session_id のハッシュ>
へ置くだけの薄い hook にする。保存のたびに走っても軽い。

この印がある session_id だけが、after-flix-work.py で exit 2 の対象になる
（印が無いパッケージは「他人の赤」とみなし、検査そのものをしない）。

印を置くついでに、そのパッケージの常駐がまだ居なければ起動だけ頼む。作業の
区切りで初めて頼んでいた頃は、その回の検査は必ず冷たいまま（次の区切りから
やっと温かい）だった。増殖の歯止めは reserve_daemon → too_busy が持つ
（上限 MAX_DAEMONS・90 秒に 1 回・load が高ければ見送り）。

編集されたファイルの取り出し口は 2 つある。エージェントによって編集ツールの
入力の形が違うため、両方を読む:

- `tool_input.file_path` / `tool_input.path`（Edit・Write）
- `tool_input.command` にパッチ本文が丸ごと来る形（apply_patch）。
  `*** Add File:` / `*** Update File:` / `*** Delete File:` / `*** Move to:` の
  行からパスを拾う（1 パッチに複数ファイルが入りうるので全部）

exit は常に 0（このフックは何も判定しない・何も止めない）。ペイロードの形が
読めない・想定外の失敗はすべて無音で降りる（after-flix-edit.py の
edited_path() と同じ作法）。
"""

import hashlib
import importlib.util
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.realpath(__file__))
MARKER_TTL_SEC = 24 * 60 * 60  # 印は 1 日で掃除する（セッションを跨いで溜め続けない）

# apply_patch のパッチ本文でファイル名が現れる行。Delete も拾う: ファイルが
# 消えてもパッケージは型検査したい（消したモジュールを参照している側が赤くなる）。
PATCH_FILE_PREFIXES = (
    "*** Add File: ",
    "*** Update File: ",
    "*** Delete File: ",
    "*** Move to: ",
)


def _load_shared():
    path = os.path.join(HERE, "after-flix-edit.py")
    spec = importlib.util.spec_from_file_location("after_flix_edit", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def patch_paths(command):
    """apply_patch のパッチ本文からファイルのパスを全部取り出す。

    1 つのパッチが複数ファイルを含みうるので、先頭の 1 件で止めない。
    """
    out = []
    for line in command.splitlines():
        for prefix in PATCH_FILE_PREFIXES:
            if line.startswith(prefix):
                p = line[len(prefix):].strip()
                if p:
                    out.append(p)
                break
    return out


def edited_paths(payload):
    """ペイロードから編集されたファイルのパスを取り出す。

    file_path / path が来る形（Edit・Write）を先に見る。どちらも無く command が
    文字列で来る形（apply_patch）だけ、パッチ本文としても読む。
    """
    ti = payload.get("tool_input")
    if not isinstance(ti, dict):
        return []
    path = ti.get("file_path") or ti.get("path")
    if isinstance(path, str) and path:
        return [path]
    command = ti.get("command")
    if isinstance(command, str) and command:
        return patch_paths(command)
    return []


def absolutize(path, payload):
    """パッチ本文の相対パスを絶対パスにする。

    apply_patch のパスはターンの cwd 基準の相対で来る。cwd はペイロード →
    CLAUDE_PROJECT_DIR → プロセスの cwd の順に探し、実在する物を優先する。
    """
    if os.path.isabs(path):
        return path
    bases = [payload.get("cwd"), os.environ.get("CLAUDE_PROJECT_DIR"), os.getcwd()]
    cands = [os.path.join(b, path) for b in bases if isinstance(b, str) and b]
    for c in cands:
        if os.path.exists(c):
            return c
    return cands[0] if cands else path


def session_hash(session_id):
    return hashlib.sha1(session_id.encode("utf-8")).hexdigest()[:16]


def sweep_old_markers(sd):
    """古い印を掃除する。セッションは増え続けるので、居座らせない。"""
    now = time.time()
    try:
        names = os.listdir(sd)
    except OSError:
        return
    for name in names:
        if not name.startswith("touched-"):
            continue
        p = os.path.join(sd, name)
        try:
            if now - os.path.getmtime(p) > MARKER_TTL_SEC:
                os.unlink(p)
        except OSError:
            pass


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0
    if not isinstance(payload, dict):
        return 0
    paths = [p for p in edited_paths(payload) if p.endswith(".flix")]
    if not paths:
        return 0
    session_id = payload.get("session_id")
    if not isinstance(session_id, str) or not session_id:
        return 0
    try:
        afe = _load_shared()
        for path in paths:
            pkg = afe.find_pkg(absolutize(path, payload))
            if not pkg:
                continue
            sd = afe.state_dir(pkg)
            os.makedirs(sd, exist_ok=True)
            marker = os.path.join(sd, f"touched-{session_hash(session_id)}")
            open(marker, "a").close()
            os.utime(marker, None)  # 既にある印も「まだ触っている」印として鮮度を更新する
            sweep_old_markers(sd)
            if not afe.pid_alive(pkg):
                # 温め直しの数秒を作業の区切りまで持ち越さない。増殖の歯止めは
                # reserve_daemon → too_busy が持つ（上限 MAX_DAEMONS・90 秒に 1 回・
                # load が高ければ見送り）ので、ここでは「居なければ頼む」だけ。
                afe.reserve_daemon(pkg)
    except OSError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
