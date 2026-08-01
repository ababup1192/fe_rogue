---
name: visual-dict
description: web/Canvas/Shadertoy の絵の技法をこのエンジンの部品に翻訳する対応表。「見栄えを良くして」「〜っぽい絵にして」、グロー・vignette・グラデ・残像・パーティクル・完全ループ GIF を作る/移植するときに参照する。
---

# visual-dict — web の絵の技法 → エンジンの部品（翻訳辞書 v1）

いつ使う: 見栄え・映えの実装、web の作例（Canvas / Shadertoy / GSAP 系）の技法を
このエンジンで再現するとき。**書く前に該当行を引く** — 車輪の再発明（同じ近似を
また手組みすること）を防ぐのがこの辞書の仕事。

根拠: 6 ジャンル（弾幕STG / 森ARPG / レース / ホラーADV / 海中パズル / 雪山ローグ）を
canvas の狙い絵 → 実エンジンの headless bake（静止画 + 完全ループ GIF）で再現した
実験（2026-08）。以下の対応と癖はすべてその実験で実証・発見された物。

## 対応表

| web の技法 | エンジンの部品 | 実証済みの作法・癖 |
|---|---|---|
| グロー / bloom | `DrawCmd.BlendMode.Add` + 柔らかい円 | `Render.glowAt` は同心円 24 輪・減衰カーブ固定。大半径は段差が見える → 半径違いを数枚重ねてディザする |
| 放射グラデ（光だまり・暗幕・vignette） | **`ShaderDoc` の Radial + Gradient 面**（SoftRaster が画素評価） | これが正解ルート（Multiply の暗幕もこれで組める）。癖: Radial は uv 空間なので非正方形 rect では楕円に歪む → 正方形 rect を大きく置く。`Light` は RadialGlow 焼きテクスチャ前提で、texturePath 無しの bake では使えない |
| 線形グラデ（空・水・空気色） | 専用 primitive は**無い** | 「頂点色つきポリゴン」は module-index の記載のみで実装は単色 — 1px 色帯の積みで近似する。部品数がそのまま焼き時間に乗るのでコスト注意。`ShaderDoc` の Gradient 面も選択肢 |
| 残像 / トレイル | 過去位置に減衰 α で再描画 | **動き専用** — 静止画では 1px 未満のズレで写らない |
| パーティクル | `Fx` / `FxDoc`（時刻の純関数） | burst / drift / gravity。状態を持たないので巻き戻し・bake と相性が良い |
| 動く暗背景（霧・雲・水） | `ShaderDoc`（Fbm / Warp / Worley） | Worley は等方スケールのみ（横長面で潰れる → CPU で組んで小矩形の Add 斑に退避）。周期（タイル化）Fbm は無い — スクロールでループを閉じたい時は Time ノードで逆位相 2 層の「呼吸」に翻訳する |
| コースティクス | Worley の F2−F1 | ShaderDoc で形が届かない時は CPU 計算 + 2×2px の Add 斑 |
| 画面揺れ | `CameraRig`（減衰ノイズ） | **動き専用**。bake では world 層だけ translate（UI・雨・HUD は外に出す） |
| 白フラッシュ / hitstop | 白矩形の α を easeOut 減衰 | **動き専用** — 静止画に入れるなら α を実機の 1/3 程度に（常時の靄に見える） |
| イージング / バネ | `Curve` / `EcsTween` | easeOutCubic / easeOutBack / 減衰バネ = exp·cos。`Float64.exp` が無いので `Float64.pow` で代用 |
| ドット絵キャラ | `PxSprite`（文字格子） | scale は整数のみ。伸縮の中間コマは `PxSprite.runs` の矩形を中心周りに伸縮して回避。legend の色に α は持てない（Add 前提で色に織り込む） |
| タイル地形 | `TileLayer` / `DualGrid` / `Terrain` | タイル角の丸めは明色の欠き取り（チャンファ）で DualGrid 風に |
| 光の帯 / ハードシャドウ | 半透明ポリゴン（`Light` / `Shadow`） | 影は光源と反対へ伸ばす。長さは距離の逆数で減らすと自然 |
| 角丸パネル / 枠 | `DrawCmd.BoxStyle` | `Render.outline` は枠 α=1 固定 — 半透明の枠は Item.Box + BoxStyle を直組み |

## 映えの基本レシピ（迷ったらこの 5 行）

- 背景は真っ黒でなく「ゆっくり動く暗色」（ShaderDoc の Fbm を暗く敷く）
- 動く値は全部イージング — 値を飛ばさない。座標は float のまま（pixelSnap は任意。
  カクカクの絵が滑らかに動くのが正解）
- 重要な物ほど光る（Add）。暗背景 + 差し色 2〜3 色
- 画面は 1 秒も静止させない（ambient 粒・idle の揺れ・明滅）
- 打撃の瞬間 = hitstop + 揺れ + 白フラッシュ + 粒（全部盛りが web の「映え」の正体）

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

## 辞書の穴（エンジン側の宿題 — 勝手に直さず、相談してから）

1. 線形グラデ primitive（頂点色ポリゴン）— module-index の記載と実装の齟齬。見た目とコストの両方に効く
2. 放射の Multiply 版（darkAt）と、glowAt の減衰カーブ・輪数を渡す口
3. `Light` のテクスチャレス・フォールバック
4. `Render.outline` の枠 α
5. `ShaderDoc` の語彙: 軸別スケール・量子化ノード・周期 Fbm・GIF 経路のシェーダ面（bakeGifWith）
6. `PxSprite` の小数 scale / legend α
7. `Float64.exp`
