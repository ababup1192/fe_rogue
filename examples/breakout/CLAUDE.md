# breakout

値ベースの入口教材。人間向けの案内（遊び方・読む順・練習課題・用語集）は README.md にある。

## モジュール地図（src 全16ファイル）

| ファイル | 役割 |
|---|---|
| Main | App に部品を繋ぐ目次（5行の宣言） |
| App | ランナー — ループ・入力・描画・音再生など外の世界に触れる処理を独占（エンジン昇格予定層） |
| Controls | キー割り当て（Frame → Field.Input）+ step/reloadParams |
| World | 全状態の型（mod Field）と定数。Phase/GameCore/Store/調整値 |
| Levels | 面の文字データ（4面目を足すならここ。count と rows は同時に増やす — 忘れは bug! で落ちる） |
| Step | 1フレームのルール（純粋）。物理→衝突の政策→フェーズの結末 |
| Bounce | パドル反射の角度・加速の式（本作の要） |
| View | World → 絵（Placed 列）。Layer(World/Screen)・カメラシェイク |
| Sfx | World の前後 → 鳴らす音名 |
| Palette | 色のロール名（描画コードは色リテラル禁止） |
| GameParameters | F1 リロードの調整値（fail-open） |
| Bake | make bake の入口（Gallery + SfxBake を呼ぶ） |
| Gallery | ギャラリー生成（PNG/GIF/コマ送りサイト → gallery/index.html） |
| SfxBake | 効果音8種を SfxSynth で合成して WAV へ |
| Trace | テストとギャラリー共有のシナリオ（初期 World 集） |
| Harness | 画面なしフォント焼き |

## コマンド（このディレクトリで）

| コマンド | 用途 |
|---|---|
| `make run` | ゲームを起動する |
| `make bake` | ギャラリー（PNG・GIF・コマ送りサイト）と効果音 WAV を生成する |
| `make test` | テストを実行する（検証のみ・生成はしない。~7 秒） |
| `make check` | 型検査だけ走らせる |

## 検証の流儀

- 挙動を変えないリファクタは `make bake` 後に `gallery/` の全ファイル shasum が**バイト一致**することで機械的に証明する（PNG/GIF/WAV は決定的に生成される）
- 挙動を意図的に変えたときだけ該当ファイルの SHA が変わる。テストの数値 pin（反射角・加速・trauma 等）も同じ思想
- テストは検証だけを行う。成果物の生成は `Bake.all` の仕事（テストコードに生成を書かない）

## コメントの流儀

- 独自比喩を使わない（番地・縁・単独者・群れ・店・局面・糸などは過去に排除済み）
- ECS 等の業界標準用語（Store など）は英語のまま + 初出で一言説明
- record 束ねは「複数の値」にだけ使う。単一値の named-param 化（`x: {x = Float64}` → 本体で `x#x`）は禁止
