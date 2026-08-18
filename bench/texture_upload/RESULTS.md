# texture_upload 計測記録

環境: この Mac (Apple Silicon) / vsync off / design 320x240 / 1 フレームに 320x240 の ARGB を 2 枚
GPU へ上げる（毎フレーム焼いたアトラスを差し替えるゲームの使い方）。画素の中身は毎フレーム同じ物を
使うので、画素を作る費用は入っていない。

計測の流儀: **A/B は必ず背中合わせで取る**（`bench/sprite_stress/RESULTS.md` と同じ）。
区間ごとにやり方を切り替えて 1 回の実行の中でペアを取り、「何も上げない」区間をその時の床として添える。

区間の意味:

| mode | 中身 |
|---|---|
| none | 何も上げない（床） |
| old  | 直す前の `RenderTexture.uploadArgb`（`BufferUtils.createIntBuffer` → 1 要素ずつ `put` → `glTexImage2D`） |
| bulk | 写し方だけ直した形（`memAllocInt` → `int[]` のまま一括 `put` → `glTexImage2D`） |
| new  | いまの `RenderTexture.updateTexturePixels` |

## 2026-08-18 の実測（200frame/区間・4 往復・数字は 4 回の平均）

| mode | frame_avg | frame_p50 | frame_p99 | upload_avg |
|---|---|---|---|---|
| none | 1.65ms | 1.05ms | 5.14ms | 0.00ms |
| old  | 2.83ms | 2.31ms | 6.20ms | 1.32ms |
| bulk | 2.03ms | 1.40ms | 5.42ms | 0.68ms |
| new  | 2.19ms | 1.33ms | 5.56ms | 0.68ms |

床を引いた「上げるのに増えた分」:

| | old | new | 差 |
|---|---|---|---|
| frame_avg | +1.17ms | +0.54ms | **−0.63ms** |
| frame_p50 | +1.27ms | +0.29ms | **−0.98ms** |
| upload_avg | 1.32ms | 0.68ms | **−0.65ms**（−49%） |

別の走りでは frame_avg の差が −0.86ms、frame_p50 の差が −1.04ms だった。
**frame_p50 と upload_avg は走りをまたいで安定していて、frame_avg だけがぶれる**
（外れフレームが平均を押す）。

`docs/performance.md` の足切り（R3 のフレーム時間 avg 8ms に対して 1 割 = 0.8ms）に照らすと、
**frame_p50 では超え（−1.0ms = 12%）、frame_avg では 8〜11% で線をまたぐ**。線の上に乗せた判断は
`docs/performance.md` の改修一覧に書いた。

## 効きはどこから来たか

- **写し方（1 要素ずつ → 一括）が全部**。old → bulk で upload_avg が 1.32 → 0.68ms。
- **`glTexSubImage2D` は効かなかった**。bulk（`glTexImage2D` のまま）と new を並べても
  0.68ms 対 0.68ms で、走りをまたいでも差が出ない。辺長が同じときだけ `glTexSubImage2D` へ
  分ける案は**測って入れないと決めた**（分岐だけ増えて数字が動かない）。
- 残る 0.68ms はドライバが 300KB×2 を転送する分で、CPU 側の写しは 0.02ms しかない
  （GL を開けない所での実測。`render_gl/test/TestTextureUpload.flix` が前提を固定している）。

## 絵が変わっていないこと

`make gl-parity` が 6 場面すべて **一致 (0 px)**（`spriteNearest` / `texField` が
テクスチャのアップロード経路を通る）。
