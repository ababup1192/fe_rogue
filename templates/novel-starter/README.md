# 消えた絵

flix_game_engine のノベル・推理テンプレート。雨の夜の洋館、停電した書斎から一枚の絵が
消えた。文章を読み、疑う相手を選ぶと物語が分岐し、選ぶたびに館の照明がひとつ消える。
台本（文章・分岐・結末）は全部 JSON の rows なので、書き換えれば別の事件になる。

## 始め方

Flix コンパイラはエンジンリポの `bin/flix` ラッパ経由で呼ぶので、devbox shell の外でも動きます。
エンジンの場所が既定（生成時に埋め込み）と違うときは `ENGINE=/path/to/flix_game_engine` を付けてください。

| コマンド | 何をするか |
|---|---|
| `make run`    | ゲームを起動する（窓が開く） |
| `make debug`  | 保存即反映(watchFile)と F8 を有効にして起動 |
| `make check`  | 型検査だけ走らせる（一番速い確認） |
| `make test`   | テストを実行する |
| `make bake`   | ギャラリー PNG を焼く（決定的: title / choice / ending） |
| `make snapshot-check`  | 焼いた絵をスナップショットとバイト比較する |
| `make snapshot-update` | いまの gallery をスナップショットとして更新する |
| `make atelier-preview` | atelier/ の候補と assets/ の現行を debug/atelier/ に焼く |

## 遊び方

クリック / Z / Enter で読み進める。選択肢は ↑↓（またはマウス）で選んで決定。
疑う相手を選ぶたびに館の灯りがひとつ消え、部屋が暗くなる。結末は 2 つ。

## 読む順（全体像のつかみ方）

**遊ぶ → 読む → JSON をいじる** の順で仕組みが見えます。

1. まず `make run` で遊ぶ（読み進めて、疑う相手を選ぶ）。
2. コードは **エントリ→状態→描画→入力** の順で読む:
   1. `src/Main.flix` … 部品を App に繋いで起動する目次。冒頭 doc に**毎フレームの流れ
      （入力→状態更新→描画 がどの行か）**が書いてある（`update = …` の 3 行）。まずここ。
   2. `src/World.flix` … 進行の規則そのもの（拍の送り・分岐・「疑うと灯りが消える」。純粋）。
      冒頭 doc に**場面の移り変わりの図**（表紙→物語→結末→表紙）があり、遷移を起こす関数には
      doc に `[遷移: X→Y]` が付いている。まず `advance`（決定＝読み進める）と
      `pick`（選択肢を選ぶ）を読む。
   3. `src/View.flix` … 状態を絵に写す（書斎・雨の窓・空の額縁・灯り・暗幕・表紙を、何をどこに）。
   4. `src/NovelKit.flix` … 会話窓と選択肢のキット（UiDialog + UiTypewriter + UiSlots の束ね）。
   5. `src/Controls.flix` … キーの割り当て（選ぶだけ）と Doc の読み直し。
   6. `src/bake/Bake.flix` … 決定的な場面を PNG に焼く（スナップショットとアトリエ）。
3. 台本・手触り・色・絵は下の `assets/` の Doc を保存即反映でいじる。

**いちばん小さい変え方**（保存即反映を体験する）: `make debug` で起動したまま
`assets/novel.story.json` の一節の `text` を書き換えて保存すると、その場で文章が変わる。
選択肢の `label` を変えれば選べる言葉が変わり、`suspect` を `false` にすればその選択で
灯りが消えなくなる。台本（rows）を足し引きすれば事件そのものを作り替えられる。

数値・色・絵・枠は `assets/` の Doc（保存即反映）:

- `assets/novel.story.json` … 台本。`src/StoryDoc.flix` が読む（material）。
- `assets/novel.kind.json` … 手触りの数値（文字送りの速さ・暗くなる度合い）。`src/KindDoc.flix` が読む（tuning）。
- `assets/novel.theme.json` … 場面の色票。`src/ThemeDoc.flix` が読む（material）。
- `assets/novel.sprite.json` … ドット絵（空の額縁）。entityId は `novel.sprites`（material）。
- `assets/ui/*.ui.json` + `assets/ui/palette.json` … 会話窓・選択肢の枠と色（material）。

それぞれに Studio 用の schema が並んでいて、`project.json` の `editor.resources` が宣言しています。

## 絵の開発ループ

- `make bake` で `gallery/` に決定的な PNG（表紙・分岐・結末）を焼き、`make snapshot-update` で更新、`make snapshot-check` で防護。
- 候補のスプライト・テーマは `atelier/` に置き、`make atelier-preview` で `debug/atelier/` に焼いて目視。

## AI エージェント向け指針の配布（sync-agents）

エンジン側で `make sync-agents GAME=/path/to/このゲーム` を実行すると、エンジン共通の
エージェント指針（agents-pack/AGENTS.core.md）とこのゲームの `AGENTS.local.md` を連結した
`AGENTS.md` が生成され、共通スキルが `.claude/skills/` にコピーされます。`AGENTS.md` は
生成物なので直接編集せず、ゲーム固有の原則は `AGENTS.local.md` に書いて再 sync してください。
