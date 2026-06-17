/// WeaponSelectScene の表面 API を固定する:
///   1. `applyVisibility` が `WeaponSelect` フェーズでだけ Panel / ItemList を visible + focused にする
///   2. `weaponSubline` / `rangeText` が性能 2 行目を仕様どおりに組む（残り使用回数つき）
///   3. `weaponBadges` が **苦手な武器の行だけ**「不得意」バッジを入れ、得意な武器には入れない
///   4. `parseWeaponIndex` が metadata "w:<idx>" を index に戻す
mod TestWeaponSelectScene {

    // ════════════════════════════════════════════════════════
    // ヘルパー
    // ════════════════════════════════════════════════════════

    /// `WeaponSelectScene.add` の {GameEngine.Game, Fs.FileRead} effect を discharge して
    /// pure に見せる test 用ラッパ（TestActionMenuScene.actionMenuAddPure と同じパターン）。
    def weaponSelectAddPure(scene: Scene[NodeTag]): Scene[NodeTag] =
        unchecked_cast(
            (run {
                TestUnitFixtures.withMockGame(() -> WeaponSelectScene.add(scene))
            } with Fs.FileRead.runWithIO)
            as _ \ {})

    /// Panel と ItemList の (visible, focused) を 1 タプルで観測する。
    def visibilityState(scene: Scene[NodeTag]): (Bool, Bool) =
        let panelVisible = match Scene.getEngineNode(WeaponSelectScene.panelPath(), scene) {
            case Some(EngineNode.PanelWithState(p, _)) => CanvasItem.isVisible(p)
            case _                                       => bug!("WeaponSelect panel not found")
        };
        let menuVisible =
            match Scene.getEngineNode(WeaponSelectScene.menuPath(), scene) {
                case Some(EngineNode.ItemListWithState(l, _)) =>
                    (CanvasItem.isVisible(l), ItemList.isFocused(l))
                case _ => bug!("WeaponSelect ItemList not found")
            };
        (panelVisible, fst(menuVisible) and snd(menuVisible))

    /// 剣だけを得意とするテスト用 UnitResource（不得意バッジ検証用）。
    /// `testResource` は全タイプ得意なので、`proficientWeaponTypes` を剣のみに絞った版を作る。
    def swordOnlyResource(): UnitCatalog.UnitResource =
        {proficientWeaponTypes = WeaponCatalog.WeaponType.Sword :: Nil
            | TestUnitFixtures.testResource(4, 10)}

    /// 射程 min-max を差し替えたテスト武器（rangeText の範囲表記検証用）。
    def weaponWithRange(min: Int32, max: Int32): UnitCatalog.WeaponResource =
        {range = {min = min, max = max} | TestUnitFixtures.testWeapon()}

    // ════════════════════════════════════════════════════════
    // applyVisibility
    // ════════════════════════════════════════════════════════

    /// `WeaponSelect` 以外のフェーズでは Panel = hidden / ItemList = hidden。
    @Test
    def testApplyVisibilityHidesOutsideWeaponSelect(): Unit \ Assert =
        let scene = weaponSelectAddPure(Scene.empty());
        let after = WeaponSelectScene.applyVisibility(TurnPhase.Phase.ActionSelect, scene);
        Assert.assertEq(expected = (false, false), visibilityState(after))

    /// `WeaponSelect` フェーズでは Panel = visible / ItemList = visible + focused。
    @Test
    def testApplyVisibilityShowsAndFocusesInWeaponSelect(): Unit \ Assert =
        let scene = weaponSelectAddPure(Scene.empty());
        let after = WeaponSelectScene.applyVisibility(TurnPhase.Phase.WeaponSelect, scene);
        Assert.assertEq(expected = (true, true), visibilityState(after))

    // ════════════════════════════════════════════════════════
    // weaponSubline / rangeText — 性能 2 行目
    // ════════════════════════════════════════════════════════

    /// 単射程 (min == max) は「射N」。残り使用回数を末尾に出す。
    @Test
    def testWeaponSublineSingleRange(): Unit \ Assert =
        // testWeapon: 攻2 命80 射1-1 耐久10
        Assert.assertEq(
            expected = "威2  中80  射1  残10",
            WeaponSelectScene.weaponSubline(TestUnitFixtures.testWeapon()))

    /// 範囲射程 (min != max) は「射min-max」。
    @Test
    def testRangeTextSpan(): Unit \ Assert =
        Assert.assertEq(
            expected = "射1-2",
            WeaponSelectScene.rangeText((weaponWithRange(1, 2))#range))

    /// 単射程は範囲なしの「射N」表記。
    @Test
    def testRangeTextSingle(): Unit \ Assert =
        Assert.assertEq(
            expected = "射1",
            WeaponSelectScene.rangeText((TestUnitFixtures.testWeapon())#range))

    // ════════════════════════════════════════════════════════
    // weaponBadges — 不得意な武器の行にだけバッジを入れる
    // ════════════════════════════════════════════════════════

    /// 剣だけ得意なユニットに [剣, 斧] を持たせると、斧 (index 1) の行だけ「不得意」バッジが付く。
    /// 得意な剣 (index 0) にはキー自体が入らない（バッジ非表示）。
    @Test
    def testWeaponBadgesOnlyOnNonProficient(): Unit \ Assert =
        let sword = TestUnitFixtures.testWeaponWithType(2, WeaponCatalog.WeaponType.Sword);
        let axe   = TestUnitFixtures.testWeaponWithType(2, WeaponCatalog.WeaponType.Axe);
        let badges = WeaponSelectScene.weaponBadges(swordOnlyResource(), sword :: axe :: Nil);
        // 斧の行 (index 1) にだけ「不得意」が入り、剣の行 (index 0) には入らない。
        Assert.assertEq(
            expected = (None, Some("不得意")),
            (Map.get(0, badges), Map.get(1, badges)))

    /// 全タイプ得意なユニット (testResource) では、どの武器にもバッジが付かない（空 Map）。
    @Test
    def testWeaponBadgesEmptyWhenAllProficient(): Unit \ Assert =
        let sword = TestUnitFixtures.testWeaponWithType(2, WeaponCatalog.WeaponType.Sword);
        let axe   = TestUnitFixtures.testWeaponWithType(2, WeaponCatalog.WeaponType.Axe);
        let badges = WeaponSelectScene.weaponBadges(
            TestUnitFixtures.testResource(4, 10), sword :: axe :: Nil);
        Assert.assertEq(expected = 0, Map.size(badges))

    // ════════════════════════════════════════════════════════
    // parseWeaponIndex — metadata "w:<idx>" の往復
    // ════════════════════════════════════════════════════════

    @Test
    def testParseWeaponIndex(): Unit \ Assert =
        Assert.assertEq(expected = Some(3), WeaponSelectScene.parseWeaponIndex("w:3"))

    @Test
    def testParseWeaponIndexUnknown(): Unit \ Assert =
        Assert.assertEq(expected = None, WeaponSelectScene.parseWeaponIndex("s:1"))
}
