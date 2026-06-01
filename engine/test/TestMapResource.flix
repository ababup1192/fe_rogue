// MapResource の Saveable round-trip テスト。
//
// 観点:
//   - Level / Material / FieldValue が encode → parse → decode で復元される
//   - wallMap の 16 キーが全て保持される
//   - manualTiles / entities / fields の各 nested 構造が壊れない
//   - 壊れた JSON は None を返す

mod TestMapResource {

    use MapResource.{Level, LevelData, ManualTile, Entity, FieldValue, Material, MaterialData, AutoRule, PatternCell}

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

    // ========================================================================
    // PatternCell matching (engine/src/MapResource.flix)
    // ========================================================================

    @Test
    def testPatternCellUnspecifiedMatchesEverything(): Unit \ Assert =
        let matches0 = MapResource.patternCellMatches(PatternCell.Unspecified, 0i32);
        let matches1 = MapResource.patternCellMatches(PatternCell.Unspecified, 1i32);
        let matches2 = MapResource.patternCellMatches(PatternCell.Unspecified, 2i32);
        Assert.assertEq(expected = true, matches0 and matches1 and matches2)

    @Test
    def testPatternCellAnythingRejectsZero(): Unit \ Assert =
        let m = MapResource.patternCellMatches(PatternCell.Anything, 0i32);
        Assert.assertEq(expected = false, m)

    @Test
    def testPatternCellAnythingAcceptsNonZero(): Unit \ Assert =
        let m1 = MapResource.patternCellMatches(PatternCell.Anything, 1i32);
        let m2 = MapResource.patternCellMatches(PatternCell.Anything, 2i32);
        Assert.assertEq(expected = true, m1 and m2)

    @Test
    def testPatternCellNothingAcceptsOnlyZero(): Unit \ Assert =
        let m0 = MapResource.patternCellMatches(PatternCell.Nothing, 0i32);
        let m1 = MapResource.patternCellMatches(PatternCell.Nothing, 1i32);
        Assert.assertEq(expected = true, m0 and not m1)

    @Test
    def testPatternCellValueExactMatch(): Unit \ Assert =
        let mYes = MapResource.patternCellMatches(PatternCell.Value(2i32), 2i32);
        let mNo  = MapResource.patternCellMatches(PatternCell.Value(2i32), 1i32);
        Assert.assertEq(expected = true, mYes and not mNo)

    @Test
    def testPatternCellNotValueRejectsOnlyN(): Unit \ Assert =
        let mZero = MapResource.patternCellMatches(PatternCell.NotValue(1i32), 0i32);
        let mTwo  = MapResource.patternCellMatches(PatternCell.NotValue(1i32), 2i32);
        let mOne  = MapResource.patternCellMatches(PatternCell.NotValue(1i32), 1i32);
        Assert.assertEq(expected = true, mZero and mTwo and not mOne)

    // ========================================================================
    // ruleMatches: 3×3 pattern を 3×3 intGrid に対して評価
    // ========================================================================

    /// 全 Unspecified の 3×3 pattern は任意の intGrid にマッチする。
    @Test
    def testRuleMatchesAllUnspecified(): Unit \ Assert =
        let u = PatternCell.Unspecified;
        let pattern = Vector#{u, u, u, u, u, u, u, u, u};
        let rule = mkRule(pattern, 3);
        let intGrid = Vector#{1i32, 0i32, 2i32, 0i32, 1i32, 0i32, 2i32, 0i32, 1i32};
        let m = MapResource.ruleMatches(intGrid, 3, 3, 1, 1, rule);
        Assert.assertEq(expected = true, m)

    /// 中央 Value(1) は intGrid 中央が 1 のときマッチ。
    @Test
    def testRuleMatchesValueAtCenter(): Unit \ Assert =
        let u = PatternCell.Unspecified;
        let pattern = Vector#{u, u, u,
                               u, PatternCell.Value(1i32), u,
                               u, u, u};
        let rule = mkRule(pattern, 3);
        let intGrid = Vector#{0i32, 0i32, 0i32, 0i32, 1i32, 0i32, 0i32, 0i32, 0i32};
        let m = MapResource.ruleMatches(intGrid, 3, 3, 1, 1, rule);
        Assert.assertEq(expected = true, m)

    // testBuildAutoRuleTilesSkipsManualCoords は MapLoader.buildAutoRuleTiles を呼ぶが、
    // MapLoader は段階 2c で `examples/fe_rogue/src/lib/map/` へ移動したため
    // engine 側からは参照できなくなった。MapLoader 側のテストは fe_rogue 配下で
    // 追加する場合に書き直す (現状は MapResource 側の ruleMatches テストでカバー)。

    /// 中央 Value(1) を要求するルールは、intGrid 中央が床 (1) のときだけマッチし、
    /// 自動壁 (2) や空 (0) では拒否される (= 床上だけに装飾を置く LDtk 風ルール)。
    @Test
    def testRuleMatchesCenterMustBeFloor(): Unit \ Assert =
        let u = PatternCell.Unspecified;
        let pattern = Vector#{u, u, u,
                               u, PatternCell.Value(1i32), u,
                               u, u, u};
        let rule = mkRule(pattern, 3);
        let gridFloor = Vector#{0i32, 0i32, 0i32, 0i32, 1i32, 0i32, 0i32, 0i32, 0i32};
        let gridWall  = Vector#{0i32, 0i32, 0i32, 0i32, 2i32, 0i32, 0i32, 0i32, 0i32};
        let gridEmpty = Vector#{0i32, 0i32, 0i32, 0i32, 0i32, 0i32, 0i32, 0i32, 0i32};
        let mFloor = MapResource.ruleMatches(gridFloor, 3, 3, 1, 1, rule);
        let mWall  = MapResource.ruleMatches(gridWall,  3, 3, 1, 1, rule);
        let mEmpty = MapResource.ruleMatches(gridEmpty, 3, 3, 1, 1, rule);
        Assert.assertEq(expected = true, mFloor and not mWall and not mEmpty)

    /// Nothing (= IntGrid == 0) は intGrid に空セルがあるときだけマッチする。
    @Test
    def testRuleMatchesNothingRequiresEmpty(): Unit \ Assert =
        let u = PatternCell.Unspecified;
        let pattern = Vector#{u, PatternCell.Nothing, u,
                               u, u, u,
                               u, u, u};
        let rule = mkRule(pattern, 3);
        // pattern[1] (= 上中央) は Nothing を要求。intGrid[(1, 0)] = 1 なので拒否
        let intGridReject = Vector#{0i32, 1i32, 0i32, 0i32, 1i32, 0i32, 0i32, 0i32, 0i32};
        let mReject = MapResource.ruleMatches(intGridReject, 3, 3, 1, 1, rule);
        // intGrid[(1, 0)] = 0 ならマッチ
        let intGridAccept = Vector#{0i32, 0i32, 0i32, 0i32, 1i32, 0i32, 0i32, 0i32, 0i32};
        let mAccept = MapResource.ruleMatches(intGridAccept, 3, 3, 1, 1, rule);
        Assert.assertEq(expected = true, mAccept and not mReject)

    /// NotValue(1) は床ではないセル (空・壁・自動壁) でマッチする。
    @Test
    def testRuleMatchesNotValueOnePassesNonFloor(): Unit \ Assert =
        let u = PatternCell.Unspecified;
        let pattern = Vector#{u, PatternCell.NotValue(1i32), u,
                               u, u, u,
                               u, u, u};
        let rule = mkRule(pattern, 3);
        // pattern[1] = NotValue(1)。intGrid[(1, 0)] = 2 (自動壁) なのでマッチ
        let intGrid = Vector#{0i32, 2i32, 0i32, 0i32, 1i32, 0i32, 0i32, 0i32, 0i32};
        let m = MapResource.ruleMatches(intGrid, 3, 3, 1, 1, rule);
        Assert.assertEq(expected = true, m)

    /// 境界外は 0 (空) 扱い → Nothing でマッチ、Value(1) では拒否される。
    @Test
    def testRuleMatchesOutOfBoundsBehavesAsZero(): Unit \ Assert =
        let u = PatternCell.Unspecified;
        let nothing = PatternCell.Nothing;
        // pattern[0] は左上 (col=-1, row=-1) → 範囲外 → Nothing でマッチ
        let pattern = Vector#{nothing, u, u, u, u, u, u, u, u};
        let rule = mkRule(pattern, 3);
        let intGrid = Vector#{1i32, 1i32, 1i32, 1i32, 1i32, 1i32, 1i32, 1i32, 1i32};
        let m = MapResource.ruleMatches(intGrid, 3, 3, 0, 0, rule);
        Assert.assertEq(expected = true, m)

    @Test
    def testRuleMatchesOutOfBoundsAnythingFails(): Unit \ Assert =
        let u = PatternCell.Unspecified;
        // pattern[0] (左上 = 範囲外 = 0) を Anything (= !=0) で要求 → 不一致
        let pattern = Vector#{PatternCell.Anything, u, u, u, u, u, u, u, u};
        let rule = mkRule(pattern, 3);
        let intGrid = Vector#{1i32, 1i32, 1i32, 1i32, 1i32, 1i32, 1i32, 1i32, 1i32};
        let m = MapResource.ruleMatches(intGrid, 3, 3, 0, 0, rule);
        Assert.assertEq(expected = false, m)

    // ========================================================================
    // AutoRule: legacy migration / round-trip
    // ========================================================================

    /// legacy size=3 のルールは size=5 に padding migration される。
    @Test
    def testAutoRuleLegacySizeThreeMigratedToFive(): Unit \ Assert =
        let legacyJson =
            "{\"name\":\"L\",\"size\":3,\"srcX\":0,\"srcY\":0,\"pattern\":[0,0,0,0,-1,0,0,0,0]}";
        let parsed = Json.Parse.parse(legacyJson);
        let mat = legacyMaterialFromAutoRule(parsed);
        let info = match mat {
            case Some(m) => match List.head(MapResource.materialData(m)#autoRules) {
                case Some(r) => Some((r#size, Vector.length(r#pattern)))
                case None    => None
            }
            case None    => None
        };
        Assert.assertEq(expected = Some((5i32, 25)), info)

    /// "v" フィールド無しの legacy JSON: 旧 2 (size=3 の idx=1) は migration 後の
    /// 5×5 の idx=7 (= row 1, col 2) に NotValue(1) として現れる。
    @Test
    def testAutoRuleLegacyTwoBecomesNotValueOne(): Unit \ Assert =
        let legacyJson =
            "{\"name\":\"L\",\"size\":3,\"srcX\":0,\"srcY\":0,\"pattern\":[0,2,0,0,-1,0,0,1,0]}";
        let parsed = Json.Parse.parse(legacyJson);
        let mat = legacyMaterialFromAutoRule(parsed);
        let firstPattern = match mat {
            case Some(m) => match List.head(MapResource.materialData(m)#autoRules) {
                case Some(r) => r#pattern
                case None    => Vector#{}
            }
            case None    => Vector#{}
        };
        let cell = Vector.nth(7, firstPattern);
        Assert.assertEq(expected = Some(PatternCell.NotValue(1i32)), cell)

    /// Legacy -1 (中央装飾, size=3 idx=4) は migration 後の 5×5 中央 idx=12 で Unspecified。
    @Test
    def testAutoRuleLegacyCenterBecomesUnspecified(): Unit \ Assert =
        let legacyJson =
            "{\"name\":\"L\",\"size\":3,\"srcX\":0,\"srcY\":0,\"pattern\":[0,0,0,0,-1,0,0,0,0]}";
        let parsed = Json.Parse.parse(legacyJson);
        let mat = legacyMaterialFromAutoRule(parsed);
        let centerCell = match mat {
            case Some(m) => match List.head(MapResource.materialData(m)#autoRules) {
                case Some(r) => Vector.nth(12, r#pattern)
                case None    => None
            }
            case None    => None
        };
        Assert.assertEq(expected = Some(PatternCell.Unspecified), centerCell)

    /// Legacy 1 = 床 (size=3 idx=0) → migration 後の 5×5 idx=6 (= row 1, col 1) で Value(1)。
    @Test
    def testAutoRuleLegacyOneBecomesValueOne(): Unit \ Assert =
        let legacyJson =
            "{\"name\":\"L\",\"size\":3,\"srcX\":0,\"srcY\":0,\"pattern\":[1,0,0,0,-1,0,0,0,0]}";
        let parsed = Json.Parse.parse(legacyJson);
        let mat = legacyMaterialFromAutoRule(parsed);
        let cell = match mat {
            case Some(m) => match List.head(MapResource.materialData(m)#autoRules) {
                case Some(r) => Vector.nth(6, r#pattern)
                case None    => None
            }
            case None    => None
        };
        Assert.assertEq(expected = Some(PatternCell.Value(1i32)), cell)

    /// v=2 の round-trip で中央セルの値が保存される (Unspecified に潰されない)。
    @Test
    def testAutoRuleCenterValuePreservedOnRoundTrip(): Unit \ Assert =
        let u = PatternCell.Unspecified;
        // 5×5 の中央 (idx=12) に Value(1) を置く
        let pattern = Vector#{u, u, u, u, u,
                               u, u, u, u, u,
                               u, u, PatternCell.Value(1i32), u, u,
                               u, u, u, u, u,
                               u, u, u, u, u};
        let rule = ({name = "centerFloor", size = 5, pattern = pattern,
                      srcX = 0, srcY = 0}: AutoRule);
        let mat = Material.Material(({
            tileset      = "x",
            tileSize     = 16,
            wallMap      = Map.empty(),
            floorPalette = (Nil: List[(Int32, Int32)]),
            decorPalette = (Nil: List[(Int32, Int32)]),
            autoRules    = rule :: Nil
        }: MaterialData));
        let restored = roundTripMaterial(mat);
        let centerCell = match restored {
            case Some(m) => match List.head(MapResource.materialData(m)#autoRules) {
                case Some(r) => Vector.nth(12, r#pattern)
                case None    => None
            }
            case None    => None
        };
        Assert.assertEq(expected = Some(PatternCell.Value(1i32)), centerCell)

    /// 新仕様 (v=2) で書かれた JSON を round-trip。NotValue / Nothing / Anything が保存される。
    @Test
    def testAutoRuleRoundTripPreservesPatternCells(): Unit \ Assert =
        let original = sampleMaterialWithMixedPattern();
        let restored = roundTripMaterial(original);
        let restoredPattern = match restored {
            case Some(m) => match List.head(MapResource.materialData(m)#autoRules) {
                case Some(r) => r#pattern
                case None    => Vector#{}
            }
            case None    => Vector#{}
        };
        let origPattern = match List.head(MapResource.materialData(original)#autoRules) {
            case Some(r) => r#pattern
            case None    => Vector#{}
        };
        Assert.assertEq(expected = origPattern, restoredPattern)

    /// encodeAutoRule は "v" フィールドを JSON に書き出す。
    @Test
    def testAutoRuleEncodesVersionField(): Unit \ Assert =
        let original = sampleMaterialWithMixedPattern();
        let json = Saveable.toJson(original);
        let text = Json.Write.toPrettyString(2, json);
        let hasV = String.contains({substr = "\"v\""}, text);
        Assert.assertEq(expected = true, hasV)

    // ========================================================================
    // ヘルパー (AutoRule / PatternCell)
    // ========================================================================

    def mkRule(pattern: Vector[PatternCell], size: Int32): AutoRule =
        ({name = "test", size = size, pattern = pattern, srcX = 0, srcY = 0}: AutoRule)

    /// テスト用に "1 個の AutoRule だけ持つ Material" を legacy JSON 文字列から復元する。
    /// material 全体の JSON を組み立て直す手間を避けるため、autoRules 部分だけ受け取る。
    def legacyMaterialFromAutoRule(parsed: Option[Json.JsonElement]): Option[Material] = {
        let ruleJson = match parsed {
            case Some(j) => Json.Write.toPrettyString(0, j)
            case None    => "{}"
        };
        let materialJson = "{\"tileset\":\"x\",\"tileSize\":16,"
            + "\"wallMap\":{},\"floorPalette\":[],\"decorPalette\":[],"
            + "\"autoRules\":[" + ruleJson + "]}";
        Json.Parse.parse(materialJson) |> Option.flatMap(Saveable.fromJson)
    }

    /// NotValue(1), Anything, Nothing, Value(2) を混ぜた pattern を持つ Material。
    /// 新仕様の size=5 に統一。中央 (idx=12) は Unspecified。
    def sampleMaterialWithMixedPattern(): Material =
        let u = PatternCell.Unspecified;
        let pattern = Vector#{u, u, u, u, u,
                               u, u, PatternCell.NotValue(1i32), u, u,
                               u, PatternCell.Anything, u, PatternCell.Nothing, u,
                               u, u, PatternCell.Value(2i32), u, u,
                               u, u, u, u, u};
        let rule = ({name = "mix", size = 5, pattern = pattern,
                      srcX = 16, srcY = 0}: AutoRule);
        Material.Material(({
            tileset      = "test",
            tileSize     = 16,
            wallMap      = Map.empty(),
            floorPalette = (Nil: List[(Int32, Int32)]),
            decorPalette = (Nil: List[(Int32, Int32)]),
            autoRules    = rule :: Nil
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
