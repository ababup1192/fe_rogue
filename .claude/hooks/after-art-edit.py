#!/usr/bin/env python3
"""絵に関わるファイルを書いた直後に走る検査（Claude Code の PostToolUse hook）。

絵の下限はモデルの判断に任せると飛ばされるので、機械の側から必ず声を出す。
exit 2 で stderr が Claude に返る（作業自体は止めない）。

検査の中身は bin/lint-view.py と bin/lint-palette.py にある。この hook は
「書いた直後に、書いたファイルだけ」を見る薄い入口で、同じ検査は
どの OS・どのエージェントからでも次のコマンドで走らせられる:

    python3 bin/fge view [ファイル...]
    python3 bin/fge palette
    python3 bin/fge ui-overflow --strict [ファイル...]

Windows で `python3` が無い場合は .claude/settings.json の hook 行を
`python .claude/hooks/after-art-edit.py` に変える。
"""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def run(sub, args=()):
    """bin/fge のサブコマンドを走らせ、失敗したら (True, 出力) を返す。"""
    path = ROOT / "bin" / "fge"
    if not path.is_file():
        return False, ""
    try:
        proc = subprocess.run(
            [sys.executable, str(path), sub, *args],
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
        failed, out = run("palette")
        if failed:
            msgs.append(
                "lint-palette が失敗しました。意味色キーが色票に無いと Studio が"
                "仮色で塗り、編集画面と実機で配色が食い違います。\n\n" + out
            )

    # ui.json の text が折り返し宣言漏れ (固定幅の枠 + wrap/fit なし) になっていないか。
    if name.endswith(".ui.json"):
        failed, out = run("ui-overflow", ["--strict", str(target)])
        if failed:
            msgs.append(
                "lint-ui-overflow が失敗しました。固定幅の枠内の text に wrap/fit が"
                "無いと、実行時の長い文言が枠からはみ出します。\n\n" + out
            )

    # 描画が矩形と円だけになっていないか。
    # 名前では絞らない — 描画の少ないファイルは lint-view 側の MIN_DRAWS が除外する。
    if name.endswith(".flix"):
        failed, out = run("view", [str(target)])
        if failed:
            msgs.append(out)

    if not msgs:
        return 0

    print("\n\n".join(msgs), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
