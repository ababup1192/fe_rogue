#!/usr/bin/env python3
"""文脈が太ったら「NOTES.md に 3 行残して /clear」を促す（PostToolUse hook）。

毎ツール後に走るので軽さ最優先。transcript の全パースはせず、末尾 64KB だけ
読んで最後の usage 行から文脈トークン数を概算する。1ms 級で済ませたいため。

exit 2 + stderr が Claude への注入になる。想定外は何が起きても無音の exit 0。
フックの都合で作業を壊さないことを最優先する。
"""

import json
import os
import sys
import tempfile

# 初回はここで注入し、以後 STEP 増えるごとに再注入する。
# 130k は実セッションの実測から: 短いセッションは 100k 未満で終わり、
# 長丁場は 130k を超えて伸び続ける（800k 到達例あり）ため、この境で切る。
THRESHOLD = 130000
STEP = 30000

# 末尾だけ読む量。usage 行は数百バイトなので 64KB あれば直近の数十行が入る。
TAIL_BYTES = 65536


def read_context_tokens(path):
    """transcript 末尾から現在の文脈トークン数を概算する。見つからなければ None。"""
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        if size > TAIL_BYTES:
            f.seek(size - TAIL_BYTES)
        # 途中から読むので先頭行が途切れうる。decode 失敗と JSON 失敗は捨てる
        text = f.read().decode("utf-8", errors="replace")
    last = None
    for line in text.splitlines():
        # json.loads を全行に掛けると重いので、印のある行だけ試す
        if "cache_read_input_tokens" not in line:
            continue
        try:
            record = json.loads(line)
        except ValueError:
            continue
        message = record.get("message")
        if not isinstance(message, dict):
            continue
        usage = message.get("usage")
        if isinstance(usage, dict) and "cache_read_input_tokens" in usage:
            last = usage
    if last is None:
        return None
    # cache_read だけだと不足する: 初回ターンは cache_creation 側に大きく積まれる
    return (
        int(last.get("cache_read_input_tokens") or 0)
        + int(last.get("cache_creation_input_tokens") or 0)
        + int(last.get("input_tokens") or 0)
    )


def marker_path(session_id):
    # セッション ID をそのままファイル名にすると変な文字が混ざる余地があるので、
    # 英数とハイフン以外は落とす
    safe = "".join(c for c in session_id if c.isalnum() or c == "-")
    return os.path.join(tempfile.gettempdir(), "claude-session-diet-" + safe)


def read_notified_level(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return 0


def main():
    payload = json.load(sys.stdin)
    transcript_path = payload.get("transcript_path")
    session_id = payload.get("session_id")
    if not transcript_path or not session_id:
        return 0
    if not os.path.isfile(transcript_path):
        return 0

    tokens = read_context_tokens(transcript_path)
    if tokens is None or tokens < THRESHOLD:
        return 0

    # レベル = しきい値を何段超えたか。同じ段では 2 度言わない（連発すると
    # 注入自体が文脈を太らせて逆効果になる）
    level = (tokens - THRESHOLD) // STEP + 1
    marker = marker_path(session_id)
    if read_notified_level(marker) >= level:
        return 0
    try:
        with open(marker, "w", encoding="utf-8") as f:
            f.write(str(level))
    except OSError:
        pass

    man = tokens / 10000.0
    sys.stderr.write(
        "# session-diet: 文脈が約{0:.0f}万トークンまで太っています。"
        "1ターンの費用が上がり続けるので、キリの良い所で NOTES.md 先頭に"
        "「次やること」3行を書き、ユーザーに /clear を提案してください。\n".format(man)
    )
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except BaseException:
        # フックの失敗で作業を止めない。理由を問わず黙って降りる
        sys.exit(0)
