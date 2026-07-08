/// MapSetup — ダンジョンマップを純粋な値（MapSnapshot / Plan / TileLayerHandle）として確定し、
/// World store へ seed する build choke の部品。
///
/// scene にはマップのノードを積まない。地形（壁・placements）は `World.terrainOf`、Plan と
/// スポーン起点は `World.mapLayoutOf`、背景タイルの描画は `World.tileLayersOf` を各読み手が読む。
/// GPU タイル bake（`initTileBuffer`）は DungeonComposer / MapLoader が行い、ここではその結果の
/// TileLayer 値を軽量ハンドル（TileLayerHandle）へ射影するだけ。
///
/// 経路は 2 本:
///   - `build(floor)`     — DungeonGenerator で Plan を乱数生成して組む（通常のフロア進入）。
///   - `buildFromPlan(p)` — 保存済み Plan から乱数を使わず決定論再構築する（中断再開 / 全滅復帰）。
/// どちらも `Built` を返し、`seed` が World へ 3 つの Cmd（SetMapSnapshot / SetMapLayout /
/// SetTileLayers）を emit する。
mod MapSetup {
    import java.lang.{System => JSystem}

    /// マップ確定の成果物。terrain（壁・placements・座標系）/ layout（Plan＋スポーン起点）/
    /// handles（背景タイルの描画ハンドル・floor 層が先）。
    pub type alias Built = {
        terrain = MapSnapshot,
        layout  = MapLayout,
        handles = List[TileLayerHandle]
    }

    /// Walls / Floor 共通テクスチャ名（n-format は両層で同一タイルセットを使う）。
    def textureName(): String = "tileset_dungeon_green"

    /// フロア定義からマップを確定する。FE_ROGUE_MODE=map-test のときはランダム生成と
    /// DungeonComposer をバイパスして単一 .map.json (room_1) を描画する（視覚一致確認用）。
    pub def build(floor: FloorCatalog.FloorResource): Built
            \ {GameEngine.Game, Fs.FileRead, Math.Random, IO} =
        let modeStr = unsafe IO { JSystem.getenv("FE_ROGUE_MODE") };
        let isMapTest = not Object.isNull(modeStr) and modeStr == "map-test";
        if (isMapTest) fromMapJson(AssetPath.resolve("assets/maps/room_1.map.json"))
        else           buildFromPlan(DungeonGenerator.generate(textureName(), generatorConfig(floor)))

    /// `DungeonGenerator.Plan` から **乱数を使わず** マップを確定する。`composeFromSideConnections`
    /// は Math.Random 非依存ゆえ決定論的で、同一 Plan からは必ず同一マップになる
    /// （スナップショット復元 / 中断ロードもこの経路）。
    pub def buildFromPlan(plan: DungeonGenerator.Plan): Built
            \ {GameEngine.Game, Fs.FileRead} =
        let result = DungeonComposer.composeFromSideConnections(textureName(),
                                                                 plan#modulePaths,
                                                                 plan#sideConnections);
        // Floor 層は Walls の下（zIndex = -1）に重ねる。
        let floorLayer = TileLayer.mapVisual(Visual.setZIndex(-1), result#floorLayer);
        {
            terrain = snapshotOfLayer(result#layer, result#placements),
            layout  = ({plan = plan, spawnGrid = result#spawnGrid}: MapLayout),
            handles = handleOf(floorLayer) :: handleOf(result#layer) :: Nil
        }

    /// 確定済みマップを World へ seed する（build choke 専用）。spawn 系（Player / Enemy /
    /// アイテム / 宝箱 / 階段）はこの後に World を読んで配置する。
    pub def seed(built: Built): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetMapSnapshot(Some(built#terrain)));
        World.Command.emit(World.Cmd.SetMapLayout(Some(built#layout)));
        World.Command.emit(World.Cmd.SetTileLayers(built#handles))

    /// ダンジョン退場（Title / CharacterSelect へ抜ける）時のマップ store 掃除。
    /// 地形 / Plan を None に、タイルハンドルを空にする（存在ゲートが盤面レスと判定する源）。
    pub def clear(): Unit \ World.Command =
        World.Command.emit(World.Cmd.SetMapSnapshot(None));
        World.Command.emit(World.Cmd.SetMapLayout(None));
        World.Command.emit(World.Cmd.SetTileLayers(Nil))

    /// 視覚一致確認用ルート: 単一 .map.json を MapLoader 経由で確定する。
    /// DungeonComposer を通さないためタイル自動結合ルールが再評価されない。
    /// Player 配置は最小ダミー（spawnGrid を level 内の安全セルに固定）。
    pub def fromMapJson(levelPath: String): Built \ {GameEngine.Game, Fs.FileRead} =
        // Walls 層 (manualTiles + collisionCells): loadLevelRaw で raw を取って手動で GPU upload
        let raw = MapLoader.loadLevelRaw(levelPath, textureName());
        let instances = TileRendering.buildTileInstances(raw#tiles, raw#tileSet, raw#tileSize);
        let (tileVaoId, tileCount) = GameEngine.Game.initTileBuffer(instances);
        let wallsLayer = TileLayer.make({
            tileSet        = raw#tileSet,
            tiles          = raw#tiles,
            collisionCells = raw#collisionCells,
            gridSize       = raw#gridSize
        }) |> TileLayer.withGpuResources(tileVaoId, tileCount);
        // Floor 装飾層 (decorTiles): Walls と同テクスチャ、Walls の下 (zIndex=-1) に重ねる
        let floorLayer = MapLoader.loadDecorLayer(levelPath, textureName())
            |> TileLayer.mapVisual(Visual.setZIndex(-1));
        let gs = raw#gridSize;
        // 簡易 spawn: (3, 3) が床であることが多い。床でなければ最初の床セルを使う。
        let safe = findFirstFloor(raw#collisionCells, gs, ({x = 3, y = 3}: {x = Int32, y = Int32}));
        // map-test では合成しないので床範囲 = gridSize 全体の単一部屋（idx=0=anchor・部屋数 1）。
        // Plan は単一モジュールの placeholder（スナップショット復元の対象外）。
        let plan: DungeonGenerator.Plan =
            {modulePaths = levelPath :: Nil, sideConnections = Nil, roomCount = 1};
        {
            terrain = snapshotOfLayer(wallsLayer, RoomLayout.singleRoom(gs#x, gs#y)),
            layout  = ({plan = plan, spawnGrid = safe}: MapLayout),
            handles = handleOf(floorLayer) :: handleOf(wallsLayer) :: Nil
        }

    /// TileLayer 値 → 軽量描画ハンドル。`worldPos` はレイヤーの transform 位置
    /// （マップは常に原点に置く＝camera 適用は描画側）。color / zIndex はレイヤー生値。
    def handleOf(layer: TileLayer): TileLayerHandle =
        let TileLayer.TileLayer(r) = layer;
        { textureName = r#tileSet#atlasSource#textureName,
          tileSize    = r#tileSet#atlasSource#tileSize,
          worldPos    = r#transform#position,
          color       = r#visual#modulate,
          zIndex      = r#visual#zIndex,
          tileVaoId   = r#tileVaoId,
          tileCount   = r#tileCount }

    /// Walls 層の TileLayer 値と placements → MapSnapshot（純粋データ地形）への射影。
    /// engine 内部表現（collisionCells が Float64 グリッド座標）への依存はここに閉じる。
    /// mapGlobal はレイヤーの transform 位置（マップは常に原点）。
    def snapshotOfLayer(walls: TileLayer,
                        placements: List[DungeonComposer.ModulePlacement]): MapSnapshot =
        let TileLayer.TileLayer(r) = walls;
        snapshotOf(walls, r#transform#position, placements)

    /// TileLayer 値 / Map global / placements → MapSnapshot へ射影する唯一の変換点。
    /// pub: テストが実 TileLayer 値から地形 fixture を組むのに使う。
    pub def snapshotOf(layer: TileLayer,
                       mapGlobal: {x = Float64, y = Float64},
                       placements: List[DungeonComposer.ModulePlacement]): MapSnapshot =
        let TileLayer.TileLayer(r) = layer;
        {
            tileSize   = TileLayer.tileSize(layer),
            usedRect   = TileLayer.getUsedRect(layer),
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
            case _ => bug!("MapSetup.snapshotOf: non-integer collision cell (${v#x}, ${v#y})")
        }

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
}
