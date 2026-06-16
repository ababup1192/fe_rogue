/// PlayerScene の持ち物上限ロジックを 3 観点で固定する:
///   1. ロード職以外は 8 個目でいっぱいになる（7 個ならまだ拾える）
///   2. ロード職（resource#description == "ロード"）は 16 個まで持てる（8 個ではまだ余裕）
///   3. 「個数」は武器 + 杖 + 消費アイテムの 3 リストを合算して数える
///
/// 持ち物上限は「床アイテムを拾えるか」を決めるゲーム仕様で、職種によって 8 / 16 と
/// 分岐するため、境界（7→8, 8→16）を直値で押さえておく。
mod TestInventoryCapacity {

    // ════════════════════════════════════════════════════════
    // フィクスチャ
    // ════════════════════════════════════════════════════════

    /// ロード職の UnitResource（description だけ "ロード" に上書き）。
    def lordResource(): UnitCatalog.UnitResource =
        {description = "ロード" | TestUnitFixtures.testResource(4, 10)}

    /// テスト用の杖 1 本（耐久 3）。中身は容量カウントに影響しないダミー値。
    def testStaff(): Staff.StaffResource = {
        name       = "テスト杖",
        effect     = Staff.StaffEffect.Heal,
        durability = 3,
        sprite     = testSprite(),
        description = "",
        effectRule = None
    }

    /// テスト用の消費アイテム 1 個。容量カウントだけが目的なのでダミー値。
    def testConsumable(): Consumable.ConsumableResource = {
        name       = "きずぐすり",
        effect     = Consumable.ConsumableEffect.Heal,
        magnitude  = 10,
        duration   = 0,
        healAmount = 10,
        durability = 3,
        sprite     = testSprite(),
        description = "",
        effectRule = None
    }

    /// 容量カウントに影響しないダミー sprite。
    def testSprite(): Sprite.SpriteResource = {
        texture = "t", hframes = 1, vframes = 1, frame = 0,
        offset = {x = 0.0, y = 0.0}, scale = {x = 1.0, y = 1.0}, flipForFacing = false
    }

    /// 指定 resource と各リストの所持数から PlayerScene.Data を 1 体組む。
    /// 容量判定に効くのは resource#description と 3 リストの長さだけなので、
    /// それ以外は意味を持たないデフォルト値で埋める。
    def makeData(resource: UnitCatalog.UnitResource,
                  weaponCount: Int32, staffCount: Int32, consumableCount: Int32):
            PlayerScene.Data = {
        id              = 0,
        classId         = "test_player",
        gridPos         = {x = 1, y = 1},
        moveTiles       = 4,
        hp              = 10,
        waited          = false,
        attackTargetId  = None,
        resource        = resource,
        weapons         = List.repeat(weaponCount, TestUnitFixtures.testWeapon()),
        staves          = List.repeat(staffCount, testStaff()),
        consumables     = List.repeat(consumableCount, testConsumable()),
        selectedItem    = None,
        moveStepsTaken  = 0,
        facing          = Staff.Direction.Down,
        hidden          = false,
        usedStairs      = false,
        level           = 1,
        exp             = 0,
        pendingLevelUp  = None,
        statuses        = Nil,
        rings          = Nil,
        ringEquipped          = false,
        followUpUsed   = false
    }

    // ════════════════════════════════════════════════════════
    // ロード職以外: 上限 8 個
    // ════════════════════════════════════════════════════════

    /// 武器 7 本ではまだ満杯でない、武器 8 本でちょうど満杯になる（境界 = 8）。
    @Test
    def testNormalUnitFullAtEight(): Unit \ Assert =
        let sevenItems = makeData(TestUnitFixtures.testResource(4, 10), 7, 0, 0);
        let eightItems = makeData(TestUnitFixtures.testResource(4, 10), 8, 0, 0);
        Assert.assertEq(
            expected = (false, true),
            (PlayerScene.isInventoryFull(sevenItems),
             PlayerScene.isInventoryFull(eightItems)))

    // ════════════════════════════════════════════════════════
    // ロード職: 上限 16 個
    // ════════════════════════════════════════════════════════

    /// ロード職は 8 個ではまだ満杯でなく、16 個でちょうど満杯になる（境界 = 16）。
    @Test
    def testLordUnitFullAtSixteen(): Unit \ Assert =
        let eightItems   = makeData(lordResource(), 8, 0, 0);
        let sixteenItems = makeData(lordResource(), 16, 0, 0);
        Assert.assertEq(
            expected = (false, true),
            (PlayerScene.isInventoryFull(eightItems),
             PlayerScene.isInventoryFull(sixteenItems)))

    // ════════════════════════════════════════════════════════
    // 個数は 3 リストの合算
    // ════════════════════════════════════════════════════════

    /// 武器 3 + 杖 3 + 消費 2 = 合計 8 個。3 リストを足し合わせて数えていることを、
    /// itemCount = 8 と「8 個でいっぱい(通常職)」の両方で確認する。
    @Test
    def testItemCountSumsAllThreeLists(): Unit \ Assert =
        let mixed = makeData(TestUnitFixtures.testResource(4, 10), 3, 3, 2);
        Assert.assertEq(
            expected = (8, true),
            (PlayerScene.itemCount(mixed), PlayerScene.isInventoryFull(mixed)))
}
