/// LDTK (.ldtkl) レベルファイルを読み込み、TileMapLayer として解釈する。
///
/// 1. テクスチャ寸法は GameEngine.Game.getTextureInfo で自動取得する。
/// 2. tileSize は .ldtkl の __gridSize から自動補完する。
/// 3. autoLayerTiles を解析して GPU インスタンスバッファを構築し initTileBuffer でアップロード。
/// 4. intGridCsv の非ゼロセルを衝突セルとして展開する（PhysicsStep が壁として扱う）。
/// 5. entityInstances の `__identifier == "Door"` をグリッド座標として収集する。
///
/// 複数モジュールを 1 枚にマージしたい場合は GPU アップロードを伴わない
/// loadLevelRaw を使って素材を取り出し、DungeonComposer 側でまとめてから
/// initTileBuffer を 1 度だけ呼ぶ。
mod LDTKLoader {
    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonArray, JsonNumber, JsonString}

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

    /// 装飾レイヤー（Floor 等）の生データ。collision / door は Wall 専用なので含まない。
    /// autoLayerTiles の `src` は LDTK 側で margin/spacing 込みで計算済みなので
    /// シェーダーへはそのまま渡せる（auto-rule 再適用は不要）。
    pub type alias LDTKLayerRaw = {
        tiles    = List[TileData],
        tileSet  = TileSet,
        gridSize = Vec2.Vec2i,
        tileSize = Float64
    }

    /// GPU アップロード前の生データ。DungeonComposer が複数モジュールを 1 枚にマージする際に使う。
    /// tileSize は描画 / 座標換算で繰り返し参照するので展開済みで持つ
    /// （tileSet#atlasSource#tileSize と同値）。
    pub type alias LDTKLevelRaw = {
        tiles          = List[TileData],
        collisionCells = List[Vec2.Vec2],
        doors          = List[Vec2.Vec2i],
        tileSet        = TileSet,
        gridSize       = Vec2.Vec2i,
        tileSize       = Float64
    }

    // ========================================================================
    // 公開 API
    // ========================================================================

    /// LDTK レベルファイルを読み込み TileMapLayer を構築する。
    /// 失敗時は bug! でクラッシュする（パス未存在・JSON パース失敗・該当レイヤーなし等）。
    pub def loadLevel(config: LDTKLoaderConfig): LDTKLevelData
            \ { GameEngine.Game, Fs.FileRead } =
        let raw = loadLevelRaw(config);
        let instances = buildTileInstances(raw#tiles, raw#tileSet, raw#tileSize);
        let (tileVaoId, tileCount) = GameEngine.Game.initTileBuffer(instances);
        let tileLayer = TileMapLayer.make({
            tileSet        = raw#tileSet,
            tiles          = raw#tiles,
            collisionCells = raw#collisionCells,
            gridSize       = raw#gridSize
        }) |> TileMapLayer.withGpuResources(tileVaoId, tileCount);
        { tileLayer = tileLayer }

    /// LDTK レベルファイルから生のタイル / 衝突セル / Door 一覧を取り出す。
    /// GPU アップロードは行わないので、複数モジュールをマージしてから
    /// 一括で initTileBuffer したい呼び出し側（DungeonComposer 等）が使う。
    pub def loadLevelRaw(config: LDTKLoaderConfig): LDTKLevelRaw
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

        let layerInstances = getArr(getField("layerInstances", root));

        // 該当レイヤー: autoLayerTiles に要素のあるものを採用（AutoLayer / IntGrid 兼用）
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
        let cHei     = getInt(getField("__cHei", wallLayer));

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

        // Door エンティティ一覧（grid 座標）
        let doors: List[Vec2.Vec2i] = extractDoors(layerInstances);

        // TileSet を組み立てる（GPU リソースとは独立に持てる）
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

        {
            tiles          = tiles,
            collisionCells = collisionCells,
            doors          = doors,
            tileSet        = tileSet,
            gridSize       = ({x = cWid, y = cHei}: Vec2.Vec2i),
            tileSize       = tileSize
        }

    /// 指定 `__identifier` のレイヤーから autoLayerTiles を取り出す（auto-rule 再適用なし）。
    /// 装飾用レイヤー（Floor 等）を別 TileMapLayer として描画する用途。
    /// 該当レイヤーが見つからない / autoLayerTiles が空なら bug!。
    pub def loadLayerByIdentifier(config: LDTKLoaderConfig, layerIdentifier: String): LDTKLayerRaw
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
        let layerInstances = getArr(getField("layerInstances", root));

        let targetLayer = match List.find(layer -> {
            let layerObj = getObj(layer);
            match Map.get("__identifier", layerObj) {
                case Some(JsonString(s)) => s == layerIdentifier
                case _                   => false
            }
        }, layerInstances) {
            case Some(l) => getObj(l)
            case None    => bug!("LDTKLoader: layer '${layerIdentifier}' not found in ${config#path}")
        };

        let tileSize = getFloat(getField("__gridSize", targetLayer));
        let cWid     = getInt(getField("__cWid", targetLayer));
        let cHei     = getInt(getField("__cHei", targetLayer));

        let autoTiles = getArr(getField("autoLayerTiles", targetLayer));
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

        {
            tiles    = tiles,
            tileSet  = tileSet,
            gridSize = ({x = cWid, y = cHei}: Vec2.Vec2i),
            tileSize = tileSize
        }

    /// TileData のリストを GPU インスタンス（TileInstance）のリストに変換する。
    /// UV は texture サイズと flipH/flipV から計算する。
    /// loadLevel と DungeonComposer の両方が使う。
    pub def buildTileInstances(tiles: List[TileData],
                                tileSet: TileSet,
                                tileSize: Float64): List[GameEngine.TileInstance] =
        let texWidth  = tileSet#atlasSource#texWidth;
        let texHeight = tileSet#atlasSource#texHeight;
        List.map(tile -> {
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
        }, tiles)

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

    def getString(el: Json.JsonElement): String = match el {
        case JsonString(s) => s
        case _             => bug!("LDTKLoader: expected JSON string")
    }

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

    /// layerInstances を走査し、`__identifier == "Door"` の entityInstances から
    /// `__grid: [col, row]` を Vec2.Vec2i として収集する。
    /// Entities レイヤーが存在しない or Door が無い場合は空リスト。
    def extractDoors(layerInstances: List[Json.JsonElement]): List[Vec2.Vec2i] =
        List.flatMap(layer -> {
            let layerObj = getObj(layer);
            match Map.get("entityInstances", layerObj) {
                case Some(JsonArray(arr)) =>
                    Vector.toList(arr) |> List.filterMap(entityEl -> {
                        let entityObj = getObj(entityEl);
                        let identifier = getString(getField("__identifier", entityObj));
                        if (identifier == "Door") {
                            let (col, row) = parseIntPair(getField("__grid", entityObj));
                            Some(({x = col, y = row}: Vec2.Vec2i))
                        } else
                            None
                    })
                case _ => Nil
            }
        }, layerInstances)
}
