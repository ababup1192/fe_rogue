/// LDtk 風の独自スキーマでマップを表現する Resource 群。
///
/// `Level` (マップ実体) と `Material` (素材) を別々に永続化する設計で、
/// Level は `materialId` で Material を参照する。これにより同じマップを
/// 別 Material に差し替えて複数テーマの見た目を再生できる。
///
/// JSON 形状の概略:
///   Level     : {"tileSize":16, "width":10, "height":10, "materialId":"inca_stone",
///                "decorTiles":[{"x":..,"y":..,"srcX":..,"srcY":..}, ...],
///                "manualTiles":[{"x":..,"y":..,"srcX":..,"srcY":..}, ...],
///                "entities":[{"identifier":"Door","x":5,"y":3,"fields":{...}}]}
///   Material  : {"tileset":"inca_walls", "tileSize":16,
///                "wallMap":{"0000":[3,5], "0001":[4,5], ...16件},
///                "floorPalette":[[0,0],[1,0]], "decorPalette":[[5,5]]}
///   FieldValue: {"string":"goblin"} / {"int":3} / {"bool":true}
///
/// 自動壁 (AutoLayerWalls) は **decorTiles のセル (=床)** を元に動的計算される:
///   床のないセルで 8 近傍に床があるセル = 壁 (描画 + 衝突)
/// `wallMap` のキーは "TRBL" 形式 ("0000" 〜 "1111", 16 通り)。
/// マップ縁は wall として扱う慣習 (LDTKRules と同じ)。
///
/// 設計メモ: Flix は type alias に instance を定義できないため、Level / Material は
/// 単一 case の enum でラップする (UnitCatalog と同じパターン)。データへのアクセスは
/// `levelData` / `materialData` で record を取り出す。
mod MapResource {

    /// Level の中身。フィールドの集合はここに集約し、enum 経由で持ち回す。
    /// - `manualTiles` は Walls 層由来 (自動壁の上書き、衝突は持たない)
    /// - `decorTiles`  は Floor 層由来 (床、=通行可、=自動壁の判定源)
    /// - `editorPalette` は IDE エディタ専用の Palette 設定 (Sheet 名 / cellSize / margin)。
    ///   ゲームランタイム (MapLoader 等) は無視する。Map ごとに別の設定を持たせるため。
    /// LDtk は Walls と Floor が別 tileset を使う構成のため、層を分けて保持する。
    pub type alias LevelData = {
        tileSize      = Int32,
        width         = Int32,
        height        = Int32,
        materialId    = String,
        manualTiles   = List[ManualTile],
        decorTiles    = List[ManualTile],
        entities      = List[Entity],
        editorPalette = Option[EditorPalette]
    }

    /// IDE Maps タブの Palette 設定 (Floor / Walls 各層)。
    /// `.map.json` 内に書かれることで Map 切替時に復元される。
    pub type alias EditorPalette = {
        floor = EditorLayerPalette,
        walls = EditorLayerPalette
    }

    /// 1 レイヤー分の Palette 設定。
    pub type alias EditorLayerPalette = {
        textureName = Option[String],
        cellW       = Int32,
        cellH       = Int32,
        marginX     = Int32,
        marginY     = Int32
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
    ///   tileSize : tileset PNG 上の 1 タイルの px (正方形前提)
    /// タイルの切り抜きサイズ / マージン / Palette ズームは IDE 側 Walls Palette と共有する。
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

    /// "TRBL" 4-bit 文字列キーの完全集合 (旧仕様、フォールバック用)。
    pub def wallMapKeys(): List[String] =
        "0000" :: "0001" :: "0010" :: "0011" ::
        "0100" :: "0101" :: "0110" :: "0111" ::
        "1000" :: "1001" :: "1010" :: "1011" ::
        "1100" :: "1101" :: "1110" :: "1111" :: Nil

    /// 4-trit (W=壁, F=床, E=空) の auto-layer パターンを「使用頻度別セクション」で並べた定義。
    /// IDE の auto-layer タブで段階的に開示するため、セクション毎にキーをまとめる。
    /// 各タプル = (見出し用ヒント, キーリスト)。見出しは表示しないが debug 用に保持。
    pub def wallMapSections(): List[(String, List[String])] =
        // Section 1: 四角い部屋の最低限 (8 パターン)
        ("room-basic",
            "EWFW" ::  // 上辺 (床が真下)
            "FWEW" ::  // 下辺 (床が真上)
            "WFWE" ::  // 左辺 (床が真右)
            "WEWF" ::  // 右辺 (床が真左)
            "EWWE" ::  // 左上外コーナー
            "EEWW" ::  // 右上外コーナー
            "WWEE" ::  // 左下外コーナー
            "WEEW" ::  // 右下外コーナー
            Nil) ::
        // Section 2: 壁の塊 / 厚い壁 (5 パターン)
        ("solid-walls",
            "WWWW" ::  // 中央壁 (壁の中身)
            "EWWW" ::  // 上が空、他壁 (壁の上端)
            "WEWW" ::  // 右が空、他壁
            "WWEW" ::  // 下が空、他壁
            "WWWE" ::  // 左が空、他壁
            Nil) ::
        // Section 3: 通路 T 字 (床が一方向だけ通る、4 パターン)
        ("corridors",
            "FWWW" ::  // 床が上、他壁 (上から床に降りる T 字)
            "WFWW" ::  // 床が右
            "WWFW" ::  // 床が下
            "WWWF" ::  // 床が左
            Nil) ::
        // Section 4: 行き止まり / 孤立 (7 パターン)
        ("dead-ends",
            "WEEE" ::  // 上にだけ壁 (行き止まりの先)
            "EWEE" ::  // 右にだけ壁
            "EEWE" ::  // 下にだけ壁
            "EEEW" ::  // 左にだけ壁
            "EEEE" ::  // 孤立壁
            "FEEE" ::  // 床が上、他空 (床と空の境界)
            "EFEE" ::  // 床が右、他空
            Nil) ::
        Nil
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
    use MapResource.{Level, LevelData, ManualTile, Entity, FieldValue, Material, MaterialData, EditorPalette, EditorLayerPalette}

    // ── Level ──

    pub def encodeLevel(l: Level): JsonElement =
        let d = MapResource.levelData(l);
        let base = Map#{
            "tileSize"    => JsonNumber(intToBd(d#tileSize)),
            "width"       => JsonNumber(intToBd(d#width)),
            "height"      => JsonNumber(intToBd(d#height)),
            "materialId"  => JsonString(d#materialId),
            "manualTiles" => JsonArray(d#manualTiles |> List.map(encodeManualTile) |> List.toVector),
            "entities"    => JsonArray(d#entities    |> List.map(encodeEntity)     |> List.toVector)
        };
        // decorTiles は空なら省略 (後方互換: 既存 .map.json に decorTiles キーが無くても decode 可)
        let withDecor = if (List.isEmpty(d#decorTiles)) base
                        else Map.insert("decorTiles",
                            JsonArray(d#decorTiles |> List.map(encodeManualTile) |> List.toVector),
                            base);
        // editorPalette は None なら省略
        let withEditor = match d#editorPalette {
            case None    => withDecor
            case Some(p) => Map.insert("editorPalette", encodeEditorPalette(p), withDecor)
        };
        JsonObject(withEditor)

    pub def decodeLevel(element: JsonElement): Option[Level] =
        forM (
            obj           <- expectObject(element);
            tileSizeJ     <- Map.get("tileSize",    obj);
            widthJ        <- Map.get("width",       obj);
            heightJ       <- Map.get("height",      obj);
            materialIdJ   <- Map.get("materialId",  obj);
            manualTilesJ  <- Map.get("manualTiles", obj);
            entitiesJ     <- Map.get("entities",    obj);
            tileSize      <- expectInt(tileSizeJ);
            width         <- expectInt(widthJ);
            height        <- expectInt(heightJ);
            materialId    <- expectString(materialIdJ);
            manualTiles   <- decodeList(decodeManualTile, manualTilesJ);
            entities      <- decodeList(decodeEntity,     entitiesJ);
            // decorTiles は省略可能 (デフォルト Nil)
            decorTiles    <- match Map.get("decorTiles", obj) {
                case None     => Some((Nil: List[ManualTile]))
                case Some(dj) => decodeList(decodeManualTile, dj)
            }
            // 旧 wallMask キーがあっても無視 (前方互換)
        ) yield {
            // editorPalette は省略可能 (デフォルト None)
            let editorPalette = match Map.get("editorPalette", obj) {
                case None    => None
                case Some(e) => decodeEditorPalette(e)
            };
            Level.Level(({
                tileSize      = tileSize,
                width         = width,
                height        = height,
                materialId    = materialId,
                manualTiles   = manualTiles,
                decorTiles    = decorTiles,
                entities      = entities,
                editorPalette = editorPalette
            }: LevelData))
        }

    // ── EditorPalette ──

    def encodeEditorPalette(p: EditorPalette): JsonElement =
        JsonObject(Map#{
            "floor" => encodeEditorLayerPalette(p#floor),
            "walls" => encodeEditorLayerPalette(p#walls)
        })

    def decodeEditorPalette(element: JsonElement): Option[EditorPalette] =
        forM (
            obj   <- expectObject(element);
            floorJ <- Map.get("floor", obj);
            wallsJ <- Map.get("walls", obj);
            floor  <- decodeEditorLayerPalette(floorJ);
            walls  <- decodeEditorLayerPalette(wallsJ)
        ) yield ({floor = floor, walls = walls}: EditorPalette)

    def encodeEditorLayerPalette(lp: EditorLayerPalette): JsonElement = {
        let base = Map#{
            "cellW"   => JsonNumber(intToBd(lp#cellW)),
            "cellH"   => JsonNumber(intToBd(lp#cellH)),
            "marginX" => JsonNumber(intToBd(lp#marginX)),
            "marginY" => JsonNumber(intToBd(lp#marginY))
        };
        let withTex = match lp#textureName {
            case None    => base
            case Some(n) => Map.insert("textureName", JsonString(n), base)
        };
        JsonObject(withTex)
    }

    def decodeEditorLayerPalette(element: JsonElement): Option[EditorLayerPalette] =
        forM (
            obj   <- expectObject(element);
            cellWJ <- Map.get("cellW", obj);
            cellHJ <- Map.get("cellH", obj);
            cellW  <- expectInt(cellWJ);
            cellH  <- expectInt(cellHJ)
        ) yield {
            let marginX = match Map.get("marginX", obj) {
                case Some(j) => match expectInt(j) { case Some(v) => v case None => 0 }
                case None    => 0
            };
            let marginY = match Map.get("marginY", obj) {
                case Some(j) => match expectInt(j) { case Some(v) => v case None => 0 }
                case None    => 0
            };
            let textureName = match Map.get("textureName", obj) {
                case Some(JsonString(s)) => Some(s)
                case _                   => None
            };
            ({textureName = textureName, cellW = cellW, cellH = cellH,
              marginX = marginX, marginY = marginY}: EditorLayerPalette)
        }

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
