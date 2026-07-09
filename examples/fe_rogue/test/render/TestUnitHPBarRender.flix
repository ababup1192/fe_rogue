/// UnitHPBarRender の純粋ロジックテスト（scene / LWJGL 非依存）。
///
/// - `fillWidth`: 残量比 → Fill 幅。満タン/半分/0/最大超え/負値/maxHp<=0 をクランプ。
/// - `teamFillColor`: 味方=青 / 敵=赤 の出し分け。
///
/// attach / update / setColor の scene 変換は LDTK/LWJGL を要するため統合/手動確認に委ねる。
mod TestUnitHPBarRender {

    use UnitHPBarRender.Team

    def colorT(c: Color): (Float32, Float32, Float32) = (c#r, c#g, c#b)

    // ── fillWidth ────────────────────────────────────────────

    @Test
    def testFillWidthFull(): Unit \ Assert =
        Assert.assertEq(expected = 20.0, UnitHPBarRender.fillWidth(12, 12, 20.0))

    @Test
    def testFillWidthHalf(): Unit \ Assert =
        Assert.assertEq(expected = 10.0, UnitHPBarRender.fillWidth(6, 12, 20.0))

    @Test
    def testFillWidthZero(): Unit \ Assert =
        Assert.assertEq(expected = 0.0, UnitHPBarRender.fillWidth(0, 12, 20.0))

    /// currentHp > maxHp は 1.0 にクランプ（満タン幅）。
    @Test
    def testFillWidthOverClamped(): Unit \ Assert =
        Assert.assertEq(expected = 20.0, UnitHPBarRender.fillWidth(99, 12, 20.0))

    /// 負の HP は 0 にクランプ。
    @Test
    def testFillWidthNegativeClamped(): Unit \ Assert =
        Assert.assertEq(expected = 0.0, UnitHPBarRender.fillWidth(-3, 12, 20.0))

    /// maxHp <= 0 は 0 扱い（ゼロ除算回避）。
    @Test
    def testFillWidthZeroMax(): Unit \ Assert =
        Assert.assertEq(expected = 0.0, UnitHPBarRender.fillWidth(5, 0, 20.0))

    // ── teamFillColor ────────────────────────────────────────

    @Test
    def testTeamColorPlayerBlue(): Unit \ Assert =
        Assert.assertEq(expected = (0.25f32, 0.5f32, 0.95f32),
            colorT(UnitHPBarRender.teamFillColor(Team.Player)))

    @Test
    def testTeamColorEnemyRed(): Unit \ Assert =
        Assert.assertEq(expected = (0.9f32, 0.25f32, 0.25f32),
            colorT(UnitHPBarRender.teamFillColor(Team.Enemy)))
}
