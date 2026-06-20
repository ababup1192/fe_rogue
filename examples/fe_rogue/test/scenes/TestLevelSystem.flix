/// TestLevelSystem — レベルアップ・EXP・成長の純粋ロジックのテスト
///
/// LevelSystem は副作用を持たないので、テストも effect ゼロ（Assert のみ）。
/// 乱数は `Rolls` として決め打ちの値を渡すので、結果は完全に決定的。
mod TestLevelSystem {

    use LevelSystem.{Stats, Rolls, StatChange}

    /// StatChange を assertEq 用のタプルに変換するアダプタ（レコードは Eq を持たないため）。
    def changeToTuple(change: StatChange): (String, Int32, Int32, Bool) =
        (change#label, change#before, change#after, change#gained)

    /// テスト用の成長率。各ステータスに別々の値を入れて成長判定の境界を確認できるようにする。
    def rates(hp: Int32, attack: Int32, defense: Int32,
              magicAttack: Int32, magicDefense: Int32, speed: Int32,
              skill: Int32, luck: Int32, constitution: Int32): UnitCatalog.GrowthRates =
        {hp = hp, attack = attack, defense = defense,
         magicAttack = magicAttack, magicDefense = magicDefense, speed = speed,
         skill = skill, luck = luck, constitution = constitution}

    // EXP の「獲得量」(レベル差ベース) は Combat.battleExp が持ち、テストは TestCombat 側にある。
    // ここは「蓄積（gainExp）」「成長（applyGrowth）」「パネル結果（buildResult）」を確認する。

    // ========================================================================
    // EXP 蓄積: 100 到達でレベルアップ・余剰繰り越し
    // ========================================================================

    /// 95 + 30 = 125 は 100 を超えるのでレベルアップし、余剰 25 を繰り越す。
    @Test
    def testGainExpLevelsUpAndCarriesOver(): Unit \ Assert =
        let r = LevelSystem.gainExp(95, 30);
        Assert.assertEq(expected = (25, true), (r#exp, r#levelUp))

    /// 40 + 30 = 70 は 100 未満なのでレベルアップせず、EXP は 70 のまま。
    @Test
    def testGainExpStaysBelowThreshold(): Unit \ Assert =
        let r = LevelSystem.gainExp(40, 30);
        Assert.assertEq(expected = (70, false), (r#exp, r#levelUp))

    /// ちょうど 100 でレベルアップし、繰り越しは 0（境界）。
    @Test
    def testGainExpExactlyHundredLevelsUp(): Unit \ Assert =
        let r = LevelSystem.gainExp(70, 30);
        Assert.assertEq(expected = (0, true), (r#exp, r#levelUp))

    // ========================================================================
    // 成長判定: 乱数 < 成長率 のステータスだけ +1
    // ========================================================================

    /// 8 ステータスを全て 10 から始め、成長率と乱数の組で +1 されるかを一括確認する。
    ///   hp           : rate 50, roll 49 → 49 < 50 で成長 → 11
    ///   attack       : rate 50, roll 50 → 50 < 50 は偽 で据え置き → 10
    ///   defense      : rate 0,  roll 0  → 0 < 0 は偽（rate 0 は決して成長しない）→ 10
    ///   magicAttack  : rate 100,roll 99 → 99 < 100 で成長（rate 100 は必ず成長）→ 11
    ///   magicDefense : rate 50, roll 50 → 据え置き → 10
    ///   speed        : rate 50, roll 49 → 成長 → 11
    ///   skill        : rate 50, roll 49 → 成長 → 11
    ///   luck         : rate 0,  roll 0  → 据え置き → 10
    ///   constitution : rate 50, roll 49 → 成長 → 11
    @Test
    def testApplyGrowthBumpsOnlyWhenRollBelowRate(): Unit \ Assert =
        let before: Stats =
            {hp = 10, attack = 10, defense = 10, magicAttack = 10, magicDefense = 10,
             speed = 10, skill = 10, luck = 10, constitution = 10};
        let rollValues: Rolls =
            {hp = 49, attack = 50, defense = 0, magicAttack = 99, magicDefense = 50,
             speed = 49, skill = 49, luck = 0, constitution = 49};
        let after = LevelSystem.applyGrowth(before,
            rates(50, 50, 0, 100, 50, 50, 50, 0, 50), rollValues);
        Assert.assertEq(
            expected = (11, 10, 10, 11, 10, 11, 11, 10, 11),
            (after#hp, after#attack, after#defense, after#magicAttack,
             after#magicDefense, after#speed, after#skill, after#luck, after#constitution))

    // ========================================================================
    // パネル用の結果組み立て: 8 行の前後差分と (+1) フラグ
    // ========================================================================

    /// HP・魔力・技 が上がった場合、その 3 行だけ gained=true になり、
    /// toLevel は fromLevel + 1、ラベルは固定順（HP, 力, 魔力, 技, 速さ, 幸運, 守備, 魔防）で並ぶ。
    @Test
    def testBuildResultMarksRaisedStats(): Unit \ Assert =
        let before: Stats =
            {hp = 14, attack = 5, defense = 3, magicAttack = 2, magicDefense = 1,
             speed = 4, skill = 6, luck = 7, constitution = 8};
        let after: Stats =
            {hp = 15, attack = 5, defense = 3, magicAttack = 3, magicDefense = 1,
             speed = 4, skill = 7, luck = 7, constitution = 9};
        let result = LevelSystem.buildResult("ナイト", 3, before, after);
        // ヘッダ情報（名前・前後レベル）と 9 行ぶんの (ラベル, 前, 後, 上昇したか) を一括比較。
        let expectedRows =
            ("HP",   14, 15, true)  ::
            ("力",   5,  5,  false) ::
            ("魔力", 2,  3,  true)  ::
            ("技",   6,  7,  true)  ::
            ("速さ", 4,  4,  false) ::
            ("幸運", 7,  7,  false) ::
            ("守備", 3,  3,  false) ::
            ("魔防", 1,  1,  false) ::
            ("体格", 8,  9,  true)  :: Nil;
        Assert.assertEq(
            expected = ("ナイト", 3, 4, expectedRows),
            (result#unitName, result#fromLevel, result#toLevel,
             result#changes |> List.map(changeToTuple)))

}
