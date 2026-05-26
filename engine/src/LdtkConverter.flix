/// LDtk の `.ldtkl` レベルファイルを `MapResource.Level` に変換する。
///
/// `.ldtkl` には LDtk GUI が auto-rule を評価した結果 (`autoLayerTiles`) が
/// 既に展開済みで埋まっている。これをすべて `ManualTile` (flip 情報込み) に
/// 1 対 1 で転記すれば、autotile の再評価なしで視覚を完全再現できる。
///
/// 変換規則:
///   - 全 layer の `autoLayerTiles` を底から上に積み上げて manualTiles に
///     (LDtk の layerInstances は先頭が最前面なので逆順で処理する)
///   - `__identifier == "Walls"` 層の `intGridCsv` を wallMask に (0/1)
///   - 全 layer の `entityInstances` を `Entity` に (fields は MVP では空)
///
/// `materialId` は引数で指定する。Material 自体は別途用意する必要があるが、
/// 当面は manualTiles だけで描画できるので Material は空でも構わない。
mod LdtkConverter {
    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonArray, JsonNumber, JsonString, JsonBool}

    /// `.ldtkl` ファイルを読んで `MapResource.Level` を構築する。
    /// パース失敗 / 必須フィールド欠落は `bug!` で停止する (converter は
    /// 一度きりの開発時スクリプトなので例外伝播より即停止が望ましい)。
    pub def convertLdtkl(path: String, materialId: String):
            MapResource.Level \ Fs.FileRead =
        let text = match run { Fs.ReadFile.read(path) } with Fs.ReadFile.runWithFileRead {
            case Ok(t)  => t
            case Err(e) => bug!("LdtkConverter: failed to read ${path}: ${e}")
        };
        let json = match Json.Parse.parse(String.trim(text)) {
            case Some(j) => j
            case None    => bug!("LdtkConverter: failed to parse JSON: ${path}")
        };
        let root = getObj(json);
        let layerInstances = getArr(getField("layerInstances", root));

        // tileSize / width / height は最初の layer から取る (全 layer 同一前提)
        let firstLayer = match List.head(layerInstances) {
            case Some(l) => getObj(l)
            case None    => bug!("LdtkConverter: empty layerInstances: ${path}")
        };
        let tileSize = getInt(getField("__gridSize", firstLayer));
        let cWid     = getInt(getField("__cWid",     firstLayer));
        let cHei     = getInt(getField("__cHei",     firstLayer));

        // 層ごとにタイルを集める。Walls は wall tileset、Floor は decor tileset で
        // 別 TileMapLayer として描画されるため、混ぜずに分ける。
        let manualTiles = collectLayerTiles("Walls", layerInstances, tileSize);
        let decorTiles  = collectLayerTiles("Floor", layerInstances, tileSize);

        // wallMask: "Walls" 層の intGridCsv を採用
        let wallMask = match List.find(layer -> {
            let lo = getObj(layer);
            match Map.get("__identifier", lo) {
                case Some(JsonString(s)) => s == "Walls"
                case _                   => false
            }
        }, layerInstances) {
            case Some(l) =>
                let lo = getObj(l);
                match Map.get("intGridCsv", lo) {
                    case Some(JsonArray(arr)) =>
                        arr |> Vector.map(getInt)
                    case _ => emptyVec()
                }
            case None => emptyVec()
        };

        // entities: 全 layer の entityInstances を集める
        let entities = List.flatMap(layer -> {
            let layerObj = getObj(layer);
            match Map.get("entityInstances", layerObj) {
                case Some(JsonArray(arr)) =>
                    Vector.toList(arr) |> List.map(entityToMapEntity)
                case _ => Nil
            }
        }, layerInstances);

        MapResource.Level.Level(({
            tileSize    = tileSize,
            width       = cWid,
            height      = cHei,
            materialId  = materialId,
            wallMask    = wallMask,
            manualTiles = manualTiles,
            decorTiles  = decorTiles,
            entities    = entities
        }: MapResource.LevelData))

    /// 指定した `__identifier` を持つ層の autoLayerTiles を ManualTile のリストにする。
    /// 該当層が存在しない / 空ならば空リスト。
    def collectLayerTiles(targetIdentifier: String,
                           layerInstances: List[JsonElement],
                           tileSize: Int32): List[MapResource.ManualTile] =
        match List.find(layer -> {
            let lo = getObj(layer);
            match Map.get("__identifier", lo) {
                case Some(JsonString(s)) => s == targetIdentifier
                case _                   => false
            }
        }, layerInstances) {
            case None    => Nil
            case Some(l) =>
                let lo = getObj(l);
                let autoTiles = match Map.get("autoLayerTiles", lo) {
                    case Some(JsonArray(arr)) => Vector.toList(arr)
                    case _                    => Nil
                };
                List.map(tileEl -> tileToManual(tileEl, tileSize), autoTiles)
        }

    /// LDtk の 1 autoLayerTile を `ManualTile` に変換する。
    /// px は drawing 座標 (spacing 無関係) なので tileSize で割って grid 座標化、
    /// src は tileset 上のピクセル位置 (LDtk が spacing/padding 込みで計算済み) なので
    /// そのままピクセル単位で保存する。
    /// f は 0=normal, 1=flipH, 2=flipV, 3=both (LDTKLoader と同じ規約)。
    def tileToManual(tileEl: JsonElement, tileSize: Int32): MapResource.ManualTile =
        let tileObj = getObj(tileEl);
        let (pxX, pxY)   = parseIntPair(getField("px",  tileObj));
        let (srcX, srcY) = parseIntPair(getField("src", tileObj));
        let f = getInt(getField("f", tileObj));
        ({
            x     = pxX / tileSize,
            y     = pxY / tileSize,
            srcX  = srcX,
            srcY  = srcY,
            flipH = f == 1 or f == 3,
            flipV = f == 2 or f == 3
        }: MapResource.ManualTile)

    /// LDtk の entityInstance を `MapResource.Entity` に変換する。
    /// fieldInstances は MVP では空 Map にする (将来必要なら追加)。
    def entityToMapEntity(entityEl: JsonElement): MapResource.Entity =
        let entityObj = getObj(entityEl);
        let identifier = getString(getField("__identifier", entityObj));
        let (gx, gy) = parseIntPair(getField("__grid", entityObj));
        ({
            identifier = identifier,
            x          = gx,
            y          = gy,
            fields     = Map.empty()
        }: MapResource.Entity)

    /// 空の `Vector[Int32]` を作るための helper。Vector.empty が無いので
    /// 0 件の List 経由で構築する。
    def emptyVec(): Vector[Int32] =
        (Nil: List[Int32]) |> List.toVector

    // ────────────────────────────────────────────────────────
    // JSON 抽出ヘルパー (LDTKLoader と同じパターン)
    // ────────────────────────────────────────────────────────

    def getFloat(el: JsonElement): Float64 = match el {
        case JsonNumber(bd) => bd.doubleValue()
        case _              => bug!("LdtkConverter: expected JSON number")
    }

    def getInt(el: JsonElement): Int32 =
        Float64.truncateToInt32(getFloat(el))

    def getString(el: JsonElement): String = match el {
        case JsonString(s) => s
        case _             => bug!("LdtkConverter: expected JSON string")
    }

    def getObj(el: JsonElement): Map[String, JsonElement] = match el {
        case JsonObject(m) => m
        case _             => bug!("LdtkConverter: expected JSON object")
    }

    def getArr(el: JsonElement): List[JsonElement] = match el {
        case JsonArray(v) => Vector.toList(v)
        case _            => bug!("LdtkConverter: expected JSON array")
    }

    def getField(key: String, obj: Map[String, JsonElement]): JsonElement =
        match Map.get(key, obj) {
            case Some(v) => v
            case None    => bug!("LdtkConverter: missing field '${key}'")
        }

    def parseIntPair(el: JsonElement): (Int32, Int32) = match el {
        case JsonArray(v) =>
            match Vector.toList(v) {
                case a :: b :: _ => (getInt(a), getInt(b))
                case _ => bug!("LdtkConverter: expected pair, got too few elements")
            }
        case _ => bug!("LdtkConverter: expected JSON array (pair)")
    }
}
