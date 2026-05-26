/// `.map.json` (MapResource.Level) を読み TileMapLayer を構築する loader。
///
/// 役割:
///   - `manualTiles` をそのまま描画タイル列に変換 (autotile 無しの素描画)
///   - `wallMask` の非ゼロセルを collisionCells に展開 (PhysicsStep が壁として扱う)
///   - `entities` のうち `identifier == "Door"` を doors として抽出
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

        // manualTiles → TileData
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
        }, d#manualTiles);

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
}
