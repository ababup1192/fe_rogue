# ヘッドレス生成の最小レシピ

**ここで言う「ヘッドレス生成」**は、実ウィンドウ（GLFW/OpenGL）を開かずに、場面を PNG 連番と
GIF に生成すること。テスト・CI・見た目の確認、どれもこれで足りる。新しい場所（リポジトリの
外の `/tmp` でも、このリポジトリの `scratch/` の下でも）に最小構成を組むときの写経元がこの
1 ページ。Makefile や templates を読み歩かなくても、ここだけ読めば組める。

このレシピは 2 つの実例を検証済みの正として写した:

- `github:ababup1192/flix_game_engine` を丸ごと 1 依存として借りる形
  （`/tmp/probe_bonfire` で実際に焼けることを確認済み）
- `flix_engine_core` / `flix_engine_world` / `flix_engine_tools` を個別に借り、
  `flix test` の中から `Bakery.bakeGif` を直接呼ぶ形（`scratch/field_walk_demo`）

どちらも中身は同じ 4 手（依存を借りる・フォントを 1 本置く・場面を作る・焼いて確認する）。

## 1. ディレクトリ構成（最小）

```
my_bake/
  flix.toml
  bin/flix        # リポジトリの外に組むときだけ要る（後述）
  Makefile         # 任意。無くても flix run で焼ける
  assets/
    Xolonium-Regular.ttf   # フォント本体（後述）
  src/
    Scene.flix     # 場面（絵の中身）
    bake/
      Bake.flix    # entrypoint（Bake.all）
      Gallery.flix # 焼き込み設定 + bakeGif 呼び出し
```

## 2. flix.toml — 依存の借り方

一番簡単なのは、このエンジンを丸ごと 1 依存として借りる形:

```toml
[package]
name        = "my_bake"
description = "何を焼く場面か、一言"
version     = "0.1.0"
flix        = "0.75.1"
authors     = ["you <you@example.com>"]

[dependencies]
"github:ababup1192/flix_game_engine" = { version = "0.19.0", security = "unrestricted" }
```

`version` は書いている時点の最新に読み替える（`flix.toml` の直下、このリポジトリ自身の
`[dependencies]` を見れば分かる）。個別のパッケージ（`flix_engine_core` /
`flix_engine_world` / `flix_engine_tools`）を要るぶんだけ借りる形でもよい
（`scratch/field_walk_demo/flix.toml` が実例）。どちらでも `Bakery` / `HeadlessFont` /
`Render` などの語彙は同じように使える。

依存の実体（jar）は `flix build` や `flix run` を初めて走らせたときに `lib/` の下へ
自動で降ってくる。**`lib/` は自分で作らない・中身を手で置かない** — 空でよいので
`.gitignore` に入れておく。

## 3. フォント 3 点セット

`Text` を 1 文字でも描くなら（描かない場面はまず無い）、フォントが要る。要るのは 3 つだけ:

1. **TTF 本体**を 1 本、`assets/` に置く（Xolonium 等。このリポジトリの
   `templates/game-starter/assets/Xolonium-Regular.ttf` を丸ごとコピーしてよい）
2. `HeadlessFont.buildAtlas("ui", ttfPath)` を呼んで `FontAtlas` を作る
   （GL が無くても Java2D の `FontMetrics` だけでメトリクスを測る。グリフ画像そのものは
   焼かない — 実描画は `SoftRaster` が出力解像度で直接 `drawString` するので不要）
3. その `FontAtlas` を `BakeConfig#fontAtlas` に、TTF パスを `BakeConfig#fontTtf` に渡す

```flix
let atlas = HeadlessFont.buildAtlas("ui", "assets/Xolonium-Regular.ttf");
```

## 4. 場面を作る（Scene）

`Render.PlacedItem` のリストを返す関数を 1 つ用意すれば場面になる。最小形:

```flix
mod Scene {
    pub def design(): Vec2.Vec2 = { x = 320.0, y = 240.0 }

    pub def itemsAt(t: Float64): List[Render.PlacedItem] =
        Render.vgrad(design(), { top = Color.rgb8(16, 18, 42), bottom = Color.rgb8(35, 44, 85) }, 0)
            |> (bg -> { at = { x = 0.0, y = 0.0 }, item = bg })
            :: Nil
}
```

絵を書く前に `/visual-dict` を引く（このレシピの範囲外。絵の下限 5 性質は
[docs/drawing-floor.md](drawing-floor.md)）。

## 5. 焼き込み設定 + Bakery 呼び出し

```flix
// src/bake/Gallery.flix
mod Gallery {
    def scale(): Int32 = 2
    def ttfPath(): String = "assets/Xolonium-Regular.ttf"

    def config(atlas: FontAtlas): Bakery.BakeConfig =
        { design = Scene.design(), scale = scale(), background = Color.rgb8(16, 18, 42),
          texturePath = Map.empty(), fontTtf = ttfPath(), fontAtlas = atlas,
          outDir = "gallery", frameW = 320 * scale(), frameH = 240 * scale(),
          gifDelayMs = 110, gifFps = 9 }

    // 焼く時刻の並び。乱数や実時間に依存させない（決定的な場面にする）。
    def timeSteps(): List[Float64] = List.range(0, 12) |> List.map(i -> Int32.toFloat64(i) * 0.15)

    pub def bakeAll(): Unit \ IO =
        let atlas = HeadlessFont.buildAtlas("ui", ttfPath());
        let toCmds = t -> Render.draw(Scene.itemsAt(t));
        discard Bakery.bakeGif(config(atlas), timeSteps(), 1, toCmds, "my_scene");
        println("焼けた: gallery/my_scene.gif, gallery/frames/my_scene/0..11.png")
}
```

```flix
// src/bake/Bake.flix — entrypoint
mod Bake {
    pub def all(): Unit \ IO = Gallery.bakeAll()
}
```

`Bakery.bakeGif` が RasterReq 組み立て・SoftRaster 呼び出し・GIF エンコード・コマ別 PNG
書き出しを全部やる（`engine_tools/src/Bakery.flix`）。呼ぶ側が用意するのは
「1 回だけ宣言する設定」と「時刻 → 描画コマンド」の投影だけでよい。

## 6. リポジトリ内 vs リポジトリ外の差分

| | リポジトリ内（`scratch/` 等） | リポジトリ外（`/tmp` 等） |
|---|---|---|
| `flix.toml` の依存 | 個別パッケージ（`flix_engine_core` 等）を相対で借りてもよい | `flix_game_engine` を GitHub 経由で丸ごと借りる |
| フォント | 既存の `templates/*/assets/*.ttf` を相対パスでそのまま使い回してよい（コピー不要） | `assets/` に TTF を 1 本コピーして持つ（借りる先が無い） |
| flix コマンドの実行 | リポジトリ直下の `bin/flix`（devbox の flix.jar を自動で見つける）をそのまま使う | `bin/flix` を自分の場所にも置く（`/tmp/probe_bonfire/bin/flix` を丸ごとコピーしてよい。devbox / PATH の flix / 手元の `bin/flix.jar` の順で jar を探す） |
| 焼き込みの入口 | `@Test` の中から `Bakery.bakeGif` を直接呼ぶ形でもよい（`scratch/field_walk_demo/test/TestFieldWalkBake.flix`）。焼いたファイルが実在するかを検査する煙テストにできる | `Bake.all()` を entrypoint にして `./bin/flix run --entrypoint Bake.all` |
| git | `scratch/` はリポジトリの `.gitignore` で丸ごと除外済み。焼いた PNG/GIF も気にせず作れる | 好きに使い捨てる場所（`/tmp` 等） |

## 7. 実行コマンド

entrypoint 形式（`Bake.all` を用意した場合）:

```bash
./bin/flix run --entrypoint Bake.all
```

テスト形式（`@Test` の中で焼く場合、リポジトリ内なら）:

```bash
../../bin/flix test    # scratch/<name>/ から見て repo 直下の bin/flix
```

`make` を使うならこれだけの Makefile で足りる:

```makefile
.PHONY: bake check
bake:
	./bin/flix run --entrypoint Bake.all
check:
	./bin/flix check
```

## 8. 焼けた後の確認

焼いて終わりにしない。人に見せる前に自分で確かめる（このリポジトリの `bin/` にある
検査は、焼いた PNG のパスさえ渡せばリポジトリ外からでも使える）:

```bash
python3 bin/lint-view.py path/to/my_bake/src/bake/Gallery.flix   # 矩形と円だけになっていないか
python3 bin/img-digest.py gallery/my_scene.png                    # 目視の前に数値で当たりを付ける
```

最後に `gallery/my_scene.gif` か `gallery/frames/my_scene/*.png` を実際に開いて目で見る。
絵の下限 5 性質（面に階調か質感 / 主役が背景から分離 / 層が分かれている / 時間が流れている /
形が物として読める）を満たしているかは、機械では最後まで判定できない。造形が怪しいときは
`Bakery.silhouettePng`（シルエット焼き — 対象を黒・背景を白）で形だけを取り出して見る
（写経例は [docs/drawing-floor.md](drawing-floor.md)）。
