/// MapScene — ダンジョンマップ（TileMapLayer）を Scene に追加する
///
/// シーン構造とプロパティ（LDTK パス・タイルセットテクスチャ名等）は
/// MapScene.scene.json で管理し、SceneLoader が TileMapLayer ビルダーから
/// LDTKLoader を呼んで `.ldtkl` を読み込む。
/// 衝突セルは TileMapLayer 内部に格納され、PhysicsStep / RayCast2D / CharacterBody2D の
/// 衝突クエリが透過的に利用する（PlayerScene 等は内部実装を知らない）。
///
/// 他シーンが「マップ 1 マスのピクセルサイズ」「セルが床か壁か」などを問い合わせる
/// 際は `MapSnapshot` レコードを経由する。関数フィールドにフレーム時点の TileMapLayer と
/// Map global を捕獲したクロージャが入り、何度呼んでも同じフレームの結果を返す。
///
/// 取得は `BoardQuery` effect の戻り値（Board）に含まれる形で行う。MapSnapshot 単体を
/// effect で公開する MapQuery 経路は廃止し、Board を盤面情報の唯一の入口に統一した。
pub type alias MapSnapshot = {
    tileSize    = Float64,
    usedRect    = { position = Vec2.Vec2i, size = Vec2.Vec2i },
    isWall      = Vec2.Vec2i -> Bool,
    isFloor     = Vec2.Vec2i -> Bool,
    mapToLocal  = Vec2.Vec2i -> Vec2.Vec2,
    // gridToWorld: mapToLocal と違い Map の global position 加算済み
    // （呼び出し側が MapScene の位置を知らずに済む）
    gridToWorld = Vec2.Vec2i -> Vec2.Vec2
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
