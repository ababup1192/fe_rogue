# liars_room — うそつきのへや

値ベース第三作（Flix 組み込み Datalog が主役）。部屋を歩いて色つきの住人に話しかけ、
証言から**全員の正体（うそ/ほんと）を推理してメモに書き、提出して答え合わせ**する。
全 10 ステージ、難易度はパラメータ化されシード固定で決定論的に生成される。コメントは日本語。

## モジュール地図（src — 生成系は src/bake/ に隔離）

| ファイル | 役割 |
|---|---|
| Main | App に部品を繋ぐ目次（宣言のみ） |
| Controls | キー割り当て（Frame → Room.Input）+ step / projectUi / reloadUi / wantsQuit |
| LiarsRoom | ルールの中心: フェーズ機械込みの tick・Session 型・sfxEvent・BGM の火入れ |
| Room | 部屋の型（World / Input / Phase / Mark）とグリッドルール（移動・話しかけ対象） |
| RoomMap | 部屋のテキストアート（小中大 3 テンプレ）+ パーサ |
| Stmt | 発言の AST（Say / Not）・正規化（否定の偶奇潰し）・日本語文言・直接評価 holds |
| Rules | ★Datalog ルールパック = 発言の意味論の唯一の置き場（consistent / propagate / reachable） |
| Solver | 総当たり（solutions / uniqueSolution）と仮置きの深さ（probeDepth）— 独立 2 実装の相互 oracle |
| Random | 乱数。第一級の Generator[a]（Seed/initialSeed/step/map/andThen/int/list/uniform/oneOf）と、種を書かない Rng エフェクト（sample/withSeed）+ 相互変換 toGen を一枚岩で同居。splitmix64 は private |
| Gen | 難易度 → 発言セットの組み立て（build = 実行時・無検証、validated = 探索とテスト用） |
| Stage | 10 ステージの難易度表 + 出題プール（各 6 シード）。**ステージを足すならここ + SeedSearch** |
| Human | 人間シルエットの手続き描画（ピクトグラム風・4 方向・歩行 / 立ち・探偵帽） |
| Palette | DB32 のロール名（NPC 7 色 + 呼び名。描画コードは色リテラル禁止） |
| View | Session → 絵（Placed 列）。部屋 + 人 + 頭上の印。シェイクは盤面だけ揺らす |
| GameUi | 全 ui.json ページの読み込みと毎フレームの投影（UiDialog / UiSlots / UiMenu を使う） |
| Sfx | 前後 Session → 鳴らす音名（実体は LiarsRoom.sfxEvent） |
| Trace | テストとギャラリー共有の入力部品（タップ・体勢作り・stepN） |
| Harness | 画面なしフォント焼き + UI spawn（フォントが持つ全グリフが使える） |
| LiarsLint | UiWorld → RenderLint 入力の橋（幾何 lint） |
| bake/Bake | make bake の入口（Sfx + NpcGallery + GameGallery） |
| bake/SeedSearch | 合格 seed の探索（`bin/flix run --entrypoint SeedSearch.search`） |
| bake/SfxBake | 効果音 7 種（BGM の時計ループ含む）を SfxSynth で合成 |
| bake/NpcGallery | シルエット 8 人 × 4 方向の PNG / 歩行 GIF |
| bake/GameGallery | 画面スクショ 7 枚 + 会話デモ GIF |

test/ は検証のみ: TestRules（意味論の pin）・TestSolver（10 ステージの機械証明:
唯一解 pin・fold vs Datalog の解集合一致・難易度カーブ・決定論）・
TestLiarsRoom（フェーズ機械とメモの挙動 pin）・TestViewGuards（UI lint・パーツ数・到達性）。

## UI の bind 規約

実行時に変わる 1 色テキストは ui.json の `bind` キー（stageLabel / resultHeadline 等）に GameUi.bindText が流し込む。
各画面の `assets/<名前>.preview.json`（サンプル文言 + Hud 合成）で ui.json エディタが本番相当の画面を再現できる。

## パズルの仕組み（要点）

- 発言の意味論は Rules.flix の Datalog ルールパックにしか存在しない
  （正直者の発言は真・嘘つきの発言は逆、同類/別類は推移閉包で伝播）。
- 二重否定は表示だけの飾り: Stmt.normalize が inject 前に偶奇で潰すので、
  Datalog には否定が一切現れない（層化否定の問題なし）。
- 出題はステージごとの**シードプール（6 本）からのくじ引き**: タイトルからの経過フレーム数
  （entropy）で選ぶので毎回違う問題が出る。不正解のやり直しは World が覚えた puzzleSeed で
  同じ問題を再構成する。実行時の再構成は無検証の Gen.build（軽い）。
  「プールの全シードが一意解 + 狙った深さで必ず解ける」ことは TestSolver が全数証明する。
- **回答 = メモ**: 全員ぶんマークが埋まると提出行が点灯し、メモ内の Enter で答え合わせ
  （Room.memoComplete / memoMatchesTruth）。全員一致でクリア、違えばシェイクして
  「どこかがちがう」（どこかは言わない・メモは残る）。当てずっぽうは 1/C(n,k) =
  ステージ1で33%・10で2.9%（「正直者を1人信じる」旧方式は57〜67%で甘すぎた）。
- ヒント（H キー・1 ステージ 1 回）は唯一解から嘘つきを 1 人選んでメモに書き込むだけ
  （Room.applyHint）。推理エンジンではなく答えの一部開示。
- **告発・擁護だけの構成では「嘘つき = ちょうど半数」は一意解にできない**
  （全員の種別を反転した割り当ても整合するため）。半々にするなら同類/別類を入れる。

## コマンド（このディレクトリで）

| コマンド | 用途 |
|---|---|
| `make run` | ゲームを起動する |
| `make bake` | ギャラリーと効果音 WAV を生成する |
| `make test` | テストを実行する（検証のみ・~6 秒） |
| `make check` | 型検査だけ走らせる |

## 操作

矢印 / WASD = 歩く / Z = 話す・しるし / C = すいりメモ / H = ヒント（1 ステージ 1 回）/ X = もどる /
Enter = メモ内でこたえあわせ・画面送り / F1 = ui.json リロード /
左 Shift 長押し 5 秒 = デバッグ（全メモが正解で埋まる。D は WASD の右移動に譲った）
