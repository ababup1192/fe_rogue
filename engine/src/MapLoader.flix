/// `.map.json` (MapResource.Level) を読み TileMapLayer を構築する loader。
///
/// 役割:
///   - `wallMask` から TRBL を計算し `Material.wallMap` で AutoLayerWalls タイルに展開
///   - `manualTiles` は AutoLayerWalls の上書き層として最後に重ねる (同セル優先)
///   - `wallMask` の非ゼロセルを collisionCells に展開 (PhysicsStep が壁として扱う)
///   - `entities` のうち `identifier == "Door"` を doors として抽出
///
/// Material ファイルは `<projectRoot>/assets/materials/<materialId>.material.json`。
/// 見つからない場合は AutoLayerWalls タイルを生成せず、manualTiles のみで描画する
/// (既存マップとの後方互換)。
///
/// LDTKLoader と同じ `LDTKLevelRaw` を返すので、DungeonComposer 等の下流処理を
/// そのまま流用できる (将来 DungeonComposer に loader 注入で接続する計画)。
mod MapLoader {

    /// `.map.json` から TileMapLayer を 1 枚構築する。
    /// GPU upload まで完了した状態で返す。
    pub def loadLevel(mapPath: String, textureName: String): TileMapLayer
            \ { GameEngine.Game, Fs.FileRead } =
        let raw = loadLevelRaw(mapPath, textureName);
        let instances = LDTKLoader.buildTileInstances(raw#tiles, raw#tileSet, raw#tileSize);
        let (tileVaoId, tileCount) = GameEngine.Game.initTileBuffer(instances);
        TileMapLayer.make({
            tileSet        = raw#tileSet,
            tiles          = raw#tiles,
            collisionCells = raw#collisionCells,
            gridSize       = raw#gridSize
        }) |> TileMapLayer.withGpuResources(tileVaoId, tileCount)

    /// GPU upload 前の生データを返す。複数モジュールを合成する場合 (DungeonComposer 系) に使う。
    pub def loadLevelRaw(mapPath: String, textureName: String): LDTKLoader.LDTKLevelRaw
            \ { GameEngine.Game, Fs.FileRead } =
        let level = match Persistence.load(mapPath) {
            case Some(l) => l
            case None    => bug!("MapLoader: failed to load ${mapPath}")
        };
        let d = MapResource.levelData(level);
        let tileSizeI = d#tileSize;
        let tileSize  = Int32.toFloat64(tileSizeI);

        // Material をロード (見つからなければ None で AutoLayerWalls をスキップ)
        let materialOpt: Option[MapResource.Material] =
            Persistence.load(materialPathFor(mapPath, d#materialId));

        // 床マスク: decorTiles のあるセル = 床 (通行可)
        let floorMask: Set[(Int32, Int32)] =
            d#decorTiles |> List.map(t -> (t#x, t#y)) |> List.toSet;
        // 自動壁セル: 床なし + 8 近傍に床がある (ldtk Auto-Layer 流)
        let wallCells: Set[(Int32, Int32)] =
            computeWallCells(floorMask, d#width, d#height);

        // AutoLayerWalls タイル: wallCells を TRBL 計算 → Material.wallMap で展開
        // manualTiles と重なる座標は除外 (manualTiles を上書きとして優先)
        let manualCoords: Set[(Int32, Int32)] =
            d#manualTiles |> List.map(t -> (t#x, t#y)) |> List.toSet;
        let autoTiles: List[TileData] = match materialOpt {
            case None      => Nil
            case Some(mat) =>
                let md = MapResource.materialData(mat);
                buildAutoLayerTiles(wallCells, md, manualCoords, tileSizeI)
        };

        // manualTiles → TileData
        let manualTiles: List[TileData] = List.map(t -> {
            ({
                px    = ({x = Int32.toFloat64(t#x * tileSizeI),
                           y = Int32.toFloat64(t#y * tileSizeI)}: Vec2.Vec2),
                srcX  = Int32.toFloat64(t#srcX),
                srcY  = Int32.toFloat64(t#srcY),
                flipH = t#flipH,
                flipV = t#flipV,
                alpha = 1.0f32
            }: TileData)
        }, d#manualTiles);

        // AutoLayerWalls を下、manualTiles を上で重ねる
        let tiles: List[TileData] = List.append(autoTiles, manualTiles);

        // 自動壁セル → collisionCells (Float64 grid 座標)
        let cells = wallCells
            |> Set.toList
            |> List.map(coord -> {
                let (col, row) = coord;
                ({x = Int32.toFloat64(col), y = Int32.toFloat64(row)}: Vec2.Vec2)
            });

        // doors: entities の identifier="Door" を grid 座標で
        let doors = d#entities
            |> List.filter(e -> e#identifier == "Door")
            |> List.map(e -> ({x = e#x, y = e#y}: {x = Int32, y = Int32}));

        // TileSet 構築 (textureName 経由で texture info 取得)
        let texInfo = match GameEngine.Game.getTextureInfo(textureName) {
            case Some(info) => info
            case None       => bug!("MapLoader: texture '${textureName}' not registered")
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
        let tileSet = TileSet.make(atlasFilled);

        ({
            tiles          = tiles,
            collisionCells = cells,
            doors          = doors,
            tileSet        = tileSet,
            gridSize       = ({x = d#width, y = d#height}: {x = Int32, y = Int32}),
            tileSize       = tileSize
        }: LDTKLoader.LDTKLevelRaw)

    /// 装飾レイヤー (Floor 等) を別 tileset で描画するための TileMapLayer を構築する。
    /// `decorTiles` を読み、衝突無しの TileMapLayer を返す。
    /// Walls 層と異なる texture で重ねるための関数 (LDTKLoader.loadLayerByIdentifier 相当)。
    pub def loadDecorLayer(mapPath: String, textureName: String): TileMapLayer
            \ { GameEngine.Game, Fs.FileRead } =
        let level = match Persistence.load(mapPath) {
            case Some(l) => l
            case None    => bug!("MapLoader.loadDecorLayer: failed to load ${mapPath}")
        };
        let d = MapResource.levelData(level);
        let tileSizeI = d#tileSize;
        let tileSize  = Int32.toFloat64(tileSizeI);
        // decorTiles → TileData
        let tiles: List[TileData] = List.map(t -> {
            ({
                px    = ({x = Int32.toFloat64(t#x * tileSizeI),
                           y = Int32.toFloat64(t#y * tileSizeI)}: Vec2.Vec2),
                srcX  = Int32.toFloat64(t#srcX),
                srcY  = Int32.toFloat64(t#srcY),
                flipH = t#flipH,
                flipV = t#flipV,
                alpha = 1.0f32
            }: TileData)
        }, d#decorTiles);
        // tileSet 構築 (装飾用 texture)
        let texInfo = match GameEngine.Game.getTextureInfo(textureName) {
            case Some(info) => info
            case None       => bug!("MapLoader.loadDecorLayer: texture '${textureName}' not registered")
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
        let tileSet = TileSet.make(atlasFilled);
        let instances = LDTKLoader.buildTileInstances(tiles, tileSet, tileSize);
        let (vao, count) = GameEngine.Game.initTileBuffer(instances);
        TileMapLayer.make({
            tileSet        = tileSet,
            tiles          = tiles,
            collisionCells = Nil,   // 装飾レイヤーは衝突を持たない
            gridSize       = ({x = d#width, y = d#height}: {x = Int32, y = Int32})
        }) |> TileMapLayer.withGpuResources(vao, count)

    /// 装飾レイヤー (decorTiles) の生データを返す。LDTKLoader.loadLayerByIdentifier 互換。
    /// DungeonComposer.composeDecorationLayer の dispatch ターゲットとして使う。
    pub def loadDecorLayerRaw(mapPath: String, textureName: String): LDTKLoader.LDTKLayerRaw
            \ { GameEngine.Game, Fs.FileRead } =
        let level = match Persistence.load(mapPath) {
            case Some(l) => l
            case None    => bug!("MapLoader.loadDecorLayerRaw: failed to load ${mapPath}")
        };
        let d = MapResource.levelData(level);
        let tileSizeI = d#tileSize;
        let tileSize  = Int32.toFloat64(tileSizeI);
        let tiles: List[TileData] = List.map(t -> {
            ({
                px    = ({x = Int32.toFloat64(t#x * tileSizeI),
                           y = Int32.toFloat64(t#y * tileSizeI)}: Vec2.Vec2),
                srcX  = Int32.toFloat64(t#srcX),
                srcY  = Int32.toFloat64(t#srcY),
                flipH = t#flipH,
                flipV = t#flipV,
                alpha = 1.0f32
            }: TileData)
        }, d#decorTiles);
        let texInfo = match GameEngine.Game.getTextureInfo(textureName) {
            case Some(info) => info
            case None       => bug!("MapLoader.loadDecorLayerRaw: texture '${textureName}' not registered")
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
        let tileSet = TileSet.make(atlasFilled);
        ({
            tiles    = tiles,
            tileSet  = tileSet,
            gridSize = ({x = d#width, y = d#height}: {x = Int32, y = Int32}),
            tileSize = tileSize
        }: LDTKLoader.LDTKLayerRaw)

    /// `<mapPath>/../../materials/<materialId>.material.json` を組み立てる。
    /// mapPath = ".../assets/maps/level_0.map.json"
    /// → ".../assets/materials/inca_stone.material.json"
    def materialPathFor(mapPath: String, materialId: String): String = {
        let parent = stripAfterLast(mapPath, '/');           // ".../assets/maps"
        let grand  = stripAfterLast(parent, '/');             // ".../assets"
        grand + "/materials/" + materialId + ".material.json"
    }

    /// 最後の `c` の位置以降を取り除いた prefix を返す。`c` が無ければ全体を返す。
    def stripAfterLast(s: String, c: Char): String = {
        let len = String.length(s);
        let idx = lastIndexOf(s, c, len - 1);
        if (idx < 0) s
        else s.substring(0, idx)
    }

    def lastIndexOf(s: String, c: Char, start: Int32): Int32 =
        if (start < 0) -1
        else if (String.charAt(start, s) == c) start
        else lastIndexOf(s, c, start - 1)

    /// 自動壁セルを計算する。
    ///   - 床なし (= floorMask に含まれない)
    ///   - かつ 8 近傍に少なくとも 1 つ床がある
    /// マップ範囲は (0..width, 0..height)。
    def computeWallCells(floorMask: Set[(Int32, Int32)],
                          width: Int32, height: Int32): Set[(Int32, Int32)] =
        List.range(0, width * height)
            |> List.filterMap(idx -> {
                let col = Int32.remainder(idx, width);
                let row = idx / width;
                if (Set.memberOf((col, row), floorMask)) None
                else if (any8NeighborIsFloor(floorMask, col, row)) Some((col, row))
                else None
            })
            |> List.toSet

    /// 8 近傍 (上下左右 + 斜め) に床が 1 つでもあるか。
    def any8NeighborIsFloor(floorMask: Set[(Int32, Int32)], col: Int32, row: Int32): Bool =
        Set.memberOf((col - 1, row - 1), floorMask) or
        Set.memberOf((col,     row - 1), floorMask) or
        Set.memberOf((col + 1, row - 1), floorMask) or
        Set.memberOf((col - 1, row    ), floorMask) or
        Set.memberOf((col + 1, row    ), floorMask) or
        Set.memberOf((col - 1, row + 1), floorMask) or
        Set.memberOf((col,     row + 1), floorMask) or
        Set.memberOf((col + 1, row + 1), floorMask)

    /// wallCells + Material.wallMap から AutoLayerWalls タイル列を構築する。
    /// `manualCoords` に含まれる (col, row) は manualTiles に上書きされるのでスキップする。
    def buildAutoLayerTiles(wallCells: Set[(Int32, Int32)],
                              md: MapResource.MaterialData,
                              manualCoords: Set[(Int32, Int32)],
                              tileSizeI: Int32): List[TileData] = {
        wallCells
            |> Set.toList
            |> List.filterMap(coord -> {
                let (col, row) = coord;
                if (Set.memberOf((col, row), manualCoords)) None
                else {
                    let key = trblKeyAt(wallCells, col, row);
                    match Map.get(key, md#wallMap) {
                        case None              => None
                        case Some((srcX, srcY)) => Some(({
                            px    = ({x = Int32.toFloat64(col * tileSizeI),
                                       y = Int32.toFloat64(row * tileSizeI)}: Vec2.Vec2),
                            srcX  = Int32.toFloat64(srcX),
                            srcY  = Int32.toFloat64(srcY),
                            flipH = false,
                            flipV = false,
                            alpha = 1.0f32
                        }: TileData))
                    }
                }
            })
    }

    /// (col, row) の TRBL 4-bit キー。隣セルが壁 (wallCells に含まれる) なら 1。
    /// 壁の連続を辿るので、wallCells の各セルから見た「四方向に壁仲間がいるか」が出る。
    pub def trblKeyAt(wallCells: Set[(Int32, Int32)], col: Int32, row: Int32): String = {
        let t = if (Set.memberOf((col,     row - 1), wallCells)) "1" else "0";
        let r = if (Set.memberOf((col + 1, row    ), wallCells)) "1" else "0";
        let b = if (Set.memberOf((col,     row + 1), wallCells)) "1" else "0";
        let l = if (Set.memberOf((col - 1, row    ), wallCells)) "1" else "0";
        t + r + b + l
    }
}
