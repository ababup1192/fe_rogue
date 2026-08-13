#!/usr/bin/env python3
"""このセッションが .flix を編集したパッケージへ印だけ残す（PostToolUse hook）。

after-flix-work.py（Stop / SubagentStop hook）は「作業ツリーで汚れている
パッケージ全部」を見る。複数エージェントが並行で走っていると、他のセッションが
編集中の（赤くて当然の）パッケージまで拾ってしまい、無関係な赤で他人のターンを
止めることになる。ここでは検査を一切せず（常駐にも触らず・JVM も起こさない）、
「session_id がこのパッケージの .flix を書いた」という印を
~/.cache/flix-checkd/<パッケージのハッシュ>/touched-<session_id のハッシュ>
へ置くだけの薄い hook にする。保存のたびに走っても軽い。

この印がある session_id だけが、after-flix-work.py で exit 2 の対象になる
（印が無いパッケージは「他人の赤」とみなし、検査そのものをしない）。

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


def _load_shared():
    path = os.path.join(HERE, "after-flix-edit.py")
    spec = importlib.util.spec_from_file_location("after_flix_edit", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


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
    ti = payload.get("tool_input") or {}
    path = ti.get("file_path") or ti.get("path") or ""
    if not isinstance(path, str) or not path.endswith(".flix"):
        return 0
    session_id = payload.get("session_id")
    if not isinstance(session_id, str) or not session_id:
        return 0
    try:
        afe = _load_shared()
        pkg = afe.find_pkg(path)
        if not pkg:
            return 0
        sd = afe.state_dir(pkg)
        os.makedirs(sd, exist_ok=True)
        marker = os.path.join(sd, f"touched-{session_hash(session_id)}")
        open(marker, "a").close()
        os.utime(marker, None)  # 既にある印も「まだ触っている」印として鮮度を更新する
        sweep_old_markers(sd)
    except OSError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
