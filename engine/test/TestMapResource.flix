// MapResource の Saveable round-trip テスト。
//
// 観点:
//   - Level / Material / FieldValue が encode → parse → decode で復元される
//   - wallMap の 16 キーが全て保持される
//   - manualTiles / entities / fields の各 nested 構造が壊れない
//   - 壊れた JSON は None を返す

mod TestMapResource {

    use MapResource.{Level, LevelData, ManualTile, Entity, FieldValue, Material, MaterialData}

    // ========================================================================
    // FieldValue round-trip
    // ========================================================================

    @Test
    def testFieldValueStringRoundTrip(): Unit \ Assert =
        let original = FieldValue.StringV("goblin");
        let restored = roundTripFieldValue(original);
        Assert.assertEq(expected = Some(original), restored)

    @Test
    def testFieldValueIntRoundTrip(): Unit \ Assert =
        let original = FieldValue.IntV(42);
        let restored = roundTripFieldValue(original);
        Assert.assertEq(expected = Some(original), restored)

    @Test
    def testFieldValueBoolRoundTrip(): Unit \ Assert =
        let original = FieldValue.BoolV(true);
        let restored = roundTripFieldValue(original);
        Assert.assertEq(expected = Some(original), restored)

    // ========================================================================
    // Material round-trip
    // ========================================================================

    /// 16 個の wallMap キーと 2 つのパレットを持つ Material が round-trip する
    @Test
    def testMaterialRoundTrip(): Unit \ Assert =
        let original = sampleMaterial();
        let origData = MapResource.materialData(original);
        let restored = roundTripMaterial(original);
        let restoredOk =
            Option.nonEmpty(restored)
            and (match restored {
                case Some(m) =>
                    let d = MapResource.materialData(m);
                    d#tileset    == origData#tileset
                    and d#tileSize == origData#tileSize
                    and Map.size(d#wallMap)        == Map.size(origData#wallMap)
                    and List.length(d#floorPalette) == List.length(origData#floorPalette)
                    and List.length(d#decorPalette) == List.length(origData#decorPalette)
                case None    => false
            });
        Assert.assertEq(expected = true, restoredOk)

    /// 16 個のキーが全て保持される
    @Test
    def testMaterialWallMapKeysComplete(): Unit \ Assert =
        let original = sampleMaterial();
        let restored = roundTripMaterial(original);
        let keys = match restored {
            case Some(m) => Map.keysOf(MapResource.materialData(m)#wallMap)
            case None    => Set.empty()
        };
        Assert.assertEq(
            expected = List.toSet(MapResource.wallMapKeys()),
            keys)

    /// 任意の wallMap キーの (col, row) ペアが復元される
    @Test
    def testMaterialWallMapValuePreserved(): Unit \ Assert =
        let original = sampleMaterial();
        let restored = roundTripMaterial(original);
        let coord1010 = match restored {
            case Some(m) => Map.get("1010", MapResource.materialData(m)#wallMap)
            case None    => None
        };
        Assert.assertEq(expected = Some((7, 2)), coord1010)

    // ========================================================================
    // Level round-trip
    // ========================================================================

    @Test
    def testLevelRoundTrip(): Unit \ Assert =
        let original = sampleLevel();
        let origData = MapResource.levelData(original);
        let restored = roundTripLevel(original);
        let restoredOk =
            Option.nonEmpty(restored)
            and (match restored {
                case Some(l) =>
                    let d = MapResource.levelData(l);
                    d#tileSize == origData#tileSize
                    and d#width  == origData#width
                    and d#height == origData#height
                    and d#materialId == origData#materialId
                    and List.length(d#manualTiles) == List.length(origData#manualTiles)
                    and List.length(d#decorTiles)  == List.length(origData#decorTiles)
                    and List.length(d#entities)    == List.length(origData#entities)
                case None    => false
            });
        Assert.assertEq(expected = true, restoredOk)

    @Test
    def testLevelEntityFieldsPreserved(): Unit \ Assert =
        let original = sampleLevel();
        let restored = roundTripLevel(original);
        let firstEntity = match restored {
            case Some(l) => List.head(MapResource.levelData(l)#entities)
            case None    => None
        };
        let enemyId = match firstEntity {
            case Some(e) => Map.get("enemyId", e#fields)
            case None    => None
        };
        Assert.assertEq(
            expected = Some(FieldValue.StringV("goblin")),
            enemyId)

    @Test
    def testLevelManualTilePreserved(): Unit \ Assert =
        let original = sampleLevel();
        let restored = roundTripLevel(original);
        let firstTile = match restored {
            case Some(l) => List.head(MapResource.levelData(l)#manualTiles)
            case None    => None
        };
        let tileCoord = match firstTile {
            case Some(t) => Some((t#x, t#y, t#srcX, t#srcY))
            case None    => None
        };
        Assert.assertEq(expected = Some((3, 4, 16, 0)), tileCoord)

    // ========================================================================
    // 壊れた JSON は None
    // ========================================================================

    @Test
    def testInvalidLevelJsonReturnsNone(): Unit \ Assert =
        let parsed = Json.Parse.parse("{\"tileSize\": 16}");
        let decoded: Option[Level] =
            Option.flatMap(Saveable.fromJson, parsed);
        Assert.assertEq(expected = false, Option.nonEmpty(decoded))

    @Test
    def testInvalidMaterialJsonReturnsNone(): Unit \ Assert =
        let parsed = Json.Parse.parse("{\"tileset\": \"x\"}");
        let decoded: Option[Material] =
            Option.flatMap(Saveable.fromJson, parsed);
        Assert.assertEq(expected = false, Option.nonEmpty(decoded))

    // ========================================================================
    // ヘルパー
    // ========================================================================

    def roundTripFieldValue(v: FieldValue): Option[FieldValue] =
        let json    = Saveable.toJson(v);
        let pretty  = Json.Write.toPrettyString(2, json);
        Json.Parse.parse(pretty) |> Option.flatMap(Saveable.fromJson)

    def roundTripMaterial(m: Material): Option[Material] =
        let json    = Saveable.toJson(m);
        let pretty  = Json.Write.toPrettyString(2, json);
        Json.Parse.parse(pretty) |> Option.flatMap(Saveable.fromJson)

    def roundTripLevel(l: Level): Option[Level] =
        let json    = Saveable.toJson(l);
        let pretty  = Json.Write.toPrettyString(2, json);
        Json.Parse.parse(pretty) |> Option.flatMap(Saveable.fromJson)

    /// 16 キー全て埋めた最小 Material。座標値は適当だが、後段テストで
    /// "1010" → (7, 2) のように具体値を参照する。
    def sampleMaterial(): Material =
        let wallMap = Map#{
            "0000" => (0, 0), "0001" => (1, 0), "0010" => (2, 0), "0011" => (3, 0),
            "0100" => (4, 0), "0101" => (5, 0), "0110" => (6, 0), "0111" => (7, 0),
            "1000" => (0, 1), "1001" => (1, 1), "1010" => (7, 2), "1011" => (3, 1),
            "1100" => (4, 1), "1101" => (5, 1), "1110" => (6, 1), "1111" => (7, 1)
        };
        Material.Material(({
            tileset      = "inca_walls",
            tileSize     = 16,
            wallMap      = wallMap,
            floorPalette = (0, 5) :: (1, 5) :: Nil,
            decorPalette = (5, 5) :: Nil,
            autoRules    = (Nil: List[MapResource.AutoRule])
        }: MaterialData))

    /// 4x3 の小さな部屋 + decorTile + manualTile + entity (enemyId="goblin")
    def sampleLevel(): Level =
        let manual = ({x = 3, y = 4, srcX = 16, srcY = 0, flipH = false, flipV = false}: ManualTile) :: Nil;
        let decor  = ({x = 1, y = 1, srcX = 0,  srcY = 0, flipH = false, flipV = false}: ManualTile)
                   :: ({x = 2, y = 1, srcX = 0,  srcY = 0, flipH = false, flipV = false}: ManualTile) :: Nil;
        let goblinFields = Map#{
            "enemyId" => FieldValue.StringV("goblin"),
            "isElite" => FieldValue.BoolV(false),
            "level"   => FieldValue.IntV(3)
        };
        let entity = ({
            identifier = "Spawn",
            x          = 1, y = 1,
            fields     = goblinFields
        }: Entity);
        Level.Level(({
            tileSize      = 16,
            width         = 4,
            height        = 3,
            materialId    = "inca_stone",
            manualTiles   = manual,
            decorTiles    = decor,
            entities      = entity :: Nil,
            editorPalette = (None: Option[MapResource.EditorPalette]),
            intGrid       = (Vector#{}: Vector[Int32])
        }: LevelData))
}
