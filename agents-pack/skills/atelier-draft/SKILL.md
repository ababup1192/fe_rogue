---
name: atelier-draft
description: assets のスロットに対する素材候補を atelier/ に複数案つくり、焼いて自己批評して報告する。assets/ には書かない。
---

# atelier-draft — 素材候補づくり

引数: スロット（Doc の `entityId` または `assets/` のパス）+ 案数 N + 方向性（例:「もっと暖かい色」「短く鋭い音」）。

## 手順

1. スロットの Doc とその `<種類>.schema.json` を読む。スキーマが仕様書。
   `entityId` を控える（候補は同じ `entityId` を名乗ることでスロット互換になる）。
2. `atelier/` に N 案の Doc を書く。命名は `<名前>.a.<種類>.json` / `.b` / `.c` …。
   `version`・`entityId` はスロットと合わせ、`note` に方向性の意図を書く。
   **`assets/` には絶対に書かない。**
3. headless bake で焼く。絵なら `make bake` か `make gallery-prologue`、
   音なら `make gallery-sounds` など、その候補が映る適切なターゲットを選ぶ
   （候補を一時的にスロットへ差して焼く場合は、焼き終わったら必ず元に戻す）。
4. `debug/` のコンタクトシート（all.png）や波形・スペクトログラム
   （sounds.png / music.png）を目視・目聴して、案ごとに自己批評する
   （方向性に合うか、既存素材とのなじみ、ゲームの設計原則との整合）。
5. 候補一覧（ファイルパス・狙い）と批評（推し案とその理由、迷い所）を報告する。
   採用（swap 昇格）は人間の判断に委ね、勝手に昇格しない。
