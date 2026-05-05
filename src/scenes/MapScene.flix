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

    // (B) 定数
    def name(): String = "DungeonLevel0"
    pub def mapPath(): NodePath = name() :: Nil

    /// 全モジュールが共有するタイルセットのテクスチャ名
    def textureName(): String = "inca_tileset"

    /// 第一歩のダンジョン構成: Level_0 + Pathway_1 + Level_1 の横連結（Overlap 配置）。
    ///   Level_0(0,0)   cols 0..12,  右ドア (12,6)
    ///   Pathway_1(8,0) cols 8..20,  左ドア (12,6) 右ドア (16,6)
    ///   Level_1(16,0)  cols 16..28, 左ドア (16,6)
    /// Door セル (12,6) と (16,6) は両モジュールが重なる位置で、
    /// openDoors に含めることで壁から床に書き換える。
    /// Level_0/1 の上下ドア (6,0)/(6,12) は openDoors に含めないので壁のまま残る。
    def modules(): List[DungeonComposer.ModuleSpec] =
        ({ ldtkPath = "title_map/World_Level_0.ldtkl",
            offsetGrid = ({x = 0,  y = 0}: Vec2.Vec2i) }: DungeonComposer.ModuleSpec) ::
        ({ ldtkPath = "title_map/World_Pathway_1.ldtkl",
            offsetGrid = ({x = 8,  y = 0}: Vec2.Vec2i) }: DungeonComposer.ModuleSpec) ::
        ({ ldtkPath = "title_map/World_Level_1.ldtkl",
            offsetGrid = ({x = 16, y = 0}: Vec2.Vec2i) }: DungeonComposer.ModuleSpec) ::
        Nil

    def openDoors(): List[Vec2.Vec2i] =
        ({x = 12, y = 6}: Vec2.Vec2i) ::
        ({x = 16, y = 6}: Vec2.Vec2i) ::
        Nil

    // (C) 構築
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead} =
        let layer = DungeonComposer.compose(textureName(), modules(), openDoors());
        Scene.addNode(name(),
                       EngineNode.TileMapLayerWithState(layer, NodeTag.NoTag),
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
