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
/// 取得は `BoardQuery` effect の戻り値（Board）に含まれる形で行う。Board が盤面情報の
/// 唯一の入口。
// Flix 0.72.0 の test stage で cross-package type alias (Vec2.Vec2 等) が
// 解決されない不具合のため、`Vec2.Vec2` を `{x = Float64, y = Float64}` に展開している。
pub type alias MapSnapshot = {
    tileSize    = Float64,
    usedRect    = { position = {x = Int32, y = Int32}, size = {x = Int32, y = Int32} },
    isWall      = {x = Int32, y = Int32} -> Bool,
    isFloor     = {x = Int32, y = Int32} -> Bool,
    mapToLocal  = {x = Int32, y = Int32} -> {x = Float64, y = Float64},
    // gridToWorld: mapToLocal と違い Map の global position 加算済み
    // （呼び出し側が MapScene の位置を知らずに済む）
    gridToWorld  = {x = Int32, y = Int32} -> {x = Float64, y = Float64},
    // moduleOfCell: ワールドグリッド座標 → 包含モジュール idx。
    // 部屋優先で「先勝ち」（modulePaths の若い idx を返す）。
    // どのモジュールにも含まれない場合（void 領域）は None。
    // 「同じ部屋／通路にいる」検知やモジュール内セル列挙の起点に使う。
    moduleOfCell = {x = Int32, y = Int32} -> Option[Int32]
}

mod MapScene {

    /// MapScene の TileMapLayer ノードに紐づくデータ。
    /// - `anchorOffset` は modulePaths[0] の正規化後 offsetGrid（負 offset 回避のための shift 量）。
    /// - `spawnGrid` は anchor 部屋の中で「壁でない」と保証されたセルのワールド座標。
    ///   PlayerScene が安全なスポーン地点として使う（LDTK によって部屋の中央が壁になっていても OK）。
    pub type alias Data = {
        anchorOffset = {x = Int32, y = Int32},
        spawnGrid    = {x = Int32, y = Int32},
        // 配置済み全モジュールのワールド bbox（idx 順）。
        // 「セル → モジュール idx」逆引きや、敵スポーン候補セルの列挙に使う。
        // anchor を除く部屋判定 / 通路除外もこのリストから判定する（idx < roomCount）。
        // 構造は engine の DungeonComposer.ModulePlacement と一致：
        //   {idx = Int32, offset = {x,y = Int32}, gridSize = {x,y = Int32}}
        // Flix 0.72.0 の test stage で cross-package type alias が解決されないため展開済み。
        placements   = List[{idx = Int32,
                              offset = {x = Int32, y = Int32},
                              gridSize = {x = Int32, y = Int32}}],
        // 部屋数。modulePaths が「部屋を先・通路を後ろ」で並ぶ前提なので
        // idx < roomCount なら「部屋」、それ以外は「通路」と判定できる。
        roomCount    = Int32
    }

    // (B) 定数
    def name(): String = "DungeonLevel0"
    def floorName(): String = "DungeonLevel0Floor"
    pub def mapPath(): NodePath = name() :: Nil

    /// 全キャラ（Player / Enemy）の共通親となる Marker2D の名前。
    /// `ySortEnabled = true` を有効にしてここに直接の子を Y 順で並べることで
    /// 「下にいるキャラが手前」という Godot Y-sort 挙動を実現する
    pub def worldName(): String = "World"

    /// World Marker2D の NodePath。PlayerScene / EnemyScene が
    /// 自身のノードをここの子として `addChildAt` する起点
    pub def worldPath(): NodePath = worldName() :: Nil

    /// Walls レイヤー（衝突あり）が使うタイルセットのテクスチャ名
    def textureName(): String = "inca_tileset"

    /// Floor 装飾レイヤーのテクスチャ名（LDTK 上の "Floor" レイヤーが参照）
    def floorTextureName(): String = "tilemap_floor"

    /// ランダム生成設定: 部屋数と利用可能な部屋・通路 LDTK プール。
    /// roomCount を増やすほどダンジョンが大きくなる。配置不能なら部屋数を減らして続行。
    def generatorConfig(): DungeonGenerator.Config = {
        roomPaths       = "assets/ldtk/World_Level_0.ldtkl" ::
                          "assets/ldtk/World_Level_1.ldtkl" ::
                          "assets/ldtk/World_Level_2.ldtkl" ::
                          "assets/ldtk/World_Level_3.ldtkl" ::
                          "assets/ldtk/World_Level_4.ldtkl" :: Nil,
        horizontalPaths = "assets/ldtk/World_Pathway_1.ldtkl" ::
                          "assets/ldtk/World_Pathway_4.ldtkl" :: Nil,
        verticalPaths   = "assets/ldtk/World_Pathway_2.ldtkl" ::
                          "assets/ldtk/World_Pathway_3.ldtkl" :: Nil,
        roomCount       = 8
    }

    // (C) 構築
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead, Math.Random, IO} =
        let plan = DungeonGenerator.generate(textureName(), generatorConfig());
        // LDTK の auto-tile rules を consumer 側で読み込んで渡す
        // （engine の DungeonComposer は path を持たない純粋関数）
        let ruleSet = LDTKRules.loadRules("assets/ldtk/FE.ldtk");
        let result = DungeonComposer.composeFromSideConnections(textureName(),
                                                                 ruleSet,
                                                                 plan#modulePaths,
                                                                 plan#sideConnections);
        let mapData: Data = { anchorOffset = result#anchorOffset,
                               spawnGrid    = result#spawnGrid,
                               placements   = result#placements,
                               roomCount    = plan#roomCount };
        // Floor 装飾レイヤーを Walls の下（zIndex < Walls）に重ねる。
        // tilemap_floor テクスチャを使用、衝突なし、auto-rule 再適用なし。
        let floorRaw = DungeonComposer.composeDecorationLayer(floorTextureName(),
                                                                result#moduleSpecs,
                                                                "Floor");
        let floorLayer = CanvasItem.setZIndex(-1, floorRaw);
        // Player / Enemy をまとめる Y-sort root。これより前に登録することで
        // PlayerScene.add / EnemyScene.add が `worldPath()` を起点にできる。
        let worldMarker = Marker2D.make(Vec2.zero())
            |> CanvasItem.setYSortEnabled(true);
        scene
            |> Scene.addNode(floorName(),
                              EngineNode.TileMapLayerWithState(floorLayer, NodeTag.NoTag))
            |> Scene.addNode(name(),
                              EngineNode.TileMapLayerWithState(result#layer, NodeTag.Map(mapData)))
            |> Scene.addNode(worldName(),
                              EngineNode.Marker2DWithState(worldMarker, NodeTag.NoTag))

    // ────────────────────────────────────────────────────────
    // (D) Scene からの取り出しヘルパ
    // ────────────────────────────────────────────────────────

    /// scene 内に登録された TileMapLayer を取り出す。
    /// MapScene.add 済みであることが前提（未登録なら bug!）
    pub def getMapLayer(scene: Scene[NodeTag]): TileMapLayer =
        match Scene.getEngineNode(mapPath(), scene) {
            case Some(EngineNode.TileMapLayerWithState(layer, _)) => layer
            case _ => bug!("MapScene: TileMapLayer not found at ${mapPath()}")
        }

    /// MapScene.add が記録した anchor の正規化後 offset を取り出す。
    pub def getAnchorOffset(scene: Scene[NodeTag]): {x = Int32, y = Int32} =
        getMapData(scene)#anchorOffset

    /// anchor 内の床セルとして保証されたスポーン地点（ワールド座標）を取り出す。
    /// PlayerScene.add がプレイヤーをここに配置する。
    pub def getSpawnGrid(scene: Scene[NodeTag]): {x = Int32, y = Int32} =
        getMapData(scene)#spawnGrid

    /// 配置済み全モジュールのワールド bbox（idx 順）。EnemyScene のスポーン候補列挙や
    /// `moduleOfCell` の構築に使う。
    pub def getPlacements(scene: Scene[NodeTag]): List[DungeonComposer.ModulePlacement] =
        getMapData(scene)#placements

    /// 部屋数。`idx < roomCount` なら部屋、それ以外は通路と判定できる。
    pub def getRoomCount(scene: Scene[NodeTag]): Int32 =
        getMapData(scene)#roomCount

    /// LDTK 由来のタイルサイズ（ピクセル）。MapScene の TileMapLayer と同じ 16px 正方形を前提。
    /// グリッド ⇄ ピクセル変換が必要な全 Scene が参照する唯一の情報源。
    pub def tileSize(): Float64 = 16.0

    /// グリッド座標 → セル中心ピクセル座標。`tileSize` で求めた正方形セルの中央点を返す。
    /// MapScene の `mapToLocal` 慣習に揃えてあり、Marker2D / Sprite2D を「マスのど真ん中」に
    /// 置きたい全 Scene（Player/Enemy/Cursor/Flag/Range 系）が共通で使う。
    pub def cellCenter(cell: {x = Int32, y = Int32}): Vec2.Vec2 =
        let s = tileSize();
        let v = Vec2i.toVec2(cell);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    /// `placements` を「先勝ち（idx 昇順）」で走査し、`coord` を含む最初のモジュール idx を返す。
    /// modulePaths は「部屋を先・通路を後ろ」で並ぶため、部屋優先で逆引きできる。
    /// MapSnapshot.moduleOfCell の実装。
    pub def moduleOfCellIn(coord: {x = Int32, y = Int32},
                            placements: List[DungeonComposer.ModulePlacement]): Option[Int32] =
        List.findMap(p -> {
            let minX = p#offset#x;
            let minY = p#offset#y;
            let maxX = p#offset#x + p#gridSize#x;
            let maxY = p#offset#y + p#gridSize#y;
            if (coord#x >= minX and coord#x < maxX
                and coord#y >= minY and coord#y < maxY) Some(p#idx)
            else None
        }, placements)

    def getMapData(scene: Scene[NodeTag]): Data =
        match Scene.getEngineNode(mapPath(), scene) {
            case Some(EngineNode.TileMapLayerWithState(_, NodeTag.Map(data))) => data
            case _ => bug!("MapScene: NodeTag.Map not found at ${mapPath()}")
        }
}
