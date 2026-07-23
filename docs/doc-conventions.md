# Doc 規約 — ゲームデータ JSON の共通ルール

このエンジンのゲームデータ（キャラ・テーマ・光・シェーダーなど）は、すべて
「Doc」と呼ぶ JSON ファイルで持つ。Doc は種類が違っても**外側の形は全部同じ**。
だから一度覚えれば全部読めるし、エディタ・ホットリロード・テスト・AI 生成が
どの Doc にも同じやり方で効く。

この文書はその「外側の形」を決める規約。**新しい機能はここに従う Doc を
1 つ足す形でだけ増やす。外側の形そのものは変えない。**

## 命名

| 場合 | ファイル名 | 例 |
|---|---|---|
| 同じ種類のファイルが複数ある | `<名前>.<種類>.json` | `grass.theme.json` / `cave.light.json` / `b1.dungeon.json` |
| プロジェクトに 1 つだけ | `<種類>.json` | `characters.json` / `hitbox.json` |
| スキーマ（種類ごとに 1 つ） | `<種類>.schema.json` | `theme.schema.json` |

## 外形 6 点（すべての Doc が守ること）

1. **`version` を持つ**（整数）。将来形を変える時の移行の目印。
2. **スキーマを持つ**（`<種類>.schema.json`）。エディタのフォーム生成・
   起動時の検証・AI がデータを書く時の仕様書、の 3 役を 1 枚で担う。
3. **読み込みは fail-open**。書き損じや欠けは既定値へ倒す。色 1 つのミスで
   画面を壊すより、保存即反映で直せる方を選ぶ。
4. **`note` フィールド歓迎**。人間と AI のためのメモを一級として許す
   （パーサは黙って無視する）。
5. **project.json の `editor.resources[]` が唯一の登録窓口**。
   `{ id, pattern, title, schema }` を宣言すると、エディタの目次に並ぶ。
   キー名は `schema`（`schemaPath` ではない — 間違えると黙って sibling 規約に
   倒れて迷子になるため、未知キーはエディタが警告する）。
   宣言していない Doc はエディタに現れない（それだけ。ゲームは動く）。
6. **保存で即反映・golden でテスト可能**。ゲームは `App.watchFile` で Doc を
   監視でき、編集は走っているゲームにその場で映る。Doc → 絵/トレースは
   決定的なので、スナップショットのバイト一致でテストできる。

## データの流れ（Doc がゲームに効くまで）

```
*.kind.json → load（起動時に値へ）→ seed（純関数・一度きり）→ World（唯一の権威）
                                     ↑ 保存を watchFile が拾って再 load
```

Doc は「初期値と見た目の宣言」まで。実行中の状態は World だけが持つ。
振る舞い（ルール・生成・物理）はコードで書く — Doc に振る舞いは入れない。

## 新しい Doc を足すときのチェックリスト

- [ ] ファイル名は命名表に従っているか
- [ ] `version: 1` があるか
- [ ] `<種類>.schema.json` を書いたか
- [ ] パーサは fail-open か（壊れた入力で bug! せず既定へ倒すか）
- [ ] project.json の `editor.resources[]` に宣言したか
- [ ] `App.watchFile` で監視する配線をゲームに入れたか（即反映が欲しい場合）
- [ ] Doc → 出力（絵・値）を pin するテストを 1 本書いたか

## 任意の推奨規約：いま画面に出ている Doc を名乗る

ゲームは表示中の Doc が変わったとき、`debug/active-docs.json` に
「宣言 id → いま読んでいるファイル」を書いてよい（任意・変化時のみ）:

```json
{ "active": { "dungeon": "assets/b1.dungeon.json", "theme": "assets/grass.theme.json" } }
```

エディタはこれを見て「いま画面に出ているファイル」に 🎮 印を付け、
表示中でないファイルを編集している時に注意を出す。ファイルが無ければ
エディタは何も出さない（付けるかどうかはゲームの自由）。

## スキーマの書き方（sections 方言の細かい取り決め）

- **スカラー型は `text` を標準**にする。schema の `kind: "field"` と `"value"` は
  同義（どちらも「スカラー 1 個のセクション」）。**`@参照`（テーマ色などを名前で
  引く）を書く欄は `color` でなく `text`** にする — color ピッカーは `#rrggbb` の
  固定色しか表せず、`@wall` のような参照を書けないため。
- **terrain の `entries[].char` は表内で一意**が契約。重複していたら先勝ち
  （先の宣言が有効・後は捨てる）で decode する（壊れ扱いにせず静かに畳む = fail-open）。

## 良いお手本

flix_ge_dungeon の assets/ がこの規約の実例になっている:
`characters.json` + `characters.schema.json`（キャラ）、`*.theme.json`（地形の
見た目）、`*.light.json`（灯り）、`*.dungeon.json`（フロア）、`sprites.json`
（飾り）、`*.shader.json`（水・マグマの面）。project.json の editor 宣言と
セットで、エディタ・ホットリロード・テストが全部この形の上で動く。

templates/rpg-starter の assets/ も実例:
`rpg.terrain.json` + `terrain.schema.json`（セル文字→質感の表。色は `#rrggbb` か
`@キー` のテーマ参照。`entries[].char` は一意・重複は先勝ち）。`rows` を塗るだけで
DualGrid の角の変化形が自動生成される「地形」Doc の書き方の見本になっている。
