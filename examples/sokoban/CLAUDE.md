# sokoban

値ベース第二作（undo が主役）。人間向けの案内（遊び方・読む順・練習課題・用語集）は README.md、
作りながらの解説は TUTORIAL.md（英）/ TUTORIAL.ja.md（日）にある。コメントは日本語。

## モジュール地図（src 全 18 ファイル）

| ファイル | 役割 |
|---|---|
| Main | App に部品を繋ぐ目次（宣言のみ） |
| Controls | キー割り当て（Frame → Board.Input）+ step / projectUi / reloadUi / wantsQuit |
| Sokoban | ルールの中心: step（盤面を dt 進める）・tick（undo 履歴込みの 1 フレーム）・Session 型・sfxEvent |
| Board | 盤面の型（World / Input / Screen / Slide）とグリッドルール（move / beginHop / won） |
| Level | sokoban テキスト記法のパーサ + 同梱レベル。**レベルを足すならここ** |
| View | Session → 絵（Placed 列）。compose が盤面と UI を 1 本に合成 |
| Crate | クレートの手続き描画（板 + 継ぎ目 + 対角ブレースの多角形） |
| Robot | ロボットの手続き描画（4 方向 × 歩行位相） |
| Palette | 色のロール名（描画コードは色リテラル禁止） |
| GameUi | Title / Clear ページ（assets/*.ui.json）の読み込みと毎フレームの投影 |
| Sfx | Session の前後 → 鳴らす音名（実体は Sokoban.sfxEvent） |
| Bake | make bake の入口（GameGallery + RobotGallery + SfxBake） |
| GameGallery | スクショ 4 枚・GIF 3 本・ダッシュボードを焼く |
| RobotGallery | ロボット画像 3 点を焼く |
| SfxBake | 効果音 4 種を SfxSynth で合成して WAV へ |
| SokobanLint | UiWorld → RenderLint 入力の橋（幾何 lint） |
| Trace | テストとギャラリー共有のシナリオ（入力キュー列・解答手順） |
| Harness | 画面なしフォント焼き + UI spawn |

test/ は検証のみ: TestSokoban（挙動 pin）・TestSolver + Solver（BFS ソルバーによる機械証明）・
TestViewGuards（UI lint と描画パーツ数の下限ガード）。

## コマンド（このディレクトリで）

| コマンド | 用途 |
|---|---|
| `make run` | ゲームを起動する |
| `make bake` | ギャラリーと効果音 WAV を生成する |
| `make test` | テストを実行する（検証のみ・~7 秒） |
| `make check` | 型検査だけ走らせる |

## 検証の流儀

- 挙動を変えないリファクタは `make bake` 後に `gallery/` と `assets/sfx/` の shasum が**バイト一致**することで機械的に証明する
- レベルは Solver（独立実装の BFS）が最短押し数を機械証明し、静的検査（連結性・角デッドロック）が出荷品質を守る
- テストは検証だけ。生成は `Bake.all` の仕事（テストコードに生成を書かない）

## コメントの流儀

- コメントは日本語。独自比喩を使わない（住む・糸・門・心臓部・拍・呼吸などは排除済み。Worldline は正式な語彙なので使ってよい）
- ECS 等の業界標準用語（Store など）は英語のまま + 初出で一言説明
- record 束ねは「複数の値」にだけ使う。単一値の named-param 化は禁止
