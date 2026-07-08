/// `.map.json` (MapResource.Level) を読み TileLayer を構築する loader。
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
/// `TileRendering.TileLevelRaw` を返すので、DungeonComposer 等の下流処理を
/// そのまま流用できる (将来 DungeonComposer に loader 注入で接続する計画)。
mod MapLoader {

    /// `.map.json` から TileLayer を 1 枚構築する。
    /// GPU upload まで完了した状態で返す。
    pub def loadLevel(mapPath: String, textureName: String): TileLayer
            \ { GameEngine.Game, Fs.FileRead } =
        let raw = loadLevelRaw(mapPath, textureName);
        let instances = TileRendering.buildTileInstances(raw#tiles, raw#tileSet, raw#tileSize);
        let (tileVaoId, tileCount) = GameEngine.Game.initTileBuffer(instances);
        TileLayer.make({
            tileSet        = raw#tileSet,
            tiles          = raw#tiles,
            collisionCells = raw#collisionCells,
            gridSize       = raw#gridSize
        }) |> TileLayer.withGpuResources(tileVaoId, tileCount)

    /// GPU upload 前の生データを返す。複数モジュールを合成する場合 (DungeonComposer 系) に使う。
    pub def loadLevelRaw(mapPath: String, textureName: String): TileRendering.TileLevelRaw
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
                buildAutoLayerTiles(wallCells, floorMask, md, manualCoords, tileSizeI)
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

        // IntGrid 再構築 (load 時に毎回): floorMask=1, wallCells=2, それ以外=0
        let intGrid = buildIntGrid(floorMask, wallCells, d#width, d#height);
        // AutoRule タイル: パターンマッチで装飾を重ねる
        let ruleTiles: List[TileData] = match materialOpt {
            case None      => Nil
            case Some(mat) =>
                let md = MapResource.materialData(mat);
                buildAutoRuleTiles(intGrid, d#width, d#height, md#autoRules, manualCoords, tileSizeI)
        };

        // 描画順: 自動壁 → manualTiles → ruleTiles (最前面)
        let tiles: List[TileData] =
            List.append(List.append(autoTiles, manualTiles), ruleTiles);

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

        // Tileset 構築 (textureName 経由で texture info 取得)
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
        let tileSet = Tileset.make(atlasFilled);

        ({
            tiles          = tiles,
            collisionCells = cells,
            doors          = doors,
            tileSet        = tileSet,
            gridSize       = ({x = d#width, y = d#height}: {x = Int32, y = Int32}),
            tileSize       = tileSize
        }: TileRendering.TileLevelRaw)

    /// 装飾レイヤー (Floor 等) を別 tileset で描画するための TileLayer を構築する。
    /// `decorTiles` を読み、衝突無しの TileLayer を返す。
    /// Walls 層と異なる texture で重ねるための関数。
    pub def loadDecorLayer(mapPath: String, textureName: String): TileLayer
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
        let tileSet = Tileset.make(atlasFilled);
        let instances = TileRendering.buildTileInstances(tiles, tileSet, tileSize);
        let (vao, count) = GameEngine.Game.initTileBuffer(instances);
        TileLayer.make({
            tileSet        = tileSet,
            tiles          = tiles,
            collisionCells = Nil,   // 装飾レイヤーは衝突を持たない
            gridSize       = ({x = d#width, y = d#height}: {x = Int32, y = Int32})
        }) |> TileLayer.withGpuResources(vao, count)

    /// 装飾レイヤー (decorTiles) の生データを返す。
    /// DungeonComposer.composeDecorationLayer の dispatch ターゲットとして使う。
    pub def loadDecorLayerRaw(mapPath: String, textureName: String): TileRendering.TileLayerRaw
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
        let tileSet = Tileset.make(atlasFilled);
        ({
            tiles    = tiles,
            tileSet  = tileSet,
            gridSize = ({x = d#width, y = d#height}: {x = Int32, y = Int32}),
            tileSize = tileSize
        }: TileRendering.TileLayerRaw)

    /// `<mapPath>/../../materials/<materialId>.material.json` を組み立てる。
    /// mapPath = ".../assets/maps/level_0.map.json"
    /// → ".../assets/materials/inca_stone.material.json"
    pub def materialPathFor(mapPath: String, materialId: String): String = {
        let parent = stripAfterLast(mapPath, '/');           // ".../assets/maps"
        let grand  = stripAfterLast(parent, '/');             // ".../assets"
        grand + "/materials/" + materialId + ".material.json"
    }

    /// 最後の `c` の位置以降を取り除いた prefix を返す。`c` が無ければ全体を返す。
    pub def stripAfterLast(s: String, c: Char): String = {
        let len = String.length(s);
        let idx = lastIndexOf(s, c, len - 1);
        if (idx < 0) s
        else s.substring(0, idx)
    }

    pub def lastIndexOf(s: String, c: Char, start: Int32): Int32 =
        if (start < 0) -1
        else if (String.charAt(start, s) == c) start
        else lastIndexOf(s, c, start - 1)

    /// 自動壁セルを計算する。
    ///   - 床なし (= floorMask に含まれない)
    ///   - かつ 8 近傍に少なくとも 1 つ床がある
    /// マップ範囲は (0..width, 0..height)。
    pub def computeWallCells(floorMask: Set[(Int32, Int32)],
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
    pub def any8NeighborIsFloor(floorMask: Set[(Int32, Int32)], col: Int32, row: Int32): Bool =
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
    /// lookup 順序: 4-trit キー (例 "EWFW") → 旧 4-bit キー (例 "0101") の順 (フォールバック)。
    def buildAutoLayerTiles(wallCells: Set[(Int32, Int32)],
                              floorMask: Set[(Int32, Int32)],
                              md: MapResource.MaterialData,
                              manualCoords: Set[(Int32, Int32)],
                              tileSizeI: Int32): List[TileData] = {
        wallCells
            |> Set.toList
            |> List.filterMap(coord -> {
                let (col, row) = coord;
                if (Set.memberOf((col, row), manualCoords)) None
                else {
                    let coordOpt = lookupWallTile(wallCells, floorMask, md#wallMap, col, row);
                    match coordOpt {
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

    /// 4-trit キー (壁/床/空) で wallMap を引き、無ければ旧 4-bit キーにフォールバック。
    pub def lookupWallTile(wallCells: Set[(Int32, Int32)],
                             floorMask: Set[(Int32, Int32)],
                             wallMap: Map[String, (Int32, Int32)],
                             col: Int32, row: Int32): Option[(Int32, Int32)] = {
        let trit = trblTritKeyAt(wallCells, floorMask, col, row);
        match Map.get(trit, wallMap) {
            case Some(v) => Some(v)
            case None    => Map.get(trblKeyAt(wallCells, col, row), wallMap)
        }
    }

    /// (col, row) の TRBL 4-bit キー。隣セルが壁 (wallCells に含まれる) なら 1。
    pub def trblKeyAt(wallCells: Set[(Int32, Int32)], col: Int32, row: Int32): String = {
        let t = if (Set.memberOf((col,     row - 1), wallCells)) "1" else "0";
        let r = if (Set.memberOf((col + 1, row    ), wallCells)) "1" else "0";
        let b = if (Set.memberOf((col,     row + 1), wallCells)) "1" else "0";
        let l = if (Set.memberOf((col - 1, row    ), wallCells)) "1" else "0";
        t + r + b + l
    }

    /// (col, row) の 4-trit キー。各方向: W=壁, F=床, E=空 (マップ外含む)。
    /// 例: "EWFW" = 上が空、右が壁、下が床、左が壁 (= 部屋の上辺の壁)。
    pub def trblTritKeyAt(wallCells: Set[(Int32, Int32)],
                            floorMask: Set[(Int32, Int32)],
                            col: Int32, row: Int32): String =
        tritAt(wallCells, floorMask, col,     row - 1)
        + tritAt(wallCells, floorMask, col + 1, row    )
        + tritAt(wallCells, floorMask, col,     row + 1)
        + tritAt(wallCells, floorMask, col - 1, row    )

    def tritAt(wallCells: Set[(Int32, Int32)],
                floorMask: Set[(Int32, Int32)],
                col: Int32, row: Int32): String =
        if      (Set.memberOf((col, row), wallCells)) "W"
        else if (Set.memberOf((col, row), floorMask)) "F"
        else                                          "E"

    /// IntGrid を再構築する。0=空, 1=床, 2=自動壁。マップ範囲全セル分。
    pub def buildIntGrid(floorMask: Set[(Int32, Int32)],
                           wallCells: Set[(Int32, Int32)],
                           width: Int32, height: Int32): Vector[Int32] =
        List.range(0, width * height)
            |> List.map(i -> {
                let col = Int32.remainder(i, width);
                let row = i / width;
                if      (Set.memberOf((col, row), floorMask)) 1i32
                else if (Set.memberOf((col, row), wallCells)) 2i32
                else                                          0i32
            })
            |> List.toVector

    /// AutoRule リストを各セルに適用してタイル列を生成する。
    /// 各セルでルールを順番にチェック、最初にマッチしたら出力タイルを採用。
    /// `manualCoords` のセルは手動 Walls の上書きを優先するためスキップする
    /// (Floor decorTiles は AutoRule の主用途なのでスキップ対象に含めない)。
    pub def buildAutoRuleTiles(intGrid: Vector[Int32],
                                 width: Int32, height: Int32,
                                 rules: List[MapResource.AutoRule],
                                 manualCoords: Set[(Int32, Int32)],
                                 tileSizeI: Int32): List[TileData] =
        List.range(0, width * height)
            |> List.filterMap(i -> {
                let col = Int32.remainder(i, width);
                let row = i / width;
                if (Set.memberOf((col, row), manualCoords)) None
                else applyFirstMatchingRule(intGrid, width, height, col, row, rules, tileSizeI)
            })

    /// このセルでマッチする最初のルールを見つけて TileData を返す。なければ None。
    def applyFirstMatchingRule(intGrid: Vector[Int32],
                                 width: Int32, height: Int32,
                                 col: Int32, row: Int32,
                                 rules: List[MapResource.AutoRule],
                                 tileSizeI: Int32): Option[TileData] = match rules {
        case Nil          => None
        case r :: rest    =>
            // srcX < 0 / srcY < 0 は Tile 未設定の Rule。マッチしても描画しない。
            if (r#srcX < 0i32 or r#srcY < 0i32)
                applyFirstMatchingRule(intGrid, width, height, col, row, rest, tileSizeI)
            else if (MapResource.ruleMatches(intGrid, width, height, col, row, r))
                Some(({
                    px    = ({x = Int32.toFloat64(col * tileSizeI),
                               y = Int32.toFloat64(row * tileSizeI)}: Vec2.Vec2),
                    srcX  = Int32.toFloat64(r#srcX),
                    srcY  = Int32.toFloat64(r#srcY),
                    flipH = false, flipV = false, alpha = 1.0f32
                }: TileData))
            else applyFirstMatchingRule(intGrid, width, height, col, row, rest, tileSizeI)
    }

}
