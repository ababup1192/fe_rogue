# 陽だまりの城下町

flix_game_engine の RPG・アドベンチャー（見下ろし）テンプレート。
高い青空の下、40×30 マスの城下町（民家・パン屋・教会・橋・門・柵・街灯・水路・
巡回する住人・窯の煙・旗）を ←→↑↓ で歩き、住人に話しかけ（1 行ふきだし）、薬草を拾う。
木戸の鍵は物ではなく約束 — 門番に頼まれた数の薬草を持って話しかけると開く。
薬草を goal 個（Doc で調整可）拾うとクリア。拾うたび、広場に灯りがひとつ点く。
歩数で魔物に出会う 1 対 1 のコマンド戦闘つき（乱数なし — 難しさは Doc の数で決まる）。

操作: ←→↑↓（WASD 可）で歩く / Z・Enter・Space で話す・進める。

## 遊び方

Flix コンパイラはエンジンリポの `bin/flix` ラッパ経由で呼ぶので、devbox shell の外でも動きます。
エンジンの場所が既定と違うときは `ENGINE=/path/to/flix_game_engine` を付けてください。

| コマンド | 何をするか |
|---|---|
| `make run` | 起動（窓が開く） |
| `make debug` | 保存即反映（watchFile）+ F8 検分 + fps 表示つきで起動 |
| `make check` / `make test` | 型検査 / テスト（36 本） |
| `make palette` | Studio 用の色の写し（`assets/rpg.palette.json`）を作り直す |
| `make bake` | スナップショット用の決定的な 6 場面を `gallery/` に焼く |
| `make bake-town` / `bake-house` / `bake-motion` / `bake-seam` | 街の全景 / 建物の寄り / 動き物 / 継ぎ目検分を `debug/` に焼く |
| `make snapshot-check` / `make snapshot-update` | スナップショットとバイト比較 / いまの gallery を更新 |
| `make atelier-preview` | atelier/ の候補と assets/ の現行を debug/atelier/ に焼く |

- **F1** … Doc を全部読み直す（保存即反映が効かない時の手動リロード）。
- **F8**（`make debug` 中のみ）… 時間停止 + ←→で時間スクラブ + 矩形を囲って注釈チケット。

## 読む順（全体像のつかみ方）

**遊ぶ → 読む → JSON をいじる** の順で仕組みが見えます。

1. まず `make run` で遊ぶ（矢印キーで歩き、住人に話しかけ、薬草を拾う）。
2. コードは **エントリ→状態→描画** の順で読む:
   1. `src/Main.flix` … App に繋いで起動する目次。冒頭 doc に**毎フレームの流れ
      （入力→状態更新→描画 がどの行か）**が書いてある。まずここ。
   2. `src/World.flix` … ゲームの状態そのものと、次の状態を作る規則（歩ける・ぶつかる・
      約束で開く・戦い・クリア。すべて純粋）。冒頭 doc に**場面の移り変わりの図**があり、
      遷移を起こす関数には doc に `[遷移: X→Y]` が付いている。
   3. `src/View.flix` … 状態を絵に写す（タイル・建物・水面・ふきだしを、何をどこに描くか）。
      街タイルの縁・角・橋の選定は `src/TownMap.flix`（rows には素材しか書かない）。
   4. `src/Controls.flix` … キーの割り当て(InputMap)と Doc の読み直し。
   5. `src/bake/Bake.flix` … 決定的な 6 場面を PNG に焼く（スナップショットとアトリエ）。
3. 手触り・色・絵・盤面は下の `assets/` の Doc を保存即反映でいじる。

**いちばん小さい変え方**（保存即反映を体験する）: `make debug` で起動したまま
`assets/rpg.map.json` の `"goal": 5` を `2` に書き換えて保存すると、薬草 2 個でクリアになる。
`assets/rpg.kind.json` の歩く速さを大きくすると足が速くなる。数値ひとつで手触りが変わる。

## Doc 一覧（保存即反映）

街並み側:

- `assets/town.map.json` … 街のタイル盤（40×30 の rows と legend: g/p/w/#）。縁・角・橋の選定はコード（TownMap）。
- `assets/town.sprite.json` … 街のドット絵（タイル家族・建物・門・柵・街灯・旗）。16×16 等倍。
- `assets/town.shader.json` … 水面のシェーダー（流れる網目）。
- `assets/town.fx.json` … 窯の煙のパーティクル。

物語側:

- `assets/rpg.map.json` … 間取り・住人と 1 行・扉と約束・薬草・goal・表紙の文言。
- `assets/rpg.kind.json` … 手触りの数値（歩く速さ・文字送り）。
- `assets/rpg.theme.json` … 色票。画風は「晴れた昼の城下町」（AGENTS.local.md）。
- `assets/rpg.sprite.json` … 主人公・住人・薬草・魔物のドット絵。
- `assets/rpg.battle.json` … 1 対 1 のコマンド戦闘の数（乱数なし）。
- `assets/rpg.palette.json` … Studio 用の色の写し（`make palette` の生成物。手で直さない）。

それぞれに Studio 用の schema が並んでいて、`project.json` の `editor.resources` が宣言しています。
Studio で開けばそのまま編集できます。

## スナップショットの焼き方

- `make bake` で `gallery/` に決定的な PNG を焼き、`make snapshot-update` で更新、`make snapshot-check` で防護。
- 見た目を意図して変えたら: `make snapshot-check` で差分を確認（意図した変化だけが DIFF に
  なっていること）→ `make snapshot-update` で更新 → もう一度 `make snapshot-check` が全 OK。
- 候補のスプライト・テーマは `atelier/` に置き、`make atelier-preview` で `debug/atelier/` に焼いて目視。
