---
name: engine-guide
description: "Main.flix と Game.flix の書き方、XxxScene との連携方法のガイド。NodeTag 設計、trait instance のディスパッチ、カスタム effect（GamePhaseState・ライフサイクル副作用要求）、フェーズ遷移を含む（start / gameLoop の詳細は game-loop、個別の XxxScene 設計パターンは scene-editor を参照）"
user-invocable: false
---

# ゲームエンジン お作法ガイド

`src/engine/**` の上に `Scene[NodeTag]` を扱うゲーム層を載せる構成。
本ガイドは **Main.flix と Game.flix の書き方、XxxScene との連携** に絞る。
個別の Scene 設計は `scene-editor` skill を参照。

## ファイル責務

| ファイル | 責務 |
|---|---|
| `src/Main.flix` | EngineConfig 組み立てと `Game.start` 起動。**ゲームロジックは書かない** |
| `src/scenes/Game.flix` | GamePhase enum / カスタム effect / NodeTag enum / trait instance（dispatch のみ）/ mod Game |
| `src/scenes/XxxScene.flix` | 個別シーン（構築・ライフサイクル・状態遷移・応答） |
| `src/engine/**` | エンジン層。通常変更しないが、組もうとしているゲームロジックが、エンジン拡張により影響を受ける場合は、開発者に選択肢を挙げ相談する |

## Main.flix

EngineConfig と起動のみ。**IO 系ハンドラ（`Math.Random`, `Fs.*`）はここで剥がす**。

```flix
def main(): Unit \ {IO, Chan, NonDet} =
    if (GameEngine.ensureMainThread()) ()
    else {
        let config: GameEngine.EngineConfig = { screenWidth = ..., ... };
        run { Game.start(GameEngine.Game.getFontAtlas("default")) }
        with LwjglLayer.withLwjgl(config)
        with Math.Random.runWithIO
        with Fs.FileRead.runWithIO
        ...
    }
```

## Game.flix の並び順

`GamePhase enum` → カスタム effect 群 → type alias → `NodeTag enum` → trait instance 群（Node / Input / Button / Area / NodeRemoved を必要なものだけ）→ `mod Game { 構築関数 / start / gameLoop / applyPhaseChange }`

## カスタム effect — 横断的な間接化

「複数シーンに跨る副作用」「ライフサイクル外から発火する処理」はカスタム effect で宣言する。
**handler の Aef を増やさず、副作用の実体は `Game.start` 内で `with handler` 注入**する。

代表的な使い分け（次の 2 節で詳しく扱う）:
- `GamePhaseState` — フェーズの読み書き
- `XxxRequest` 系 — ライフサイクル関数からの副作用要求（乱数・スポーン等）
- `XxxStateChanged` — あるシーンの状態遷移を別シーンに通知

判断基準: **handler の Aef に直接副作用を足したくないが、副作用は必要** なときだけ使う。乱用しない。

## GamePhase / GamePhaseState — フェーズ遷移の流れ

`GamePhase` はゲーム全体の進行状態（Menu / Playing / GameOver 等）。
**ノード単位の状態（NodeTag に持たせる XxxData）とは別レイヤー** で扱う。

`GamePhaseState` は「フェーズの読み書き」を表すカスタム effect。
**遷移はどの handler から発火してもよい**（Input / Area / NodeRemoved 等どこでも）。
handler 側は条件を判定して `put` するだけ。実体の切り替えは gameLoop が担う。

```flix
pub eff GamePhaseState {
    def get(): GamePhase
    def put(target: GamePhase): Unit
}
```

3 段の流れ:

1. 任意の handler が `GamePhaseState.put(target)` で遷移要求
2. gameLoop が前フレームの phase と現在の phase を比較し、変化があれば `applyPhaseChange` を呼ぶ
3. `applyPhaseChange` が新しい phase に対応したシーンを構築（フルリビルド or オーバーレイ）

実体（region の `Ref` を読み書きする handler）は `start` で注入する → **`game-loop` skill 参照**。

メリット: handler は遷移条件だけに集中でき、シーン再構築は 1 か所に集約される。

## ライフサイクルでのカスタム effect 利用 — 副作用を Aef から切り離す

`process` / `ready` 等のライフサイクル関数で副作用（乱数、音、ファイル等）が必要なとき、
**それを直接呼ばず、カスタム effect を emit するだけにする**。
副作用の実体は `start` の handler で注入する。

例: process 中に「ランダム位置でスポーンしたい」場合、`Math.Random` を Aef に持たせず `SpawnRequest` を介す。

```flix
/// process から「個体のスポーン」を要求する。実体は handler 側
pub eff SpawnRequest {
    def request(scene: Scene[NodeTag]): Scene[NodeTag]
}

// XxxScene.process: SpawnRequest を emit するだけ。Math.Random は知らない
pub def process(node, path, scene): (..., ...) \ SpawnRequest =
    if (offscreen) (node, SpawnRequest.request(Scene.removeAt(path, scene)))
    else (node, scene)
```

実体（乱数 + ビルダーで実スポーンする handler）は `start` で注入する → **`game-loop` skill 参照**。

メリット:
- ライフサイクル関数の Aef は `{ SpawnRequest }` のまま小さく保てる
- `Math.Random` などの IO 系は **start から外側へ伝播せず**、`Main.flix` で剥がせる
- handler を差し替えればテスト時に決定的なスポーンに切り替えられる

## NodeTag enum

`Scene[NodeTag]` の型パラメータ。**ノード単位の状態（XxxData）もここに含める**。

```flix
pub enum NodeTag {
    case Xxx(XxxScene.XxxData)   // 主要ノード + 状態
    case XxxArea                 // 衝突検知用 Area2D（識別だけ）
    case ScoreLabel(HUDScene.Score)       // ラベル + 値
    case NoTag                   // タグ不要なノード
}
```

設計指針:
- バリアント名は **役割接頭辞**（`xxArea`, `xxLabel`, `xxPart`）で揃える
- エンジン型（Sprite2D, Area2D 等）は **NodeTag に入れない**（EngineNode 側に持つ）
- `XxxData` の中身は **そのシーンの mod 内で `pub type alias` 定義** する

## trait instance はディスパッチだけ

各 instance は二重 match で **XxxScene の関数に委譲するだけ**。Game.flix にロジックを書かない。

```flix
// Node: EngineNode + NodeTag の組で各 Scene のライフサイクルへ
instance Node[NodeTag] {
    type Aef = { SpawnRequest }
    redef ready(node, path, scene) = match node {
        case EngineNode.RigidBody2DWithState(_, NodeTag.Xxx(_)) =>
            checked_ecast(XxxScene.ready(node, path, scene))
        case _ => (node, scene)
    }
    redef process(...) = ...
    redef physicsProcess(...) = ...
}

// Area: NodeTag ペアで分岐。衝突は対称なので左右両方向書く
match (selfState, otherState) {
    case (NodeTag.XxxArea, NodeTag.Yyy) => XxxScene.onXxxHitYyy(scene)
    case (NodeTag.Yyy, NodeTag.XxxArea) => XxxScene.onXxxHitYyy(scene)
    case _ => checked_ecast(scene)
}

// Button: NodeTag ではなく buttonPath で識別（NodeTag は NoTag のまま）
redef onButtonPressed(buttonPath, _, scene) =
    if (buttonPath == XxxScene.playButtonPath()) ... else scene

// NodeRemoved: removeAtAndNotify されたノードに対しカスタム effect で要求を出す
redef onNodeRemoved(_path, state, scene) = match state {
    case NodeTag.Yyy => SpawnRequest.request(scene)
    case _ => scene
}
```

## mod Game

### シーン構築 — フェーズ別に別関数

`Scene.empty()` に各 `XxxScene.addXxx` をパイプで繋ぐ。

```flix
pub def buildPlayingScene(fontAtlas, ...): Scene[NodeTag] \ {Math.Random, Fs.FileRead} =
    Scene.empty()
        |> addBackground
        |> XxxScene.addXxx
        |> CameraScene.addCamera(XxxScene.name())
        |> ScoreScene.addHud(fontAtlas, ...)

pub def buildMenuScene(...): Scene[NodeTag] \ Fs.FileRead = ...
```

### start / gameLoop / applyPhaseChange

ゲーム全体の制御の中心で、責務分担とエディタ・ホットリロード統合の話があるため
**専用の `game-loop` skill に切り出し**ている。これらを編集するときは `game-loop` を参照すること。

要点だけ:
- `start` — 起動時 1 回。region + Ref / エディタ常駐 / 横断 effect の handler 注入
- `gameLoop` — 毎フレームの固定パイプライン（終了判定 → エディタ入力 → エンジンパイプライン → フェーズ差分 → 描画）
- `applyPhaseChange` — フェーズに応じてシーンを組み立てる（フルリビルド or オーバーレイ）
- いずれも **配線役**。Scene 固有のロジックを書かず、Scene の関数を呼ぶだけ

## SceneLoader と tagParser

`SceneLoader.loadScene` / `loadSceneWithFont` は `NodeTag` を知らない。
呼び出し側が `tagParser: Option[String] -> Result[Json.JsonError, t]` を渡してタグ変換を担う。

```flix
// XxxScene.flix 内に定義する
def tagParser(opt: Option[String]): Result[Json.JsonError, NodeTag] =
    use Json.JsonError.JsonError;
    use Json.Path.Path.Root;
    match opt {
        case None | Some("NoTag") => Ok(NodeTag.NoTag)
        case Some("MyTag")        => Ok(NodeTag.MyTag)
        case Some(unknown)        => Err(JsonError(Root, Set#{"known tag (got: ${unknown})"}))
    }

pub def addXxx(scene: Scene[NodeTag]): Scene[NodeTag] \ Fs.FileRead =
    SceneLoader.loadScene("src/scenes/Xxx.scene.json", tagParser, scene)

// Label2D を含む場合は loadSceneWithFont
pub def addXxxWithFont(fontAtlas: FontAtlas, scene: Scene[NodeTag]): Scene[NodeTag] \ Fs.FileRead =
    SceneLoader.loadSceneWithFont("src/scenes/Xxx.scene.json", fontAtlas, tagParser, scene)
```

ルール:
- `tagParser` は **そのシーンが使うタグのみ** を列挙する。他シーンのタグは知らなくてよい
- JSON の `"tag"` キーなし / `"NoTag"` はどちらも `None` / `Some("NoTag")` で来るので両方 `NoTag` に対応する
- 未知タグは `Err` にしてクラッシュさせる（サイレント無視しない）

## XxxScene との連携契約

Game.flix が各 XxxScene に期待する公開 API:

| 用途 | 期待される関数 |
|---|---|
| シーン構築 | `addXxx(scene): Scene \ Fs.FileRead`、必要なら `addXxxForMenu` 等のフェーズ別バリアント |
| ライフサイクル | `ready` / `process` / `physicsProcess`（必要なものだけ） |
| 入力ディスパッチ | `input(event, scene): Scene \ {...}` |
| 衝突応答 | `onXxxHitYyy(scene): Scene \ {...}` |
| ボタン識別 | `xxButtonPath(): NodePath` |
| 動的スポーン | `spawnRecycledXxx(scene): Scene` |
| ノード名 | `name(): String`（カメラ追従先など他シーンから参照される場合） |

## 注意事項

- NodeTag にエンジン型を入れない（EngineNode 側に持つ）
- Main.flix / trait instance にロジックを書かない（配線だけ）
- 動的スポーンの名前はカウンタや座標から導出してユニーク化
- 同一フレームで追加したノードの process は次フレームから実行される
- カスタム effect は handler の Aef を増やしたくない場面限定で使う（乱用しない）
