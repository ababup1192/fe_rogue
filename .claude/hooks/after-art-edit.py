#!/usr/bin/env python3
"""絵に関わるファイルを書いた直後に走る検査（Claude Code の PostToolUse hook）。

絵の下限はモデルの判断に任せると飛ばされるので、機械の側から必ず声を出す。
exit 2 で stderr が Claude に返る（作業自体は止めない）。

検査の中身は bin/lint-view.py と bin/lint-palette.py にある。この hook は
「書いた直後に、書いたファイルだけ」を見る薄い入口で、同じ検査は
どの OS・どのエージェントからでも次のコマンドで走らせられる:

    python3 bin/lint-view.py [ファイル...]
    python3 bin/lint-palette.py

Windows で `python3` が無い場合は .claude/settings.json の hook 行を
`python .claude/hooks/after-art-edit.py` に変える。
"""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def run(script, args=()):
    """bin/ のスクリプトを走らせ、失敗したら (True, 出力) を返す。"""
    path = ROOT / "bin" / script
    if not path.is_file():
        return False, ""
    try:
        proc = subprocess.run(
            [sys.executable, str(path), *args],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            timeout=60,
        )
    except (OSError, subprocess.SubprocessError):
        return False, ""
    if proc.returncode == 0:
        return False, ""
    return True, (proc.stdout + proc.stderr).strip()


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    raw = (payload.get("tool_input") or {}).get("file_path") or ""
    if not raw:
        return 0
    target = Path(raw)
    if not target.is_file():
        return 0

    name = target.name
    msgs = []

    # ドット絵の意味色キーが色票に実体を持つか。
    # 解けないキーは Studio が仮色で塗るので、編集画面と実機で配色が食い違う。
    if name.endswith(".sprite.json"):
        failed, out = run("lint-palette.py")
        if failed:
            msgs.append(
                "lint-palette が失敗しました。意味色キーが色票に無いと Studio が"
                "仮色で塗り、編集画面と実機で配色が食い違います。\n\n" + out
            )

    # View が矩形と円だけになっていないか。
    if name.endswith(".flix") and ("View" in name or target.parent.name == "bake"):
        failed, out = run("lint-view.py", [str(target)])
        if failed:
            msgs.append(out)

    if not msgs:
        return 0

    print("\n\n".join(msgs), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
