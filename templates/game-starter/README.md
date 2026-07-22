# __TITLE__

flix_game_engine のスターター。主人公（ドット絵）を矢印キーで動かせるだけの、
「ここから自分のゲームを育てる」ための骨組みが入っています。
`make new-game` で生成された時点で check / test / bake が全部通る状態です。

## 始め方

Flix コンパイラはエンジンリポの `bin/flix` ラッパ経由で呼ぶので、devbox shell の外でも動きます。
エンジンの場所が既定（生成時に埋め込み）と違うときは `ENGINE=/path/to/flix_game_engine` を付けてください。

| コマンド | 何をするか |
|---|---|
| `make run`    | ゲームを起動する（窓が開く） |
| `make debug`  | 保存即反映(watchFile)と F8 を有効にして起動 |
| `make check`  | 型検査だけ走らせる（一番速い確認） |
| `make test`   | テストを実行する |
| `make bake`   | ギャラリー PNG を焼く（決定的） |
| `make bench`  | 焼いた絵を golden とバイト比較する |
| `make golden` | いまの gallery を golden として祝福する |
| `make atelier-preview` | atelier/ の候補と assets/ の現行を debug/atelier/ に焼く |

## 触る場所

- `src/World.flix` … ゲームの状態そのものと、次の状態を作る規則（純粋）。
- `src/Controls.flix` … キーの割り当てと Doc の読み直し。
- `src/View.flix` … 状態を絵に写す（何をどこに描くか）。
- `src/Main.flix` … 上の3つを App に繋いで起動する目次。
- `src/bake/Bake.flix` … 決定的な場面を PNG に焼く（golden とアトリエ）。

数値・色・絵は `assets/` の Doc（保存即反映）:

- `assets/sample.kind.json` … 手触りの数値（例: 速さ）。`src/SampleDoc.flix` が読む。
- `assets/*.theme.json` … 色票。`src/ThemeDoc.flix` が読む。
- `assets/*.sprite.json` … ドット絵（文字格子）。entityId は `<パッケージ名>.sprites`。

それぞれに Studio 用の schema（sections 方言 / sprite は draft-07）が並んでいて、
`project.json` の `editor.resources` が宣言しています。Studio で開けばそのまま編集できます。

## 絵の開発ループ

- `make bake` で `gallery/` に決定的な PNG を焼き、`make golden` で祝福、`make bench` で防護。
- 候補のスプライト・テーマは `atelier/` に置き、`make atelier-preview` で `debug/atelier/` に焼いて目視。

## AI エージェント向け指針の配布（sync-agents）

エンジン側で `make sync-agents GAME=/path/to/このゲーム` を実行すると、エンジン共通の
エージェント指針（agents-pack/AGENTS.core.md）とこのゲームの `AGENTS.local.md` を連結した
`AGENTS.md` が生成され、共通スキルが `.claude/skills/` にコピーされます。`AGENTS.md` は
生成物なので直接編集せず、ゲーム固有の原則は `AGENTS.local.md` に書いて再 sync してください。
