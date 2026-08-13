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
| `defaultFont` | 文字列 | 省略可（`"ui"`） | `font` を明示しない text ノードが使う既定フォント名。全 text が同じフォントのページで各ノードの `"font"` 反復を 1 行に畳める。 |

`root` が無い、またはトップレベルが JSON オブジェクトでない場合は parse エラー。
各テンプレート値は JSON オブジェクトでなければならない。

## ノード共通キー

| キー | 型 | 既定 | 説明 |
|------|----|----|------|
| `name` | 文字列 | 必須 | 兄弟内で一意な識別名。名前パスの構成要素。**空文字・`/` 含みは不可**（名前パスを壊す）。 |
| `widget` | 文字列 | `"none"` | 描画種別。`"box"` / `"text"` / `"sprite"` / `"poly"` / `"none"`（レイアウト専用コンテナ）。未知値は不可。 |
| `use` | 文字列 | なし | 参照するテンプレート名。テンプレ値を既定にノード側フィールドで上書きする。未定義名は不可。 |
| `visible` | 真偽 | `true` | 初期可視。祖先が不可視なら子も不可視（継承）。`false` のノードは**レイアウトからも除外**され、その部分木は場所を取らない（CSS の `display:none` 相当）。フロー内の兄弟は隙間を詰め、`abs` の子も配置されない。`height:auto` の親は可視な子だけで高さが決まるので、項目を隠すと窓が縮む。 |
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
| `font` | 文字列 | トップレベル `defaultFont`（無ければ `"ui"`） | フォント名（atlas 引き当てキー）。 |
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

**poly は凸単位で持つ**。実機レンダラは `GL_TRIANGLE_FAN`（凸前提）で塗るため、凹多角形は正しく塗れず
潰れる（中空リングは塗り潰しになる）。ui.json の `points` で宣言できるのは**単一の凸多角形**。中空リング
（アヌラス）や凹形状は、実行時に `UiStore.setPolyPolys(path, polys)` で**凸サブポリゴンの列**
（`List[List[Vec2]]`。各要素が 1 つの凸多角形）を流し込む。1 サブポリ = 1 `PolygonRenderCmd`。
例: `TurnEndHoldUi` の充填リングは外周 2 点＋内周 2 点の凸クアッドをセグメントぶん並べて渡す
（engine `Arc2D.toRenderCmds` と同じ分割）。

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

## 窓ごとの前後は z-index の範囲で分ける（同 layer に複数窓が重なるとき）

同じ `layer` に複数の root（窓）が同時に見え、かつ**重なって開く**とき（例: ActionMenu の右隣に
WeaponSelect が被さる）は、後から手前に出す窓に **`zIndex` の帯を丸ごと上へ確保**する。extract は
全 root の drawable を `zIndex` 単位でフラットに並べるため、窓どうしが同じ帯（panel/header/highlight/
text が同じ値域）だと、後ろの窓の text が前の窓の panel の上へ載って交錯する（窓単位の前後にならない）。

- 帯は窓ごとに間隔を空けて割り当てる。例: ActionMenu = panel110 / header118 / highlight119 / text120-121、
  その手前に出す WeaponSelect = panel130 / header138 / highlight139 / text·icon140-142。
- 帯の中の相対序列（panel<header<highlight<text）は各窓で保つ。窓間の分離は帯の**下駄**（+20 等）で付ける。
- 別 `layer` の窓（CanvasLayer が別）は `layer` 差で既に分離されるので、この帯調整は要らない。

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

## 選択メニューの標準構成（塗り箱ハイライト + 固定行ピッチ）

縦並びの選択メニュー（ActionMenu / WeaponSelect / ItemMenu / GameOverMenu / SuspendConfirm）は、選択行を
**塗り箱ハイライト**で示し、行は**固定ピッチ**で並べる。新しいメニューもこの構成に揃えること。

- **項目数が窓（表示行数）を超えうるメニューはウィンドウ化する**（ItemMenu の在庫は個数上限なし・
  重量制のみ）。表示行を固定数の窓にし、`windowOffset`（選択が窓に入るよう表示 offset をクランプする
  純関数）で `items[offset..offset+行数)` を各行へ流し込む。ハイライトは窓内の相対行 `sel − offset` に置く。

- **項目行は固定高**にする。`menu` を `gap: 0.0` にし、各項目（またはそれを包む行コンテナ）へ
  `height: <行ピッチ>` を Px で与える。行ピッチが固定なので、後述の塗り箱を**レイアウト結果を
  読み戻さずに**決定論的に置ける（`= inset + sel × 行ピッチ`）。1 行テキストは行コンテナ
  （`none`, `mainAlign: center`）で包んで `label` text を上下中央に置く（テキストは矩形左上に
  描かれるため、固定高セルに直に置くと上寄せになる）。項目の `meta` は行コンテナ側に持たせる
  （`UiMenu.itemIds` は `menu` 直下の meta 持ち子を項目列と見なす）。

- **塗り箱ハイライト**は `menu` 直下に **abs 子** として 1 枚宣言する（項目より背面 z、`box`）。
  塗り・枠・角丸・寸法は ui.json 側で固定宣言し（行セルより `inset` 分だけ小さくして隣行と
  接しないようにする）、位置だけ毎フレーム `UiMenu.applyHighlight({listPath, highlightPath, sel,
  rowPitch, inset}, ui)` が選択行へ動かす。配色は `fill #16314f / 枠 #2f6df0 0.5px / cornerRadius 2`
  （inset 0.5）。

- **選択行の文字色は変えない**（通常色のまま）。選択は塗り箱で示すので、文字色まで変えると
  二重強調になる。disabled 項目だけ淡色にする。

- **防御**: 毎フレームの `frameStep` で `UiMenu.clampSelection`（または同等のクランプ）で選択を
  `[0, 項目数)` に収める。動的に項目を流し込むメニューは、スロット数超過を `bug!` で弾く。
  ui.json のスロット数とコード側の `maxSlots()` は一致させる（実 asset を parse して数える
  テストで pin する）。

## 移行完了サマリ（HUD / メニュー / 画面はすべて World-entity UI）

ゲームの HUD・メニュー・全画面 UI は全部この World-entity UI（`UiStore` / `UiSpec` / `UiRender`）に
載っている。`scene.json` / `Scene` ノードで組む UI はもう無い。現在の地図:

- **描画** — `ui.json`（`src/ui/assets/<Name>.ui.json`）でツリーを宣言し、起動時に `Game.start` が
  `spawnUiOrBug`（別名 2 枚立ては `spawnUiAsOrBug`）で 1 回だけ spawn する。毎フレーム `UiRender.renderUi`
  が box/text/sprite（drawable チャンネル）と poly（polygon チャンネル）へ射影し、`Game.renderFrame` が
  盤面 drawable と合流させて 1 回で描く。F1 で `UiSpec.reloadAll` が `sources` 台帳ぶんをホットリロードする。

- **状態** — 各 UI の動的状態は 2 系統。①`UiStore` 内の名前パスキー state（`selection` / `focus` / `visible`）
  ＝リロードを生き延びる。②UI ごとの `XxxState` resource（`TitleMenuState` / `ItemMenuState` / `TradeMenuState` /
  `CharacterSelectState` / `TopBarState` / `LevelUpPanelState` 等）＝region の Ref を handler 注入。
  毎フレーム `XxxUi.frameStep`（または `step`）が state を読んで見た目（color / text / abs / 可視 / sprite /
  poly 頂点）を `UiStore` の setter で塗り直す（フェーズや root 可視で自己 gate）。

- **入力** — `Game.onKeyPressed` が現在の画面（`GamePhase`）/ フェーズ（`TurnPhase`）に応じて各 `XxxUi` の
  `moveSelection` / `confirmCurrentSelection` / `onKeyPressed` へ委譲する（`dispatchMenuKey` /
  `*Direction` の 1 表が真理点）。入力ハンドラは state resource を書くだけで、見た目は次フレームの
  `frameStep` が反映する。

- **移行した UI 一覧** — 全画面: `TitleMenuUi`（タイトル）/ `CharacterSelectUi`（出撃メンバー選択・
  カード列カルーセル）。メニュー・モーダル: `ActionMenuUi` / `WeaponSelectUi` / `ItemMenuUi`（windowing）/
  `TradeMenuUi`（最大 4 ペイン）/ `SuspendConfirmUi` / `GameOverMenuUi`。HUD・演出: `TopBarUi` /
  `LogUi` / `ItemPickupPopupUi` / `TurnEndHoldUi`（充填リング poly）/ `BattlePanelUi`（戦闘予報）/
  `LevelUpPanelUi` / `UnitCardUi`（味方左 / 敵右の 2 root 共有）。

- **残った `scene/`（Scene ノード）は盤面・シム系のみ** — Player / Enemy / Map / Camera / Cursor（入力）/
  ArrowCursor / Fog / Minimap / RangeOverlays / Bgm / Entity。UI 窓の `NodeTag` は全滅し、残る `NodeTag` は
  駒・overlay・driver だけ（`Player` / `Enemy` / `Map` / `*Range` / `Cursor` / `Stairs` / `Chest` /
  `EnemyTurnDriver` / `FogDriver` / `Camera` 等）。
