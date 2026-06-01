// UnitCatalog の Saveable[UnitCatalog] と weapons.json デコーダが、実 JSON と同じ
// 構造の文字列を round-trip でデコードできるかを検証する。ファイル I/O は介さず、
// 文字列リテラルを直接 Json.Parse.parse → decode して確認する。
//
// units.json と weapons.json は別ファイルなので、テスト内では:
//   1. sampleUnitsJson() を Saveable.fromJson で UnitCatalog (weapons は空) にする
//   2. sampleWeaponsJson() を UnitCatalogCodec.decodeWeaponsFile で武器マップに decode
//   3. 1. の weapons フィールドを 2. の結果で差し替えて、本番 load と同じ形にする

mod TestUnitCatalog {

    /// units.json と同じ構造の JSON 文字列リテラル。
    /// 各ユニットは `initialInventory` で持ち物（武器・杖の混在）を持つ。
    /// `magicAttack` / `magicDefense` は省略可能。
    /// knight は武器 + 杖を持ち、goblin は武器のみ持つ。
    def sampleUnitsJson(): String = String.unlines(
        "{" ::
        "  \"units\": {" ::
        "    \"knight\": {" ::
        "      \"moveTiles\": 4," ::
        "      \"hp\": 14," ::
        "      \"attack\":  6," ::
        "      \"defense\": 5," ::
        "      \"magicAttack\":  1," ::
        "      \"magicDefense\": 2," ::
        "      \"speed\":   2," ::
        "      \"initialInventory\": [" ::
        "        { \"kind\": \"weapon\", \"id\": \"trainingSpear\" }," ::
        "        { \"kind\": \"staff\",  \"id\": \"live_staff\" }" ::
        "      ]," ::
        "      \"sprite\": { \"texture\": \"character_sheet\", \"hframes\": 5, \"vframes\": 2, \"frame\": 0 }" ::
        "    }," ::
        "    \"goblin\": {" ::
        "      \"moveTiles\": 3," ::
        "      \"hp\": 3," ::
        "      \"attack\":  3," ::
        "      \"defense\": 1," ::
        "      \"speed\":   4," ::
        "      \"initialInventory\": [" ::
        "        { \"kind\": \"weapon\", \"id\": \"trainingSword\" }" ::
        "      ]," ::
        "      \"sprite\": { \"texture\": \"character_sheet\", \"hframes\": 5, \"vframes\": 2, \"frame\": 4 }" ::
        "    }" ::
        "  }," ::
        "  \"players\": [\"knight\"]," ::
        "  \"enemies\": [\"goblin\"]" ::
        "}" :: Nil)

    /// weapons.json と同じ構造の JSON 文字列リテラル。
    /// trainingSpear は `weaponType` 省略（Physical デフォルトを検証）、
    /// trainingSword は明示 "Magic"（魔法トグル切替の効果を検証）。
    def sampleWeaponsJson(): String = String.unlines(
        "{" ::
        "  \"weapons\": {" ::
        "    \"trainingSpear\": { \"name\": \"trainingSpear\", \"attack\": 2, \"durability\": 41, \"range\": { \"min\": 1, \"max\": 1 }, \"sprite\": { \"texture\": \"roguelike_weapons\", \"hframes\": 54, \"vframes\": 12, \"frame\": 50 } }," ::
        "    \"trainingSword\": { \"name\": \"trainingSword\", \"attack\": 3, \"durability\": 41, \"range\": { \"min\": 1, \"max\": 2 }, \"weaponType\": \"Magic\", \"sprite\": { \"texture\": \"roguelike_weapons\", \"hframes\": 54, \"vframes\": 12, \"frame\": 49 } }" ::
        "  }" ::
        "}" :: Nil)

    /// 2 つの JSON 文字列をパースしてマージし、本番 `UnitCatalog.load` 相当の
    /// in-memory カタログを返す。テスト用ヘルパー。
    def buildSampleCatalog(): Option[UnitCatalog.UnitCatalog] =
        let unitsParsed   = Json.Parse.parse(sampleUnitsJson());
        let weaponsParsed = Json.Parse.parse(sampleWeaponsJson());
        let unitCatalogOpt: Option[UnitCatalog.UnitCatalog] =
            Option.flatMap(Saveable.fromJson, unitsParsed);
        let weaponsOpt = Option.flatMap(UnitCatalogCodec.decodeWeaponsFile, weaponsParsed);
        forM (
            c <- unitCatalogOpt;
            w <- weaponsOpt
        ) yield {
            let UnitCatalog.UnitCatalog(payload) = c;
            UnitCatalog.UnitCatalog({weapons = w | payload})
        }

    /// units / weapons / pools の key 集合が期待通りで、各ユニットの initialInventory が
    /// 正しく decode されていること。
    @Test
    def testDecodeSampleCatalog(): Unit \ Assert =
        let decoded = buildSampleCatalog();
        let unitKeys = match decoded {
            case Some(c) => Map.keysOf(UnitCatalog.unitsOf(c))
            case None    => Set.empty()
        };
        let weaponKeys = match decoded {
            case Some(c) => Map.keysOf(UnitCatalog.weaponsOf(c))
            case None    => Set.empty()
        };
        let poolKeys = match decoded {
            case Some(c) => Map.keysOf(UnitCatalog.poolsOf(c))
            case None    => Set.empty()
        };
        Assert.assertEq(
            expected = (true,
                         Set#{"knight", "goblin"},
                         Set#{"trainingSpear", "trainingSword"},
                         Set#{"players", "enemies"}),
            (Option.nonEmpty(decoded), unitKeys, weaponKeys, poolKeys))

    /// 持ち物リストの最初の武器エントリ id を取り出す helper（テスト用）
    def firstWeaponId(u: UnitCatalog.UnitResource): String =
        match List.find(e -> e#kind == UnitCatalog.ItemKind.Weapon, u#initialInventory) {
            case Some(e) => e#id
            case None    => ""
        }

    /// pool 取得が期待通りに UnitResource を返す。初期持ち物の先頭武器が trainingSpear であること。
    @Test
    def testPoolLookup(): Unit \ Assert =
        match buildSampleCatalog() {
            case None    => Assert.assertEq(expected = "decoded", "none")
            case Some(c) =>
                let party = UnitCatalog.pool("players", c);
                let knight = List.head(party);
                let (hp, weaponId) = match knight {
                    case Some(u) => (u#hp, firstWeaponId(u))
                    case None    => (-1, "")
                };
                Assert.assertEq(expected = (1, 14, "trainingSpear"),
                                (List.length(party), hp, weaponId))
        }

    /// initialInventory の先頭武器 → lookupWeapon の経路で `WeaponResource` が引けること。
    @Test
    def testLookupWeapon(): Unit \ Assert =
        match buildSampleCatalog() {
            case None    => Assert.assertEq(expected = "decoded", "none")
            case Some(c) =>
                let knight = match Map.get("knight", UnitCatalog.unitsOf(c)) {
                    case Some(u) => u
                    case None    => bug!("knight not in sample catalog")
                };
                let weapon = UnitCatalog.lookupWeapon(firstWeaponId(knight), c);
                Assert.assertEq(expected = (2, 41, 1, 1),
                                (weapon#attack, weapon#durability,
                                 weapon#range#min, weapon#range#max))
        }

    /// `min..max` の射程 (例: trainingSword の 1-2) が JSON から正しくデコードされる。
    @Test
    def testWeaponRangeDecodesMinMax(): Unit \ Assert =
        match buildSampleCatalog() {
            case None    => Assert.assertEq(expected = "decoded", "none")
            case Some(c) =>
                let sword = UnitCatalog.lookupWeapon("trainingSword", c);
                Assert.assertEq(expected = (1, 2),
                                (sword#range#min, sword#range#max))
        }

    /// 明示された magicAttack / magicDefense が JSON から読み取られる
    /// （knight: magicAttack=1, magicDefense=2）
    @Test
    def testUnitDecodesMagicStats(): Unit \ Assert =
        match buildSampleCatalog() {
            case None    => Assert.assertEq(expected = "decoded", "none")
            case Some(c) =>
                let knight = match Map.get("knight", UnitCatalog.unitsOf(c)) {
                    case Some(u) => u
                    case None    => bug!("knight not in sample catalog")
                };
                Assert.assertEq(expected = (1, 2),
                                (knight#magicAttack, knight#magicDefense))
        }

    /// magicAttack / magicDefense を省略したユニットはデフォルト 0 でデコードされる
    /// （旧 units.json への後方互換）
    @Test
    def testUnitDecodesMagicStatsDefaultsToZero(): Unit \ Assert =
        match buildSampleCatalog() {
            case None    => Assert.assertEq(expected = "decoded", "none")
            case Some(c) =>
                let goblin = match Map.get("goblin", UnitCatalog.unitsOf(c)) {
                    case Some(u) => u
                    case None    => bug!("goblin not in sample catalog")
                };
                Assert.assertEq(expected = (0, 0),
                                (goblin#magicAttack, goblin#magicDefense))
        }

    /// `weaponType` 明示の武器が魔法武器としてデコードされる（trainingSword: "Magic"）
    @Test
    def testWeaponDecodesMagicType(): Unit \ Assert =
        match buildSampleCatalog() {
            case None    => Assert.assertEq(expected = "decoded", "none")
            case Some(c) =>
                let sword = UnitCatalog.lookupWeapon("trainingSword", c);
                Assert.assertEq(expected = UnitCatalog.WeaponType.Magic,
                                sword#weaponType)
        }

    /// `weaponType` 省略の武器は物理武器（Physical）としてデコードされる
    /// （旧 weapons.json への後方互換）
    @Test
    def testWeaponDecodesTypeDefaultsToPhysical(): Unit \ Assert =
        match buildSampleCatalog() {
            case None    => Assert.assertEq(expected = "decoded", "none")
            case Some(c) =>
                let spear = UnitCatalog.lookupWeapon("trainingSpear", c);
                Assert.assertEq(expected = UnitCatalog.WeaponType.Physical,
                                spear#weaponType)
        }

    // ════════════════════════════════════════════════════════
    // initialInventory: 持ち物リスト (kind + id) のデコード
    // ════════════════════════════════════════════════════════

    /// InventoryEntry record を `(kindStr, id)` の tuple list に変換する（assertEq 用）。
    def entriesToTuples(inv: List[UnitCatalog.InventoryEntry]): List[(String, String)] =
        List.map(e -> {
            let kindStr = match e#kind {
                case UnitCatalog.ItemKind.Weapon => "weapon"
                case UnitCatalog.ItemKind.Staff  => "staff"
            };
            (kindStr, e#id)
        }, inv)

    /// knight の `initialInventory` が [weapon:trainingSpear, staff:live_staff] として読まれる
    @Test
    def testUnitDecodesInitialInventory(): Unit \ Assert =
        match buildSampleCatalog() {
            case None    => Assert.assertEq(expected = "decoded", "none")
            case Some(c) =>
                let knight = match Map.get("knight", UnitCatalog.unitsOf(c)) {
                    case Some(u) => u
                    case None    => bug!("knight not in sample catalog")
                };
                Assert.assertEq(
                    expected = ("weapon", "trainingSpear") :: ("staff", "live_staff") :: Nil,
                    entriesToTuples(knight#initialInventory))
        }

    /// goblin の `initialInventory` は武器のみ 1 件で杖は無い
    @Test
    def testUnitDecodesInventoryWeaponOnly(): Unit \ Assert =
        match buildSampleCatalog() {
            case None    => Assert.assertEq(expected = "decoded", "none")
            case Some(c) =>
                let goblin = match Map.get("goblin", UnitCatalog.unitsOf(c)) {
                    case Some(u) => u
                    case None    => bug!("goblin not in sample catalog")
                };
                Assert.assertEq(
                    expected = ("weapon", "trainingSword") :: Nil,
                    entriesToTuples(goblin#initialInventory))
        }
}
