---
name: wire-doc
description: まだコードに繋がっていない Doc(JSON)を、既存の loader パターン(fromJson/defaults/fail-open, watchFile)を踏襲して配線し、橋渡しテストを最大3本書く。
---

# wire-doc — 未配線 Doc の配線

引数: 未配線の Doc ファイル（例: `assets/foo.kind.json`）。

## 手順

1. 既存の Doc loader を1つ読んで、パターンを確認する
   （`fromJson` 系の変換、`defaults`（既定値はコード側）、fail-open —
   壊れた入力で落とさず既定値へ倒す）。
2. 同じ形で新しい loader を書く。`<種類>.schema.json` が無ければ書き、
   `project.json` の `editor.resources[]` に宣言する。
3. Main（App 起動部）に `App.watchFile` の配線を足し、保存即反映にする。
   既存の watchFile 配線をお手本にする。
4. 橋渡しテストを **最大3本** 書く:
   - 壊れた JSON → 既定値に倒れる
   - 1 フィールド上書き → その値だけ変わる
   - rows があるなら、rows の長さに追随する
   期待値は Doc の既定値（コード側の defaults）から導き、数値リテラルを貼らない。
5. `make check` → `make test` で確認して報告する。
