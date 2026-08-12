# Render に回転を通す（Box / Text / 群回転）— 計画と実装結果

**状態: 実装済み（2026-07-25）**。フェーズ 1〜6 まで完了。決めごとから変わった点と、残った穴は
末尾の「実装で決まったこと」に書く。


きっかけ: neon_deck（Balatro 風）でカードを傾けたい。いまは Sprite だけが回転を持ち、
Box（＝カードの面）と Text（＝ランク表記）は回せない。カード 1 枚は
「Box 2 枚 + Text + Pip(Poly)」の集まりなので、本当に欲しいのは
**「まとめて 1 つの軸のまわりに傾ける」** という操作。

## 1. 調べてわかった事実（前提）

| 事実 | 場所 |
|---|---|
| `Drawable` は元から `rotation` を持つ（**ラジアン**・**矩形の中心まわり**） | `engine/src/core/DrawCmd.flix:80`, `render_gl/src/Sprite.flix:55,67-79` |
| GL 経路は Box もテキストも同じ Drawable で描くので、**GL 側の改修は不要** | `render_gl/src/Frame.flix:254` |
| `Render.Item` で回転を持つのは Sprite だけ。Box / Text は 0.0 固定で流している | `engine_world/src/Render.flix:637,550` |
| Poly は `Render.rotated` / `rotatedAround`（**回転数**・1 周 = 1.0）で頂点を回せる | 同 340-350 |
| **SoftRaster は rotation を完全に無視している** | `engine_tools/src/SoftRaster.flix`（`rotation` の参照が 0 件） |
| いまリポジトリ全体で rotation に 0 以外を入れている箇所は **ゼロ** | 全 `*.flix` grep |

**一番大事なのは 5 行目**。生成（golden・F8 注釈・エディタのプレビュー）は SoftRaster が描くので、
回転を足しても生成した絵には出ない＝「目で確かめる」「golden で守る」ができない。
つまり SoftRaster 対応は付け足しではなく、この計画の必須部分。

**6 行目のおかげで単位を揃え直せる**。いま Sprite はラジアン、`rotated` は回転数とバラバラだが、
実際に 0 以外を使っている場所が無いので、**全部を「回転数（1 周 = 1.0）」に統一**しても
今日の絵は 1 ピクセルも変わらない（cos0/sin0 のまま）。golden のバイト一致で機械的に証明できる。

## 2. 設計の決めごと

1. **単位は回転数（1 周 = 1.0・正で時計回り）**。`Render.rotated` と ui.json の poly に合わせる。
   ラジアンへの変換は Drawable を作る出口（`spriteDrawable` / `boxDrawable` / `textDrawables`）で 1 回だけ。
2. **回す軸（pivot）は種類ごとに 1 つに決める**。分岐を増やさないため。
   - Box: その矩形の中心（GL の式がそもそも中心まわりなので、ただ流すだけ）
   - Text: 置き場所（`at`）そのもの＝文字列の左上。文字ごとの四角を `at` まわりに回して置き直す
   - Sprite: 既存どおり自分の中心
   - Poly: 頂点に対する既存の `rotated` をそのまま使う
3. **群回転は enum を増やさず、`PlacedItem` の列に対する純関数にする**。
   `Clipped` のような入れ子ケースを足すと、Annotate / UiExtract / Light / editor_server など
   `Item` を見る全部の場所に分岐が増える。列を写す関数なら追加分岐はゼロ。

### API 案（`Render` に 2 本だけ足す）

```flix
/// item 自身を t（1 周 = 1.0）回す。軸は種類ごとの既定（Box=中心 / Text=置き場所 / Sprite=中心）。
/// Poly は頂点に対する rotated を使うこと（ここでは素通し）。
pub def turned(t: Float64, item: Item): Item

/// 置き場所つきの列を、pivot（画面座標）のまわりにまとめて t 回す。
/// カード 1 枚のような「Box と Text と Poly の集まり」を丸ごと傾ける入口。
pub def turnedAll(t: Float64, pivot: Vec2.Vec2, items: List[PlacedItem]): List[PlacedItem]
```

`turnedAll` の中身は「各 item の“軸となる点”を pivot まわりに回して `at` を置き直し、
自分自身も t だけ回す」。Poly だけは頂点を `rotated(t)` してから `at` を回す。

### やらないこと（v1 の線引き）

- `Clipped` の窓は回さない（窓は画面に平行な矩形のまま）。中身だけ回る。ui.json の poly と同じ割り切り。
- `Shader` の面は回さない（uv の意味が変わるため。必要になったら spec 側の Rotate で回す）。
- F8 注釈の当たり矩形は回転前の外接矩形のまま（傾いた札のクリック判定はゲーム側の責任）。

## 3. 手順（フェーズ）

| # | 内容 | 触るファイル | 目安 |
|---|---|---|---|
| 1 | `Item.Box` / `Item.Text` に `rotation` を足し、出口でラジアン変換。Sprite も回転数へ読み替え | `engine_world/src/Render.flix`（+ 構築している 8 ファイル。ほぼテスト） | 0.3 日 |
| 2 | `turned` / `turnedAll` を追加 | 同上 | 0.2 日 |
| 3 | **SoftRaster を回転対応**（`drawBox` / `drawTextured` / `drawGlyph` に AffineTransform、`drawableAabb` を回転後の外接矩形に） | `engine_tools/src/SoftRaster.flix` | 0.3 日 |
| 4 | テスト（純投影）＋ golden の据え置き確認 | `engine_world/test/TestRender.flix` | 0.2 日 |
| 5 | ui.json 宣言（box / text に `rotation`。UiSpec 経路は poly と同じく loud に Err） | `engine_world/src/UiDoc.flix`, `UiSpec.flix`, `docs/ui.schema.json` | 0.3 日 |
| 6 | 配布（`make sync-engine-world` → engine_full 再ビルド → neon_deck の lib へ) と neon_deck のカード傾き実装 | Makefile 経由 + `neon_deck/src/View.flix`, `CardLayout.flix` | 0.2 日 |

合計 **約 1.5 日**。フェーズ 5 は後回し可能（neon_deck はコードから呼ぶため）。ただし
「新しい表現は JSON で宣言できる形にする」という約束があるので、同じリリースに入れたい。

## 4. テストと検証

- **純投影テスト**（`TestRender`）: 数値で決まる話なので、ここは書く価値がある。
  - 90 度（t=0.25）回した Box の Drawable の rotation が τ/4 になる
  - `turnedAll` で pivot＝自分の中心なら `at` が動かない
  - `turnedAll(0.5, pivot)` を 2 回かけると元に戻る（往復）
  - Text を回すと文字の四角の中心が `at` まわりに回っている
- **今の絵が変わらない証明**: 回転 0 のままの `make bake-par` → `git status` で
  gallery / golden の差分ゼロ（単位の読み替えが無害だと機械的に示す）。
- **回転が効く証明**: neon_deck に傾けたカードの生成シーンを 1 枚足して目視 → golden に祝福。
  GL 実機（`make run`）と生成した絵が同じ傾きに見えるかも確認する（SoftRaster と GL の式が揃っているか）。
- 波及パッケージ: `make test-engine-world` と `make test-engine-tools`、他は `flix check`。

## 5. リスク

- **SoftRaster と GL の傾きがズレる**のが一番怖い。AffineTransform の回転中心を
  GL の式（`pos + size/2`）と同じ点にすること。ズレは生成した絵と実機の見比べで発見できる。
- **テキストの回転はグリフ単位**なので、大きく回すと字間がわずかに変わる可能性がある。
  カードの傾き（±5 度程度）では問題にならない想定。強く回す用途が出たら再検討。
- Item のレコードにフィールドを足すと、リテラルで組んでいる 8 ファイルがコンパイルエラーになる
  （読み出し側の match は壊れない）。機械的な追随で済む。

## 6. 実装で決まったこと（計画からの差分）

- **Poly は素通しにしなかった**。`turned` は Poly の頂点を回す（軸は置き場所）。そうしないと
  「箱＋文字＋多角形」の集まりを丸ごと傾けたときに多角形だけ取り残される。
- **ui.json の box / text / 図形 widget は UiDoc 局所の `BoxSpec` / `TextSpec` / `ShapeSpec` で包んだ**
  （poly の PolySpec と同じ流儀）。図形は計画の範囲外だったが、フィールドが平置きの ui.json では
  `"widget":"star","rotation":0.1` と書けてしまい黙って無視される穴になるため一緒に塞いだ。
  共有型 `UiWidget.BoxComp` を汚さないので、UiStore 経路は素の Comp のまま。UiSpec 経路は
  傾き指定を loud に Err する。
- **SoftRaster は AffineTransform で回す**。軸は GL の式（`pos + size/2`）と同じ点。dirty-rect の
  外形も回転後の外接矩形へ広げた（広げないと Add / Multiply 合成で角が欠ける）。

### 検証の結果

- engine_world 678 / engine_tools 34 / neon_deck 55 とも green。
- `make bake-par` 後の gallery / golden の差分ゼロ = 単位（ラジアン→回転数）の読み替えが
  既存の絵を 1 バイトも変えていない。
- neon_deck のカードを扇状に傾けて生成し、箱・文字・スート記号が一緒に回ることを目視で確認 →
  golden 祝福済み。GL 実機（`make run`）との見比べも確認済み。

### 残った穴（既知・今後の判断）

1. **Sprite の rotation の単位が変わった**（ラジアン → 回転数）。リポジトリ内に 0 以外の利用は
   無かったので今日の絵は変わらないが、外部のゲームが直に値を入れていれば意味が変わる。
   リリースノートに書くこと。
2. F8 注釈・UI の当たり判定は傾ける前の矩形のまま。

## 7. 別枠: DragRow 昇格（同じ HANDOFF の項目 5）

neon_deck で手札とジョーカーの 2 例が出たので、マウスの並べ替えを engine_world の汎用層へ
持ち上げられる。ただし**この回転の件とは独立**で、混ぜると検証が絡まる。
回転を出してから、別のリリースで扱うことを勧める。
