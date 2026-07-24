# 霧の里

flix_game_engine の RPG・アドベンチャー（見下ろし）テンプレート。
霧の出た段々畑の里を ←→↑↓ で歩き、住人に話しかけ（1 行ふきだし）、薬草を拾う。
木戸の鍵は物ではなく約束 — 門番に頼まれた数の薬草を持って話しかけると開く。
薬草を goal 個（Doc で調整可）拾うとクリア。拾うたび、夕暮れの里に灯りがひとつ点く。

操作: ←→↑↓（WASD 可）で歩く / Z・Enter・Space で話す・進める。

## 始め方

Flix コンパイラはエンジンリポの `bin/flix` ラッパ経由で呼ぶので、devbox shell の外でも動きます。
エンジンの場所が既定（生成時に埋め込み）と違うときは `ENGINE=/path/to/flix_game_engine` を付けてください。

| コマンド | 何をするか |
|---|---|
| `make run`    | ゲームを起動する（窓が開く） |
| `make debug`  | 保存即反映(watchFile)と F8 を有効にして起動 |
| `make check`  | 型検査だけ走らせる（一番速い確認） |
| `make test`   | テストを実行する |
| `make bake`   | ギャラリー PNG を焼く（決定的な 5 場面: title / walk / talk / door / clear） |
| `make bench`  | 焼いた絵を golden とバイト比較する |
| `make golden` | いまの gallery を golden として祝福する |
| `make atelier-preview` | atelier/ の候補と assets/ の現行を debug/atelier/ に焼く |

## 読む順（全体像のつかみ方）

**遊ぶ → 読む → JSON をいじる** の順で仕組みが見えます。

1. まず `make run` で遊ぶ（矢印キーで歩き、住人に話しかけ、薬草を拾う）。
2. コードは **エントリ→状態→描画→入力** の順で読む:
   1. `src/Main.flix` … 3 つを App に繋いで起動する目次。冒頭 doc に**毎フレームの流れ
      （入力→状態更新→描画 がどの行か）**が書いてある（`update = …` の 3 行）。まずここ。
   2. `src/World.flix` … ゲームの状態そのものと、次の状態を作る規則（歩ける・ぶつかる・
      約束で開く・クリア。すべて純粋）。冒頭 doc に**場面の移り変わりの図**（表紙→里→クリア）が
      あり、遷移を起こす関数には doc に `[遷移: X→Y]` が付いている。まず `step`（毎フレームの拍）と
      `confirm`（決定＝話す/進める）を読む。
   3. `src/View.flix` … 状態を絵に写す（タイル・木戸・灯り・霧・ふきだしを、何をどこに描くか）。
   4. `src/Controls.flix` … キーの割り当て（InputMap）と Doc の読み直し。
   5. `src/bake/Bake.flix` … 決定的な 5 場面を PNG に焼く（golden とアトリエ）。
3. 手触り・色・絵・盤面は下の `assets/` の Doc を保存即反映でいじる。

**いちばん小さい変え方**（保存即反映を体験する）: `make debug` で起動したまま
`assets/rpg.map.json` の `"goal": 5` を `2` に書き換えて保存すると、薬草 2 個でクリアになる。
`assets/rpg.kind.json` の `"walk": 6.0` を大きくすると歩きが速くなる。数値ひとつで手触りが変わる。

数値・色・絵・盤面は `assets/` の Doc（保存即反映）:

- `assets/rpg.map.json` … 里の間取り。タイルの rows（`#`=石垣 `,`=畑 `.`=道）・住人と 1 行・
  扉と約束（promise / need / ask / opened）・薬草と灯りの配置・goal・表紙の文言。
  `src/MapDoc.flix` が読む。
- `assets/rpg.terrain.json` … セル文字→質感の表。**rows を塗るだけで地形が描ける**
  デュアルグリッド（角の埋まり方から丸/四角/ひし形が自動生成される）。チップ絵を描かず
  色と質感パラメータだけで地形を作る。色は `#rrggbb` か `@キー`（rpg.theme.json 参照）。
  `src/View.flix` が engine の `TerrainDoc`（読み込み）と `Terrain.fromRows`（描画）に渡す。
- `assets/rpg.kind.json` … 手触りの数値（歩く速さ・文字送り）。`src/KindDoc.flix` が読む。
- `assets/rpg.theme.json` … 色票（空・畑・霧・灯りなど）。`src/ThemeDoc.flix` が読む。
- `assets/rpg.sprite.json` … ドット絵（主人公・住人・薬草。文字格子）。entityId は `rpg.sprites`。

それぞれに Studio 用の schema が並んでいて、`project.json` の `editor.resources` が宣言しています。
Studio で開けばそのまま編集できます。

## このテンプレートが守っている線引き

- 入っている物: マップ 1 枚・壁の衝突・歩行・住人の 1 行ふきだし・約束で開く扉 1 組・
  薬草 N 個でクリア（N と配置は Doc）・決定的な 5 場面。
- 入れていない物: 戦闘・レベル・経験値・インベントリ・セーブ・複数マップ。
  亜種（コマンド戦闘型など）の決め打ちになる要素は骨格に持ち込まない。

## 絵の開発ループ

- `make bake` で `gallery/` に決定的な PNG を焼き、`make golden` で祝福、`make bench` で防護。
- 候補のスプライト・テーマは `atelier/` に置き、`make atelier-preview` で `debug/atelier/` に焼いて目視。

## AI エージェント向け指針の配布（sync-agents）

エンジン側で `make sync-agents GAME=/path/to/このゲーム` を実行すると、エンジン共通の
エージェント指針（agents-pack/AGENTS.core.md）とこのゲームの `AGENTS.local.md` を連結した
`AGENTS.md` が生成され、共通スキルが `.claude/skills/` にコピーされます。`AGENTS.md` は
生成物なので直接編集せず、ゲーム固有の原則は `AGENTS.local.md` に書いて再 sync してください。
