# IDE で Resource を編集する設計メモ

ゲームの「データ + UI ヒント」を JSON で外出しする Godot Resource 風の仕組みを、
将来 IDE 上で Inspector ライクに編集できるようにするための設計指針。
今回 fe_rogue で `UnitCatalog` を導入したのと同じ枠組みを、IDE 側に汎用エディタとして
載せるための前提と注意点をまとめる。

## 全体アーキテクチャ

```
[engine/src/Resource.flix]
    └─ ResourceSchema 規格 (FieldType / FieldHint / FieldEntry)
        + Saveable[ResourceSchema]    ← schema 自身を JSON round-trip
        + checkConsistency             ← Flix 型と schema のズレ検査

[examples/fe_rogue/]
    ├─ src/game/UnitCatalog.flix       ← Flix 型 + Saveable[UnitCatalog]
    ├─ assets/units/units.json         ← データ（カタログ + プール）
    └─ assets/units/_schema.json       ← engine 規格に沿った schema (手書き)

[ide/]  ← 将来 PR で実装
    └─ src/ResourceEditor.flix         ← schema を walk して widget を出す汎用エディタ
```

エンジンは「規格と検査」だけを担当し、IDE は「規格に沿った schema」を読んで
generic な編集 UI を組み立てる。ゲームは「Flix 型と data + schema」を提供するだけ。

## 既に揃っている基盤

| 必要なもの | 利用する既存 API | 場所 |
|---|---|---|
| Resource schema 規格 | `Resource.ResourceSchema` 型 | `engine/src/Resource.flix` |
| schema ロード | `Resource.loadSchema(path)` | 同上 |
| schema/型 整合検査 | `Resource.checkConsistency(expected, schema)` | 同上 |
| データ JSON ロード | `Persistence.load(path)` | `engine/src/Persistence.flix:46` |
| **データ JSON 書き戻し** | `Persistence.save(path, value)` | `engine/src/Persistence.flix:33` |
| ラウンドトリップ保証 | `Saveable.toJson ∘ fromJson = id` | game 側で `instance Saveable[T]` を実装 |
| ファイル一覧取得 | `Fs.Glob` | engine 標準 |
| ファイル変更検知 | `Fs.ModificationTime` | engine 標準 |
| プロパティパス操作 | `JsonOps.{getAtNodePath, setAtNodePath}` | `ide/src/JsonOps.flix` |
| スプライト描画 | `Sprite2D.make / setHframes / setVframes / setFrame` | engine 既存 |

JSON I/O・schema 規格・整合検査は engine 側で完結している。IDE はこの上に
**UI（フォーム + プレビュー）と配線** を載せるだけでよい。

## なぜ engine に Resource 概念を置いたか

IDE は **ゲームプロジェクトの Flix モジュールを直接呼び出せない**。理由:

1. Flix にリフレクションがない（型から自動 UI 生成が不可）
2. IDE は独立バイナリで `ide/flix.toml` は engine と editor のみに依存し、
   各 game project（fe_rogue 等）には依存しない
3. IDE は `SceneLoader.constTagParser(())` でゲーム固有 enum を意図的に捨てる設計

→ 「IDE 側からゲームの schema 関数を呼ぶ」案は不可能。
schema を **JSON サイドカー** として engine 規格でファイル化することで、IDE は
JSON だけ読めば任意のゲームの Resource を編集できるようになる。

## IDE 側で実装が必要なもの（将来 PR）

1. **アセットブラウザ** — `assets/` 配下を `Fs.Glob` で列挙し、サイドカー schema が
   ある JSON ファイルを Resource として表示。

2. **汎用プロパティパネル** — `ResourceSchema` を walk して各 `FieldEntry` に
   widget を割り当てる:
   - `Field(FieldSchema{ftype=IntT, hint=Slider(...)})`  → `JSlider`
   - `Field(FieldSchema{ftype=IntT, hint=Spinner(...)})` → `JSpinner`
   - `Field(FieldSchema{ftype=IntT, hint=FrameGrid(...)})` → カスタムグリッド
   - `Field(FieldSchema{ftype=TextT, hint=Plain})`       → `JTextField`
   - `Field(FieldSchema{ftype=TexturePathT})`            → テクスチャ選択ドロップダウン
   - `Nested(...)` → サブフォーム / 折りたたみグループ

3. **catalog 形式判別** — データ JSON のトップに `units` / `pools` のような構造があれば
   テーブル UI でユニット並列編集、無ければ単一レコードフォーム。**schema は中身のフィールド構造を
   記述するだけで、ファイル全体が catalog か single かは data 構造から判断する**。

4. **ライブプレビュー** — `sprite.texture + sprite.frame` の値を `Sprite2D` で描画。
   本番ゲームと同じ描画パスを使うことで「IDE では見えるが実機で違う」問題を回避。

5. **保存** — 編集中バッファ → `Persistence.save("assets/units/units.json", value)`。
   保存前に `Saveable.toJson ∘ fromJson` を通してラウンドトリップ検証してから書き出す。

6. **ホットリロード連携** — ゲーム実行中なら `Fs.ModificationTime` を見ている `Game.start`
   側が変更を検知して `UnitCatalog.load` をやり直し、既存ユニットの `Data` を更新可能に
   （現状は再起動推奨。ホットリロード対応は別タスク）。

## 同期戦略（v1: Z 案、将来: X 案）

`UnitResource` のフィールド構造（"hp" / "moveTiles" / "sprite"）は **3 箇所** で
同期されている必要がある:

1. `UnitCatalog.flix` の `UnitResource` 型定義
2. `_schema.json` のフィールド集合
3. 各 data JSON の実値

### v1: Z 案 — 手書き同期 + 起動時検査

3 箇所を **手で同期** し、ズレは `Resource.checkConsistency` が起動時に検出する:

```flix
// UnitCatalog.flix
pub def expectedUnitFields(): Set[String] =
    Set#{"moveTiles", "hp", "sprite"}

// Game.flix の start 内
match Resource.checkConsistency(UnitCatalog.expectedUnitFields(), schema) {
    case Ok(_)    => ()
    case Err(msg) => bug!("UnitResource schema/type mismatch: ${msg}")
}
```

ズレたら起動瞬間に panic する。CI がゲーム起動を含めば自動で防波堤になる。

### v2 (将来昇格パス): X 案 — Flix codegen で SSOT 統一

痛みが出てきたら以下に昇格する:

- engine に schema 構築 helpers を追加（`Resource.intSlider("HP", 1, 100, 5)` など）
- 各 game project に `tools/GenerateSchemas.flix` を配置し、Flix で書いた `schema()`
  関数の戻り値を `Persistence.save` で `_schema.json` に書き出す
- ビルド前に `flix run --main Tools.GenerateSchemas` を走らせる
- `_schema.json` は生成物として扱う（git にコミットはする、CI で生成差分を検査）

これで SSOT が Flix 側に統一され、`expectedUnitFields()` も自動同期できる。

## IDE の責任境界（運用ルール）

| 操作 | IDE 単独で可 | コーダー必須 |
|---|:---:|:---:|
| ユニット値の編集（hp = 14 → 16 等） | ✅ | |
| ユニット追加（カタログにエントリ追加） | ✅ | |
| プール構成変更（pools.party の中身変更） | ✅ | |
| UI ヒント変更（slider 範囲 100 → 200 等） | ✅ | |
| **新フィールド追加**（`def: Int32` 追加） | | ✅ |
| **フィールド削除** | | ✅ |
| **フィールド rename** | | ✅ |

理由: フィールド追加/削除/rename は Flix 型変更を伴うため、コード再ビルドが必要。
IDE 上では「+ フィールド追加」ボタンを **意図的に出さない**。デザイナが「IDE で field
増やしたい」と言ってきた場合、それは「コーダーに依頼」の合図と認識する運用にする。

## 設計上の留意点

- **Resource は値型**: IDE で編集 → ファイルに書き戻し → ゲームが再ロード、という流れ。
  Godot のように in-memory で参照を共有するのではなく、毎回ファイル経由で同期する。
  これにより undo/redo・diff・git コミットがすべてファイルベースで成立する。

- **schema 編集の境界**: schema JSON は IDE で編集可能だが、**フィールド集合を変えると
  Flix 側との整合検査で起動が止まる**。UI ヒント（slider 範囲やラベル）だけ変えるのは
  安全に IDE で完結する。

- **エラーは握り潰さない**: パース失敗・schema 不整合は engine 側で `Option None` /
  `Result Err` として表面化させ、ゲーム側は panic で即可視化。IDE 側でも同じ
  ポリシーを採用し、「ファイル X はスキーマ違反」と明示する。

- **将来テクスチャ単独 Resource に切り出す余地**: `SpriteResource` を nested に
  してあるので、「テクスチャだけ別ファイル化して複数ユニットで共有」が必要になったら
  `sprite: TexturePath` のような参照型に置換できる（Godot の `ExtResource` 相当）。

## 参考: 既存実装

- `engine/src/Resource.flix` — 規格本体
- `engine/test/TestResource.flix` — round-trip + 整合検査のユニットテスト
- `examples/fe_rogue/src/game/UnitCatalog.flix` — game 側の `Saveable[UnitCatalog]` 実装例
- `examples/fe_rogue/assets/units/{units,_schema}.json` — 規格に沿ったデータ + schema 一例
- `engine/src/Persistence.flix:33,46` — save / load の I/O 本体
- `examples/escape_game/src/game/SaveData.flix:49-55` — 別ジャンルでの `Saveable` 実装例
- `ide/src/JsonOps.flix` — JSON ノードのパス指定での参照・書き換えユーティリティ
