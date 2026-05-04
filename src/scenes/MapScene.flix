/// MapScene — ダンジョンマップ（TileMapLayer）を Scene に追加する
///
/// LDTKLoader が読み込んだ TileMapLayer を `EngineNode.TileMapLayerWithState` として登録。
/// 衝突セルは TileMapLayer 内部に格納され、PhysicsStep / RayCast2D / CharacterBody2D の
/// 衝突クエリが透過的に利用する（PlayerScene 等は内部実装を知らない）。
mod MapScene {

    // (B) 定数
    def name(): String = "DungeonLevel0"
    pub def mapPath(): NodePath = name() :: Nil

    def levelFilePath(): String = "title_map/World_Level_0.ldtkl"
    def tilesetTextureName(): String = "inca_tileset"

    /// マップ 1 グリッドのピクセルサイズ（World_Level_0.ldtkl の __gridSize）
    pub def gridSize(): Float64 = 16.0

    /// マップのグリッド幅（World_Level_0.ldtkl の __cWid）
    pub def cellWidth(): Int32 = 13

    /// マップのグリッド高さ（World_Level_0.ldtkl の __cHei）
    pub def cellHeight(): Int32 = 13

    // (C) 構築
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead} =
        let levelData = LDTKLoader.loadLevel(
            LDTKLoader.simpleConfig({
                path        = levelFilePath(),
                textureName = tilesetTextureName()
            }));
        scene |> Scene.addNode(name(),
            EngineNode.TileMapLayerWithState(levelData#tileLayer, NodeTag.NoTag))
}
