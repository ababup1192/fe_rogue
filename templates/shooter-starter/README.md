# Shooter

flix_game_engine の縦スクロール・シューティングのテンプレート。
下の自機を ←→ で寄せ、Space で弾を撃つ。敵は「波」で上から降りてくる。
弾を当てて撃破し、波を全部そろえて全滅させれば CLEAR。敵が自機まで降りてきたら GAME OVER。

原始的なシューティングに、読んで学べる最小限を足した骨格 — 連射レート（fireInterval）・
波（文字格子で配置）・弾↔敵/敵↔自機の当たり判定・撃破の控えめな爆発演出・流れる星の背景。

操作: ←→（自機を寄せる）/ Space（撃つ・押しっぱなしで連射 / Title・Clear・GameOver では決定）/
Enter（決定）。

## 始め方

Flix コンパイラはエンジンリポの `bin/flix` ラッパ経由で呼ぶので、devbox shell の外でも動きます。
エンジンの場所が既定（生成時に埋め込み）と違うときは `ENGINE=/path/to/flix_game_engine` を付けてください。

| コマンド | 何をするか |
|---|---|
| `make run`    | ゲームを起動する（窓が開く） |
| `make debug`  | 保存即反映(watchFile)と F8 を有効にして起動 |
| `make check`  | 型検査だけ走らせる（一番速い確認） |
| `make test`   | テストを実行する |
| `make bake`   | ギャラリー PNG を焼く（決定的な 4 場面: title / s1_play / s2_clear / s3_over） |
| `make bench`  | 焼いた絵を golden とバイト比較する |
| `make golden` | いまの gallery を golden として祝福する |

## 読む順（全体像のつかみ方）

**遊ぶ → 読む → JSON をいじる** の順で仕組みが見えます。

1. まず `make run` で遊ぶ（自機を寄せ・撃って・波を全滅させる）。
2. コードは **エントリ→状態→描画→入力→焼き** の順で読む:
   1. `src/Main.flix` … 4 つ（init/update/view/reloads）を App に繋いで起動する目次。
      冒頭 doc に**ゲームループの全体像**が書いてある。まずここ。
   2. `src/World.flix` … ゲームの状態そのものと、次の状態を作る規則（自機移動・発射・
      弾/敵の移動・当たり判定・波の進行。すべて純粋）。冒頭 doc に**毎フレームの流れ**と
      **場面の移り変わりの図**（Title→Playing→Clear/GameOver→Title）があり、
      遷移を起こす関数には doc に `[遷移: X→Y]` が付いている。まず `step`（毎フレームの拍）を読む。
   3. `src/View.flix` … 状態を絵に写す（宇宙・星・自機・弾・敵・爆発・スコア・場面ごとの幕を、
      何をどこに描くか）。
   4. `src/Controls.flix` … キーの割り当て（左右 = 押しっぱなし / 発射 = Space / 決定 = Space・Enter）
      と Doc の読み直し。
   5. `src/bake/Bake.flix` … 決定的な 4 場面を PNG に焼く（golden 比較・目視批評）。
3. 数値・色・敵の配置をいじる（保存すると走行中のゲームに即反映されます）:
   - `assets/shooter.rules.json` … 移動速度・弾速・連射間隔・敵速・得点。
   - `assets/shooter.theme.json` … 宇宙・自機・弾・敵・爆発・文字の色。
   - `assets/shooter.waves.json` … 敵の波（文字格子。'.'=空き、'X' などが敵 1 体）。

黒箱（エンジンの部品）に出会ったら `docs/module-index.md`（エンジンリポ）で
`Render`（描画・`glowAt` の爆発）・`App`（ゲームループ・`axis`/`isDown`/`justPressed`）・
`JsonCodec`（JSON 読み）・`Bakery`（PNG 焼き）を引きます。

## いちばん小さな変え方（保存即反映）

- **連射を速くする**: `assets/shooter.rules.json` の `fireInterval` を小さく（例 0.12）すると速く撃てる。
- **敵の攻めを激しくする**: `enemyFallSpeed` を大きくすると波が速く降りてくる。
- **弾の色を変える**: `assets/shooter.theme.json` の `bullet` を好きな `#rrggbb` に。
- **敵の並びを変える**: `assets/shooter.waves.json` の格子（rows）を書き換える。
  行や文字を増やせば敵が増え、波（外側の配列）を足せばステージが伸びる。

規則そのもの（撃つ・当たる・降りる・全滅で次の波へ）はコード（`src/World.flix`）側にあります。
Doc はあくまで「調整したい初期値の宣言」で、壊れても既定値で必ず起動します（fail-open）。
