// GroundScene — 地面タイルの構築・リサイクル
//
// 地面は StaticBody2D + 子 Sprite2D で構成される。
// 画面幅をカバーするよう複数タイル配置し、カメラの左端を超えたタイルは
// 右端に再配置する無限スクロール方式。
//
//   StaticBody2DWithState(body, Ground)
//     └── Sprite2DWithState(sprite, NoTag)

mod GroundScene {

    // ========================================================================
    // 定数
    // ========================================================================

    /// 地面グループ名（一括操作用）
    pub def groundGroup(): String = "grounds"

    /// 地面タイルの幅（px）。参考実装 168 の 2 倍
    def groundWidth(): Float64 = 336.0

    /// 地面タイルの高さ（px）。参考実装 56 の 2 倍
    def groundHeight(): Float64 = 112.0

    /// 地面の中心 Y 座標。画面下端(512) から高さの半分を引いた値
    pub def groundCenterY(): Float64 = 512.0 - groundHeight() / 2.0

    /// 地面の上端 Y 座標（鳥の位置クランプに使用）
    pub def groundTopY(): Float64 = 512.0 - groundHeight()

    /// 地面テクスチャ名
    def groundTexture(): String = "ground"

    /// 地面の衝突形状（タイル全体をカバーする矩形）
    def groundCollisionShape(): CollisionShape2D =
        CollisionShape2D.RectShape2D({width = groundWidth(), height = groundHeight()})

    /// 地面の Z-index（パイプや鳥より前面に描画）
    def groundZIndex(): Int32 = 10

    // ========================================================================
    // シーン構築
    // ========================================================================

    /// 地面タイル 1 枚をシーンに追加する
    /// name: ノード名（ユニーク）
    /// xCenter: タイル中心の X 座標
    def spawnGround(name: String, xCenter: Float64,
                    scene: Scene[NodeTag]): Scene[NodeTag] =
        let body = StaticBody2D.make(
            {x = xCenter, y = groundCenterY()},
            groundCollisionShape());
        let sprite = Sprite2D.make(groundTexture(), Vec2.zero(), {x = 2.0, y = 2.0})
            |> CanvasItem.setZIndex(groundZIndex());
        scene
            |> Scene.addNode(name,
                EngineNode.StaticBody2DWithState(body, NodeTag.Ground))
            |> Scene.addToGroup(name :: Nil, groundGroup())
            |> Scene.addChild(name, "sprite",
                EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))

    /// 地面シーン定義 JSON のパス
    def sceneJsonPath(): String = "src/scenes/GroundScene.scene.json"

    /// 初期地面タイルを配置する（2 枚で画面幅 + スクロールバッファをカバー）。
    /// 構造は GroundScene.scene.json から読み込む。
    /// 画面外になったタイルの再配置は NodeRemovedHandler が担う
    pub def addGrounds(scene: Scene[NodeTag]): Scene[NodeTag] \ Fs.FileRead =
        SceneLoader.loadScene(sceneJsonPath(), scene)

    /// 地面グループ内の最右端 X 座標を返す（リサイクル位置決定に使用）
    def maxGroundX(scene: Scene[NodeTag]): Float64 =
        Scene.getNodesInGroup(groundGroup(), scene)
            |> List.map(p -> Scene.globalPositionAt(p, scene)#x)
            |> List.maximum
            |> Option.getWithDefault(0.0)

    /// リサイクル時に新タイルを spawn する
    /// 新タイルの X は現在の最右端 + groundWidth。ID は X 座標から導出
    pub def spawnRecycledGround(scene: Scene[NodeTag]): Scene[NodeTag] =
        let nextX = maxGroundX(scene) + groundWidth();
        let id = Float64.tryToInt32(nextX) |> Option.getWithDefault(0);
        spawnGround("ground_${id}", nextX, scene)

    // ========================================================================
    // ロジック（process）
    // ========================================================================

    /// 地面タイルが画面左端を完全に通過したらノードを除去する
    /// 除去通知は NodeRemovedHandler が Recycle 効果に変換し、上位ハンドラが
    /// 最右端に新タイルを再スポーンする
    pub def process(node: EngineNode[NodeTag], path: NodePath,
                    scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ Recycle =
        match node {
            case EngineNode.StaticBody2DWithState(_, NodeTag.Ground) =>
                let pos = Scene.globalPositionAt(path, scene);
                let halfWidth = groundWidth() / 2.0;
                if (pos#x + halfWidth < Game.getViewportLeftX(scene))
                    (node, Scene.removeAtAndNotify(path, scene))
                else
                    (node, scene)
            case _ => (node, scene)
        }
}
