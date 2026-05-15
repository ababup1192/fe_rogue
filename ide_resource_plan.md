# IDE で UnitResource を編集する設計メモ

`assets/units/*.json`（味方・敵のステータス + テクスチャを定義する Godot Resource 風 JSON）を
IDE 上で Inspector ライクに編集できるようにするための、将来作業のためのチェックリスト。
今回の Resource 化（`UnitResource` 導入）とは別フェーズで実装する。

## 既に揃っている基盤（追加実装不要）

| 必要なもの | 利用する既存 API | 場所 |
|---|---|---|
| JSON ロード | `Persistence.load(path)` | `engine/src/Persistence.flix:46` |
| **JSON 書き戻し**（保存ボタン） | `Persistence.save(path, value)` | `engine/src/Persistence.flix:33` |
| ラウンドトリップ保証 | `Saveable.toJson ∘ fromJson = id` | `Game.UnitResource` の instance |
| ファイル一覧取得 | `Fs.Glob` | `Game.start` 既使用 effect |
| ファイル変更検知（ホットリロード） | `Fs.ModificationTime` | 同上 |
| プロパティパス操作 | `JsonOps.{getAtNodePath, setAtNodePath}` | `ide/src/JsonOps.flix` |
| スプライト描画 | `Sprite2D.make / setHframes / setVframes / setFrame` | engine 既存 |

→ 「JSON を読む / 書く / 監視する / 描画する」までは engine 側に揃っている。
IDE 側はその上に **UI（フォーム + プレビュー）と配線** を載せるだけでよい。

## IDE 側で実装が必要なもの

1. **アセットブラウザ** — `assets/units/` を `Fs.Glob` で列挙してリスト表示。
   ファイル名 or `name` フィールドで一覧。

2. **プロパティパネル** — `UnitResource` の各フィールドにフォーム要素を割り当てる:
   - `moveTiles`, `hp`: 数値スピナ（範囲は妥当な上下限を IDE 側で設定）
   - `name`: テキスト入力（IDE のヘッダ表示にも使う）
   - `sprite.texture`: 既存テクスチャアセットから選択するドロップダウン
   - `sprite.hframes` / `sprite.vframes`: 数値スピナ
   - `sprite.frame`: グリッド選択（`hframes × vframes` の格子を可視化、クリックで選択）

3. **ライブプレビュー** — 選択中の frame を `Sprite2D` に流して 64×64 程度で描画。
   本番ゲームと完全に同じ描画パスを使うことで「IDE では正しく見えるが実機で違う」問題を回避。

4. **保存** — 編集中バッファ → `Persistence.save("assets/units/<name>.json", value)`。
   保存前に `Saveable.toJson` でシリアライズし、その JSON をパース戻して原本と一致するか
   ラウンドトリップ検証してから書き出すと安全。

5. **ホットリロード連携** — ゲーム実行中なら `Fs.ModificationTime` を見ている `Game.start`
   側が変更を検知して `UnitResource.load` をやり直し、既存 `Data` を新しい値で上書きする。
   IDE 側は保存するだけで、再起動なしに反映が見える状態が理想。

## ゲーム側で IDE 連携のためにやっておくべきこと（Resource 化と同時にやる）

これらは IDE 実装フェーズに入ってから足すと型変更が広範囲に波及するので、
今回の `UnitResource` 導入と同じ PR でやっておきたい。

- **`name: String` フィールドを `UnitResource` に追加** — IDE のリスト表示・タブ名に必要。
  ファイル名で代用も可能だが、表示名と識別子は分けたほうが将来のリネーム耐性が高い。
- **`Saveable[UnitResource]` の `fromJson` で未知フィールドを無視する寛容さ** —
  IDE 側が将来フィールドを追加した古いゲームバイナリでも JSON が壊れないように、
  `match JsonObject(m)` で必要なキーだけ取り、それ以外は単に読み捨てる実装にする。
- **ファイル配置を `assets/units/` に固定** — ディレクトリ glob のため。
  サブカテゴリが欲しくなったら `assets/units/players/`・`assets/units/enemies/` のような
  サブディレクトリ運用に切り替える（後付けでも壊れない）。

## 設計上の留意点

- **Resource は値型**: IDE で編集 → ファイルに書き戻し → ゲームが再ロード、という流れ。
  Godot のように in-memory で参照を共有するのではなく、毎回ファイル経由で同期する。
  これにより undo/redo・diff・git コミットがすべてファイルベースで成立する。

- **スキーマは `Saveable` 実装が真実の所在**: IDE の form は `UnitResource` の型定義を
  見て手書きする。Flix にはリフレクションがないので自動生成は不可。
  フィールド追加時は **型定義 / `Saveable` 実装 / IDE form の 3 箇所を手で同期** する。
  この 3 つがズレたら fromJson が `None` を返してロード失敗するので、ズレは即検知できる。

- **エラーは握り潰さない**: パース失敗時は IDE 側で「ファイル X はスキーマ違反」と
  明示する。`fromJson` が `None` を返す = そのケース。
  ゲーム側のロード（`?bug` で panic）と同じ「失敗を即可視化」の方針を踏襲する。

- **将来テクスチャ単独 Resource に切り出す余地**: `SpriteResource` を nested にしてあるので、
  「テクスチャだけ別ファイル化して複数ユニットで共有」が必要になったら
  `sprite: TexturePath` のような参照型に置換できる。Godot の `ExtResource` 相当。

## 参考: 既存類似実装

- `examples/escape_game/src/game/SaveData.flix:49-55` — `Saveable` instance の書き方の手本
- `engine/src/SceneLoader.flix:119-122` — `.scene.json` ロードと変換のパターン
- `ide/src/JsonOps.flix` — JSON ノードのパス指定での参照・書き換えユーティリティ
