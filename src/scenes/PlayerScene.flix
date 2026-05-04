/// PlayerScene — プレイヤーキャラクター（CharacterBody2D）と子 Sprite / 子 Camera
///
/// ノード構造（Godot 準拠）:
///   Player (CharacterBody2D, NodeTag.Player(Data))
///     ├─ Sprite (Sprite2D, 描画専用)
///     └─ Camera (Camera2D, 親追従でビューが Player を中心に表示)
///
/// 移動指示は `Data#pendingMotion` に積み、physicsProcess が CharacterBody2D.moveAndCollide で
/// 消費する（衝突応答はエンジン側に委譲）。
/// Camera は Player の子なので、`findActiveCamera` がシーンツリーから求めた global 座標を
/// 介して自動追従する（手動同期不要）。
mod PlayerScene {

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// プレイヤー固有の状態（Godot のキャラクタ固有メンバ変数相当）。
    /// CharacterBody2D の拡張ではなく、ゲーム側 state として保持する。
    pub type alias Data = {
        pendingMotion = Vec2.Vec2  // 次の physicsProcess で消費される移動指示
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def name(): String = "Player"
    pub def playerPath(): NodePath = name() :: Nil

    def spriteName(): String = "Sprite"
    def cameraName(): String = "Camera"

    def playerTexture(): String = "character_sheet"
    def textureSize(): Vec2.Vec2 = {x = 80.0, y = 32.0}
    def regionPos(): Vec2.Vec2 = {x = 0.0, y = 0.0}
    def regionSize(): Vec2.Vec2 = {x = 16.0, y = 16.0}

    def tileSize(): Float64 = 16.0
    def collisionSize(): Vec2.Vec2 = {x = 14.0, y = 14.0}

    /// プレイヤー初期グリッド座標（マップの開けた床面）
    pub def initialGrid(): (Int32, Int32) = (5, 5)

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// グリッド座標 (col, row) を world ピクセル座標（タイル中心）に変換する
    pub def gridToWorld(col: Int32, row: Int32): Vec2.Vec2 =
        let s = tileSize();
        { x = Int32.toFloat64(col) * s + s / 2.0,
          y = Int32.toFloat64(row) * s + s / 2.0 }

    def initialData(): Data = { pendingMotion = Vec2.zero() }

    /// プレイヤー（CharacterBody2D）と子 Sprite / 子 Camera を Scene に追加する。
    /// Sprite と Camera は Player のローカル原点 (0, 0) に配置する（親追従）。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] =
        let (col, row) = initialGrid();
        let initPos = gridToWorld(col, row);
        let body = CharacterBody2D.make(initPos, moveSpeed = 0.0)
            |> CharacterBody2D.setCollisionShape(
                Some(CollisionShape2D.RectShape2D({
                    width  = collisionSize()#x,
                    height = collisionSize()#y
                })));
        let sprite = Sprite2D.makeRegion({
            texture       = playerTexture(),
            position      = Vec2.zero(),
            displayScale  = {x = 1.0, y = 1.0},
            regionPosPx   = regionPos(),
            regionSizePx  = regionSize(),
            textureSizePx = textureSize()
        });
        let camera = Camera2D.make(Vec2.zero()) |> Camera2D.setZoom({x = 0.5, y = 0.5});
        scene
            |> Scene.addNode(name(),
                EngineNode.Body2DWithState(body, NodeTag.Player(initialData())))
            |> Scene.addChildAt(playerPath(), spriteName(),
                EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))
            |> Scene.addChildAt(playerPath(), cameraName(),
                EngineNode.Camera2DWithState(camera, NodeTag.NoTag))

    // ────────────────────────────────────────────────────────
    // (D) ロジック
    // ────────────────────────────────────────────────────────

    /// 入力イベント等から呼ばれ、1 グリッド分の移動指示を pendingMotion に積む。
    /// 実際の移動は次の physicsProcess で行われる。
    pub def requestMove(dCol: Int32, dRow: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        let s = tileSize();
        let motion: Vec2.Vec2 = {
            x = Int32.toFloat64(dCol) * s,
            y = Int32.toFloat64(dRow) * s
        };
        scene |> mapPlayer((body, data) -> (body, {pendingMotion = motion | data}))

    /// pendingMotion を消費して CharacterBody2D を移動・衝突応答させる。
    /// Camera は子ノードなので親子変換で自動追従される（手動同期不要）。
    /// Game.flix の Node[NodeTag] redef からディスパッチされる。
    pub def physicsProcess(_delta: Float64,
                            node: EngineNode[NodeTag],
                            _path: NodePath,
                            scene: Scene[NodeTag]):
                           (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.Body2DWithState(body, NodeTag.Player(data)) =>
                // Godot 同様、毎フレーム無条件に move_and_collide を呼ぶ。
                // motion がゼロベクトルでも moveAndCollide は安全（位置は変わらない）。
                // 壁などの衝突体に当たれば手前で止まり、collided=true が返るが今は使わない。
                let (movedBody, _collided) =
                    CharacterBody2D.moveAndCollide(data#pendingMotion, scene, body);
                // 同じ指示を次フレームでも繰り返し実行しないよう消化済みとしてリセット。
                // input によって次の指示が積まれるまで待機する。
                let cleared: Data = {pendingMotion = Vec2.zero() | data};
                (EngineNode.Body2DWithState(movedBody, NodeTag.Player(cleared)), scene)
            case _ => (node, scene)
        }

    // ────────────────────────────────────────────────────────
    // (E) ボイラプレート — pattern match を関数化
    // ────────────────────────────────────────────────────────

    /// Player の CharacterBody2D と Data をまとめて変換する
    pub def mapPlayer(f: (CharacterBody2D, Data) -> (CharacterBody2D, Data),
                       scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(playerPath(), engineNode -> match engineNode {
            case EngineNode.Body2DWithState(body, NodeTag.Player(data)) =>
                let (newBody, newData) = f(body, data);
                EngineNode.Body2DWithState(newBody, NodeTag.Player(newData))
            case other => other
        }, scene)

    /// Player の Data を取り出す（存在しない場合は bug!）
    pub def getPlayerData(scene: Scene[NodeTag]): Data =
        match Scene.getState(playerPath(), scene) {
            case Some(NodeTag.Player(data)) => data
            case _ => bug!("PlayerScene: player not found at ${playerPath()}")
        }
}
