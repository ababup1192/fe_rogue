# breakout — 値ベースの入口教材

Flix で書いたブロック崩し。ゲームの全状態を 1 つの「値」（`Field.World`）として持ち、
毎フレーム **入力 → ルールで次の値へ → 絵と音へ投影** という純粋な流れで動きます。
このリポジトリの examples を初めて読む人は、ここから始めるのがおすすめです。

## 遊ぶ

```bash
make run
```

| キー | 操作 |
|---|---|
| ← → | パドル移動 |
| Space | サーブ（ボール発射） |
| Enter | 決定（開始・次の面・やり直し） |
| F1 | `assets/parameters.json` を読み直して手応えを変える（遊びながら編集できる） |
| Esc | 終了 |

その他のコマンド:

```bash
make test   # テスト（検証のみ・~7 秒）
make bake   # ギャラリーと効果音 WAV を生成 → gallery/index.html をブラウザで開くと
            # 反射角の扇形図・衝突 GIF・コマ送りビューアが見られる
make check  # 型検査だけ
```

## 読む順

矢印の順に読むと、5 行の宣言から始まって少しずつ深くなります。

```
Main (14行)  ── ゲームの目次。これが全部
  ↓
Controls (24行) ── キーが「ゲームの意味」になる場所
  ↓
Levels (50行) ── 面のデザイン。文字で盤面を描く
  ↓
Palette (80行) ── 色。描画コードは色リテラルを書かずここのロール名だけ使う
  ↓
World (274行) ── 全状態の型と定数。「状態の持ち方の教え」2 つはここ
  ↓
Step (231行) ── 1 フレームのルール（純粋関数）。物理・衝突・フェーズ遷移
  ↓
Bounce (94行) ── パドル反射の式。本作の一番の見せ物
  ↓
View (316行) ── World から絵への投影。レイヤー・カメラシェイクもここ
  ↓
Sfx (42行) ── World の前後から「鳴らす音」を導く（絵と対になる投影）
```

後回しでよいもの: `App.flix`（ループと入力のランナー。いずれエンジンへ昇格する層）、
`GameParameters.flix`（F1 チューニングの仕組み）、`src/bake/`（Bake・Gallery・SfxBake — 生成の道具）、
`Trace.flix` / `Harness.flix`（テストとギャラリーの共有部品）。

## 1 フレームの流れ

```
キー・時計            World（値）              画面・スピーカー
   │                     │                        ↑
   │  App が Frame に焼く │                        │
   ▼                     ▼                        │
 Frame ──Controls──▶ Step.update ──▶ 次の World ──┬▶ View.frame ──▶ 絵
                      （純粋）                     └▶ Sfx.events ──▶ 音名
```

外の世界（キー読み・描画・音再生・ファイル）に触れるのは App だけ。
Step / View / Sfx は純粋関数なので、テストとギャラリーが同じコードをそのまま検証できます。

## ファイル地図（src — 生成系は src/bake/ に隔離）

| ファイル | 1 行で |
|---|---|
| Main | App に部品を繋ぐ目次（5 行の宣言） |
| Controls | キー割り当て（Frame → Input）と 1 歩進める橋 |
| Levels | 面の文字データ。**4 面目を足すならここだけ** |
| Palette | 色のロール名。**色を変えるならここだけ** |
| World | 全状態の型（mod Field）と定数。フェーズ・Store・調整値 |
| Step | 1 フレームのルール。物理 → 衝突の政策 → フェーズの結末 |
| Bounce | パドル反射の角度と加速の式 |
| View | World → 絵。レイヤー（World/Screen）とカメラシェイク |
| Sfx | World の前後 → 鳴らす音名 |
| App | ランナー（ループ・入力・描画・音再生の縁の下）。初読スキップ可 |
| GameParameters | F1 で読み直す調整値（fail-open: 壊れた JSON でも既定値で動く） |
| bake/Bake | `make bake` の入口 |
| bake/Gallery | ギャラリー（PNG・GIF・コマ送りサイト）を焼く |
| bake/SfxBake | 効果音 8 種を矩形波とノイズから合成して WAV に書く（録音素材ゼロ） |
| Trace | テストとギャラリーが共有するシナリオ（初期 World 集） |
| Harness | 画面なしでフォントを焼くための道具 |

## エンジン側の言葉（このフォルダに定義が無いもの）

| 名前 | 住んでいる場所 | 何か |
|---|---|---|
| `CollisionShape2D` / `GameEngine.*` / `FontAtlas` | `engine/` | エンジンの契約と基本型（当たり判定の形・キー・描画命令・フォント） |
| `EntityId` / `Physics2D`（integrate/detect/separate/bounce） | `engine_world/` | 物のidと、物理の 4 つの純関数。積分 → 衝突検出 → めり込み解消 → 反射 |
| `CameraRig` | `engine_world/` | カメラ（オフセット）と trauma 式シェイクの式 |
| `Render` / `PlacedItem` | `engine_world/` | 「(置き場所, 見せたい物)」の語彙と描画命令への変換 |
| `Fx` / `Quad` / `Curve` / `Hash01` | `engine_world/` | 破片・四角形・補間・ノイズの純粋な計算 |
| `Replay` | `engine_world/` | 入力の列で update を最後まで流す（テストと GIF の共通駆動） |
| `SfxSynth` / `SoftRaster` / `GifEncoder` | `engine_tools/` | 音の合成・画面なし描画・GIF 書き出し |

Flix の `run { ... } with X.runWithY` は「この処理が外の世界に触れるとき、その実体を X に任せる」
という宣言です（effect handler）。詳しくは [Flix 公式ドキュメント](https://doc.flix.dev/) の
Effects and Handlers を参照してください。

## 検証の流儀

- **数値で固定する**: テストは「反射角 0.5 → 速さ 133.25」のように計算結果を具体値で固定します
  （`test/TestBreakout.flix` がそのまま挙動の教科書になる）
- **絵はバイトで固定する**: `make bake` の生成物（PNG/GIF/WAV）は決定的なので、
  挙動を変えないリファクタは **全ファイルの shasum が一致**することで機械的に証明できます
- テストは検証だけ・生成は `make bake` — 役割を分けてあるのでテストは ~7 秒で回ります

## 練習課題

### ① 4 面目を足す（触るのは Levels.flix と、壊れるテスト 1 つ）

1. `src/Levels.flix` の `rows` に `case 4 => ...` で盤面を 1 枚描く（`.` 空 / `n` 通常 / `h` ハード / `#` 不壊）
2. `count()` を `4` にする — 盤面を足し忘れると `case _` が大声で落ちて教えてくれる
3. `make test` — `testLevelCensus` が「新しい面のブロック数を教えて」と落ちるので、
   数えて期待値に足す（これがあなたの面の設計を数字で固定した瞬間）
4. `make run` で 3 面クリア後に自分の面が出る

### ② ブロックの色を変える

`src/Palette.flix` の `blockRow` にある RGB を書き換えるだけ。描画コードは触らない。

### ③ ボールに縁取りを付ける（数行）

`src/View.flix` の `ballBoxes` は共有ヘルパー `circleItem` 越しに円を作っているので、
ボールだけ飾るにはヘルパーをほどいて item 側に修飾を繋ぐ:

```flix
def ballBoxes(core: Field.GameCore): List[Render.PlacedItem] =
    let r = Field.ballRadius();
    ({ x = core#ballPos#x - r, y = core#ballPos#y - r },
     Render.circle(r, Palette.ball(), zBall()) |> Render.outline(Palette.titleText(), 0.7)) :: Nil
```

修飾（rounded / fade / outline / striped）は「(置き場所, item)」の item 側に効く、というのがミソ。

### ④ 音を 1 つ足す（6 箇所を通す cookbook）

例:「パドルの端で受けたときだけ鳴る音」

1. `src/World.flix` — `Field.Sfx` enum に case を足す（例 `EdgeHit`）
2. `src/Step.flix` — 鳴らしたい瞬間に `sfx = Field.Sfx.EdgeHit :: core#sfx` を積む
3. `src/Sfx.flix` — `nameOf` で音名（例 `"edge"`）へ写す
4. `src/bake/SfxBake.flix` — 合成レシピを書いて `bakeAll` に 1 行足す
5. `project.json` — `"sounds"` に `{name, path, looping}` を足す
6. `make bake` して `make run`

### ⑤ 手応えを調整する（コードを触らない）

`make run` 中に `assets/parameters.json` を編集して F1 — 反射の最大角・加速・パドル速度・
残像の長さがその場で変わる。気に入った値は `Bounce.flix` / `World.flix` の既定値へ昇格させる。
