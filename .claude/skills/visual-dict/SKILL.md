---
name: visual-dict
description: 画面の絵を作るときに引く辞書。web/Canvas/Shadertoy の技法をこのエンジンの部品に翻訳し、まだ使われていない部品も一覧する。新しいゲーム・新しい画面（View）を書くとき、背景・キャラ・エフェクトを置くとき、「見栄えを良くして」「〜っぽい絵にして」と言われたとき、グロー・vignette・グラデ・残像・パーティクル・完全ループ GIF を作る/移植するときに参照する。
---

# visual-dict — 絵の技法 → エンジンの部品（翻訳辞書 v2）

いつ使う: **View を書く前に毎回**。加えて、見栄え・映えの実装、web の作例（Canvas /
Shadertoy / GSAP 系）の技法をこのエンジンで再現するとき。**書く前に該当行を引く** —
車輪の再発明（同じ近似をまた手組みすること）と、矩形だけで済ませる退避を防ぐのが
この辞書の仕事。

**engine の版に注意**: 下の表で **[新]** を付けた部品は **0.13.0 から**（0.12.1 以前には無い）。
`PxSprite.sizeOf` / `Render.fadeAll` / `Color.hex` / `Num.*` / `Grid.dimsOfRows` は **0.14.0 から**。
自分のゲームが引いている版は `flix.toml` の `github:ababup1192/flix_game_engine` を見る。
シェーダーの語彙は知らない `kind` が 1 つあるだけで **Doc 全体が既定値へ倒れる**
（エラーは出ず絵だけ別物になる）ので、書いたら必ず焼いて確かめる。

根拠: 6 ジャンル（弾幕STG / 森ARPG / レース / ホラーADV / 海中パズル / 雪山ローグ）を
canvas の狙い絵 → 実エンジンの headless bake（静止画 + 完全ループ GIF）で再現した
実験（2026-08）。以下の対応と癖はすべてその実験で実証・発見された物。

## 対応表

| web の技法 | エンジンの部品 | 実証済みの作法・癖 |
|---|---|---|
| グロー / bloom | `DrawCmd.BlendMode.Add` + 柔らかい円 | `Render.glowAt` は同心円 24 輪・減衰カーブ固定。大半径は段差が見える → 半径違いを数枚重ねてディザする |
| 放射グラデ（光だまり・暗幕・vignette） | `ShaderDoc` の `radial` / `radialAspect` **[新]** + Gradient 面（SoftRaster が画素評価） | これが正解ルート（Multiply の暗幕もこれで組める）。`radial` は uv 空間なので非正方形 rect では楕円に歪む → **`radialAspect` に aspect を渡す**。0.12.1 以前は `radialAspect` が無いので、正方形 rect を大きく置いて回避する（`radialAspect` は 0.13.0 から）。`Light` は RadialGlow 焼きテクスチャ前提で、texturePath 無しの bake では使えない |
| 線形グラデ（空・水・空気色） | **`Render.vgrad(size, {top, bottom}, z)` / `Render.gradPolygon`** **[新]**（頂点色つきポリゴン） | 実装済み・SoftRaster も対応済み（`gradSample`）。**1px 色帯の積みは禁止** — 部品数がそのまま焼き時間に乗る。任意方向・4 頂点別色は `gradPolygon`、縦のニ色は `vgrad` |
| 残像 / トレイル | 過去位置に減衰 α で再描画 | **動き専用** — 静止画では 1px 未満のズレで写らない |
| パーティクル | `Fx` / `FxDoc`（時刻の純関数） | burst / drift / gravity。状態を持たないので巻き戻し・bake と相性が良い。`FxDoc.parseWith(palette, json)` でテーマ色を `@名前` で引ける |
| 動く暗背景（霧・雲・水） | `ShaderDoc`（`fbm` / `fbmTile` / `warp` / `worley`） | Worley は等方スケールのみ（横長面で潰れる → CPU で組んで小矩形の Add 斑に退避）。**スクロールで継ぎ目を出したくない時は `fbmTile` [新]（period 指定の周期 Fbm）**。ループを閉じるだけなら `time` ノードで逆位相 2 層の「呼吸」でもよい |
| コースティクス | Worley の `f2mf1` | ShaderDoc で形が届かない時は CPU 計算 + 2×2px の Add 斑 |
| 画面揺れ | `CameraRig`（減衰ノイズ） | **動き専用**。bake では world 層だけ translate（UI・雨・HUD は外に出す） |
| 白フラッシュ / hitstop | 白矩形の α を減衰 | **動き専用** — 静止画に入れるなら α を実機の 1/3 程度に（常時の靄に見える） |
| イージング / バネ | `EcsTween.Easing` / `Curve` | 補間は `EcsTween.Easing`（`Linear` / `EaseIn` / `EaseOut` / `EaseInOut` の 4 つ。これ以外の名前は無い）。周期・揺れ・減衰バネは `Curve`（`sine` / `tri` / `arch01` / `pieces` / `dampedSpring`）。`Float64.exp` は標準にある（探せば大抵ある、が教訓） |
| ドット絵キャラ | `PxSprite`（文字格子） + **`PxShade`** | scale は整数のみ。伸縮の中間コマは `PxSprite.runs` の矩形を中心周りに伸縮して回避。legend の色に α は持てない（Add 前提で色に織り込む）。**平らに塗った絵を読み込み直後に `PxShade.polishDoc` へ通す** — ふち光・接地影・ディザ・粒が乗り、走行中の負荷は増えない |
| タイル地形 | `TileLayer` / `DualGrid` / `Terrain` | タイル角の丸めは明色の欠き取り（チャンファ）で DualGrid 風に。質感は `Material`（粒・きらめき・鱗・泡・発光・染み）を重ねる |
| 光の帯 / ハードシャドウ | 半透明ポリゴン（`Light` / `Shadow`） | 影は光源と反対へ伸ばす。長さは距離の逆数で減らすと自然 |
| 角丸パネル / 枠 | `DrawCmd.BoxStyle` / `Render.outline` / `outlineA` **[新]** | 半透明の枠は `Render.outlineA(α を渡す)`。`Render.outline` は枠 α=1 固定なので、0.12.1 以前は Item.Box + BoxStyle を直組みしていた |

## 画風は毎回決める（レシピは選択肢ではない）

**この辞書は「どう作るか」の道具箱で、「どんな絵にするか」は決めない。** 画風はゲームごとに
決め直す物で、既定は無い。AGENTS.md の「絵の下限」が要求するのは 4 つの性質
（面に階調か質感 / 主役が背景から分離 / 層が分かれている / 時間が流れている）だけで、
それをどの画風で満たすかは自由。

### まず画風を決める（部品を選ぶ前に）

1. **題材から引く**。舞台・時代・素材（濡れた石／古い紙／ブラウン管／布／夜の雪）を 1 つ決める。
   ジャンル（RPG・STG）からは引かない — ジャンルから引くと前に作った物の複製になる。
2. **色を 3 つだけ先に決める**（下地・主役・差し色）。増やしたくなったら明暗ではなく
   色相をずらす（`Color.warm` / `Color.cool`）。
3. **やらないことを 1 つ決める**（例: グローを使わない／輪郭線を引かない／黒を使わない／
   粒を撒かない）。制約が 1 本あると絵に個性が出る。
4. 決めた 3 行を `AGENTS.local.md` の「このゲームの画風」に書く。以後の批評はこれを基準にする。

### レシピは「翻訳の例」（この中から選ばない）

下の A〜D は**同じ 4 性質を、まったく違う手で満たした実例**。見てほしいのは
「どの部品で性質を満たしたか」の対応であって、A〜D のどれかを採用することではない。
**毎回 A を出すのも、4 つの中から選ぶのも手抜き**（同じ顔のゲームが並ぶ）。
決めた画風に合う手が無ければ、この対応表を横に組み替えて自分で作る。

### レシピ A: 暗背景に光る物（ネオン・SF・ダンジョン・弾幕）

- 背景は真っ黒でなく「ゆっくり動く暗色」（`ShaderDoc` の `fbm` を暗く敷く）
- 暗背景 + 差し色 2〜3 色。重要な物ほど光る（`Render.glowAt` の Add）
- 前景に暗い覆い（vignette）を掛けて視線を中央へ
- 打撃の瞬間 = hitstop + 揺れ + 白フラッシュ + 粒（web の「映え」の正体）

### レシピ B: 明るい紙・水彩（牧歌的・パズル・生活もの）

- 背景は生成りの明るい面。階調は `Render.vgrad` **[新]**（古い版は `ShaderDoc` の `uv`+gradient）
  の淡い 2 色差で（コントラストは低く）
- 分離は**明度差でなく色相差**と輪郭線で作る（Add は使わない — 白に光らせても見えない）
- 影は黒でなく `Color.cool` で寄せた紫寄りの薄い色。`Material` の粒で紙の目を出す
- 動きは大きくゆっくり（`Curve.sine` の長い周期）。粒を撒くなら埃でなく光の粉・花びら

### レシピ C: 色数を絞ったドット絵（レトロ・限定パレット）

- 色は `*.theme.json` に数色だけ。階調は色を増やさず **`PxShade` のディザ**で作る
- `App.withPixelSnap` + 整数 scale で画素の升目を揃える（半端な拡大でにじませない）
- 動きはコマ替え（`Anim`）が主役。補間で滑らかに動かすと画風が壊れる
- グローは 1 色の縁取りで代用する（加算のぼけは限定パレットと相性が悪い）

### レシピ D: 白地に線（図解・ボード・論理パズル）

- 面はほぼ塗らず、`Render.outline` と太さのある線（`Quad`）で情報を出す
- 階調の代わりに `Render.striped` / `checker` の網掛けで領域を区別する
- 分離は線の太さと余白で作る。動きは要素の出入り（`EcsTween`）だけに絞る

**共通する作法**（画風に依らず効く）

- 動く値は必ず補間を通す — 値を飛ばさない。座標は float のまま
- 光の側と影の側は `Color.warm` / `Color.cool` で色そのものを分ける（同じ色の明暗だけにしない）
- 完全に静止した画面を出さない。静けさが画風なら、揺れを極小にする（ゼロにはしない）

## まだ誰も使っていない部品（矩形に退避する前にここを見る）

実装もテストもあるのに、templates/ と examples/ で採用ゼロ〜1 の部品。**「無いから手組み」**
の前に必ず確認する。使い方は各ファイル冒頭の doc コメントが正。

| 部品 | 実体 | 1 行で何ができるか |
|---|---|---|
| `PxShade` | `engine_world/src/PxShade.flix` | 平らに塗ったドット絵に、ふち光・接地影・ディザ・地肌の粒を読み込み時 1 回だけ乗せる（走行コスト 0） |
| `FxDoc`（fx.json） | `engine_world/src/FxDoc.flix`、schema は `docs/fx.schema.json` | パーティクルを JSON で宣言（Studio で調整できる）。手組みの `Fx.derive` から昇格させる |
| `Render.vgrad` / `gradPolygon` | `engine_world/src/Render.flix:180,190` | 空・水面・光の帯を頂点色つきポリゴン 1 枚で（1px 帯積みの代替） |
| `Daylight` + `Calendar` | `engine_world/src/Daylight.flix`, `Calendar.flix` | 時刻 0..1 で空気色の幕・影の向きと長さ・ドット絵に当たる光の向きが回る（昼夜） |
| `Scatter` | `engine_world/src/Scatter.flix` | どこまでスクロールしても同じ配置になる撒き物（星・草・埃）を無限に |
| `Render.turned` / `turnedAll` | `engine_world/src/Render.flix:486,502` | 絵・集まりを傾ける（カードの傾き・振り子）。単位は回転数（1 周 = 1.0） |
| `Render.striped` / `checker` | 同 `:538,550` | 縞・市松を面に重ねる（布・床・注意帯） |
| `Render.clipped` / `clippedAll` | 同 `:311,315` | 矩形で切り抜く（スクロール窓・小窓・のぞき穴） |
| `Color.warm` / `cool` | `engine/src/core/Color.flix:29,36` | 光側を暖色・影側を寒色へ寄せて階調を増やす |
| `App.withPixelSnap` / `withSpriteAtlases` | `engine_world/src/App.flix` | 画素の升目に載せて輪郭をにじませない / ドット絵を 1 枚に焼いて 1 体 = 1 クアッド |
| `Mirror` | `engine_world/src/Mirror.flix` | ドット絵の映り込み（鏡・ガラス・磨いた床） |
| `Material` の SurfaceFx | `engine_world/src/Material.flix` | チップ絵なしで地形に質感（粒・きらめき・鱗・泡・発光・染み） |
| `Render.star` / `ellipse` / `sector` / `ngon` | `engine_world/src/Render.flix` | 星・楕円・扇・正多角形。box と circle の 2 択で我慢しない |
| `UiShape` | `engine_world/src/UiShape.flix` | ui.json の中に circle / star / line をパラメトリックに置く |

シェーダーの語彙（Field / Shade の全 kind とレシピ）は **`docs/shader-doc.md`** が正。

## 完全ループ GIF の作法

- 配管: `Bakery.bakeGif(cfg, frames, stride, toCmds, name)`。シェーダ面を使う場合は
  チャンネルが無いので `SoftRaster.renderToImageWith` + `Filmstrip.bakeFrame` +
  `GifEncoder.encode` を手組みする
- ループを閉じる: 周期項はループ長の整数倍周期だけ / 降下・スクロールはラップ幅の
  整数倍 / フラッシュ・揺れはループ境界で振幅 0
- 尺は 4〜6 秒に一番動きのある拍を 1 つ（20 秒を全部焼かない）
- 実績: 72 コマ・15fps・720×405 で 2〜4MB。グラデの帯積みが多いと 1 コマ十数秒に
  なる（scale を落とすか部品を減らす）
- 決定性: 同じ入力なら GIF がバイト一致する（実測済み）— 動きの golden 比較に使える

### 配る時は WebP に変換する

- **GIF のサイズは解像度でほぼ縮まない — 効くのはコマ数**。ドット絵は 1 画素ごとの
  ノイズが情報量の本体で、整数倍拡大した分の同色画素は LZW が畳んでしまう
  （720×405 と 480×270 が同じバイト数になった実測あり）
- **アニメ WebP は lossless で GIF の 1/3〜1/4**（実測 2.8〜4.2 倍圧縮）。
  しかもドット絵では **lossless の方が lossy より小さい**（限られた色数のため）。
  `<img src="...">` でそのまま animated 再生される
- 変換（ffmpeg は devbox に入っている。リポのルートから呼ぶこと）:
  `devbox run -- ffmpeg -y -i in.gif -c:v libwebp_anim -lossless 1 -loop 0 out.webp`
- 検証: ffprobe は animated WebP を読めない。`grep -a -o ANMF x.webp | wc -l` で
  コマ数を数え、ヘッダに `VP8X` と `ANIM` があることを見る

## 辞書の穴（エンジン側の宿題 — 勝手に直さず、相談してから）

1. 放射の Multiply 版（`darkAt`）と、`glowAt` の減衰カーブ・輪数を渡す口
2. `Light` のテクスチャレス・フォールバック
3. `ShaderDoc` の語彙: Worley の軸別スケール
4. `PxSprite` の小数 scale / legend α

解消済み（0.14.0）: コマの大きさを測る口（`PxSprite.sizeOf`）・列を丸ごと薄くする
（`Render.fadeAll` / `overItem`）・色の作り方（`Color.rgb` / `rgb8` / `hex` / `mix`）。
解消済み（0.13.0）: 頂点色つきポリゴン（`gradPolygon` / `vgrad`）・半透明の枠（`outlineA`）・
周期 Fbm（`fbmTile`）・量子化（`quantize`）・真円放射（`radialAspect`）・升目吸着（`snap`）・
減衰バネ（`Curve.dampedSpring`）・シェーダ面つき GIF（`Bakery.bakeGifWith`）。
