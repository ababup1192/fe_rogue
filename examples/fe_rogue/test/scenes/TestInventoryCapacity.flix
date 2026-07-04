/// PlayerScene の持ち物制限ロジック（重量制）を固定する。
///
/// 個数上限は撤廃され、唯一の制約は重量（最大積載量 = 体格×1.0 + 力×0.2 + 2.0）。
///   1. 軽い持ち物なら「いっぱい」ではない（まだ拾える）
///   2. 重量過多（積載 110%+ ＝ 移動不可）に達すると `isInventoryFull` が true
///   3. `wouldOverloadByPicking`: 重い物を拾うと過多になる／軽い物なら大丈夫、を直値で押さえる
///
/// テスト用 resource（`testResource`）は 体格 6・力 3 → 最大積載量 8.6（=6×1.0+3×0.2+2.0）。
/// テスト用武器（`testWeapon`）は 剣・力 2 → 重量 1.9（=1.5+2×0.2）。
mod TestInventoryCapacity {

    // ════════════════════════════════════════════════════════
    // フィクスチャ
    // ════════════════════════════════════════════════════════

    /// テスト用の消費アイテム 1 個（きずぐすり = 自己使用 → 重量 0.5）。
    def testConsumable(): Consumable.ConsumableResource = {
        name       = "きずぐすり",
        effect     = Consumable.ConsumableEffect.Heal,
        magnitude  = 10,
        duration   = 0,
        healAmount = 10,
        durability = 3,
        weight     = 0.5,
        sprite     = testSprite(),
        description = "",
        effectRule = None
    }

    /// 容量カウントに影響しないダミー sprite。
    def testSprite(): Sprite.SpriteResource = {
        texture = "t", hframes = 1, vframes = 1, frame = 0,
        offset = {x = 0.0, y = 0.0}, scale = {x = 1.0, y = 1.0}, flipForFacing = false
    }

    /// 指定 resource と武器の所持数から PlayerScene.Data を 1 体組む。
    /// 重量判定に効くのは resource（体格・力）と各リストの中身だけなので、
    /// それ以外は意味を持たないデフォルト値で埋める。
    def makeData(resource: UnitCatalog.UnitResource, weaponCount: Int32):
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
        staves          = Nil,
        consumables     = Nil,
        selectedItem    = None,
        moveStepsTaken  = 0,
        facing          = Dir4.Down,
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
    // isInventoryFull: 重量過多(110%+)でのみ true
    // ════════════════════════════════════════════════════════

    /// 最大積載量 8.6 に対し、剣 4 本 = 7.6（積載 88% = 軽量超過だが移動可）では
    /// まだ「いっぱい」ではなく、剣 5 本 = 9.5（積載 110%超 = 重量過多）で「いっぱい」になる。
    @Test
    def testFullOnlyWhenImmobile(): Unit \ Assert =
        let fourWeapons = makeData(TestUnitFixtures.testResource(4, 10), 4);
        let fiveWeapons = makeData(TestUnitFixtures.testResource(4, 10), 5);
        Assert.assertEq(
            expected = (false, true),
            (PlayerScene.isInventoryFull(fourWeapons),
             PlayerScene.isInventoryFull(fiveWeapons)))

    // ════════════════════════════════════════════════════════
    // wouldOverloadByPicking: 拾うと過多になるか（詰み防止ゲート）
    // ════════════════════════════════════════════════════════

    /// 剣(weight 1.9) 3 本 = 5.7（積載 66%、最大 8.6）の状態で、
    ///   - 重い斧(weight 5.1)を拾うと 10.8 / 8.6 = 126% → 過多になる(true)
    ///   - きずぐすり=0.5 を拾うと 6.2 / 8.6 = 72% → 過多にならない(false)
    @Test
    def testWouldOverloadByPicking(): Unit \ Assert =
        let player = makeData(TestUnitFixtures.testResource(4, 10), 3);
        let heavyAxe = ItemData.GroundItemKind.WeaponItem(
            {weight = 5.1 | TestUnitFixtures.testWeaponWithType(13, WeaponCatalog.WeaponType.Axe)});
        let lightPotion = ItemData.GroundItemKind.ConsumableItem(testConsumable());
        Assert.assertEq(
            expected = (true, false),
            (PlayerScene.wouldOverloadByPicking(player, heavyAxe),
             PlayerScene.wouldOverloadByPicking(player, lightPotion)))
}
