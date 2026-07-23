# エージェント共通指針（エンジン公式・全ゲーム共有）

このファイルはエンジンの agents-pack から配られる共通部。ゲーム固有の方針は
同じフォルダの `AGENTS.local.md` に書く。

## Doc 規約（ゲームデータ JSON）

- **1 種類 = 1 Doc + 1 スキーマ**（`<名前>.<種類>.json` と `<種類>.schema.json`）。
  外側の形は全 Doc 共通: `version` を持ち、`note` フィールド歓迎。
- **読み込みは fail-open**。書き損じや欠けは既定値へ倒す。既定値はコード側に持つ。
- **watchFile で保存即反映**。調整のたびに再起動しない。
- **データは Doc・振る舞いはコード**。繰り返し調整する数値（テンポ・閾値・収支・確率）、
  個数が増減するデータ（rows）、色テーマ、文言は Doc へ。描画アルゴリズム・演出の形・
  導出できる値・ルールはコードのまま。ロジックを JSON に書き始めたら設計の匂い。
- **プレイヤーの目に入る文言は必ず Doc に置く（既定値はコード側）**。
  コード直書きの表示文字列は違反 — Studio から変えられない。

## atelier/ 規約（採用前の候補置き場）

- `atelier/` は **採用前の候補**を置く場所。中身は `assets/` と同じ Doc 形式。
- `assets/` のパスは**スロット**（Doc の `entityId` で互換を確認する）。
- 採用は **swap**: 候補の中身をスロットへ移す(候補ファイルは消える)。それまでの中身は
  `atelier/archive/<base>.vN.<kind>.json` に積まれる(何も捨てない。戻すのもここから)。
- **AI が素材を作るときは `assets/` に直接書かず、必ず `atelier/` に書く。**

## make の入口

- `make run` / `make debug`（watchFile・F8 有効）/ `make check`（型検査・一番速い確認）
- `make test` / `make bake`（決定的な絵を焼く）/ `make bench`（gallery/ vs golden/ のバイト比較）
- `make golden`（いまの gallery を基準にする）
- `debug/` のコンタクトシート系ターゲット（例: `make gallery-prologue` の all.png、
  `make gallery-sounds` の sounds.png / music.png）で**目視・目聴**して批評する。

## テスト方針（要約）

- テストするのは「ゲームの**ルール・進行・収支**」と「JSON とプログラムの橋渡し」だけ。
  モーション・表示タイミング・座標の写経はテストしない（演出は golden と目視の仕事）。
  ただしクリック当たりの有無はルールなので残す。
- **期待値は Doc（JSON 既定値）から導く**。数値リテラルを貼らない。
- 橋渡しテストは **1 Doc につき最大3本**（壊れた JSON→既定値 / 1 フィールド上書き /
  rows 長の追随）。initialState の写経など情報量ゼロのテストは書かない。

## エンジン API 優先(車輪の再発明禁止)

- 実装の前に engine リポの `docs/module-index.md`(「やりたいこと → モジュール」の逆引き)を引く。
  メニュー・スクロール・文字折り・当たり判定・タイムラインなど、**エンジンにある物を自前で書かない**。
- 各モジュールの詳しい使い方は `engine_world/src/<名前>.flix` 冒頭の doc コメントと、
  templates/ のスターターにある実使用例が正。
- 迷ったら「低い API で書けたか」ではなく「一番高い API で書けたか」を疑う。
  自前実装が残っていたら、それはレビュー(critique)で指摘される対象。

## 迷ったら読む物

- Flix の書き方・エンジンの流儀: `.claude/skills/flix-docs`(構文の癖)、`compile-fix`(コンパイルエラーの定石)、`quality-assurance`(テスト設計)
- Doc の外形規約の正: engine リポの `docs/doc-conventions.md`
- エンジン API の地図: engine リポの `docs/module-index.md`(やりたいこと → モジュールの逆引き)
- UI に出す言葉の決め方と対応表: engine リポの `docs/glossary.md`(効果語だけ・内部語は UI に出さない)
- 動く見本: engine の `templates/game-starter`(最小)と、隣にある既存ゲーム(村・breakout 等)のソース
