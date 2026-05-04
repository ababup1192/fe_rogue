/// LDTK (.ldtkl) レベルファイルを読み込み、TileMapLayer として解釈する。
///
/// 1. テクスチャ寸法は GameEngine.Game.getTextureInfo で自動取得する。
/// 2. tileSize は .ldtkl の __gridSize から自動補完する。
/// 3. autoLayerTiles を解析して GPU インスタンスバッファを構築し initTileBuffer でアップロード。
/// 4. intGridCsv の非ゼロセルを衝突セルとして展開する（PhysicsStep が壁として扱う）。
mod LDTKLoader {
    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonArray, JsonNumber}

    /// loadLevel の設定。margin/spacing が必要ない場合は simpleConfig を使う。
    pub type alias LDTKLoaderConfig = {
        path        = String,
        textureName = String,
        marginX     = Float64,
        marginY     = Float64,
        spacingX    = Float64,
        spacingY    = Float64
    }

    /// margin/spacing を 0 で埋めた最小限の設定を生成する。
    pub def simpleConfig(config: { path = String, textureName = String }): LDTKLoaderConfig = {
        path        = config#path,
        textureName = config#textureName,
        marginX     = 0.0,
        marginY     = 0.0,
        spacingX    = 0.0,
        spacingY    = 0.0
    }

    /// loadLevel が返す結果。GPU リソースは TileMapLayer 内に格納済み。
    pub type alias LDTKLevelData = { tileLayer = TileMapLayer }

    // ========================================================================
    // 公開 API
    // ========================================================================

    /// LDTK レベルファイルを読み込み TileMapLayer を構築する。
    /// 失敗時は bug! でクラッシュする（パス未存在・JSON パース失敗・該当レイヤーなし等）。
    pub def loadLevel(config: LDTKLoaderConfig): LDTKLevelData
            \ { GameEngine.Game, Fs.FileRead } =
        let texInfo = match GameEngine.Game.getTextureInfo(config#textureName) {
            case Some(info) => info
            case None => bug!("LDTKLoader: texture '${config#textureName}' not registered")
        };
        let texWidth  = texInfo#width;
        let texHeight = texInfo#height;

        let content = run { Fs.ReadFile.read(config#path) } with Fs.ReadFile.runWithFileRead;
        let text = match content {
            case Ok(t)  => t
            case Err(e) => bug!("LDTKLoader: failed to read ${config#path}: ${e}")
        };
        let json = match Json.Parse.parse(String.trim(text)) {
            case Some(j) => j
            case None    => bug!("LDTKLoader: failed to parse JSON: ${config#path}")
        };
        let root = getObj(json);

        // 該当レイヤー: autoLayerTiles に要素のあるものを採用（AutoLayer / IntGrid 兼用）
        let layerInstances = getArr(getField("layerInstances", root));
        let wallLayer = match List.find(layer -> {
            let layerObj = getObj(layer);
            match Map.get("autoLayerTiles", layerObj) {
                case Some(JsonArray(arr)) => Vector.length(arr) > 0
                case _ => false
            }
        }, layerInstances) {
            case Some(l) => getObj(l)
            case None    => bug!("LDTKLoader: no layer with autoLayerTiles in ${config#path}")
        };

        let tileSize = getFloat(getField("__gridSize", wallLayer));
        let cWid     = getInt(getField("__cWid", wallLayer));

        // タイル一覧を解析
        let autoTiles = getArr(getField("autoLayerTiles", wallLayer));
        let tiles: List[TileData] = List.map(tileEl -> {
            let tileObj = getObj(tileEl);
            let (pxX, pxY) = parseIntPair(getField("px", tileObj));
            let (srcX, srcY) = parseIntPair(getField("src", tileObj));
            let f = getInt(getField("f", tileObj));
            let a = match Map.get("a", tileObj) {
                case Some(el) => getFloat(el)
                case None     => 1.0
            };
            {
                px    = ({x = Int32.toFloat64(pxX), y = Int32.toFloat64(pxY)}: Vec2.Vec2),
                srcX  = Int32.toFloat64(srcX),
                srcY  = Int32.toFloat64(srcY),
                flipH = f == 1 or f == 3,
                flipV = f == 2 or f == 3,
                alpha = Float64.truncateToFloat32(a)
            }
        }, autoTiles);

        // intGridCsv から衝突セルを抽出（非ゼロ = 壁）
        let intGrid = match Map.get("intGridCsv", wallLayer) {
            case Some(JsonArray(arr)) => Vector.toList(arr)
            case _ => Nil
        };
        let collisionCells: List[Vec2.Vec2] = extractCollisionCells(intGrid, cWid);

        // GPU インスタンスバッファを構築
        let instances: List[GameEngine.TileInstance] = List.map(tile -> {
            let uvoX = if (tile#flipH) (tile#srcX + tileSize) / texWidth
                       else            tile#srcX / texWidth;
            let uvoY = if (tile#flipV) (tile#srcY + tileSize) / texHeight
                       else            tile#srcY / texHeight;
            let uvsX = if (tile#flipH) -(tileSize / texWidth)
                       else            tileSize / texWidth;
            let uvsY = if (tile#flipV) -(tileSize / texHeight)
                       else            tileSize / texHeight;
            ({
                px    = tile#px,
                uvOff = ({x = uvoX, y = uvoY}: Vec2.Vec2),
                uvSc  = ({x = uvsX, y = uvsY}: Vec2.Vec2),
                alpha = tile#alpha
            }: GameEngine.TileInstance)
        }, tiles);

        let (tileVaoId, tileCount) = GameEngine.Game.initTileBuffer(instances);

        // TileSet を組み立てる
        let atlas = TileSetAtlasSource.make({
            textureName = config#textureName,
            marginX     = config#marginX,
            marginY     = config#marginY,
            spacingX    = config#spacingX,
            spacingY    = config#spacingY
        });
        let atlasFilled: TileSetAtlasSource = {
            texWidth  = texWidth,
            texHeight = texHeight,
            tileSize  = tileSize
            | atlas
        };
        let tileSet = TileSet.make(atlasFilled);

        let tileLayer = TileMapLayer.make({
            tileSet        = tileSet,
            tiles          = tiles,
            collisionCells = collisionCells
        }) |> TileMapLayer.withGpuResources(tileVaoId, tileCount);

        { tileLayer = tileLayer }

    // ========================================================================
    // 内部ヘルパー（JSON 抽出）
    // ========================================================================

    /// JsonNumber を Float64 として取り出す
    def getFloat(el: Json.JsonElement): Float64 = match el {
        case JsonNumber(bd) => bd.doubleValue()
        case _              => bug!("LDTKLoader: expected JSON number")
    }

    def getInt(el: Json.JsonElement): Int32 =
        Float64.truncateToInt32(getFloat(el))

    def getObj(el: Json.JsonElement): Map[String, Json.JsonElement] = match el {
        case JsonObject(m) => m
        case _             => bug!("LDTKLoader: expected JSON object")
    }

    def getArr(el: Json.JsonElement): List[Json.JsonElement] = match el {
        case JsonArray(v) => Vector.toList(v)
        case _            => bug!("LDTKLoader: expected JSON array")
    }

    def getField(key: String, obj: Map[String, Json.JsonElement]): Json.JsonElement =
        match Map.get(key, obj) {
            case Some(v) => v
            case None    => bug!("LDTKLoader: missing field '${key}'")
        }

    def parseIntPair(el: Json.JsonElement): (Int32, Int32) = match el {
        case JsonArray(v) =>
            match Vector.toList(v) {
                case a :: b :: _ => (getInt(a), getInt(b))
                case _ => bug!("LDTKLoader: expected pair, got too few elements")
            }
        case _ => bug!("LDTKLoader: expected JSON array (pair)")
    }

    /// intGridCsv（フラット配列）から非ゼロセルをグリッド座標として抽出する。
    /// セル i は col = i % cWid, row = i / cWid に対応する。
    def extractCollisionCells(grid: List[Json.JsonElement], cWid: Int32): List[Vec2.Vec2] =
        let (_, cells) = List.foldLeft((acc, el) -> {
            let (i, accCells) = acc;
            let v = getInt(el);
            if (v != 0) {
                let col = Int32.remainder(i, cWid);
                let row = i / cWid;
                let cell: Vec2.Vec2 = { x = Int32.toFloat64(col), y = Int32.toFloat64(row) };
                (i + 1, cell :: accCells)
            } else
                (i + 1, accCells)
        }, (0, Nil), grid);
        List.reverse(cells)
}
