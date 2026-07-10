#!/usr/bin/env bash
# jump_probe — リモートデバッグでジャンプ曲線を再現・観測する台本。
#
# 使い方:
#   1. 別ターミナルで  DEBUG=1 DEBUG_HTTP_PORT=7777 bin/flix run  で起動しておく
#   2. ./debug/jump_probe.sh            （ポートは第1引数で変えられる）
#
# 見るもの: 満タンジャンプ 24 フレームで vy がほぼ 0（頂点）→ 落下 → until=sfx:land で
# 着地の瞬間に止まる。view=full にすれば world.json 全文（タイマー・パラメータ込み）が返る。
set -euo pipefail
PORT="${1:-7777}"
BASE="http://127.0.0.1:${PORT}"

echo "== halt（ロックステップへ）=="
curl -s -X POST "${BASE}/halt"; echo

echo "== 接地静止まで流す（最大 120f・無音 30f 続いたら早期停止）=="
curl -s -X POST "${BASE}/step?view=status&until=quiet:30" --data 'idle 120'; echo

echo "== 満タンジャンプ: 24f 押しっぱなし → 頂点（vy ≈ 0 を確認）=="
curl -s -X POST "${BASE}/step?view=status" --data 'hold space 24'; echo

echo "== 落下 → 着地で停止（until=sfx:land）=="
curl -s -X POST "${BASE}/step?view=status&until=sfx:land" --data 'idle 120'; echo

echo "== 短押し比較: 4f タップ → 頂点が低い =="
curl -s -X POST "${BASE}/step?view=status" --data $'hold space 4\nidle 20'; echo

echo "== resume（リアルタイムへ戻す）=="
curl -s -X POST "${BASE}/resume"; echo
