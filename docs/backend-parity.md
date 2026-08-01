# 描画部の対応表（実機と焼いた絵を食い違わせない）

絵を描く経路は 2 つある。**どちらも同じ指定（`GameEngine.Drawable` / `PolygonRenderCmd`）を
受け取り、同じ絵になっているべき**。

| 経路 | 誰が使うか |
|---|---|
| **GL**（`render_gl`） | 実機。`make run` で見える絵 |
| **SoftRaster**（`engine_tools`） | bake・golden・F8 注釈・エディタのプレビュー |

## なぜ表が要るか

この開発の流儀は 3 つとも「SoftRaster が実機と同じ絵を写している」前提に乗っている:

- 絵の開発ループ（焼いて目視して直す）
- リグレッション防護（gallery と golden のバイト比較）
- 「挙動を変えていない」の機械証明（bake 前後のバイト一致）

SoftRaster が指定を黙って落とすと、**golden は「実機と違う絵」を正しいものとして固定する**。
しかも穴は開きっぱなしになりやすい — 新しい属性を GL にだけ足しても実機では見えるので、
誰も困らないまま SoftRaster が置き去りになる（実際、傾き `rotation` はずっとそうなっていた）。

## 対応表

| 指定 | GL | SoftRaster | 備考 |
|---|:--:|:--:|---|
| position / scale / centered | ○ | ○ | |
| rotation（傾き） | ○ | ○ | 軸は四角の中心。式は両者で同一（`pos + size/2` まわり） |
| color（tint）/ alpha | ○ | ○ | |
| uvOffset / uvScale（部分矩形） | ○ | ○ | |
| 反転（scale の符号） | ○ | ○ | |
| zIndex の並び | ○ | ○ | (z, 追加順) の安定ソートで両者一致 |
| clip（窓） | ○ | ○ | 量子化は `DrawCmd.clipPixels` を共有 |
| blend（Add / Multiply） | ○ | ○ | 式は `SoftRaster.blendPixel` にテストで固定 |
| style（角丸・枠・縞・市松）on 単色 box | ○ | ○ | 枠の濃さ（borderAlpha）も両者対応 |
| 単色多角形の塗り | ○ | ○ | **縁だけ近似**: SoftRaster は Java2D の AA、GL は AA なし |
| 頂点色つき多角形（grad のグラデ） | ○ | ○ | 補間は同じ線形の式（扇割りは `DrawCmd.gradTriangles` を共有、式は `SoftRaster.gradSample` にテストで固定）。縁は両者とも画素中心判定で AA なし — 単色多角形とは縁の写りが違う |
| **style on テクスチャ / 文字** | ○ | **×** | 落とす。焼くときに件数を報告する |
| 文字の描き方 | SDF シェーダ | 出力解像度の TTF を直接 drawString | **近似**。小サイズでは焼いた方がくっきり出る |
| 宣言シェーダーの面 | 本物の GLSL | `ShaderEval` の画素評価 | **近似**。式は揃えてあるが完全一致は保証しない |

## エンジンを拡張するときの手順

描画の指定を増やしたら（`Drawable` に属性を足す・新しい `Render.Item` を作る等）:

1. **GL と SoftRaster の両方に実装する**。片方だけなら次へ。
2. SoftRaster に実装しないなら、**`SoftRaster.dropped` に 1 行足して報告させる**。
   黙って落とすのは禁止 — 焼いた絵が嘘をつく。
3. **この表を更新する**。
4. 軸や式が両者で揃っているかを、数値のテストか焼いた絵の見比べで確かめる。

`SoftRaster.dropped` の報告は `Bakery` が焼くたびに出す:

```
[bake] 焼けない指定: style on textured sprite ×3 — 角丸・枠・縞・市松は単色の box にだけ焼ける（title）
```

## まだやっていない（将来）

GL をヘッドレスで焼いて 2 経路の PNG を突き合わせる同値テスト。決定版だが、オフスクリーンの
GL 文脈を CI で用意する必要があるので、上の「落とした物を報告する」で足りなくなったら着手する。
