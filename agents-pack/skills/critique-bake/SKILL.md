---
name: critique-bake
description: bake 系ターゲットを実行し、debug/gallery の PNG・WAV 可視化(sounds.png/music.png)を目視・目聴して、設計原則に照らした批評レポートを返す。
---

# critique-bake — 焼いて批評する

引数（任意）: 対象（絵 / 音 / 両方）、注目したい場面。

## 手順

1. ゲームの設計原則を読む（共通部はこのファイル群と AGENTS.md、
   ゲーム固有の原則 — 文字なし等 — は **AGENTS.local.md** を参照）。
2. bake を実行する:
   - 絵: `make gallery-prologue`（debug/ に全場面 + all.png）や `make bake`
   - 音: `make gallery-sounds`（debug/sounds/*.wav、debug/sounds.png、debug/music.png）
3. 出力を読む。all.png・各場面 PNG は Read で目視、音は sounds.png の波形・
   スペクトログラムと music.png のピアノロールで目聴する。
4. 設計原則に照らして批評する。観点の例:
   - 原則違反（禁止事項に触れていないか）
   - 場面ごとの読み取りやすさ（何が起きているか一目で分かるか）
   - 色・音の一貫性（季節・時間帯・テーマとのなじみ）
   - 前回の焼きからの意図しない変化
5. レポートを返す: 良い点 / 問題点（該当ファイル名つき）/ 直す案の順。
   修正はしない — 批評だけ返し、直すかどうかは呼び出し側が決める。
