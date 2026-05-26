/// LDtk 風の独自スキーマでマップを表現する Resource 群。
///
/// `Level` (マップ実体) と `Material` (素材) を別々に永続化する設計で、
/// Level は `materialId` で Material を参照する。これにより同じマップを
/// 別 Material に差し替えて複数テーマの見た目を再生できる。
///
/// JSON 形状の概略:
///   Level     : {"tileSize":16, "width":10, "height":10, "materialId":"inca_stone",
///                "wallMask":[1,1,1,...], "manualTiles":[{"x":..,"y":..,"col":..,"row":..}],
///                "entities":[{"identifier":"Door","x":5,"y":3,"fields":{...}}]}
///   Material  : {"tileset":"inca_walls", "tileSize":16,
///                "wallMap":{"0000":[3,5], "0001":[4,5], ...16件},
///                "floorPalette":[[0,0],[1,0]], "decorPalette":[[5,5]]}
///   FieldValue: {"string":"goblin"} / {"int":3} / {"bool":true}
///
/// `wallMap` のキーは "TRBL" 形式 ("0000" 〜 "1111", 16 通り)。
/// マップ縁は wall として扱う慣習 (LDTKRules と同じ)。
///
/// 設計メモ: Flix は type alias に instance を定義できないため、Level / Material は
/// 単一 case の enum でラップする (UnitCatalog と同じパターン)。データへのアクセスは
/// `levelData` / `materialData` で record を取り出す。
mod MapResource {

    /// Level の中身。フィールドの集合はここに集約し、enum 経由で持ち回す。
    /// - `manualTiles` は Walls 層由来 (wall tileset = inca_tileset 等)
    /// - `decorTiles`  は Floor/decoration 層由来 (別 tileset = tilemap_floor 等)
    /// LDtk は Walls と Floor が別 tileset を使う構成のため、層を分けて保持する。
    pub type alias LevelData = {
        tileSize    = Int32,
        width       = Int32,
        height      = Int32,
        materialId  = String,
        wallMask    = Vector[Int32],
        manualTiles = List[ManualTile],
        decorTiles  = List[ManualTile],
        entities    = List[Entity]
    }

    /// `Saveable[Level]` を実装可能にするための単一 case ラッパ。
    pub enum Level {
        case Level(LevelData)
    }

    /// `Level` から内部の record を取り出す。
    pub def levelData(l: Level): LevelData =
        let Level.Level(d) = l; d

    /// 描画タイル 1 枚の記述。autotile の上書きにも、autotile 無しの素描画にも使う。
    /// `srcX` / `srcY` は tileset PNG 上のピクセル位置 (LDtk の autoLayerTiles.src 由来)。
    /// tileset の spacing / margin を持つテクスチャでも正確に復元できるようピクセル単位で保存する。
    /// flipH / flipV は LDtk 由来のタイル flip を保持。JSON では false の場合に出力しない。
    pub type alias ManualTile = {
        x     = Int32,
        y     = Int32,
        srcX  = Int32,
        srcY  = Int32,
        flipH = Bool,
        flipV = Bool
    }

    pub type alias Entity = {
        identifier = String,
        x          = Int32,
        y          = Int32,
        fields     = Map[String, FieldValue]
    }

    /// Entity の custom field 値。文字列 / 整数 / Bool の 3 種類だけ MVP で扱う。
    /// JSON は単一キー判別 (`{"string":...}` / `{"int":...}` / `{"bool":...}`)。
    pub enum FieldValue with Eq, ToString {
        case StringV(String)
        case IntV(Int32)
        case BoolV(Bool)
    }

    /// Material の中身。
    pub type alias MaterialData = {
        tileset      = String,
        tileSize     = Int32,
        wallMap      = Map[String, (Int32, Int32)],
        floorPalette = List[(Int32, Int32)],
        decorPalette = List[(Int32, Int32)]
    }

    /// `Saveable[Material]` を実装可能にするための単一 case ラッパ。
    pub enum Material {
        case Material(MaterialData)
    }

    /// `Material` から内部の record を取り出す。
    pub def materialData(m: Material): MaterialData =
        let Material.Material(d) = m; d

    /// "TRBL" 4-bit 文字列キーの完全集合。Material の wallMap は
    /// 起動時にこの 16 個全てを含む必要がある。
    pub def wallMapKeys(): List[String] =
        "0000" :: "0001" :: "0010" :: "0011" ::
        "0100" :: "0101" :: "0110" :: "0111" ::
        "1000" :: "1001" :: "1010" :: "1011" ::
        "1100" :: "1101" :: "1110" :: "1111" :: Nil
}

// ════════════════════════════════════════════════════════════════════════
// Saveable instance — round-trip JSON
// ════════════════════════════════════════════════════════════════════════

instance Saveable[MapResource.Level] {
    pub def toJson(value: MapResource.Level): Json.JsonElement =
        MapResourceCodec.encodeLevel(value)

    pub def fromJson(element: Json.JsonElement): Option[MapResource.Level] =
        MapResourceCodec.decodeLevel(element)
}

instance Saveable[MapResource.Material] {
    pub def toJson(value: MapResource.Material): Json.JsonElement =
        MapResourceCodec.encodeMaterial(value)

    pub def fromJson(element: Json.JsonElement): Option[MapResource.Material] =
        MapResourceCodec.decodeMaterial(element)
}

instance Saveable[MapResource.FieldValue] {
    pub def toJson(value: MapResource.FieldValue): Json.JsonElement =
        MapResourceCodec.encodeFieldValue(value)

    pub def fromJson(element: Json.JsonElement): Option[MapResource.FieldValue] =
        MapResourceCodec.decodeFieldValue(element)
}

/// MapResource の JSON エンコード／デコード本体。
/// 外部からは `Saveable[...]` 経由でしか触らない想定。
mod MapResourceCodec {
    import java.math.{BigDecimal => JBigDecimal}

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber, JsonBool, JsonArray}
    use MapResource.{Level, LevelData, ManualTile, Entity, FieldValue, Material, MaterialData}

    // ── Level ──

    pub def encodeLevel(l: Level): JsonElement =
        let d = MapResource.levelData(l);
        let base = Map#{
            "tileSize"    => JsonNumber(intToBd(d#tileSize)),
            "width"       => JsonNumber(intToBd(d#width)),
            "height"      => JsonNumber(intToBd(d#height)),
            "materialId"  => JsonString(d#materialId),
            "wallMask"    => encodeIntVector(d#wallMask),
            "manualTiles" => JsonArray(d#manualTiles |> List.map(encodeManualTile) |> List.toVector),
            "entities"    => JsonArray(d#entities    |> List.map(encodeEntity)     |> List.toVector)
        };
        // decorTiles は空なら省略 (後方互換: 既存 .map.json に decorTiles キーが無くても decode 可)
        let withDecor = if (List.isEmpty(d#decorTiles)) base
                        else Map.insert("decorTiles",
                            JsonArray(d#decorTiles |> List.map(encodeManualTile) |> List.toVector),
                            base);
        JsonObject(withDecor)

    pub def decodeLevel(element: JsonElement): Option[Level] =
        forM (
            obj           <- expectObject(element);
            tileSizeJ     <- Map.get("tileSize",    obj);
            widthJ        <- Map.get("width",       obj);
            heightJ       <- Map.get("height",      obj);
            materialIdJ   <- Map.get("materialId",  obj);
            wallMaskJ     <- Map.get("wallMask",    obj);
            manualTilesJ  <- Map.get("manualTiles", obj);
            entitiesJ     <- Map.get("entities",    obj);
            tileSize      <- expectInt(tileSizeJ);
            width         <- expectInt(widthJ);
            height        <- expectInt(heightJ);
            materialId    <- expectString(materialIdJ);
            wallMask      <- decodeIntVector(wallMaskJ);
            manualTiles   <- decodeList(decodeManualTile, manualTilesJ);
            entities      <- decodeList(decodeEntity,     entitiesJ);
            // decorTiles は省略可能 (デフォルト Nil)
            decorTiles    <- match Map.get("decorTiles", obj) {
                case None     => Some((Nil: List[ManualTile]))
                case Some(dj) => decodeList(decodeManualTile, dj)
            }
        ) yield Level.Level(({
            tileSize    = tileSize,
            width       = width,
            height      = height,
            materialId  = materialId,
            wallMask    = wallMask,
            manualTiles = manualTiles,
            decorTiles  = decorTiles,
            entities    = entities
        }: LevelData))

    // ── ManualTile ──

    def encodeManualTile(t: ManualTile): JsonElement =
        let base = Map#{
            "x"    => JsonNumber(intToBd(t#x)),
            "y"    => JsonNumber(intToBd(t#y)),
            "srcX" => JsonNumber(intToBd(t#srcX)),
            "srcY" => JsonNumber(intToBd(t#srcY))
        };
        let withH = if (t#flipH) Map.insert("flipH", JsonBool(true), base) else base;
        let withV = if (t#flipV) Map.insert("flipV", JsonBool(true), withH) else withH;
        JsonObject(withV)

    def decodeManualTile(element: JsonElement): Option[ManualTile] =
        forM (
            obj   <- expectObject(element);
            xJ    <- Map.get("x",    obj);
            yJ    <- Map.get("y",    obj);
            sxJ   <- Map.get("srcX", obj);
            syJ   <- Map.get("srcY", obj);
            x     <- expectInt(xJ);
            y     <- expectInt(yJ);
            srcX  <- expectInt(sxJ);
            srcY  <- expectInt(syJ)
        ) yield {
            let flipH = match Map.get("flipH", obj) {
                case Some(JsonBool(b)) => b
                case _                 => false
            };
            let flipV = match Map.get("flipV", obj) {
                case Some(JsonBool(b)) => b
                case _                 => false
            };
            ({x = x, y = y, srcX = srcX, srcY = srcY, flipH = flipH, flipV = flipV}: ManualTile)
        }

    // ── Entity ──

    def encodeEntity(e: Entity): JsonElement =
        JsonObject(Map#{
            "identifier" => JsonString(e#identifier),
            "x"          => JsonNumber(intToBd(e#x)),
            "y"          => JsonNumber(intToBd(e#y)),
            "fields"     => encodeFieldsMap(e#fields)
        })

    def decodeEntity(element: JsonElement): Option[Entity] =
        forM (
            obj          <- expectObject(element);
            identifierJ  <- Map.get("identifier", obj);
            xJ           <- Map.get("x",          obj);
            yJ           <- Map.get("y",          obj);
            fieldsJ      <- Map.get("fields",     obj);
            identifier   <- expectString(identifierJ);
            x            <- expectInt(xJ);
            y            <- expectInt(yJ);
            fields       <- decodeFieldsMap(fieldsJ)
        ) yield ({identifier = identifier, x = x, y = y, fields = fields}: Entity)

    def encodeFieldsMap(m: Map[String, FieldValue]): JsonElement =
        let inner = m
            |> Map.foldLeftWithKey((acc, name, v) ->
                Map.insert(name, encodeFieldValue(v), acc),
                Map.empty());
        JsonObject(inner)

    def decodeFieldsMap(element: JsonElement): Option[Map[String, FieldValue]] =
        forM (
            obj <- expectObject(element);
            res <- Map.foldLeftWithKey((acc, name, json) ->
                       Option.flatMap(soFar ->
                           decodeFieldValue(json) |> Option.map(v -> Map.insert(name, v, soFar)),
                           acc),
                       Some(Map.empty()),
                       obj)
        ) yield res

    // ── FieldValue ──

    pub def encodeFieldValue(v: FieldValue): JsonElement = match v {
        case FieldValue.StringV(s) => JsonObject(Map#{"string" => JsonString(s)})
        case FieldValue.IntV(i)    => JsonObject(Map#{"int"    => JsonNumber(intToBd(i))})
        case FieldValue.BoolV(b)   => JsonObject(Map#{"bool"   => JsonBool(b)})
    }

    pub def decodeFieldValue(element: JsonElement): Option[FieldValue] =
        forM (
            obj  <- expectObject(element);
            pair <- singleEntry(obj);
            fv   <- match pair {
                case ("string", JsonString(s)) => Some(FieldValue.StringV(s))
                case ("int",    j)             => expectInt(j)  |> Option.map(FieldValue.IntV)
                case ("bool",   JsonBool(b))   => Some(FieldValue.BoolV(b))
                case _                         => None
            }
        ) yield fv

    // ── Material ──

    pub def encodeMaterial(m: Material): JsonElement =
        let d = MapResource.materialData(m);
        JsonObject(Map#{
            "tileset"      => JsonString(d#tileset),
            "tileSize"     => JsonNumber(intToBd(d#tileSize)),
            "wallMap"      => encodeWallMap(d#wallMap),
            "floorPalette" => encodeCoordList(d#floorPalette),
            "decorPalette" => encodeCoordList(d#decorPalette)
        })

    pub def decodeMaterial(element: JsonElement): Option[Material] =
        forM (
            obj            <- expectObject(element);
            tilesetJ       <- Map.get("tileset",      obj);
            tileSizeJ      <- Map.get("tileSize",     obj);
            wallMapJ       <- Map.get("wallMap",      obj);
            floorJ         <- Map.get("floorPalette", obj);
            decorJ         <- Map.get("decorPalette", obj);
            tileset        <- expectString(tilesetJ);
            tileSize       <- expectInt(tileSizeJ);
            wallMap        <- decodeWallMap(wallMapJ);
            floorPalette   <- decodeCoordList(floorJ);
            decorPalette   <- decodeCoordList(decorJ)
        ) yield Material.Material(({
            tileset      = tileset,
            tileSize     = tileSize,
            wallMap      = wallMap,
            floorPalette = floorPalette,
            decorPalette = decorPalette
        }: MaterialData))

    def encodeWallMap(m: Map[String, (Int32, Int32)]): JsonElement =
        let inner = m
            |> Map.foldLeftWithKey((acc, key, coord) ->
                Map.insert(key, encodeCoord(coord), acc),
                Map.empty());
        JsonObject(inner)

    def decodeWallMap(element: JsonElement): Option[Map[String, (Int32, Int32)]] =
        forM (
            obj <- expectObject(element);
            res <- Map.foldLeftWithKey((acc, key, json) ->
                       Option.flatMap(soFar ->
                           decodeCoord(json) |> Option.map(c -> Map.insert(key, c, soFar)),
                           acc),
                       Some(Map.empty()),
                       obj)
        ) yield res

    def encodeCoord(coord: (Int32, Int32)): JsonElement =
        let (col, row) = coord;
        JsonArray(Vector#{JsonNumber(intToBd(col)), JsonNumber(intToBd(row))})

    def decodeCoord(element: JsonElement): Option[(Int32, Int32)] = match element {
        case JsonArray(items) =>
            match Vector.toList(items) {
                case j1 :: j2 :: Nil =>
                    forM (
                        col <- expectInt(j1);
                        row <- expectInt(j2)
                    ) yield (col, row)
                case _ => None
            }
        case _ => None
    }

    def encodeCoordList(coords: List[(Int32, Int32)]): JsonElement =
        JsonArray(coords |> List.map(encodeCoord) |> List.toVector)

    def decodeCoordList(element: JsonElement): Option[List[(Int32, Int32)]] =
        decodeList(decodeCoord, element)

    // ── ヘルパー ──

    def encodeIntVector(v: Vector[Int32]): JsonElement =
        JsonArray(v |> Vector.map(n -> JsonNumber(intToBd(n))))

    def decodeIntVector(element: JsonElement): Option[Vector[Int32]] = match element {
        case JsonArray(items) =>
            List.foldRight(item -> acc ->
                Option.flatMap(soFar ->
                    expectInt(item) |> Option.map(n -> n :: soFar),
                    acc),
                Some(Nil), Vector.toList(items))
            |> Option.map(List.toVector)
        case _ => None
    }

    /// JsonArray を `decode` で 1 要素ずつデコードし List にまとめる。
    /// 失敗要素があれば全体 None。
    def decodeList(decode: JsonElement -> Option[a], element: JsonElement): Option[List[a]] =
        match element {
            case JsonArray(items) =>
                List.foldRight(item -> acc ->
                    Option.flatMap(soFar ->
                        decode(item) |> Option.map(x -> x :: soFar),
                        acc),
                    Some(Nil), Vector.toList(items))
            case _ => None
        }

    def singleEntry(map: Map[String, JsonElement]): Option[(String, JsonElement)] =
        match Map.toList(map) {
            case head :: Nil => Some(head)
            case _           => None
        }

    def expectObject(element: JsonElement): Option[Map[String, JsonElement]] =
        match element {
            case JsonObject(map) => Some(map)
            case _               => None
        }

    def expectString(element: JsonElement): Option[String] =
        match element {
            case JsonString(text) => Some(text)
            case _                => None
        }

    def expectInt(element: JsonElement): Option[Int32] = match element {
        case JsonNumber(bd) => BigDecimal.tryToFloat64(bd) |> Option.flatMap(Float64.tryToInt32)
        case _              => None
    }

    /// Int32 → BigDecimal。trailing zero を取り除いて `100` (not `100.0`) で書き出す。
    /// `Resource.flix` の同名 helper と同じ実装。
    def intToBd(value: Int32): BigDecimal =
        unsafe IO {
            let stripped = JBigDecimal.valueOf(Int32.toFloat64(value)).stripTrailingZeros();
            if (stripped.scale() < 0) stripped.setScale(0) else stripped
        }
}
