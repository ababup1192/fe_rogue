/// MapScene — ダンジョンマップ（TileMapLayer）を Scene に追加する
///
/// シーン構造とプロパティ（LDTK パス・タイルセットテクスチャ名等）は
/// MapScene.scene.json で管理し、SceneLoader が TileMapLayer ビルダーから
/// LDTKLoader を呼んで `.ldtkl` を読み込む。
/// 衝突セルは TileMapLayer 内部に格納され、PhysicsStep / RayCast2D / CharacterBody2D の
/// 衝突クエリが透過的に利用する（PlayerScene 等は内部実装を知らない）。
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
}
