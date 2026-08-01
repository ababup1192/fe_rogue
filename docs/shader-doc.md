# shader.json（ShaderDoc）の書き方

面（矩形）を「画素ごとの計算」で塗るための宣言。単色の box をやめて、動く霧・水面・
vignette・熱い溶岩を **JSON の保存だけで即調整できる**形で置ける。

- 実体: `engine/src/ShaderDoc.flix`（型）・`ShaderJson.flix`（読み書き）・
  `ShaderEval.flix`（CPU 評価 = bake）・`ShaderGen.flix`（GLSL 生成 = 実機）
- **使える語彙は engine の版で決まる**。知らない `kind` が 1 つでもあると Doc 全体が
  読めず、丸ごと既定値へ倒れる（絵が別物になるだけでエラーは出ないので気付きにくい）。
  下の表で **[新]** を付けた物は **0.13.0 から**（0.12.1 以前には無い）。自分のゲームが
  引いている版は `flix.toml` の `github:ababup1192/flix_game_engine` を見る。
- 呼び方: `Render.shaderFill(spec, rect, t, z)` / `Render.shaderFillMasked(spec, rect, polys, t, z)`
- 読み方: `ShaderJson.load(path)` は **fail-open**。`Result.getWithDefault(既定の Spec)` で受ける
- 保存即反映: `App.watchFile(path, …)` に繋ぐ（`examples/shader_gallery/src/Main.flix:18` が手本）

## 全体の形

```json
{
  "note": "この面は何で、どこをいじると何が変わるか（調整ノブの一覧）",
  "name": "水面",
  "cycleRate": 0.25,
  "shared": [ ["名前", { …場… }] ],
  "out": { "kind": "fill", "shade": { …色… }, "alpha": { …場… } }
}
```

- `cycleRate` … 0 より大きいと、色の位相が時間で回る（ゆっくり色が巡る）
- `shared` … 同じ場を 2 度書かないための束ね。`{"kind":"use","name":"…"}` で引く。
  **前方参照のみ**（自分より前に定義した名前だけ）。循環・未定義は読み込みエラー
- 知らないキーは読み飛ばされる。`note` は必ず書く（調整ノブの説明を人に残す）

## 場（Field）— 0〜1 の値を画素ごとに作る

`{"kind": "…", …}`。`of` / `a` / `b` を持つものは、その中にまた場を入れ子にできる。

**素材**

| kind | 主なキー | 何が出るか |
|---|---|---|
| `const` | `value` | 定数 |
| `uv` | `axis`("u"/"v") | 横 / 縦の位置（0〜1） |
| `fbm` | `octaves`, `scale`, `seed` | 雲・霧のムラ |
| `fbmTile` **[新]** | `octaves`, `scale`, `period{x,y}`, `seed` | **周期つき** fbm。スクロールしても継ぎ目が出ない |
| `worley` | `scale`, `seed`, `out`("f1"/"f2"/"f2mf1") | セル模様。`f2mf1` が網目（水のコースティクス） |
| `hash1` / `hash2` | `scale`, `seed`, (`comp`), (`bucket`) | 升目ごとの乱数（`hash2` は成分指定） |

**形**

| kind | 主なキー | 何が出るか |
|---|---|---|
| `disk` | `cx`, `cy`, `radius`, `feather` | 縁がぼけた丸（池・光だまりの型抜き） |
| `radial` | `cx`, `cy` | 中心からの距離。**uv 空間なので横長の面では楕円に歪む** |
| `radialAspect` **[新]** | `cx`, `cy`, `aspect` | 縦横比を渡せる距離。**vignette はこちらを使う** |
| `scales` | `scale`, `stagger` | 鱗・瓦の並び |

**きらめき**

| kind | 主なキー | 何が出るか |
|---|---|---|
| `glints` | `scale`, `rate`, `density`, `seed` | 横に伸びた光の筋 |
| `sparkle` | `scale`, `rate`, `density`, `seed` | 菱形のちかちか |
| `ripples` | `freq`, `amp`, `speed`, `seed` | 横縞のうねり |

**座標をいじる**（中の `of` を、ずらした座標で読む）

| kind | 主なキー | 何をするか |
|---|---|---|
| `scaled` | `factor`, `scroll{x,y}`, `of` | 拡大 + 流す（`scroll` が流れの速さ） |
| `warp` | `amount`, `scale`, `seed`, `of` | ぐにゃりと歪ませる |
| `tile` | `tiles{x,y}`, `of` | 敷き詰める |
| `snap` **[新]** | `cells{x,y}`, `of` | 升目に量子化（ドット絵風） |
| `swirl` | `cx`, `cy`, `strength`, `rate`, `of` | 中心ほど速く回す（渦） |
| `rotate` | `cx`, `cy`, `turns`, `rate`, `of` | まるごと回す（1 周 = 1.0） |
| `angle` | `cx`, `cy` | 中心から見た角度（放射の縞・花びら・螺旋） |

**加工**

| kind | 主なキー | 何をするか |
|---|---|---|
| `smoothstep` | `lo`, `hi`, `of` | しきい値でくっきりさせる（境の太さ = `hi`） |
| `quantize` **[新]** | `of`, `steps` | 段数を減らす（ポスタリゼーション） |
| `pow` | `of`, `p` | 明暗のカーブ |
| `math1` | `op`, `of` | `neg`/`abs`/`fract`/`floor`/`sin`/`cos`/`sat`/`oneMinus` |
| `math2` | `op`, `a`, `b` | `add`/`sub`/`mul`/`min`/`max`/`step` |
| `mix` | `a`, `b`, `t` | 一定の割合で混ぜる |
| `blend` | `a`, `b`, `by` | 場で混ぜ具合を決めて混ぜる |
| `time` | `scale`, `offset` | 時刻そのもの（明滅・呼吸に） |
| `use` | `name` | `shared` に置いた場を引く |

## 色（Shade）— 場を色に変える

色は `"#rrggbb"` か `{"r":…, "g":…, "b":…}`（0〜1）。

| kind | キー | 使いどころ |
|---|---|---|
| `solid` | `color` | ベタ |
| `ramp` | `lo`, `hi`, `field` | 2 色の間を場で補間 |
| `gradient` | `stops`(`[[位置, 色], …]`), `field` | 多段のグラデ（空・水の深さ） |
| `cosine` | `a`, `b`, `c`, `d`, `field` | `a + b·cos(2π(c·場 + d))`。**`d` をずらすだけで別配色**になるので、ステージごとの色替えに向く |

`out` は `{"kind":"fill", "shade": …, "alpha": …}`。`alpha` も場なので、形（`disk` など）を
入れれば好きな輪郭に抜ける。

## すぐ使えるレシピ

### 1. ゆっくり動く暗い背景（単色 box の置き換え）

```json
{
  "note": "背景の霧。濃さ=smoothstep の lo/hi、流れ=scroll、粗さ=scale。",
  "name": "bg_mist",
  "cycleRate": 0.0,
  "out": {
    "kind": "fill",
    "shade": {
      "kind": "gradient",
      "stops": [[0.0, "#0b1020"], [0.6, "#151d33"], [1.0, "#26314f"]],
      "field": {
        "kind": "scaled", "factor": 1.0, "scroll": { "x": 0.01, "y": 0.006 },
        "of": { "kind": "fbm", "octaves": 3, "scale": 3.0, "seed": 5 }
      }
    },
    "alpha": { "kind": "const", "value": 1.0 }
  }
}
```

上下の位置で色を変えたいときは、`field` を `uv`(v) と `fbm` の重み付き足し算にする
（`math2` の `mul` で係数を掛けて `add`）。`templates/game-starter/assets/*.shader.json` が
その形。engine が新しければ `fbm` を `fbmTile` **[新]** に替え、`period` を整数にすると
スクロールしても継ぎ目が出ない。

### 2. 水面のコースティクス（網目）

`worley` の `out` を `"f2mf1"` にして `smoothstep` で細く締め、`ramp` で 2 色。
完成形は `examples/feature_lab/assets/Water.shader.json`（丸い池型に `alpha` で抜く例）と
`examples/shader_gallery/assets/water_caustic_pond.shader.json`（`shared` で網とムラを
分けて足し合わせる実践形）。

### 3. vignette（画面の四隅を落とす）— `radialAspect` **[新]** が要る

画面いっぱいの矩形に敷き、`Render.blended(Multiply, …)` で重ねる。

```json
{
  "note": "四隅を落とす覆い。効きの強さ=stops の位置と暗い側の色、丸さ=aspect（画面の 横÷縦）。",
  "name": "vignette",
  "cycleRate": 0.0,
  "out": {
    "kind": "fill",
    "shade": {
      "kind": "gradient",
      "stops": [[0.0, "#ffffff"], [0.55, "#ffffff"], [1.0, "#404860"]],
      "field": { "kind": "radialAspect", "cx": 0.5, "cy": 0.5, "aspect": 1.6 }
    },
    "alpha": { "kind": "const", "value": 1.0 }
  }
}
```

`aspect` に面の 横÷縦 を渡すこと。`radial` のままだと横長の画面で楕円に歪む。

## bake（焼き）での注意

- 実機は GPU（`ShaderGen` が GLSL を作る）、bake は CPU（`ShaderEval` が画素ごとに評価）。
  **同じ Spec から両方が出るので絵は一致する**が、面が大きい・入れ子が深いほど焼きは遅い。
- 焼きに出なかった指定は `SoftRaster.dropped` に溜まる。実機と食い違ったらまずここを見る。
  バックエンド差の一覧は [backend-parity.md](backend-parity.md)。
- 時刻 `t` は呼ぶ側が渡す。golden に焼くときは **`t` を固定**する（実時間を渡すと毎回変わる）。

## Studio で触れるようにする

`<名前>.shader.schema.json` を隣に置くとフォームになる（手本:
`examples/feature_lab/assets/Water.shader.schema.json`）。方言は
[doc-conventions.md](doc-conventions.md) と `/doc-design` skill を参照。
