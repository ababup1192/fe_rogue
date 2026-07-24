# Raise

flix_game_engine の育成シミュレーションのテンプレート。
発表会までの毎日、いくつかの行動（れんしゅう・きんとれ・やすむ・しあい など）から 1 つを
↑↓ で選び Space/Enter で決める。選んだ行動でパラメータ（たいりょく・きあい・わざ）が育ち、
そのあと確率で「イベント」が起きて数値が上下する。日数を使い切ると発表会で合計値からランク
（きん・ぎん・どう）が決まる。プレイヤーは死なない・詰まない。

ターン制・メニュー選択・Doc 主体の作り — リアルタイム系（shooter / race）とは別系統の骨格です。
行動・イベント・結末・文言は全部 JSON の表（rows）なので、書き換えれば別の育成になります。

操作: ↑↓（←→でも可）で行動を選ぶ / Space・Enter で決定。
Title ではじめ、決めるたびに 1 日進み、Reveal（伸びの見せ物）を送ると次の日へ、
発表会（Result）で Space を押すと最初へ戻ります。

## 始め方

Flix コンパイラはエンジンリポの `bin/flix` ラッパ経由で呼ぶので、devbox shell の外でも動きます。
エンジンの場所が既定（生成時に埋め込み）と違うときは `ENGINE=/path/to/flix_game_engine` を付けてください。

| コマンド | 何をするか |
|---|---|
| `make run`    | ゲームを起動する（窓が開く） |
| `make debug`  | 保存即反映(watchFile)と F8 を有効にして起動 |
| `make check`  | 型検査だけ走らせる（一番速い確認） |
| `make test`   | テストを実行する |
| `make bake`   | ギャラリー PNG を焼く（決定的な 4 場面: title / s1_day / s2_reveal / s3_result） |
| `make bench`  | 焼いた絵を golden とバイト比較する |
| `make golden` | いまの gallery を golden として祝福する |

## 読む順（全体像のつかみ方）

**遊ぶ → 読む → JSON をいじる** の順で仕組みが見えます。

1. まず `make run` で遊ぶ（毎日ひとつ選び・育て・発表会まで進む）。
2. コードは **エントリ→状態→描画→入力→表(Doc)→焼き** の順で読む:
   1. `src/Main.flix` … 4 つ（init/update/view/reloads）を App に繋いで起動する目次。
      冒頭 doc に**ゲームループの全体像**が書いてある。まずここ。
   2. `src/World.flix` … ゲームの状態そのものと、次の状態を作る規則（選ぶ・育つ・イベント抽選・
      日の進行・結末の判定。すべて純粋）。冒頭 doc に**場面の移り変わりの図**
      （Title→Day→Reveal→…→Result→Title）があり、遷移を起こす関数には doc に
      `[遷移: X→Y]` が付いている。まず `confirm`（決定 1 回分）を読むと 1 ターンの流れが掴めます。
   3. `src/View.flix` … 状態を絵に写す（ヘッダ・3 本のパラメータ棒・メニュー・伸びの見せ物・
      発表会の幕を、何をどこに描くか）。
   4. `src/Controls.flix` … キーの割り当て（↑↓ = 選ぶ / Space・Enter = 決定）と Doc の読み直し。
      ターン制なので入力はすべて justPressed（押した瞬間）で拾います。
   5. `src/PlanDoc.flix` … 行動・イベント・結末の「表」を JSON から読む層（`Stats` の共有・
      重み付き抽選のための rows）。表の増減に追随する形の実例。
   6. `src/bake/Bake.flix` … 決定的な 4 場面を PNG に焼く（golden 比較・目視批評）。
3. 行動・イベント・結末・数値・色・文言をいじる（保存すると走行中のゲームに即反映されます）:
   - `assets/raise.plan.json` … 行動（伸び幅）・イベント（増減と出やすさ）・結末（しきい値）・
     パラメータ名・表紙の文言。**行を足せば選択肢や結末が増える**。
   - `assets/raise.rules.json` … 発表会までの日数・イベント確率・パラメータの上限・乱数の種。
   - `assets/raise.theme.json` … 背景・パネル・カーソル・文字・3 本の棒・きらめきの色。

黒箱（エンジンの部品）に出会ったら `docs/module-index.md`（エンジンリポ）で
`Render`（描画・`glowAt` の伸びのきらめき）・`App`（ゲームループ・`justPressed`）・
`JsonCodec`（JSON 読み・rows の `decodeList`）・`TextDraw`（中央そろえの文字）・
`Bakery`（PNG 焼き）を引きます。

## いちばん小さな変え方（保存即反映）

- **行動を 1 つ足す**: `assets/raise.plan.json` の `actions` に 1 行足す
  （`label` と伸び幅 `power`/`spirit`/`skill`、`note` は一言説明）。メニューに増えます。
- **イベントを起きやすくする**: `assets/raise.rules.json` の `eventChance` を大きく（例 0.8）。
- **発表会を早める / 延ばす**: `dayCount` を小さく / 大きく。
- **結末のしきい値を変える**: `endings` の `threshold`（合計値の下限）をいじる。
  一番小さいものは 0 にして必ずどれかに当たるようにします。
- **棒の色を変える**: `assets/raise.theme.json` の `bar1`/`bar2`/`bar3` を好きな `#rrggbb` に。

規則そのもの（伸ばす・確率でイベントを抽選する・結末をしきい値で選ぶ）はコード
（`src/World.flix`）側にあります。Doc はあくまで「調整したい表と初期値の宣言」で、
壊れても既定値で必ず起動します（fail-open）。
