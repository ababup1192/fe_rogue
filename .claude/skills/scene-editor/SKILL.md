---
name: scene-editor
description: xxScene.flixを新規で作るとき・編集するとき、新しいゲームロジックを組む時に考えるべき設計パターン
user-invocable: false
---

# XxxScene 設計パターン

シーンの構築と更新に関する共通パターン。

## モジュール構造

```
mod XxxScene {
    // (A) 型定義   — SpriteData, AreaData
    // (B) 定数     — name / path / texture, speed, position
    // (C) 構築     — add: Scene → Scene
    // (D) ロジック — ready / process / start / input / move
    // (E) ボイラプレート mapXxxSprite / mapXxxArea / mapXxx（合成）
}
```

## (A) 型定義

### NodeTagのデータ設計

NodeTagで使うデータは、Sceneごとに使用されるデータ型を定義する。

```Game.flix
enum NodeTag {
    case Player(PlayerScene.Data)
    case PlayerArea(PlayerScene.AreaData)
    case CoinLabel(HUDScene.Coin)
}
```

プリミティブラッパーパターンは、データの意味を明確にし、可読性を高めるために有効:

```HUDScene.flix
pub type alias Coin = Int32
```

ノードツリー構造に合わせて、親ノードと子ノードのデータを分ける:
ルートノードのデータ型の場合は、`Data`として、プレフィックスを省略する

```PlayerScene.flix
// CharacterBody2D(Player)
//  └── Area2D (PlayerArea)

pub type alias Data = { velocity = Vec2.Vec2, hp = Int32 }
pub type alias AreaData = { hit = Bool }
```
## (B) 定数

Nodeの名前やパス, テクスチャ名は、定数で一元管理する。ハードコードは禁止。

```PlayerScene.flix
def name(): String = "xxx"
def xxxPath(): NodePath = name() :: Nil
def areaName(): String = "area"
def areaPath(): NodePath = name() :: areaName() :: Nil   // 非公開
def xxxTexture = "xxx.png"
def xxxBgm = "xxx_bgm.ogg"
```

パラメータ、物理パラメータなども定数で管理する:

```PlayerScene.flix
def speed(): Float64 = 100.0
def velocityY(): Float64 = -300.0
```

## (C) 構築 — add

`add`関数は、ノードツリーを構築して、Sceneに追加する。
このときに、NodeTagと(A)で定義したデータ型(初期値)を紐づける。
さらに細かい単位で、Sceneに追加したい場合は、`addXxx` のような関数を追加する。
Scene情報は、JSONファイルで管理し、`add`関数では、JSONをロードして、ノードツリーを構築する。Nodeに付与するメタデータは、NodeTagを使って付与する。

```flix
def sceneJsonPath(): String = "src/scenes/XxxScene.scene.json"

pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ Fs.FileRead =
    let data: data = {speed = speed(), state = Walking};
    SceneLoader.loadScene(sceneJsonPath(), scene)
        |> Scene.setState(playerPath(), NodeTag.Player(data))
```

```
{
  "type": "RigidBody2D",
  "name": "player",
  "pos": [144, 256],
  "shape": {"kind": "CircleShape2D", "radius": 13},
  "gravityScale": 1.0,
  "linearVelocity": [100, 0],
  "children": [
    {
      "type": "AnimatedSprite2D",
      "name": "sprite",
      "pos": [0, 0],
      "scale": [2, 2],
      "animations": {
        "walk": [],
        "run": []
      },
      "initialAnimation": "walk",
      "fps": 10
    },
    {
      "type": "Area2D",
      "name": "area",
      "pos": [0, 0],
      "shape": {"kind": "CircleShape2D", "radius": 13}
    }
  ]
}

```

動的スポーン（名前やパラメータが実行時に決まる）の場合は、JSONを使わず、構築関数内でノードツリーを構築する。

```flix
pub def spawnXxx(name: String, position: Vec2.Vec2,
                 scene: Scene[NodeTag]): Scene[NodeTag] =
    scene
        |> Scene.addNode(name,
            EngineNode.RigidBody2DWithState(body, NodeTag.XxxData(id)))
        |> Scene.addToGroup(name :: Nil, xxxGroup())    // グループで一括削除用
        |> Scene.addChild(name, childName(),
            EngineNode.AnimSprite2DWithState(sprite, NodeTag.NoTag))
```

構築 API:
- `Scene.addNode(name, engineNode)` — ルートに追加
- `Scene.addChild(parent, child, engineNode)` — 子を追加
- `Scene.addToGroup(path, group)` — グループに登録

## (D) ロジック

### ready / process / physicsProcess

ゲームエンジンでは、以下のライフサイクルが存在する。
各Sceneでは、ライフサイクルに応じたロジックを定義し、Game.flixは、各Sceneのライフサイクルロジックを呼び出し、委譲する。

- ready: シーン（ノード）がシーンツリーに追加され、準備が整った直後に1回だけ呼び出される。子ノードの読み込みも完了した状態なので、変数の初期化やノード間の紐付けロジックをここに書く。
- input: キーの押下やマウス移動など、入力イベントを検知した瞬間に呼び出される。ジャンプボタンの判定やメニューの開閉など、特定の「イベント」をトリガーにする処理をここに書く。
- process: 画面の描画（フレーム）ごとに呼び出される。実行間隔はPCの性能や負荷によって変動するため、見た目のアニメーション更新や、物理演算に関わらない毎フレームの監視ロジックをここに書く。
- physicsProcess: 一定の時間間隔（固定フレーム）で呼び出される。描画の負荷に左右されず常に一定の周期で動くため、キャラクターの移動計算や物理的な衝突判定などのロジックをここに書く。


```PlayerScene.flix
// XxxScene 側
pub def ready(node: EngineNode[NodeTag], _path: NodePath,
                scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) =
    match node {
        case EngineNode.RigidBody2DWithState(body, NodeTag.Player(data)) =>
            if (playerData#state == PlayerState.Walking) {
                (EngineNode.RigidBody2DWithState(run(body), NodeTag.Player(data)), scene)
            } else {
                (node, scene)
            }
        case _ => (node, scene)
}

 pub def input(event: GameEngine.Key, scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Audio =
        match getPlayerData(scene)#state {
            case PlayerState.Walking =>
                if (key == GameEngine.Key.Space) {
                    GameEngine.Audio.playAudio("sfx_wing");
                    scene |> mapPlayerBody((body, birdData) -> (jump(body), birdData))
                } else scene
            case _ => scene
        }

 pub def physicsProcess(_delta: Float64, node: EngineNode[NodeTag],
                           _path: NodePath, scene: Scene[NodeTag]
                          ): (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.RigidBody2DWithState(body, NodeTag.Player(data)) =>
                let newBody = match playerData#state {
                    case PlayerState.Walking => walkingUpdate(body)
                    case _ => body
                };
                (EngineNode.RigidBody2DWithState(newBody, NodeTag.Player(data)), scene)
            case _ => (node, scene)
        }
```

### イベント処理

入力や衝突の判定などの処理は、Game.flixで、イベントのハンドラーのインスタンスを定義する。そこでは、イベント対象のパターンマッチを行い、該当するSceneのロジックを呼び出し、処理を委譲する。

```Game.flix
instance AreaEvent.AreaHandler[NodeTag] {
    type Aef = { GameEngine.Audio }
    pub def onAreaEntered(selfPath: NodePath, selfState: NodeTag,
                          otherPath: NodePath, otherState: NodeTag,
                          scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio} =
        match (selfState, otherState) {
            case (NodeTag.PlayerArea, NodeTag.EnemyArea) =>
                PlayerScene.onPlayerHitEnemy(scene)
            case (NodeTag.EnemyArea, NodeTag.PlayerArea) =>
                PlayerScene.onPlayerHitEnemy(scene)
            case _ => checked_ecast(scene)
        }
}
```

### Scene変換関数

各Sceneが、ゲームに影響を与えるには、Scene[NodeTag]を受け取って、中のノードの内容を変換したScene[NodeTag]を返すことで実現する。しかし、Scene[NodeTag]は、ツリー構造のため、特定のノードをパターンマッチして変換するのは、冗長である。そこで、Scene[NodeTag]の特定のノードをパターンマッチして変換するための、ボイラプレート関数を用意する。

```
pub def mapPlayerBody(f: (RigidBody2D, PlayerData) -> (RigidBody2D, PlayerData), scene: Scene[NodeTag]): Scene[NodeTag] =
    Scene.mapEngineNode(playerPath(), engineNode -> match engineNode {
        case EngineNode.RigidBody2DWithState(body, NodeTag.Player(data)) =>
            let (newBody, newData) = f(body, data);
            EngineNode.RigidBody2DWithState(newBody, NodeTag.Player(newData))
        case other => other
    }, scene)
```

同様に、NodeTagに紐づけられた、データも取り出すための関数も用意すると、便利だ。

```
 pub def getPlayerData(scene: Scene[NodeTag]): PlayerData =
        match Scene.getState(playerPath(), scene) {
            case Some(NodeTag.Player(playerData)) => playerData
            case _ => bug!("player not found")
        }
```

## よく使う関数一覧

| やりたいこと | 手段 |
|---|---|
| sprite + data を変換 | `mapXxxSprite` |
| 子ノード（Area2D 等）を変換 | `mapXxxArea` |
| sprite + data + 子ノードを一括変換 | `mapXxx`（合成） |
| 単一ノードの見た目変更 | `Scene.mapEngineNode(path, f)` |
| 状態のみ変更 | `Scene.setState(path, newState)` / `Scene.mapState(path, f)` |
| ノード追加 | `Scene.addNode` / `Scene.addChild` |
| ノード削除 | `Scene.removeAt(path)` / `Scene.removeGroup(group)` |
| グループ一括削除 | `Scene.addToGroup` → `Scene.removeGroup` |
