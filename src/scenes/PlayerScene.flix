/// PlayerScene — プレイヤーキャラクター（Marker2D）と子 Sprite / 子 Camera
///
/// ノード構造（Godot 準拠）:
///   Player (Marker2D, NodeTag.Player(Data))
///     ├─ Sprite (Sprite2D, 描画専用)
///     └─ Camera (Camera2D, 親追従でビューが Player を中心に表示)
///
/// 親が Marker2D なのは、移動が完全にグリッド + Tween 駆動で物理応答を持たないため。
/// 壁判定は BoardLogic がグリッド上で済ませ、見た目の補間は Tween に委ねるので、
/// CharacterBody2D の velocity / move_and_slide / CollisionShape は不要。
/// 将来エネミーとの押し合いなど物理連動が必要になったら CharacterBody2D に格上げする。
///
/// シーン構造とプロパティは PlayerScene.scene.json で管理し、`add` 時に
/// SceneLoader でロードする。NodeTag の Data はロード後に `Scene.setState` で書き込む。
///
/// 移動は moveTo(target) で論理位置（gridPos）を即更新し、
/// 見た目は engine 層の `Tween` モジュール（`Tween.Scheduler.tweenPosition`）に委ね、
/// 毎フレーム gameLoop が `Tween.tickAll` で進める。**壁判定は BoardLogic が
/// moveTo を呼ぶ前に済ませている前提**で、PlayerScene 自身は衝突応答も補間も持たない。
/// Camera は Player の子なので親子変換で自動追従する。
mod PlayerScene {

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// プレイヤー固有の状態。
    /// gridPos: 盤面上の駒の論理位置。moveTo で即座に更新される。BoardLogic が読む値。
    /// moveTiles: 1 ターンに移動できるマス数（FE の「移動力」相当）。MoveRangeScene が
    ///   この値を BFS の深さに使う。キャラクターごとに変えられるよう `Data` に持たせる。
    pub type alias Data = {
        gridPos   = Vec2.Vec2i,
        moveTiles = Int32
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def name(): String = "Player"
    pub def playerPath(): NodePath = name() :: Nil

    def sceneJsonPath(): String = "src/scenes/PlayerScene.scene.json"

    /// プレイヤーの「ローカル」初期グリッド座標（13×13 部屋の中心付近）。
    /// 本番（add）では MapScene.getSpawnGrid を使うので未参照だが、
    /// 単体テストで「想定通りのスポーン位置」を再現するために残してある。
    pub def initialGrid(): Vec2.Vec2i = {x = 5, y = 5}

    /// LDTK のタイルサイズ（ピクセル）。Marker2D の position 計算に使う。
    def tileSize(): Float64 = 16.0

    /// 1 マス分の slide にかかる時間（秒）。Godot の tween_property の duration 相当
    def slideDuration(): Float64 = 16.0 / 120.0   // ≈ 0.133 秒

    /// プレイヤー初期の移動力（マス）。`Data#moveTiles` の初期値として使う。
    /// 装備や状態異常で書き換えたい場合は `mapPlayer` で moveTiles を更新する。
    pub def defaultMoveTiles(): Int32 = 5

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// PlayerScene.scene.json から Player / Sprite / Camera を読み込んで Scene に追加する。
    /// MapScene が記録した spawnGrid（anchor 内で壁でないと保証されたセル）を読み、
    /// プレイヤーの Marker2D position と NodeTag.Player(Data).gridPos を揃える。
    /// MapScene.add 済み（NodeTag.Map が登録済み）であることが前提。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead} =
        let spawnGrid = MapScene.getSpawnGrid(scene);
        SceneLoader.loadScene(sceneJsonPath(),
                              SceneLoader.constTagParser(NodeTag.NoTag),
                              scene)
            |> setSpawn(spawnGrid)

    /// 読み込んだ Player の Marker2D position と NodeTag を spawnGrid に同期させる。
    /// セル中心座標 = spawnGrid * tileSize + tileSize/2 の慣習に合わせる。
    def setSpawn(spawnGrid: Vec2.Vec2i, scene: Scene[NodeTag]): Scene[NodeTag] =
        let s = tileSize();
        let spawnPx: Vec2.Vec2 = {
            x = Int32.toFloat64(spawnGrid#x) * s + s / 2.0,
            y = Int32.toFloat64(spawnGrid#y) * s + s / 2.0
        };
        Scene.mapEngineNode(playerPath(), node -> match node {
            case EngineNode.Marker2DWithState(marker, _) =>
                EngineNode.Marker2DWithState(Node2D.setPosition(spawnPx, marker),
                                              NodeTag.Player({
                                                  gridPos   = spawnGrid,
                                                  moveTiles = defaultMoveTiles()
                                              }))
            case other => other
        }, scene)

    // ────────────────────────────────────────────────────────
    // (D) ロジック
    // ────────────────────────────────────────────────────────

    /// 目標グリッドへの移動を開始する。**壁判定は呼び出し側（BoardLogic）が済ませている前提**で、
    /// PlayerScene 自身は衝突判定を考えない。
    ///
    /// gridPos を target に更新した Data と、 そのままの marker を返す。
    /// 同時に `Tween.Scheduler.tweenPosition` で見た目の補間を engine に委ねる
    /// （Godot の `tween.tween_property(self, "position", ...)` 同等）。
    /// scene は `startWorld` を読むだけで変換しない。 戻り値の (marker, data) を
    /// 呼び出し側が `EngineNode.Marker2DWithState(marker, NodeTag.Player(data))` に
    /// 組み立てて scene に書き戻す責務を持つ。
    pub def moveTo(map: MapSnapshot, target: Vec2.Vec2i,
                    marker: Marker2D, data: Data,
                    scene: Scene[NodeTag]): (Marker2D, Data)
                    \ Tween.Scheduler =
        let targetWorld = map#gridToWorld(target);
        let startWorld = Scene.globalPositionAt(playerPath(), scene);
        Tween.tweenPosition(playerPath(), startWorld, targetWorld, slideDuration());
        (marker, {gridPos = target | data})

    /// プレイヤーが現在 tween 中（次の入力を受け付けない状態）か。
    /// physicsProcess は連打や長押しでもこの間は moveTo を発火しない。
    pub def isMoving(): Bool \ Tween.Scheduler =
        Tween.Scheduler.isActive(playerPath())

    /// 毎フレーム engine から呼ばれる。tween 中でなければ方向キーの押下状態を polling し、
    /// 押されていれば次の moveTo を発火する（押しっぱなしで 1 マスずつ滑らかに連続移動する仕掛け）。
    /// `InputEvent.onKeyPressed` は押下エッジ専用で echo events が来ないため、
    /// 連続移動はここでの per-frame polling で実現する。
    /// Game.flix の Node[NodeTag] redef からは **PlayerMoving フェーズでのみ** dispatch
    /// される（PlayerCursor 中はカーソルが動き、味方は止まっている）。
    pub def physicsProcess(_delta: Float64,
                            node: EngineNode[NodeTag],
                            _path: NodePath,
                            scene: Scene[NodeTag]):
                           (EngineNode[NodeTag], Scene[NodeTag])
                           \ {GameEngine.Game, BoardQuery, Tween.Scheduler} =
        match node {
            case EngineNode.Marker2DWithState(marker, NodeTag.Player(data)) =>
                if (isMoving()) (node, scene)
                else
                    let board = BoardQuery.board();
                    // 移動範囲（move_tile が敷かれているセル）でフィルタする。
                    let allowed = c -> MoveRangeScene.isInRange(c, scene);
                    let movement = forM (
                        dir    <- readHeldDirection();
                        target <- BoardLogic.tryMoveWithRange(board, dir, allowed)
                    ) yield {
                        let (newMarker, newData) = moveTo(board#map, target, marker, data, scene);
                        (EngineNode.Marker2DWithState(newMarker, NodeTag.Player(newData)), scene)
                    };
                    Option.getWithDefault((node, scene), movement)
            case _ => (node, scene)
        }

    /// 押されている方向キーを Option で返す（複数同時押しは上 > 下 > 左 > 右 の優先順位）
    def readHeldDirection(): Option[Vec2.Vec2i] \ GameEngine.Game =
        let isDown = key -> GameEngine.Game.isKeyPressed(key);
        if      (isDown(GameEngine.Key.W) or isDown(GameEngine.Key.Up))    Some(Vec2.upI())
        else if (isDown(GameEngine.Key.S) or isDown(GameEngine.Key.Down))  Some(Vec2.downI())
        else if (isDown(GameEngine.Key.A) or isDown(GameEngine.Key.Left))  Some(Vec2.leftI())
        else if (isDown(GameEngine.Key.D) or isDown(GameEngine.Key.Right)) Some(Vec2.rightI())
        else None

    // ────────────────────────────────────────────────────────
    // (E) ボイラプレート — pattern match を関数化
    // ────────────────────────────────────────────────────────

    /// Player の Marker2D と Data をまとめて変換する
    pub def mapPlayer(f: (Marker2D, Data) -> (Marker2D, Data),
                       scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(playerPath(), engineNode -> match engineNode {
            case EngineNode.Marker2DWithState(marker, NodeTag.Player(data)) =>
                let (newMarker, newData) = f(marker, data);
                EngineNode.Marker2DWithState(newMarker, NodeTag.Player(newData))
            case other => other
        }, scene)

    /// Player の Data を取り出す（存在しない場合は bug!）
    pub def getPlayerData(scene: Scene[NodeTag]): Data =
        match Scene.getState(playerPath(), scene) {
            case Some(NodeTag.Player(data)) => data
            case _ => bug!("PlayerScene: player not found at ${playerPath()}")
        }

    /// プレイヤーの現在グリッド座標。BoardLogic 等が移動可否判定の起点として使う
    pub def getGridPos(scene: Scene[NodeTag]): Vec2.Vec2i =
        getPlayerData(scene)#gridPos

    /// プレイヤーの移動力（マス）。MoveRangeScene が BFS の深さに使う
    pub def getMoveTiles(scene: Scene[NodeTag]): Int32 =
        getPlayerData(scene)#moveTiles
}
