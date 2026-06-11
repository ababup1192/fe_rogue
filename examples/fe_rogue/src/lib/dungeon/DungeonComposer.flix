/// 複数の `.map.json` モジュール（部屋・通路）を 1 つの dungeon にマージする。
///
/// **n-format 設計**
///   - room の Door は空セルで配置される → 合成時に Door 位置へ床 decorTile を追加し、
///     1 マスの出っ張りを作る。anchor 部屋の `material.json` の `autoRules`
///     （右出っ張り右壁キャップ等）がその周辺に装飾タイルを描く。
///   - pathway の Door も空セル。floor は Door の 1 マス先から始まる。
///   - door A と door B を「同じ合成座標で重ねる」ことで、room の出っ張り floor と
///     pathway の空 door セルが同一セルになり、シームレスに繋がる。
///
/// 出力は Walls 層と Floor 層を別々の TileMapLayer として返す。
/// テクスチャは全モジュール共通（呼び出し側が 1 つの textureName を指定）。
///
/// **API**
///   - 高レベル: `composeFromSideConnections(textureName, modulePaths, sideConnections)` —
///     Door を `DoorSide` 列挙で指定。Composer が min/max で grid 座標に解決。
///   - 中レベル: `composeFromConnections(textureName, modulePaths, connections)` —
///     Door を `DoorRef` (moduleIndex + grid) で指定。
///   - メタ取得: `loadLevelRawDispatch(path, textureName)` —
///     DungeonGenerator が gridSize と doors のみを得るためのローダー（new pipeline では未使用）。
mod DungeonComposer {

    /// 1 モジュールの配置仕様。
    /// `ldtkPath` フィールド名は歴史的経緯。`.map.json` を渡す。
    pub type alias ModuleSpec = {
        ldtkPath   = String,
        offsetGrid = {x = Int32, y = Int32}
    }

    /// `.map.json` を読み込んで `TileLevelRaw` を返すローダー。
    /// LDTK 削除 (段階 4 後段) で `.ldtkl` 分岐を消し、`.map.json` 専用になった。
    pub def loadLevelRawDispatch(path: String, textureName: String): TileRendering.TileLevelRaw
            \ { GameEngine.Game, Fs.FileRead } =
        MapLoader.loadLevelRaw(path, textureName)

    /// あるモジュール内の特定の Door を指す参照。
    /// moduleIndex は composeFromConnections の modulePaths 上の 0-base index。
    /// grid はそのモジュールのローカル grid 座標。
    pub type alias DoorRef = {
        moduleIndex = Int32,
        grid        = {x = Int32, y = Int32}
    }

    /// 2 つの Door を「同じワールド座標に重ねる」連結指示。
    pub type alias Connection = {
        a = DoorRef,
        b = DoorRef
    }

    /// 配置済み 1 モジュールのワールド bbox。
    /// - `gridSize` はモジュールの literal 寸法（`.map.json` の width × height）。
    /// - `floorBoundsMin/MaxEx` はモジュール内の **decorTiles ∪ doors** の bbox（モジュール局所座標、
    ///   半開区間）。n-format では `gridSize` が床まわりの余白を含むため、セル所有判定
    ///   （moduleOfCell / 敵・アイテムのスポーン候補）には floorBounds を使う。
    /// - `interiorCells` はモジュールの decorTiles をワールド座標化したリスト
    ///   （door は含まない = 部屋の純粋な内部床セル）。bbox では door や壁を巻き込むので、
    ///   「部屋の中のセルだけが欲しい」場合（階段の配置など）はこちらを使う。
    pub type alias ModulePlacement = {
        idx              = Int32,
        offset           = {x = Int32, y = Int32},
        gridSize         = {x = Int32, y = Int32},
        floorBoundsMin   = {x = Int32, y = Int32},
        floorBoundsMaxEx = {x = Int32, y = Int32},
        interiorCells    = List[{x = Int32, y = Int32}]
    }

    /// 合成結果。
    /// - `layer` は Walls 層（自動壁 + autoRules、collisionCells あり）
    /// - `floorLayer` は Floor 層（decorTiles + door 出っ張り床、collisionCells なし）
    ///   呼び出し側が `zIndex = -1` を設定して Walls 層の下に重ねる。
    pub type alias ComposeResult = {
        layer        = TileMapLayer,
        floorLayer   = TileMapLayer,
        anchorOffset = {x = Int32, y = Int32},
        spawnGrid    = {x = Int32, y = Int32},
        moduleSpecs  = List[ModuleSpec],
        placements   = List[ModulePlacement]
    }

    /// モジュール 1 個をロードした内部表現。
    /// - `levelData` は decorTiles / entities / materialId を含む `MapResource.LevelData`
    /// - `doors`     は entities から `identifier == "Door"` を filter したもの
    /// - `floorSrc`  は decorTiles 先頭からサンプルした (srcX, srcY)。Door 出っ張り床に使う。
    type alias LoadedModule = {
        path      = String,
        levelData = MapResource.LevelData,
        doors     = List[{x = Int32, y = Int32}],
        floorSrc  = (Int32, Int32)
    }

    // ════════════════════════════════════════════════════════
    // 高レベル / 中レベル API
    // ════════════════════════════════════════════════════════

    /// Side ベースで連結を指定する高レベル API。
    /// 各 SideRef を `(moduleIndex, grid)` の DoorRef に解決してから内部で合成する。
    pub def composeFromSideConnections(textureName: String,
                                        modulePaths: List[String],
                                        sideConnections: List[SideConnection]): ComposeResult
            \ { GameEngine.Game, Fs.FileRead } =
        let n = List.length(modulePaths);
        if (n == 0) bug!("DungeonComposer: modulePaths must not be empty")
        else
            let loaded = List.map(loadModule, modulePaths);
            let connections = List.map(sc -> ({
                a = resolveSideRef(sc#a, loaded, n),
                b = resolveSideRef(sc#b, loaded, n)
            }: Connection), sideConnections);
            composeFromLoaded(textureName, modulePaths, loaded, connections)

    /// Door の grid 座標を直接指定する中レベル API。
    pub def composeFromConnections(textureName: String,
                                    modulePaths: List[String],
                                    connections: List[Connection]): ComposeResult
            \ { GameEngine.Game, Fs.FileRead } =
        let n = List.length(modulePaths);
        if (n == 0) bug!("DungeonComposer: modulePaths must not be empty")
        else
            let loaded = List.map(loadModule, modulePaths);
            composeFromLoaded(textureName, modulePaths, loaded, connections)

    /// 内部本体: loaded モジュール + connections から ComposeResult を構築する。
    def composeFromLoaded(textureName: String,
                           modulePaths: List[String],
                           loaded: List[LoadedModule],
                           connections: List[Connection]): ComposeResult
            \ { GameEngine.Game, Fs.FileRead } =
        let n = List.length(modulePaths);
        // 1. 連結整合性検査
        let _ = validateConnections(connections, loaded, n);
        // 2. BFS で offsetGrid 解決
        let rawOffsets = bfsOffsets(connections);
        // 3. 孤立モジュール検査
        let _ = List.forEach(i ->
            match Map.get(i, rawOffsets) {
                case Some(_) => ()
                case None    => bug!("DungeonComposer: module ${i} is not connected to anchor (modulePaths[0])")
            }, List.range(0, n));
        // 4. 正規化: 全 offsets の min を (0,0) に揃える
        let minOff   = computeMinOffset(rawOffsets);
        let shift    = Vec2i.sub(Vec2i.zero(), minOff);
        let offsets  = shiftOffsets(rawOffsets, shift);
        let anchorOffset = lookupOffset(0, offsets);
        // 5. anchor の Material を読み込む（全体に適用）
        let anchorLoaded = match List.head(loaded) {
            case Some(l) => l
            case None    => bug!("DungeonComposer: loaded is empty")
        };
        let anchorMaterial = loadAnchorMaterial(anchorLoaded);
        let doorFloorSrc = anchorLoaded#floorSrc;
        let tileSizeI = anchorLoaded#levelData#tileSize;
        let tileSize  = Int32.toFloat64(tileSizeI);
        // 6. spawnGrid（anchor 内の床セルでセンターに最近）
        let spawnGrid = findSpawnInAnchor(anchorLoaded, anchorOffset);
        // 7. ModuleSpec / ModulePlacement
        let modules = buildModuleSpecs(modulePaths, offsets);
        let placements = buildPlacements(loaded, offsets);
        // 8. 連結開口部（ドアが一致するセル）。1/2 マス幅の開口セル集合。
        let openingCells = collectSharedDoorCells(loaded, offsets, connections);
        // 8b. mergedFloor（world 座標 + door 出っ張り床追加）
        let mergedFloor = buildMergedFloor(loaded, offsets, connections, doorFloorSrc);
        // 8c. mergedManual（各モジュール固有の manualTiles を world 座標へ）。
        //     ただし開口部セルに重なる manualTile は除外する。
        //     部屋のドア位置に手置き壁（蔦壁など）があると、出っ張り床で開けても
        //     manualTile が collisionCells に入って通行不能になってしまうため、
        //     開口部では床を優先して manualTile を消す（壁チップの種類は問わない）。
        let mergedManual = buildMergedManual(loaded, offsets)
            |> List.filter(t -> not List.exists(c -> c#x == t#x and c#y == t#y, openingCells));
        // 9. 合成 grid 寸法
        let mergedGridSize = boundingBoxGridSize(loaded, offsets);
        // 10. TileSet（テクスチャ共通）
        let tileSet = buildTileSet(textureName, tileSize);
        // 11. Floor / Walls 層構築
        let floorLayer = buildFloorLayer(mergedFloor, mergedGridSize, tileSet, tileSize);
        let wallsLayer = buildWallsLayer(mergedFloor, mergedManual, mergedGridSize, anchorMaterial,
                                          tileSet, tileSize, tileSizeI);
        ({
            layer        = wallsLayer,
            floorLayer   = floorLayer,
            anchorOffset = anchorOffset,
            spawnGrid    = spawnGrid,
            moduleSpecs  = modules,
            placements   = placements
        }: ComposeResult)

    // ────────────────────────────────────────────────────────
    // モジュールロード
    // ────────────────────────────────────────────────────────

    /// `.map.json` を `MapResource.Level` として読み込み、内部 LoadedModule に変換する。
    def loadModule(path: String): LoadedModule \ Fs.FileRead =
        let levelOpt: Option[MapResource.Level] = Persistence.load(path);
        let level = match levelOpt {
            case Some(l) => l
            case None    => bug!("DungeonComposer: failed to load level ${path}")
        };
        let d = MapResource.levelData(level);
        let doors = d#entities
            |> List.filter(e -> e#identifier == "Door")
            |> List.map(e -> ({x = e#x, y = e#y}: {x = Int32, y = Int32}));
        let floorSrc = sampleFloorSrc(d);
        ({path = path, levelData = d, doors = doors, floorSrc = floorSrc}: LoadedModule)

    /// decorTiles 先頭から (srcX, srcY) を取り出す。空なら (0, 0)
    /// （pathway 等の床なしモジュール用。Door 出っ張り床のサンプルは anchor からのみ取るため未使用）。
    def sampleFloorSrc(d: MapResource.LevelData): (Int32, Int32) =
        match List.head(d#decorTiles) {
            case Some(t) => (t#srcX, t#srcY)
            case None    => (0i32, 0i32)
        }

    /// anchor の materialId から `.material.json` のパスを組み立てて読み込む。
    def loadAnchorMaterial(anchor: LoadedModule): MapResource.Material \ Fs.FileRead =
        let materialPath = MapLoader.materialPathFor(anchor#path, anchor#levelData#materialId);
        let matOpt: Option[MapResource.Material] = Persistence.load(materialPath);
        match matOpt {
            case Some(m) => m
            case None    => bug!("DungeonComposer: failed to load material ${materialPath}")
        }

    // ────────────────────────────────────────────────────────
    // 床マージ + door 出っ張り床追加
    // ────────────────────────────────────────────────────────

    /// 各モジュールの decorTiles を world 座標へ変換し、先勝ち dedup でマージ。
    /// その後、連結された 2 モジュールの **ドアがワールド座標で一致するセルすべて** に
    /// door 出っ張り床を追加する。1 マス幅通路なら 1 セル、2 マス幅通路（隣接ドア 2 枚）なら
    /// 2 セルとなり、通路の幅に応じた開口部が自動的にできる。
    /// door 床の srcX/srcY は anchor の floorSrc を使う。
    def buildMergedFloor(loaded: List[LoadedModule],
                          offsets: Map[Int32, {x = Int32, y = Int32}],
                          connections: List[Connection],
                          doorFloorSrc: (Int32, Int32)): List[MapResource.ManualTile] =
        let (_, baseTiles) = List.foldLeft(acc -> lm -> {
            let (i, list) = acc;
            let off = lookupOffset(i, offsets);
            let shifted: List[MapResource.ManualTile] = List.map(t -> ({
                x     = t#x + off#x,
                y     = t#y + off#y,
                srcX  = t#srcX,
                srcY  = t#srcY,
                flipH = t#flipH,
                flipV = t#flipV
            }: MapResource.ManualTile), lm#levelData#decorTiles);
            let newTiles = List.filter(t -> not List.exists(a ->
                a#x == t#x and a#y == t#y, list), shifted);
            (i + 1, List.append(list, newTiles))
        }, (0, Nil), loaded);
        let (sx, sy) = doorFloorSrc;
        let doorCells = collectSharedDoorCells(loaded, offsets, connections);
        List.foldLeft(acc -> cell -> {
            if (List.exists(t -> t#x == cell#x and t#y == cell#y, acc))
                acc
            else {
                let tile: MapResource.ManualTile = {
                    x     = cell#x,
                    y     = cell#y,
                    srcX  = sx,
                    srcY  = sy,
                    flipH = false,
                    flipV = false
                };
                List.append(acc, tile :: Nil)
            }
        }, baseTiles, doorCells)

    /// 連結された各モジュールペアについて、両モジュールのドアが
    /// ワールド座標で一致するセルを列挙する（= 実際に開口部となる連結点）。
    /// ドア選択を `betterDoorForSide` で決定的に揃えてあるため、隣接する 2 枚の
    /// ドアペアは連結時にそろって一致し、ここで 2 セルとも検出される。
    def collectSharedDoorCells(loaded: List[LoadedModule],
                                offsets: Map[Int32, {x = Int32, y = Int32}],
                                connections: List[Connection]):
            List[{x = Int32, y = Int32}] =
        List.foldLeft(acc -> c -> {
            let doorsA = doorsWorldOf(c#a#moduleIndex, loaded, offsets);
            let doorsB = doorsWorldOf(c#b#moduleIndex, loaded, offsets);
            let shared = List.filter(da ->
                List.exists(db -> db#x == da#x and db#y == da#y, doorsB), doorsA);
            List.append(acc, shared)
        }, Nil, connections)

    /// 指定モジュールの全ドアをワールド座標に変換して返す。
    def doorsWorldOf(idx: Int32,
                      loaded: List[LoadedModule],
                      offsets: Map[Int32, {x = Int32, y = Int32}]):
            List[{x = Int32, y = Int32}] =
        let off = lookupOffset(idx, offsets);
        match List.nth(idx, loaded) {
            case Some(lm) => List.map(d -> ({x = d#x + off#x,
                                             y = d#y + off#y}: {x = Int32, y = Int32}), lm#doors)
            case None     => Nil
        }

    /// 各モジュールの manualTiles（手置きの壁・装飾）を world 座標へ変換し、
    /// 先勝ち dedup でマージする。decorTiles と違い door 出っ張り床は足さない
    /// （manualTiles はモジュール固有のレイアウトをそのまま重ねるだけ）。
    /// 4 部屋は decorTiles が同一で manualTiles だけが異なるため、これを描かないと
    /// 全部屋が同じ見た目になる（合成経路で部屋差が消える原因）。
    def buildMergedManual(loaded: List[LoadedModule],
                          offsets: Map[Int32, {x = Int32, y = Int32}]): List[MapResource.ManualTile] =
        let (_, tiles) = List.foldLeft(acc -> lm -> {
            let (i, list) = acc;
            let off = lookupOffset(i, offsets);
            let shifted: List[MapResource.ManualTile] = List.map(t -> ({
                x     = t#x + off#x,
                y     = t#y + off#y,
                srcX  = t#srcX,
                srcY  = t#srcY,
                flipH = t#flipH,
                flipV = t#flipV
            }: MapResource.ManualTile), lm#levelData#manualTiles);
            let newTiles = List.filter(t -> not List.exists(a ->
                a#x == t#x and a#y == t#y, list), shifted);
            (i + 1, List.append(list, newTiles))
        }, (0, Nil), loaded);
        tiles

    /// 配置済みモジュール群のワールド bbox 右下端を求める。
    /// 各モジュールの (offset + gridSize) の max を取る。
    def boundingBoxGridSize(loaded: List[LoadedModule],
                             offsets: Map[Int32, {x = Int32, y = Int32}]): {x = Int32, y = Int32} =
        let (_, result) = List.foldLeft(acc -> lm -> {
            let (i, agg) = acc;
            let off = lookupOffset(i, offsets);
            let rbx = off#x + lm#levelData#width;
            let rby = off#y + lm#levelData#height;
            let next: {x = Int32, y = Int32} = ({
                x = Int32.max(agg#x, rbx),
                y = Int32.max(agg#y, rby)
            }: {x = Int32, y = Int32});
            (i + 1, next)
        }, (0, Vec2i.zero()), loaded);
        result

    // ────────────────────────────────────────────────────────
    // Layer 構築
    // ────────────────────────────────────────────────────────

    /// 共通 TileSet を構築する（全モジュール同一テクスチャ前提）。
    def buildTileSet(textureName: String, tileSize: Float64): TileSet \ GameEngine.Game =
        let texInfo = match GameEngine.Game.getTextureInfo(textureName) {
            case Some(info) => info
            case None       => bug!("DungeonComposer: texture '${textureName}' not registered")
        };
        let atlas = TileSetAtlasSource.make({
            textureName = textureName,
            marginX     = 0.0,
            marginY     = 0.0,
            spacingX    = 0.0,
            spacingY    = 0.0
        });
        let atlasFilled: TileSetAtlasSource = {
            texWidth  = texInfo#width,
            texHeight = texInfo#height,
            tileSize  = tileSize
            | atlas
        };
        TileSet.make(atlasFilled)

    /// Floor 層を構築する。decorTiles + door 出っ張り床を描画、衝突なし。
    def buildFloorLayer(mergedFloor: List[MapResource.ManualTile],
                         gridSize: {x = Int32, y = Int32},
                         tileSet: TileSet,
                         tileSize: Float64): TileMapLayer \ GameEngine.Game =
        let tiles: List[TileData] = List.map(t -> ({
            px    = ({x = Int32.toFloat64(t#x) * tileSize,
                      y = Int32.toFloat64(t#y) * tileSize}: Vec2.Vec2),
            srcX  = Int32.toFloat64(t#srcX),
            srcY  = Int32.toFloat64(t#srcY),
            flipH = t#flipH,
            flipV = t#flipV,
            alpha = 1.0f32
        }: TileData), mergedFloor);
        let instances = TileRendering.buildTileInstances(tiles, tileSet, tileSize);
        let (vao, count) = GameEngine.Game.initTileBuffer(instances);
        TileMapLayer.make({
            tileSet        = tileSet,
            tiles          = tiles,
            collisionCells = (Nil: List[Vec2.Vec2]),
            gridSize       = gridSize
        }) |> TileMapLayer.withGpuResources(vao, count)

    /// Walls 層を構築する。
    /// 1. mergedFloor から floorMask を計算
    /// 2. computeWallCells で自動壁セルを抽出
    /// 3. material#wallMap で各 wall セルのタイルを決定
    /// 4. material#autoRules で装飾タイルを overlay（manualTiles のセルは除外）
    /// 5. mergedManual（各モジュール固有の手置きタイル）を最前面に重ねる
    /// 6. 衝突セル = wallCells ∪ manualTiles のセル
    ///    （door 出っ張り床のおかげで door 位置は floor になり通れる）
    def buildWallsLayer(mergedFloor: List[MapResource.ManualTile],
                         mergedManual: List[MapResource.ManualTile],
                         gridSize: {x = Int32, y = Int32},
                         material: MapResource.Material,
                         tileSet: TileSet,
                         tileSize: Float64,
                         tileSizeI: Int32): TileMapLayer \ GameEngine.Game =
        let md = MapResource.materialData(material);
        let floorMask: Set[(Int32, Int32)] =
            mergedFloor |> List.map(t -> (t#x, t#y)) |> List.toSet;
        let wallCells = MapLoader.computeWallCells(floorMask, gridSize#x, gridSize#y);
        let intGrid = MapLoader.buildIntGrid(floorMask, wallCells, gridSize#x, gridSize#y);
        let wallTiles: List[TileData] = wallCells
            |> Set.toList
            |> List.filterMap(coord -> {
                let (col, row) = coord;
                let coordOpt = MapLoader.lookupWallTile(wallCells, floorMask, md#wallMap, col, row);
                match coordOpt {
                    case None              => None
                    case Some((sx, sy)) => Some(({
                        px    = ({x = Int32.toFloat64(col * tileSizeI),
                                  y = Int32.toFloat64(row * tileSizeI)}: Vec2.Vec2),
                        srcX  = Int32.toFloat64(sx),
                        srcY  = Int32.toFloat64(sy),
                        flipH = false,
                        flipV = false,
                        alpha = 1.0f32
                    }: TileData))
                }
            });
        // manualTiles の占有セル: autoRules を抑止し、最前面に重ね、衝突にも使う
        let manualCoords: Set[(Int32, Int32)] =
            mergedManual |> List.map(t -> (t#x, t#y)) |> List.toSet;
        let manualTileData: List[TileData] = List.map(t -> ({
            px    = ({x = Int32.toFloat64(t#x * tileSizeI),
                      y = Int32.toFloat64(t#y * tileSizeI)}: Vec2.Vec2),
            srcX  = Int32.toFloat64(t#srcX),
            srcY  = Int32.toFloat64(t#srcY),
            flipH = t#flipH,
            flipV = t#flipV,
            alpha = 1.0f32
        }: TileData), mergedManual);
        let ruleTiles = MapLoader.buildAutoRuleTiles(intGrid, gridSize#x, gridSize#y,
                                                       md#autoRules, manualCoords, tileSizeI);
        // 重ね順: 自動壁 → autoRules → manualTiles（最前面、MapLoader と同じく手置き優先）
        let tiles = List.append(List.append(wallTiles, ruleTiles), manualTileData);
        // 衝突セル = wallCells ∪ manualTiles のセル
        let collisionSet: Set[(Int32, Int32)] = Set.union(wallCells, manualCoords);
        let collisionCells: List[Vec2.Vec2] = collisionSet
            |> Set.toList
            |> List.map(c -> {
                let (col, row) = c;
                ({x = Int32.toFloat64(col), y = Int32.toFloat64(row)}: Vec2.Vec2)
            });
        let instances = TileRendering.buildTileInstances(tiles, tileSet, tileSize);
        let (vao, count) = GameEngine.Game.initTileBuffer(instances);
        TileMapLayer.make({
            tileSet        = tileSet,
            tiles          = tiles,
            collisionCells = collisionCells,
            gridSize       = gridSize
        }) |> TileMapLayer.withGpuResources(vao, count)

    // ────────────────────────────────────────────────────────
    // Spawn / Placements / Offsets
    // ────────────────────────────────────────────────────────

    /// anchor の decorTiles で「中央に最も近い床セル」を選び、worldOffset 加算して返す。
    /// PlayerScene のスポーン地点に使う。decorTile が空なら bug!。
    /// manualTiles（衝突する手置きの壁）のセルは候補から除外し、プレイヤーが
    /// 壁に埋まってスタートするのを防ぐ。
    def findSpawnInAnchor(anchor: LoadedModule,
                           anchorOffset: {x = Int32, y = Int32}): {x = Int32, y = Int32} =
        let gridW = anchor#levelData#width;
        let gridH = anchor#levelData#height;
        let cx = gridW / 2;
        let cy = gridH / 2;
        let blocked: Set[(Int32, Int32)] =
            anchor#levelData#manualTiles |> List.map(t -> (t#x, t#y)) |> List.toSet;
        let tiles = anchor#levelData#decorTiles
            |> List.filter(t -> not Set.memberOf((t#x, t#y), blocked));
        match tiles {
            case Nil => bug!("DungeonComposer: anchor has no decorTile (no floor cell)")
            case head :: rest =>
                let distSq = t -> {
                    let dx = t#x - cx;
                    let dy = t#y - cy;
                    dx * dx + dy * dy
                };
                let best = List.foldLeft(acc -> t ->
                    if (distSq(t) < distSq(acc)) t else acc, head, rest);
                ({x = anchorOffset#x + best#x,
                  y = anchorOffset#y + best#y}: {x = Int32, y = Int32})
        }

    /// offsets の最小 (x, y) を求める（次元ごと別モジュール由来でも良い）。
    /// `pub`: 正規化（min を原点に揃える）の単体テスト用に公開。呼び先は持たない純関数。
    pub def computeMinOffset(offsets: Map[Int32, {x = Int32, y = Int32}]): {x = Int32, y = Int32} =
        Map.foldLeft(acc -> off -> {
            ({x = Int32.min(acc#x, off#x), y = Int32.min(acc#y, off#y)}: {x = Int32, y = Int32})
        }, ({x = 0i32, y = 0i32}: {x = Int32, y = Int32}), offsets)

    /// 全 offsets に shift を加える。`pub`: 正規化の単体テスト用に公開。
    pub def shiftOffsets(offsets: Map[Int32, {x = Int32, y = Int32}], shift: {x = Int32, y = Int32}):
                     Map[Int32, {x = Int32, y = Int32}] =
        Map.map(off -> Vec2i.add(shift, off), offsets)

    /// offsets から特定モジュールの offset を取り出す。未配置なら bug!。
    def lookupOffset(i: Int32, offsets: Map[Int32, {x = Int32, y = Int32}]): {x = Int32, y = Int32} =
        match Map.get(i, offsets) {
            case Some(o) => o
            case None    => bug!("DungeonComposer: no offset computed for module ${i}")
        }

    /// loaded と offsets を組み合わせて ModulePlacement リストを idx 順に作る。
    /// floorBounds は decorTiles ∪ doors の bbox（モジュール局所、半開区間）。
    /// interiorCells は decorTiles を offset 加算してワールド座標化したセル列。
    /// ただし manualTiles（= 衝突する手置きの壁・装飾）のセルは除外する。
    /// 階段・ドロップアイテムの配置候補に使われるため、壁の上に置いて
    /// 取得不能になるのを防ぐ（manualTiles は collisionCells に入っている）。
    def buildPlacements(loaded: List[LoadedModule],
                         offsets: Map[Int32, {x = Int32, y = Int32}]): List[ModulePlacement] =
        let (_, reversed) = List.foldLeft(acc -> lm -> {
            let (i, list) = acc;
            let off = lookupOffset(i, offsets);
            let (fbMin, fbMaxEx) = computeFloorBounds(lm);
            let blocked: Set[(Int32, Int32)] =
                lm#levelData#manualTiles |> List.map(t -> (t#x, t#y)) |> List.toSet;
            let interior: List[{x = Int32, y = Int32}] =
                lm#levelData#decorTiles
                    |> List.filter(t -> not Set.memberOf((t#x, t#y), blocked))
                    |> List.map(t -> ({x = t#x + off#x,
                                       y = t#y + off#y}: {x = Int32, y = Int32}));
            let p: ModulePlacement = ({
                idx              = i,
                offset           = off,
                gridSize         = ({x = lm#levelData#width,
                                     y = lm#levelData#height}: {x = Int32, y = Int32}),
                floorBoundsMin   = fbMin,
                floorBoundsMaxEx = fbMaxEx,
                interiorCells    = interior
            }: ModulePlacement);
            (i + 1, p :: list)
        }, (0, Nil), loaded);
        List.reverse(reversed)

    /// LoadedModule の decorTiles ∪ doors のセル集合に対する bbox を返す
    /// （モジュール局所座標、半開区間）。両方とも空のときは gridSize 全体にフォールバック。
    def computeFloorBounds(lm: LoadedModule):
                           ({x = Int32, y = Int32}, {x = Int32, y = Int32}) =
        let decorCells: List[{x = Int32, y = Int32}] =
            lm#levelData#decorTiles |> List.map(t -> ({x = t#x, y = t#y}: {x = Int32, y = Int32}));
        let allCells = List.append(decorCells, lm#doors);
        match allCells {
            case Nil =>
                let w = lm#levelData#width;
                let h = lm#levelData#height;
                (Vec2i.zero(), ({x = w, y = h}: {x = Int32, y = Int32}))
            case head :: rest =>
                let initMin: {x = Int32, y = Int32} = head;
                let initMax: {x = Int32, y = Int32} = ({x = head#x + 1, y = head#y + 1}: {x = Int32, y = Int32});
                List.foldLeft(acc -> c -> {
                    let (mn, mx) = acc;
                    let newMin: {x = Int32, y = Int32} = ({
                        x = Int32.min(mn#x, c#x),
                        y = Int32.min(mn#y, c#y)
                    }: {x = Int32, y = Int32});
                    let newMax: {x = Int32, y = Int32} = ({
                        x = Int32.max(mx#x, c#x + 1),
                        y = Int32.max(mx#y, c#y + 1)
                    }: {x = Int32, y = Int32});
                    (newMin, newMax)
                }, (initMin, initMax), rest)
        }

    /// modulePaths を offsets と組み合わせて ModuleSpec リスト（modulePaths 順を維持）。
    def buildModuleSpecs(modulePaths: List[String],
                          offsets: Map[Int32, {x = Int32, y = Int32}]): List[ModuleSpec] =
        let (_, reversed) = List.foldLeft(acc -> path -> {
            let (i, list) = acc;
            let off = lookupOffset(i, offsets);
            let spec: ModuleSpec = ({ ldtkPath = path, offsetGrid = off }: ModuleSpec);
            (i + 1, spec :: list)
        }, (0, Nil), modulePaths);
        List.reverse(reversed)

    // ────────────────────────────────────────────────────────
    // 連結検証
    // ────────────────────────────────────────────────────────

    def validateConnections(connections: List[Connection],
                             loaded: List[LoadedModule],
                             n: Int32): Unit =
        List.forEach(c -> {
            let _ = validateDoorRef(c#a, loaded, n);
            validateDoorRef(c#b, loaded, n)
        }, connections)

    def validateDoorRef(ref: DoorRef,
                         loaded: List[LoadedModule],
                         n: Int32): Unit =
        if (ref#moduleIndex < 0 or ref#moduleIndex >= n)
            bug!("DungeonComposer: moduleIndex ${ref#moduleIndex} out of range [0, ${n})")
        else
            let lm = match List.nth(ref#moduleIndex, loaded) {
                case Some(m) => m
                case None    => bug!("DungeonComposer: loaded lookup failed for index ${ref#moduleIndex}")
            };
            let exists = List.exists(d -> vec2EqI(d, ref#grid), lm#doors);
            if (not exists)
                bug!("DungeonComposer: door (${ref#grid#x},${ref#grid#y}) not found in module ${ref#moduleIndex}")
            else
                ()

    // ────────────────────────────────────────────────────────
    // BFS による offset 解決
    // ────────────────────────────────────────────────────────

    /// connections を BFS で辿り、modulePaths[0] をアンカー (0,0) として各モジュールの
    /// offsetGrid を算出する。既配置モジュールに到達した際に offset が食い違ったら bug!。
    /// `pub`: 接続→世界座標解決の単体テスト用に公開（呼び先 bfsLoop/lookupOffset は private のまま）。
    pub def bfsOffsets(connections: List[Connection]): Map[Int32, {x = Int32, y = Int32}] =
        let edges: List[(Int32, {x = Int32, y = Int32}, Int32, {x = Int32, y = Int32})] =
            List.flatMap(c -> {
                (c#a#moduleIndex, c#a#grid, c#b#moduleIndex, c#b#grid) ::
                (c#b#moduleIndex, c#b#grid, c#a#moduleIndex, c#a#grid) ::
                Nil
            }, connections);
        let initialOffsets = Map.empty() |> Map.insert(0, Vec2i.zero());
        bfsLoop(initialOffsets, 0 :: Nil, edges)

    def bfsLoop(offsets: Map[Int32, {x = Int32, y = Int32}],
                 queue: List[Int32],
                 edges: List[(Int32, {x = Int32, y = Int32}, Int32, {x = Int32, y = Int32})]):
                 Map[Int32, {x = Int32, y = Int32}] =
        match queue {
            case Nil => offsets
            case i :: rest =>
                let myOffset = lookupOffset(i, offsets);
                let (newOffsets, addedQueue) =
                    List.foldLeft(acc -> edge -> {
                        let (off, placedQueue) = acc;
                        let (src, gSrc, dst, gDst) = edge;
                        if (src != i) acc
                        else
                            // world(i.gSrc) = world(dst.gDst) を満たすには:
                            //   offsets[i] + gSrc = offsets[dst] + gDst
                            //   ∴ offsets[dst] = offsets[i] + gSrc - gDst
                            let expected = Vec2i.sub(Vec2i.add(myOffset, gSrc), gDst);
                            match Map.get(dst, off) {
                                case None =>
                                    (Map.insert(dst, expected, off), dst :: placedQueue)
                                case Some(existing) =>
                                    if (vec2EqI(existing, expected)) acc
                                    else bug!("DungeonComposer: inconsistent offset for module ${dst}: expected (${expected#x},${expected#y}) but already placed at (${existing#x},${existing#y})")
                            }
                    }, (offsets, Nil), edges);
                bfsLoop(newOffsets, List.append(rest, addedQueue), edges)
        }

    // ────────────────────────────────────────────────────────
    // Vec2i 等値ヘルパー
    // ────────────────────────────────────────────────────────

    def vec2EqI(a: {x = Int32, y = Int32}, b: {x = Int32, y = Int32}): Bool =
        a#x == b#x and a#y == b#y

    // ════════════════════════════════════════════════════════
    // DoorSide 列挙 + Side ベース解決
    // ════════════════════════════════════════════════════════

    /// モジュールの 4 辺を表す列挙。
    /// Composer が `doors` 一覧の min-x / max-x / min-y / max-y からそれぞれ
    /// Left / Right / Top / Bottom の Door を解決する。
    pub enum DoorSide with Eq {
        case Left
        case Right
        case Top
        case Bottom
    }

    /// 反対側の辺を返す（Right ↔ Left, Top ↔ Bottom）。通路の両端の連結に使う。
    pub def oppositeSide(side: DoorSide): DoorSide = match side {
        case DoorSide.Left   => DoorSide.Right
        case DoorSide.Right  => DoorSide.Left
        case DoorSide.Top    => DoorSide.Bottom
        case DoorSide.Bottom => DoorSide.Top
    }

    /// 左右辺かどうか。横通路（Pathway_1）と縦通路（Pathway_2）の選択に使う。
    pub def isHorizontalSide(side: DoorSide): Bool = match side {
        case DoorSide.Left  => true
        case DoorSide.Right => true
        case _              => false
    }

    /// 4 辺の全列挙。生成器が「空き辺」を走査するときに使う。
    pub def allSides(): List[DoorSide] =
        DoorSide.Left :: DoorSide.Right :: DoorSide.Top :: DoorSide.Bottom :: Nil

    /// Side 指定で Door を参照する。grid 座標は `composeFromSideConnections` が内部で解決する。
    pub type alias SideRef = {
        moduleIndex = Int32,
        side        = DoorSide
    }

    /// 2 つの SideRef の Door を「同じワールド座標に重ねる」連結指示。
    pub type alias SideConnection = {
        a = SideRef,
        b = SideRef
    }

    /// SideRef を DoorRef に解決する。範囲外 / Doors 空ならば bug!。
    def resolveSideRef(ref: SideRef,
                        loaded: List[LoadedModule],
                        n: Int32): DoorRef =
        if (ref#moduleIndex < 0 or ref#moduleIndex >= n)
            bug!("DungeonComposer: moduleIndex ${ref#moduleIndex} out of range [0, ${n})")
        else
            let lm = match List.nth(ref#moduleIndex, loaded) {
                case Some(m) => m
                case None    => bug!("DungeonComposer: loaded lookup failed for index ${ref#moduleIndex}")
            };
            let grid = pickDoorBySide(ref#side, lm#doors, ref#moduleIndex);
            ({moduleIndex = ref#moduleIndex, grid = grid}: DoorRef)

    /// Side 方向で「端」のドアを 1 枚、決定的に選ぶ。
    /// 主軸（Left/Right→x, Top/Bottom→y）で辺を決め、同一辺に複数ドアがある場合は
    /// 垂直軸（Left/Right→y, Top/Bottom→x）の最小値で一意に決める。
    /// 部屋側・通路側がともにペアの「先頭」ドアを選ぶことで、連結時に
    /// 隣接する 2 枚のドアペアがそのままワールド座標で重なり、2 マス幅連結が成立する。
    def betterDoorForSide(side: DoorSide,
                           a: {x = Int32, y = Int32},
                           b: {x = Int32, y = Int32}): {x = Int32, y = Int32} =
        match side {
            case DoorSide.Left   => if (b#x < a#x or (b#x == a#x and b#y < a#y)) b else a
            case DoorSide.Right  => if (b#x > a#x or (b#x == a#x and b#y < a#y)) b else a
            case DoorSide.Top    => if (b#y < a#y or (b#y == a#y and b#x < a#x)) b else a
            case DoorSide.Bottom => if (b#y > a#y or (b#y == a#y and b#x < a#x)) b else a
        }

    /// Side 指定で代表 Door grid 座標を 1 つ選ぶ（`betterDoorForSide` の畳み込み）。
    def pickDoorBySide(side: DoorSide,
                        doors: List[{x = Int32, y = Int32}],
                        moduleIndex: Int32): {x = Int32, y = Int32} =
        match doors {
            case Nil => bug!("DungeonComposer: module ${moduleIndex} has no Doors")
            case head :: rest =>
                List.foldLeft(acc -> d -> betterDoorForSide(side, acc, d), head, rest)
        }

    /// Generator 等の外部利用向けに公開した版。Doors 空なら None。
    pub def doorBySide(side: DoorSide, doors: List[{x = Int32, y = Int32}]):
                       Option[{x = Int32, y = Int32}] =
        match doors {
            case Nil => None
            case head :: rest =>
                Some(List.foldLeft(acc -> d -> betterDoorForSide(side, acc, d), head, rest))
        }
}
