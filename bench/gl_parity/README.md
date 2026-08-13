# gl_parity — GL と SoftRaster の突き合わせ harness

同じ描画指定（`Render.PlacedItem` の列）を GL（実機の絵）と SoftRaster（bake・スナップショットの絵）の
両方で 1 コマ焼き、画素を機械で突き合わせる。スナップショットは作らない — 基準は「もう片方の経路」。

## 回し方

```
make gl-parity            # リポジトリのルートから
make -C bench/gl_parity run   # ここから直接でも同じ
```

- 隠し窓（`FLIX_GE_HIDDEN=1`）で GL を焼くので画面には何も出ない。
  窓を見たいときは `FLIX_GE_HIDDEN` を立てずに `../../bin/flix run`。
- 結果は 1 行 1 scene の表（`[parity] <scene> <段> <一致 or 差>`）。
  A 段（バイト一致を保証する層）に不一致があると exit 1。
- 不一致の絵は `debug/diff/` に「GL | Soft | 違いヒート」で並ぶ。
  GL の絵は `debug/gl/`、SoftRaster の絵は `debug/soft/`。

## 線引き

何が「バイト一致」で何が「近似」かは docs/backend-parity.md の表が正典。
A 段の scene に入れてよい絵の条件（整数座標・k/255 の色・軸平行縞のみ等）は
scene ファイル（src/Scenes.flix）の冒頭に書いてある。

## 注意

- flix.toml の `github:ababup1192/flix_game_engine` の行を消すと、`make sync` 系の
  lib 差し替え配管（エンジン最新の fpkg を受け取る仕組み）から外れる。消さないこと。
