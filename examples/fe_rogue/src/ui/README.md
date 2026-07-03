# ui.json スキーマリファレンス

World-entity UI（`UiStore` / `UiSpec` / `UiRender`）が読む `ui.json` の正式リファレンス。
`ui.json` は「テンプレート＋上書き」方式で UI ノード木を宣言する。`UiSpec.parse` が
ファイル内容を `Spec`（テンプレ解決済みノード木）へ純粋に畳み、`spawnRoot` が各ノードを
entity として `UiStore` に登録する。見た目は `UiRender` が毎フレーム描く。

## トップレベル

```json
{
  "templates": { "<名前>": { ...部分ノード... } },
  "root": { ...ノード... }
}
```

| キー | 型 | 必須 | 説明 |
|------|----|----|------|
| `root` | ノード | 必須 | UI ツリーの根ノード。1 ファイル 1 root。 |
| `templates` | オブジェクト | 省略可 | テンプレート辞書。既定値のまとまりで、各ノードが `use` で参照する。省略時は空。 |

`root` が無い、またはトップレベルが JSON オブジェクトでない場合は parse エラー。
各テンプレート値は JSON オブジェクトでなければならない。

## ノード共通キー

| キー | 型 | 既定 | 説明 |
|------|----|----|------|
| `name` | 文字列 | 必須 | 兄弟内で一意な識別名。名前パスの構成要素。**空文字・`/` 含みは不可**（名前パスを壊す）。 |
| `widget` | 文字列 | `"none"` | 描画種別。`"box"` / `"text"` / `"sprite"` / `"poly"` / `"none"`（レイアウト専用コンテナ）。未知値は不可。 |
| `use` | 文字列 | なし | 参照するテンプレート名。テンプレ値を既定にノード側フィールドで上書きする。未定義名は不可。 |
| `visible` | 真偽 | `true` | 初期可視。祖先が不可視なら子も不可視（継承）。 |
| `bind` | 文字列 | なし | text の流し込み先 bind key。実行時に `UiBinding.apply` が値を解決して text へ入れる。 |
| `meta` | 文字列 | なし | メニュー項目等の識別 metadata。選択解決（`choiceOf` 等）が読む。 |
| `layer` | 整数 | `0` | **root のみ有効**（非 root では無視）。`CanvasLayer.layerStride` 倍して zIndex に加算し、他 HUD と同じ z 序列へ合流する。 |
| `children` | 配列 | `[]` | 子ノード（宣言順）。兄弟の `name` は全て相異なること。 |

## スタイル（レイアウト属性・全 widget 共通）

Flexbox 風の縦横並べ。位置とサイズは `UiLayout` が決めるため、box/text/sprite 自身は寸法を持たない。

| キー | 型 | 既定 | 説明 |
|------|----|----|------|
| `dir` | 文字列 | `"column"` | 主軸方向。`"row"` / `"column"`。 |
| `gap` | 数値 | `0.0` | 子どうしの間隔（主軸方向、px）。 |
| `pad` | 数値4要素 | `[0,0,0,0]` | 内側余白 `[left, top, right, bottom]`。要素数 4 以外は不可。 |
| `width` | 数値 / `"auto"` / `"grow"` | `"auto"` | 幅。数値=固定 px、`"auto"`=内容ぴったり、`"grow"`=余白を伸びて占有。 |
| `height` | 数値 / `"auto"` / `"grow"` | `"auto"` | 高さ。`width` と同じ。 |
| `mainAlign` | 文字列 | `"start"` | 主軸の寄せ。`"start"` / `"center"` / `"end"` / `"spaceBetween"`。 |
| `crossAlign` | 文字列 | `"start"` | 交差軸の寄せ。`"start"` / `"center"` / `"end"` / `"stretch"`。 |
| `abs` | 数値2要素 | なし | フロー外オフセット `[x, y]`。指定するとフロー配置を外れて絶対位置に置く。要素数 2 以外は不可。 |

## box（`widget: "box"`）— 単色塗り矩形

| キー | 型 | 既定 | 説明 |
|------|----|----|------|
| `color` | `"#rrggbb"` | 必須 | 塗り色。 |
| `alpha` | 数値 | `1.0` | 不透明度 0.0〜1.0。 |
| `zIndex` | 整数 | `0` | 重なり順（後述）。 |
| `cornerRadius` | 数値 | `0.0` | 角丸半径（px、0=角丸なし）。 |
| `borderWidth` | 数値 | `0.0` | 枠線幅（px、0=枠なし）。 |
| `borderColor` | `"#rrggbb"` | 白 | 枠線色。 |

## text（`widget: "text"`）— テキスト

| キー | 型 | 既定 | 説明 |
|------|----|----|------|
| `text` | 文字列 | `""` | 表示文字列。`bind` だけのノードは空で始まり実行時に流し込む。 |
| `font` | 文字列 | `"ui"` | フォント名（atlas 引き当てキー）。 |
| `fontSize` | 数値 | `8.0` | 表示サイズ。 |
| `tint` | `"#rrggbb"` | 白 | 文字色。 |
| `zIndex` | 整数 | `0` | 重なり順。 |

## sprite（`widget: "sprite"`）— スプライト

| キー | 型 | 既定 | 説明 |
|------|----|----|------|
| `texture` | 文字列 | 必須 | テクスチャ名。 |
| `regionRect` | `{"pos":[x,y],"size":[w,h]}` | なし | アトラス切り出し矩形（px）。省略でテクスチャ全体。 |
| `scale` | 数値2要素 | `[1,1]` | 拡大率 `[x, y]`。 |
| `flipH` / `flipV` | 真偽 | `false` | 水平／垂直反転。 |
| `tint` | `"#rrggbb"` | 白 | 着色。 |
| `zIndex` | 整数 | `0` | 重なり順。 |
| `hframes` / `vframes` | 整数 | `1` / `1` | スプライトシートの格子分割（列数／行数）。 |
| `frame` | 整数 | `0` | 表示セル index = `row * hframes + col`。 |

`regionRect` を持たず `hframes * vframes > 1` のとき、extract がテクスチャ寸法を引いて
`frame` からセル矩形を導く。分割規則は engine の `Sprite2D` と同じ:
`cellW = texW / hframes`、`cellH = texH / vframes`、`col = frame mod hframes`、`row = frame / hframes`。

## poly（`widget: "poly"`）— 塗り潰し多角形

| キー | 型 | 既定 | 説明 |
|------|----|----|----|
| `points` | `[[x,y], ...]` | 必須 | 頂点列（3 点以上）。ノードのレイアウト矩形**左上を原点**とするローカル design px。 |
| `color` | `"#rrggbb"` | 必須 | 塗り色。 |
| `alpha` | 数値 | `1.0` | 不透明度 0.0〜1.0。 |
| `zIndex` | 整数 | `0` | 重なり順。 |

box/text/sprite が Drawable（sprite チャンネル）に出るのに対し、poly は engine の `PolygonRenderCmd`
（polygon チャンネル）に出る。`width`/`height` は他 widget と同じくレイアウトが占める寸法を決め、
`points` はその矩形左上を基準に置く。extract が矩形左上を各頂点へ足して design 空間の絶対座標へ移し、
root の `layer` オフセットは zIndex に加算される。`points` が 2 点以下、または各要素が `[x, y]` でなければ
parse エラー。用途例: TopBar 中央の「集合中」ラベル左の再生（▶）マーク。

## 名前パスとコード契約

各ノードは root 名を起点に `"root/child/grandchild/..."` の**名前パス**で一意に引ける。
ゲームコードは名前パス（文字列定数）でノードを指す（例 `"TopBar/phaseRow/phaseDot"`）。

- **名前パスはコードとの契約**。ノードの `name` を変えると、そのノード配下の名前パスが全て変わる。
  リネームするときはコード側のパス定数（各 UI モジュールの `xxxPath()`）も併せて直すこと。
- `name` に `/` を入れたり空にしたりできない（parse エラー）。区切りが曖昧になるため。

## zIndex と兄弟順

`zIndex` は省略可（既定 0）。extract は `(zIndex, 階層深さ, order, id)` の安定ソートで
背面→前面に並べる。同じ `zIndex` なら**宣言順（兄弟順）が効く**ので、単純な前後関係は
`zIndex` を書かず宣言順で済ませられる。

## 動的状態はリロードを生き延びる

以下はファイル由来でなくゲームが実行時に設定する状態で、`UiSpec.reloadAll`（F1 ホットリロード）
の respawn を跨いで保たれる:

- **selection**（リスト選択カーソル）／**focus**（モーダル占有）: 名前パス（String）をキーに持つため
  entity 再採番の影響を受けない。
- **visible**（可視）: respawn が despawn 前の「名前パス→可視」を採取し、再 spawn 後に同じ
  名前パスへ引き継ぐ。ゲームが動的に隠した／見せたノードはリロード後も同じ見え方になる
  （再 spawn で新設したノードだけ `ui.json` 既定の可視に戻る）。

color / text / tint など毎フレーム同期される見た目は、リロード直後の次フレームで各 UI モジュールの
`step` / `frameStep` が塗り直すので気にしなくてよい。

## 新しい UI パーツの作り方（3 ステップ）

1. `src/ui/assets/<Name>.ui.json` を作り、root とツリーを宣言する。
2. 対応する UI モジュール（`<Name>Ui.flix`）に `pub def specPath()` を置き、`AssetPath.resolve`
   でそのファイルを指す。可視トグルや選択で触るノードの名前パスを `xxxPath()` 定数に切り出す。
3. 起動時に一度 `UiSpec.spawnAsset(specPath(), ui)` で組み込む（`UiStore` へ spawn し、リロード
   台帳 `sources` に登録する）。以後 F1 の `reloadAll` が `sources` を辿って自動でリロードする。

## 1 アセットを複数 root で使う（別名 spawn）

同じ `ui.json` を別々の root として複数枚出したいとき（例: ユニット簡易カードを味方=左 /
敵=右の 2 枚に使う）は `UiSpec.spawnAssetAs(path, rootName, ui)` を使う。spec の root 名を
`rootName` に差し替えてから spawn し、`rootName` をキーに `sources` へ登録する。

- `sources` のキー（登録した root 名）は名前パス機構とコードの契約であり、リロードの権威でもある。
  `reloadAll` → `reloadOne` は読み直した spec の root 名を **常にこのキーへ強制的に付け直して**
  respawn する。ゆえに ①別名 spawn した root が同じキーで正しくリロードされ、②`ui.json` 側の
  root `name` を書き換えても旧キーの孤児ツリーが残らない（登録キーが勝つ）。
