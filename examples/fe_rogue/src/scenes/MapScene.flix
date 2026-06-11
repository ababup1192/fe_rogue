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
/// 際は `MapSnapshot` レコードを経由する。地形は**純粋データ**で持ち（壁セル集合・モジュール
/// 配置・Map global）、床判定・座標変換・モジュール逆引きは `MapScene` の純関数
/// （`isWall`/`isFloor`/`mapToLocal`/`gridToWorld`/`moduleOfCell`）で計算する。
/// 旧版は関数フィールド（クロージャ）で持っていたが、テストが地形を literal で組めるよう
/// 純粋データへ移した。本物の TileMapLayer からの射影は `MapScene.snapshotOf` 1 か所に閉じる。
///
/// 取得は `BoardQuery` effect の戻り値（Board）に含まれる形で行う。Board が盤面情報の
/// 唯一の入口。
// MapScene の責務は tilemap の view 操作と engine→snapshot 射影(snapshotOf)に限る。
// 衝突セルは TileMapLayer 内部に格納され、外部は MapSnapshot 経由でのみ参照する。

mod MapScene {
    import java.lang.{System => JSystem}

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
        //   {idx, offset, gridSize, floorBoundsMin, floorBoundsMaxEx, interiorCells}
        // n-format では gridSize ≫ 床範囲なので bbox 判定は floorBounds を使う。
        // interiorCells は decorTiles の world 座標リスト（door は含まない）。
        // Flix 0.72.0 の test stage で cross-package type alias が解決されないため展開済み。
        placements   = List[{idx = Int32,
                              offset = {x = Int32, y = Int32},
                              gridSize = {x = Int32, y = Int32},
                              floorBoundsMin = {x = Int32, y = Int32},
                              floorBoundsMaxEx = {x = Int32, y = Int32},
                              interiorCells = List[{x = Int32, y = Int32}]}],
        // 部屋数。modulePaths が「部屋を先・通路を後ろ」で並ぶ前提なので
        // idx < roomCount なら「部屋」、それ以外は「通路」と判定できる。
        roomCount    = Int32
    }

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

    /// Walls / Floor 共通テクスチャ名（n-format は両層で同一タイルセットを使う）。
    def textureName(): String = "tileset_dungeon_green"

    /// ランダム生成設定: フロアの roomCount と、フロアごとに設定された部屋・通路プール
    /// （出現率付き）から `DungeonGenerator.Config` を組み立てる。
    /// floors.json でプール未設定（空リスト）のフロアは従来のハードコード既定プールに
    /// フォールバックする（未移行 floors.json でも起動できるようにするため）。
    def generatorConfig(floor: FloorCatalog.FloorResource): DungeonGenerator.Config = {
        roomPaths       = poolOrDefault(floor#roomMaps, defaultRoomPaths()),
        horizontalPaths = poolOrDefault(floor#horizontalMaps, defaultHorizontalPaths()),
        verticalPaths   = poolOrDefault(floor#verticalMaps, defaultVerticalPaths()),
        roomCount       = floor#generation#roomCount
    }

    /// フロアの出現率付きマップ一覧を `(path, weight)` リストに変換する。
    /// stem → `.map.json` パスは `FloorCatalog.mapPathOf` で解決。
    /// 空リストなら fallback（既定プール）を返す。
    def poolOrDefault(entries: List[FloorCatalog.SpawnEntry],
                       fallback: List[(String, Int32)]): List[(String, Int32)] =
        match entries {
            case Nil => fallback
            case _   => List.map(e -> (FloorCatalog.mapPathOf(e#id), e#percent), entries)
        }

    /// 既定の部屋プール（floors.json でフロアに roomMaps が無いとき用）。
    def defaultRoomPaths(): List[(String, Int32)] =
        (AssetPath.resolve("assets/maps/room_1.map.json"), 25) ::
        (AssetPath.resolve("assets/maps/room_2.map.json"), 25) ::
        (AssetPath.resolve("assets/maps/room_3.map.json"), 25) ::
        (AssetPath.resolve("assets/maps/room_4.map.json"), 25) :: Nil

    def defaultHorizontalPaths(): List[(String, Int32)] =
        (AssetPath.resolve("assets/maps/pathway_horizontal_1.map.json"), 50) ::
        (AssetPath.resolve("assets/maps/pathway_horizontal_2.map.json"), 50) :: Nil

    def defaultVerticalPaths(): List[(String, Int32)] =
        (AssetPath.resolve("assets/maps/pathway_vertical_1.map.json"), 50) ::
        (AssetPath.resolve("assets/maps/pathway_vertical_2.map.json"), 50) :: Nil

    pub def add(floor: FloorCatalog.FloorResource, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead, Math.Random, IO} =
        // FE_ROGUE_MODE=map-test のとき、ランダム生成と DungeonComposer をバイパスして
        // 単一 .map.json (level_0) を MapLoader 経由で描画する。視覚一致確認用。
        let modeStr = unsafe IO { JSystem.getenv("FE_ROGUE_MODE") };
        let isMapTest = not Object.isNull(modeStr) and modeStr == "map-test";
        if (isMapTest) addFromMapJson(AssetPath.resolve("assets/maps/room_1.map.json"), scene)
        else           addFromLdtk(floor, scene)

    /// 既存ルート: DungeonGenerator + DungeonComposer で複数モジュールを連結する。
    /// n-format: composer が Walls 層と Floor 層を同時に構築して返す。
    def addFromLdtk(floor: FloorCatalog.FloorResource, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead, Math.Random, IO} =
        let plan = DungeonGenerator.generate(textureName(),
                                              generatorConfig(floor));
        let result = DungeonComposer.composeFromSideConnections(textureName(),
                                                                 plan#modulePaths,
                                                                 plan#sideConnections);
        let mapData: Data = { anchorOffset = result#anchorOffset,
                               spawnGrid    = result#spawnGrid,
                               placements   = result#placements,
                               roomCount    = plan#roomCount };
        // Floor 層は Walls の下（zIndex = -1）に重ねる。
        let floorLayer = CanvasItem.setZIndex(-1, result#floorLayer);
        // Player / Enemy をまとめる Y-sort root。これより前に登録することで
        // PlayerScene.add / EnemyScene.add が `worldPath()` を起点にできる。
        scene
            |> Scene.addNode(floorName(),
                              EngineNode.TileMapLayerWithState(floorLayer, NodeTag.NoTag))
            |> Scene.addNode(name(),
                              EngineNode.TileMapLayerWithState(result#layer, NodeTag.Map(mapData)))
            |> addWorldNode

    /// 新ルート (視覚一致確認用): 単一 .map.json を MapLoader 経由で描画する。
    /// DungeonComposer は通さない (auto-rule 再評価なし)。
    /// Walls / Floor 層は同一テクスチャ (tileset_dungeon_green) を共有する。
    /// Player/Enemy 配置は最小ダミー (spawnGrid を level 内の安全セルに固定)。
    pub def addFromMapJson(levelPath: String, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead} =
        // Walls 層 (manualTiles + collisionCells): loadLevelRaw で raw を取って手動で GPU upload
        let raw = MapLoader.loadLevelRaw(levelPath, textureName());
        let instances = TileRendering.buildTileInstances(raw#tiles, raw#tileSet, raw#tileSize);
        let (tileVaoId, tileCount) = GameEngine.Game.initTileBuffer(instances);
        let wallsLayer = TileMapLayer.make({
            tileSet        = raw#tileSet,
            tiles          = raw#tiles,
            collisionCells = raw#collisionCells,
            gridSize       = raw#gridSize
        }) |> TileMapLayer.withGpuResources(tileVaoId, tileCount);
        // Floor 装飾層 (decorTiles): Walls と同テクスチャ、Walls の下 (zIndex=-1) に重ねる
        let floorLayer = MapLoader.loadDecorLayer(levelPath, textureName())
            |> CanvasItem.setZIndex(-1);
        let gs = raw#gridSize;
        // 簡易 spawn: (3, 3) が床であることが多い。床でなければ最初の床セルを使う。
        let safe = findFirstFloor(raw#collisionCells, gs, ({x = 3, y = 3}: {x = Int32, y = Int32}));
        let mapData: Data = {
            anchorOffset = ({x = 0, y = 0}: {x = Int32, y = Int32}),
            spawnGrid    = safe,
            // map-test では合成しないので床範囲 = gridSize 全体の単一部屋（idx=0=anchor）。
            // idx>=1 にならないので StairsScene.placeRandom の対象外。
            placements   = singleRoom(gs#x, gs#y),
            roomCount    = 1
        };
        scene
            |> Scene.addNode(floorName(),
                              EngineNode.TileMapLayerWithState(floorLayer, NodeTag.NoTag))
            |> Scene.addNode(name(),
                              EngineNode.TileMapLayerWithState(wallsLayer, NodeTag.Map(mapData)))
            |> addWorldNode

    /// `preferred` セルが床ならそれを返し、壁ならグリッド内の最初の床セルを線形探索する。
    /// 全セル壁の場合は (0,0) を返す (実用上ありえない)。
    def findFirstFloor(walls: List[Vec2.Vec2],
                        gridSize: {x = Int32, y = Int32},
                        preferred: {x = Int32, y = Int32}): {x = Int32, y = Int32} =
        let isWall = c -> List.exists(w ->
            Float64.tryToInt32(w#x) == Some(c#x) and
            Float64.tryToInt32(w#y) == Some(c#y), walls);
        if (not isWall(preferred)) preferred
        else {
            let allCells = List.range(0, gridSize#y) |> List.flatMap(y ->
                List.range(0, gridSize#x) |> List.map(x -> ({x = x, y = y}: {x = Int32, y = Int32})));
            match List.find(c -> not isWall(c), allCells) {
                case Some(c) => c
                case None    => ({x = 0, y = 0}: {x = Int32, y = Int32})
            }
        }

    /// World ノード (Player / Enemy 等の Y-sort root) を scene に追加する。
    /// `MapScene.add` から呼ばれる本体内部経路。テストでも最小 scene を組むために流用する。
    pub def addWorldNode(scene: Scene[NodeTag]): Scene[NodeTag] =
        let worldMarker = Marker2D.make(Vec2.zero())
            |> CanvasItem.setYSortEnabled(true);
        Scene.addNode(worldName(),
                       EngineNode.Marker2DWithState(worldMarker, NodeTag.NoTag), scene)

    /// `MapScene.add` 後にのみ呼ぶことを前提とする。
    /// 呼び出し順に依存した破綻を早期検出するため、未登録なら即 bug! する。
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

    /// マップが無い文脈（カーソル可動域判定の単体テスト等）でも安全に placements を取れるよう、未登録なら Nil を返す。
    pub def tryGetPlacements(scene: Scene[NodeTag]): List[DungeonComposer.ModulePlacement] =
        match Scene.getEngineNode(mapPath(), scene) {
            case Some(EngineNode.TileMapLayerWithState(_, NodeTag.Map(data))) => data#placements
            case _ => Nil
        }

    /// 部屋数。`idx < roomCount` なら部屋、それ以外は通路と判定できる。
    pub def getRoomCount(scene: Scene[NodeTag]): Int32 =
        getMapData(scene)#roomCount

    /// 本物の TileMapLayer / Map global / placements → MapSnapshot へ射影する唯一の変換点。
    /// engine 内部表現（collisionCells が Float64 グリッド座標）への依存はここ 1 関数に閉じる。
    pub def snapshotOf(layer: TileMapLayer,
                       mapGlobal: {x = Float64, y = Float64},
                       placements: List[DungeonComposer.ModulePlacement]): MapSnapshot =
        let TileMapLayer.TileMapLayer(r) = layer;
        {
            tileSize   = TileMapLayer.tileSize(layer),
            usedRect   = TileMapLayer.getUsedRect(layer),
            wallCells  = r#collisionCells |> List.map(toGridCell) |> List.toSet,
            mapGlobal  = mapGlobal,
            placements = placements
        }

    /// 壁セルの Float64 座標を整数グリッドへ。collisionCells はタイルグリッド由来で整数 Float64 が
    /// 保証される（engine getCellSourceId/getUsedRect が整数前提）。非整数が来たら盤面衝突が静かに
    /// 欠落するので、握りつぶさず即落とす。
    def toGridCell(v: {x = Float64, y = Float64}): (Int32, Int32) =
        match (Float64.tryToInt32(v#x), Float64.tryToInt32(v#y)) {
            case (Some(x), Some(y)) => (x, y)
            case _ => bug!("MapScene.snapshotOf: non-integer collision cell (${v#x}, ${v#y})")
        }

    /// テスト・map-test・診断で全床の素朴な部屋を素早く組むための共通構築点。
    pub def placement(idx: Int32, ox: Int32, oy: Int32, w: Int32, h: Int32):
            DungeonComposer.ModulePlacement =
        {
            idx              = idx,
            offset           = ({x = ox, y = oy}: {x = Int32, y = Int32}),
            gridSize         = ({x = w,  y = h }: {x = Int32, y = Int32}),
            floorBoundsMin   = ({x = 0,  y = 0 }: {x = Int32, y = Int32}),
            floorBoundsMaxEx = ({x = w,  y = h }: {x = Int32, y = Int32}),
            interiorCells    = (Nil: List[{x = Int32, y = Int32}])
        }

    /// 全床 w×h を単一モジュール(idx=0)に割る placements。
    pub def singleRoom(w: Int32, h: Int32): List[DungeonComposer.ModulePlacement] =
        placement(0, 0, 0, w, h) :: Nil

    /// floorBounds を左右に分割した 2 モジュール（idx0 / idx1）の placements。
    /// 検知テスト（同じ部屋にいるか）で moduleOfCell を 2 部屋にしたいときに使う。
    pub def twoRoom(w: Int32, h: Int32): List[DungeonComposer.ModulePlacement] =
        let half = w / 2;
        ({idx = 0, offset = ({x = 0, y = 0}: {x = Int32, y = Int32}),
          gridSize = ({x = w, y = h}: {x = Int32, y = Int32}),
          floorBoundsMin = ({x = 0, y = 0}: {x = Int32, y = Int32}),
          floorBoundsMaxEx = ({x = half, y = h}: {x = Int32, y = Int32}),
          interiorCells = (Nil: List[{x = Int32, y = Int32}])}: DungeonComposer.ModulePlacement) ::
        ({idx = 1, offset = ({x = 0, y = 0}: {x = Int32, y = Int32}),
          gridSize = ({x = w, y = h}: {x = Int32, y = Int32}),
          floorBoundsMin = ({x = half, y = 0}: {x = Int32, y = Int32}),
          floorBoundsMaxEx = ({x = w, y = h}: {x = Int32, y = Int32}),
          interiorCells = (Nil: List[{x = Int32, y = Int32}])}: DungeonComposer.ModulePlacement) :: Nil

    /// 発見演出で「部屋の中心にカメラを寄せる」ために使う。
    /// floorBounds の bbox 計算を `moduleOfCellIn` と一致させることで、境界判定との一貫性を保つ。
    pub def moduleCenter(idx: Int32,
                          placements: List[DungeonComposer.ModulePlacement]):
            Option[{x = Int32, y = Int32}] =
        List.findMap(p ->
            if (p#idx == idx) {
                let minX = p#offset#x + p#floorBoundsMin#x;
                let minY = p#offset#y + p#floorBoundsMin#y;
                let maxX = p#offset#x + p#floorBoundsMaxEx#x;
                let maxY = p#offset#y + p#floorBoundsMaxEx#y;
                Some(({x = (minX + maxX - 1) / 2,
                       y = (minY + maxY - 1) / 2}: {x = Int32, y = Int32}))
            } else None,
            placements)

    def getMapData(scene: Scene[NodeTag]): Data =
        match Scene.getEngineNode(mapPath(), scene) {
            case Some(EngineNode.TileMapLayerWithState(_, NodeTag.Map(data))) => data
            case _ => bug!("MapScene: NodeTag.Map not found at ${mapPath()}")
        }
}
