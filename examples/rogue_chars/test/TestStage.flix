// TestStage — クリップ契約（RogueStage v3）の pin。マスタークロック 24 ticks/s と
// 各クリップの割り付けが崩れると、シートの行もリールの尺も静かにずれるのでここで固定する。

mod TestStage {

    // v3 契約はクリップ 16 本（Idle/Walk/Attack/UseItem/Damage 各 3 方向 + Death 1 本）。
    @Test
    def testClipCount(): Unit \ Assert =
        Assert.assertEq(expected = 16, List.length(RogueStage.clips()))

    // 全クリップの ticksPerFrame が整数で、宣言順に
    // Idle 系 4,4,4 / Walk 系 3,3,3 / Attack 系 2,2,2 / UseItem 系 3,3,3 / Damage 系 2,2,2 / Death 3
    // であること（= fps 6/8/12/8/12/8 が 24 の約数である証明）。
    @Test
    def testTicksPerFrame(): Unit \ Assert =
        let actual = RogueStage.clips() |> List.map(RogueStage.ticksPerFrame);
        Assert.assertEq(
            expected = 4 :: 4 :: 4 :: 3 :: 3 :: 3 :: 2 :: 2 :: 2 :: 3 :: 3 :: 3 :: 2 :: 2 :: 2 :: 3 :: Nil,
            actual)

    // シート行はクリップ宣言順（IdleDown=0 .. Death=15）。
    @Test
    def testSheetRowOrder(): Unit \ Assert =
        let actual = RogueStage.clips() |> List.map(RogueStage.sheetRow);
        Assert.assertEq(
            expected = List.range(0, 16),
            actual)

    // リールの尺 = IdleDown×2周(2×4コマ×4tick=32) + WalkDown×2(2×4×3=24) + WalkUp×2(24)
    // + WalkSide×2(24) + WalkSide反転×1(12) + AttackSide(6×2=12) + IdleDown×1(16)
    // + UseItemSide(4×3=12) + DamageSide(3×2=6) + Death(6×3=18)
    // + 白骨2コマ(2×6=12) + フェード4段(4×3=12) = 204 tick（8.5 秒）。
    @Test
    def testReelLength(): Unit \ Assert =
        Assert.assertEq(expected = 204, List.length(RogueStage.reel()))

    // リールの全 tick が実在するコマ/段を指している
    // （Char は frame < frameCount・Bones は 0..1・Fade は 0..3）。
    @Test
    def testReelStepsInRange(): Unit \ Assert =
        let bad = RogueStage.reel()
            |> List.filter(step -> match step {
                case RogueStage.ReelStep.Char(c, f, _) => f < 0 or f >= RogueStage.frameCount(c)
                case RogueStage.ReelStep.Bones(f)      => f < 0 or f >= RogueStage.bonesFrameCount()
                case RogueStage.ReelStep.Fade(s)       => s < 0 or s >= RogueStage.fadeStepCount()
            })
            |> List.length;
        Assert.assertEq(expected = 0, bad)

    // リールは白骨 → フェードで終わる（Death の後にキャラのコマが混ざらない）。
    @Test
    def testReelEndsWithBonesAndFade(): Unit \ Assert =
        let tail = RogueStage.reel() |> List.drop(204 - 24);
        let charTicks = tail
            |> List.filter(step -> match step {
                case RogueStage.ReelStep.Char(_, _, _) => true
                case _                                 => false
            })
            |> List.length;
        Assert.assertEq(expected = 0, charTicks)

    // ループするのは Idle 系と Walk 系の 6 本だけ（Attack/UseItem/Damage/Death は単発）。
    @Test
    def testLoopFlags(): Unit \ Assert =
        let actual = RogueStage.clips() |> List.map(RogueStage.loops);
        Assert.assertEq(
            expected = true :: true :: true :: true :: true :: true ::
                       false :: false :: false :: false :: false :: false ::
                       false :: false :: false :: false :: Nil,
            actual)
}
