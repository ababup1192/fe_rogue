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

    /// 第一歩のダンジョン構成: Level_0 + Pathway_1 + Level_1 の横連結（Overlap 配置 + 部屋優先）。
    /// modulePaths の順番が DungeonComposer の dedup 優先度を決める（先勝ち）。
    /// 部屋を先・通路を後ろに置くことで Overlap 領域では部屋の壁スプライトが残り、
    /// 通路の corridor wall は重ならない位置にだけ追加される。
    /// 各 SideConnection の Door grid 座標は Composer が `doors` 一覧の
    /// min-x/max-x/min-y/max-y で自動解決し、offsetGrid / openDoors も BFS で導出される。
    /// 結果として Level_0/1 の上下ドア (Top/Bottom) は連結に含めていないので壁のまま残る。
    def modulePaths(): List[String] =
        "title_map/World_Level_0.ldtkl"  ::   // index 0 (anchor / 部屋優先)
        "title_map/World_Level_1.ldtkl"  ::   // index 1 (部屋優先)
        "title_map/World_Pathway_1.ldtkl" ::  // index 2 (通路は最後＝先勝ち dedup で部屋が勝つ)
        Nil

    /// 連結グラフ（Side 指定）:
    ///   Level_0 (idx 0) Right  ↔  Pathway_1 (idx 2) Left
    ///   Pathway_1 (idx 2) Right ↔  Level_1 (idx 1) Left
    def sideConnections(): List[DungeonComposer.SideConnection] =
        ({ a = ({moduleIndex = 0, side = DungeonComposer.DoorSide.Right}
                : DungeonComposer.SideRef),
           b = ({moduleIndex = 2, side = DungeonComposer.DoorSide.Left}
                : DungeonComposer.SideRef) }
           : DungeonComposer.SideConnection) ::
        ({ a = ({moduleIndex = 2, side = DungeonComposer.DoorSide.Right}
                : DungeonComposer.SideRef),
           b = ({moduleIndex = 1, side = DungeonComposer.DoorSide.Left}
                : DungeonComposer.SideRef) }
           : DungeonComposer.SideConnection) ::
        Nil

    // (C) 構築
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead} =
        let layer = DungeonComposer.composeFromSideConnections(textureName(),
                                                                modulePaths(),
                                                                sideConnections());
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
