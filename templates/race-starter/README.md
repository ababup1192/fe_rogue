# Race

flix_game_engine の見下ろしレースのテンプレート。
画面下の車を ←→ で左右に寄せ（ハンドル）、下へ流れるコースを走ります。道（路面）から
草へはみ出すと減速。前方のライバル 2 台を抜くと順位（RANK）が上がり得点が入り、
決めた周回数（LAP）を走り切るとゴール（FINISH）です。

原始的なレースに、読んで学べる最小限を足した骨格 — ハンドル（steerSpeed）・
はみ出し減速（offRoadSlow）・ライバルの追い抜き（順位と得点）・周回とゴール・
追い抜きの控えめな閃光演出・文字格子（rows）で表すコース。

操作: ←→（ハンドル・左右に寄る）/ Space・Enter（Title・Finish では決定）。

## 始め方

Flix コンパイラはエンジンリポの `bin/flix` ラッパ経由で呼ぶので、devbox shell の外でも動きます。
エンジンの場所が既定（生成時に埋め込み）と違うときは `ENGINE=/path/to/flix_game_engine` を付けてください。

| コマンド | 何をするか |
|---|---|
| `make run`    | ゲームを起動する（窓が開く） |
| `make debug`  | 保存即反映(watchFile)と F8 を有効にして起動 |
| `make check`  | 型検査だけ走らせる（一番速い確認） |
| `make test`   | テストを実行する |
| `make bake`   | ギャラリー PNG を焼く（決定的な 4 場面: title / s1_race / s2_finish / s3_last） |
| `make bench`  | 焼いた絵を golden とバイト比較する |
| `make golden` | いまの gallery を golden として祝福する |

## 読む順（全体像のつかみ方）

**遊ぶ → 読む → JSON をいじる** の順で仕組みが見えます。

1. まず `make run` で遊ぶ（ハンドルで寄せ・ライバルを抜き・周回してゴールする）。
2. コードは **エントリ→状態→描画→入力→焼き** の順で読む:
   1. `src/Main.flix` … 4 つ（init/update/view/reloads）を App に繋いで起動する目次。
      冒頭 doc に**ゲームループの全体像**が書いてある。まずここ。
   2. `src/World.flix` … ゲームの状態そのものと、次の状態を作る規則（前進・ハンドル・
      はみ出し減速・ライバル前進・追い抜き・周回/ゴール。すべて純粋）。冒頭 doc に
      **毎フレームの流れ**と**場面の移り変わりの図**（Title→Racing→Finish→Title）があり、
      遷移を起こす関数には doc に `[遷移: X→Y]` が付いている。まず `step`（毎フレームの拍）を読む。
   3. `src/View.flix` … 状態を絵に写す（流れるコース・ライバル・自機・HUD・場面ごとの幕を、
      何をどこに描くか）。冒頭 doc に**コースの縦スクロールの描き方**がある。
   4. `src/Controls.flix` … キーの割り当て（ハンドル = ←→ 押しっぱなし / 決定 = Space・Enter）
      と Doc の読み直し。
   5. `src/bake/Bake.flix` … 決定的な 4 場面を PNG に焼く（golden 比較・目視批評）。
3. 数値・色・コースをいじる（保存すると走行中のゲームに即反映されます）:
   - `assets/race.rules.json` … 前進速度・ハンドルの効き・草の減速・ライバル速度・周回数・得点。
   - `assets/race.theme.json` … 草・路面・レーン線・自機・ライバル・ゴール・文字の色。
   - `assets/race.course.json` … コースの形（文字格子。'#'=路面、'.'=草）。

黒箱（エンジンの部品）に出会ったら `docs/module-index.md`（エンジンリポ）で
`Render`（描画・`glowAt` の閃光）・`App`（ゲームループ・`axis`/`isDown`/`justPressed`）・
`JsonCodec`（JSON 読み）・`Bakery`（PNG 焼き）を引きます。

## いちばん小さな変え方（保存即反映）

- **周回を短くする**: `assets/race.rules.json` の `totalLaps` を 1 にするとすぐゴールできる。
- **ライバルを抜きやすくする**: `rivalSpeedA` / `rivalSpeedB` を小さくすると追い抜きやすい。
- **草のペナルティを軽くする**: `offRoadSlow` を 1 に近づけるとはみ出しても遅くなりにくい。
- **コースの形を変える**: `assets/race.course.json` の格子（rows）を書き換える。
  '#' の帯を左右にずらせばカーブ、幅を変えれば道の広さ、段（行）を足せばコースが伸びる。

規則そのもの（走る・曲がる・はみ出す・抜く・周回する）はコード（`src/World.flix`）側にあります。
Doc はあくまで「調整したい初期値の宣言」で、壊れても既定値で必ず起動します（fail-open）。
