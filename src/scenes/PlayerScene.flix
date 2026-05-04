/// PlayerScene — プレイヤーキャラクター（CharacterBody2D）と追従カメラ
///
/// ノード構造:
///   Player (CharacterBody2D, NodeTag.Player(Data))
///     └─ Sprite (Sprite2D, 描画専用)
///   Camera (Camera2D, 兄弟ノード)
///
/// Camera は Player の兄弟として配置する。
/// （Scene.findActiveCamera は Camera 自身の position（local）を使うため、
///   子ノード化すると Player の位置を反映できない）
/// 追従は physicsProcess で Player の new position を Camera にコピーして実現する。
///
/// 移動指示は `Data#pendingMotion` に積み、physicsProcess が CharacterBody2D.moveAndCollide で
/// 消費する（衝突応答はエンジン側に委譲）。
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

    pub def cameraPath(): NodePath = cameraName() :: Nil

    /// プレイヤー（CharacterBody2D + 子 Sprite）と兄弟ノードの Camera を Scene に追加する。
    /// Camera は Player と同じワールド座標から開始する。
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
        let camera = Camera2D.make(initPos);
        scene
            |> Scene.addNode(name(),
                EngineNode.Body2DWithState(body, NodeTag.Player(initialData())))
            |> Scene.addChildAt(playerPath(), spriteName(),
                EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))
            |> Scene.addNode(cameraName(),
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
    /// 移動が発生した場合は Camera を同じ位置に追従させる。
    /// Game.flix の Node[NodeTag] redef からディスパッチされる。
    pub def physicsProcess(_delta: Float64,
                            node: EngineNode[NodeTag],
                            _path: NodePath,
                            scene: Scene[NodeTag]):
                           (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.Body2DWithState(body, NodeTag.Player(data)) =>
                // 移動指示が空なら何もしない（毎フレーム呼ばれるが指示があるときだけ動く）
                if (Vec2.isZeroApprox(data#pendingMotion)) (node, scene)
                else
                    // 移動指示の分だけ動かす。壁などの衝突体に当たれば手前で止まり、
                    // collided=true が返るが今は無視する。
                    let (movedBody, _collided) =
                        CharacterBody2D.moveAndCollide(data#pendingMotion, scene, body);
                    // 同じ移動指示が次フレームでも再実行されないよう、消化済みとして
                    // pendingMotion をゼロに戻す（input によって次の指示が積まれるまで待機）。
                    let cleared: Data = {pendingMotion = Vec2.zero() | data};
                    let newPos = Node2D.getPosition(movedBody);
                    let updatedScene = followCamera(newPos, scene);
                    (EngineNode.Body2DWithState(movedBody, NodeTag.Player(cleared)),
                     updatedScene)
            case _ => (node, scene)
        }

    /// Camera ノードの位置を pos に合わせる（Player の動きにカメラを追従させる）
    def followCamera(pos: Vec2.Vec2, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene |> Scene.mapEngineNode(cameraPath(), en -> match en {
            case EngineNode.Camera2DWithState(cam, st) =>
                EngineNode.Camera2DWithState(Node2D.setPosition(pos, cam), st)
            case other => other
        })

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
