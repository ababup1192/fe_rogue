/// MapScene — ダンジョンマップ（TileMapLayer）を Scene に追加する
///
/// シーン構造とプロパティ（LDTK パス・タイルセットテクスチャ名等）は
/// MapScene.scene.json で管理し、SceneLoader が TileMapLayer ビルダーから
/// LDTKLoader を呼んで `.ldtkl` を読み込む。
/// 衝突セルは TileMapLayer 内部に格納され、PhysicsStep / RayCast2D / CharacterBody2D の
/// 衝突クエリが透過的に利用する（PlayerScene 等は内部実装を知らない）。
///
/// 他シーンが「マップ 1 マスのピクセルサイズ」「セルが床か壁か」などを問い合わせる
/// 際は MapQuery effect を経由する。実体は Game.start が sceneRef を closure に
/// 抱えて handler を注入する（PlayerScene 等は MapScene の存在を知らずに使える）。
pub eff MapQuery {
    def tileSize(): Float64
    def getUsedRect(): { position = Vec2.Vec2i, size = Vec2.Vec2i }
    def isWall(coords: Vec2.Vec2i): Bool
    def isFloor(coords: Vec2.Vec2i): Bool
    def mapToLocal(coords: Vec2.Vec2i): Vec2.Vec2
}

mod MapScene {

    // (B) 定数
    def name(): String = "DungeonLevel0"
    pub def mapPath(): NodePath = name() :: Nil

    def sceneJsonPath(): String = "src/scenes/MapScene.scene.json"

    // (C) 構築
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead} =
        SceneLoader.loadScene(sceneJsonPath(),
                              SceneLoader.constTagParser(NodeTag.NoTag),
                              scene)

    // ────────────────────────────────────────────────────────
    // (D) MapQuery effect の実体
    // ────────────────────────────────────────────────────────

    /// scene 内に登録された TileMapLayer を取り出す。
    /// MapScene.add 済みであることが前提（未登録なら bug!）
    pub def getMapLayer(scene: Scene[NodeTag]): TileMapLayer =
        match Scene.getEngineNode(mapPath(), scene) {
            case Some(EngineNode.TileMapLayerWithState(layer, _)) => layer
            case _ => bug!("MapScene: TileMapLayer not found at ${mapPath()}")
        }
}
