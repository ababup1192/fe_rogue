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

        // AutoLayerWalls タイル: wallMask=1 のセルを TRBL 計算 → wallMap で展開
        // manualTiles と重なる座標は除外 (manualTiles を上書きとして優先)
        let manualCoords: Set[(Int32, Int32)] =
            d#manualTiles |> List.map(t -> (t#x, t#y)) |> List.toSet;
        let autoTiles: List[TileData] = match materialOpt {
            case None      => Nil
            case Some(mat) =>
                let md = MapResource.materialData(mat);
                buildAutoLayerTiles(d, md, manualCoords, tileSizeI)
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

        // wallMask の非ゼロセル → collisionCells (Float64 grid 座標)
        let cells = extractCollisionCells(d#wallMask, d#width);

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

    /// wallMask (Vector[Int32], 行優先) から非ゼロセルを `Vec2.Vec2` のリストに展開する。
    /// `i % width = col`, `i / width = row`。
    def extractCollisionCells(mask: Vector[Int32], width: Int32): List[Vec2.Vec2] =
        let n = Vector.length(mask);
        List.range(0, n)
            |> List.filterMap(i -> {
                let v = match Vector.nth(i, mask) {
                    case Some(n0) => n0
                    case None     => 0i32
                };
                if (v != 0i32) {
                    let col = Int32.remainder(i, width);
                    let row = i / width;
                    Some(({x = Int32.toFloat64(col), y = Int32.toFloat64(row)}: Vec2.Vec2))
                } else None
            })

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

    /// wallMask + Material.wallMap から AutoLayerWalls タイル列を構築する。
    /// `manualCoords` に含まれる (col, row) は manualTiles に上書きされるのでスキップする。
    def buildAutoLayerTiles(d: MapResource.LevelData, md: MapResource.MaterialData,
                              manualCoords: Set[(Int32, Int32)],
                              tileSizeI: Int32): List[TileData] = {
        let mask = d#wallMask;
        let w = d#width;
        let h = d#height;
        List.range(0, w * h)
            |> List.filterMap(idx -> {
                let col = Int32.remainder(idx, w);
                let row = idx / w;
                let isWall = match Vector.nth(idx, mask) {
                    case Some(v) => v != 0i32
                    case None    => false
                };
                if (not isWall) None
                else if (Set.memberOf((col, row), manualCoords)) None
                else {
                    let key = trblKeyAt(mask, w, h, col, row);
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

    /// (col, row) の TRBL 4-bit キー文字列。マップ外は壁扱い。
    def trblKeyAt(mask: Vector[Int32], width: Int32, height: Int32,
                   col: Int32, row: Int32): String = {
        let t = if (neighborIsWall(mask, width, height, col,     row - 1)) "1" else "0";
        let r = if (neighborIsWall(mask, width, height, col + 1, row    )) "1" else "0";
        let b = if (neighborIsWall(mask, width, height, col,     row + 1)) "1" else "0";
        let l = if (neighborIsWall(mask, width, height, col - 1, row    )) "1" else "0";
        t + r + b + l
    }

    def neighborIsWall(mask: Vector[Int32], width: Int32, height: Int32,
                        col: Int32, row: Int32): Bool =
        if (col < 0 or col >= width or row < 0 or row >= height) true
        else {
            let idx = row * width + col;
            match Vector.nth(idx, mask) {
                case Some(v) => v != 0i32
                case None    => false
            }
        }
}
