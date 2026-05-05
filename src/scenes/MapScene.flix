/// MapScene — ダンジョンマップ（TileMapLayer）を Scene に追加する
///
/// 複数の LDTK モジュール（部屋・通路）を `DungeonComposer.compose` でマージし、
/// 1 枚の TileMapLayer としてシーンに登録する。第一歩として
/// `Level_0 + Pathway_1 + Level_1` を横一直線（Overlap 配置）で連結する。
///
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

    /// MapScene の TileMapLayer ノードに紐づくデータ。
    /// `anchorOffset` は modulePaths[0] の正規化後 offsetGrid（負 offset 回避のための shift 量と等しい）。
    /// PlayerScene 等が「anchor 部屋の中央付近」をスポーン位置とするために参照する。
    pub type alias Data = {
        anchorOffset = Vec2.Vec2i
    }

    // (B) 定数
    def name(): String = "DungeonLevel0"
    pub def mapPath(): NodePath = name() :: Nil

    /// 全モジュールが共有するタイルセットのテクスチャ名
    def textureName(): String = "inca_tileset"

    /// ランダム生成設定: 部屋数と利用可能な部屋・通路 LDTK プール。
    /// roomCount を増やすほどダンジョンが大きくなる。配置不能なら部屋数を減らして続行。
    def generatorConfig(): DungeonGenerator.Config = {
        roomPaths      = "title_map/World_Level_0.ldtkl" ::
                         "title_map/World_Level_1.ldtkl" :: Nil,
        horizontalPath = "title_map/World_Pathway_1.ldtkl",
        verticalPath   = "title_map/World_Pathway_2.ldtkl",
        roomCount      = 5
    }

    // (C) 構築
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead, Math.Random, IO} =
        let plan = DungeonGenerator.generate(textureName(), generatorConfig());
        let result = DungeonComposer.composeFromSideConnections(textureName(),
                                                                 plan#modulePaths,
                                                                 plan#sideConnections);
        let mapData: Data = { anchorOffset = result#anchorOffset };
        Scene.addNode(name(),
                       EngineNode.TileMapLayerWithState(result#layer, NodeTag.Map(mapData)),
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

    /// MapScene.add が記録した anchor の正規化後 offset を取り出す。
    /// PlayerScene が「anchor 部屋の中央付近」をスポーン位置とするのに使う。
    pub def getAnchorOffset(scene: Scene[NodeTag]): Vec2.Vec2i =
        match Scene.getEngineNode(mapPath(), scene) {
            case Some(EngineNode.TileMapLayerWithState(_, NodeTag.Map(data))) => data#anchorOffset
            case _ => bug!("MapScene: anchor offset not found at ${mapPath()} (NodeTag.Map missing)")
        }
}
