/// WeaponIconScene の純粋ロジックテスト（scene / LWJGL 非依存）。
///
/// - `symbolSprite`: 武器系統 → 象徴スプライト（鉄シリーズ / 魔法は tome 代表）の写像。
///   texture / frame / hframes / vframes が weapons.json の iron_* / tome_apprentice と一致すること。
///
/// attach / setModulate の scene 変換は LWJGL を要するため統合 / 手動確認に委ねる
/// （`TestUnitHPBarScene` と同方針）。パターンマッチを避け Option.map + assertEq で書く。
mod TestWeaponIconScene {

    use WeaponCatalog.WeaponType

    // ── 検証用アクセサ（パターンマッチ回避） ──────────────────
    def frameOf(o: Option[Sprite.SpriteResource]): Option[Int32] = o |> Option.map(s -> s#frame)
    def texOf(o: Option[Sprite.SpriteResource]): Option[String] = o |> Option.map(s -> s#texture)
    def hframesOf(o: Option[Sprite.SpriteResource]): Option[Int32] = o |> Option.map(s -> s#hframes)
    def vframesOf(o: Option[Sprite.SpriteResource]): Option[Int32] = o |> Option.map(s -> s#vframes)

    // ── frame（系統 → 鉄シリーズの固定セル） ──────────────────

    @Test
    def testSwordFrame(): Unit \ Assert =
        Assert.assertEq(expected = Some(20), frameOf(WeaponIconScene.symbolSprite(WeaponType.Sword)))

    @Test
    def testAxeFrame(): Unit \ Assert =
        Assert.assertEq(expected = Some(288), frameOf(WeaponIconScene.symbolSprite(WeaponType.Axe)))

    @Test
    def testLanceFrame(): Unit \ Assert =
        Assert.assertEq(expected = Some(283), frameOf(WeaponIconScene.symbolSprite(WeaponType.Lance)))

    @Test
    def testBowFrame(): Unit \ Assert =
        Assert.assertEq(expected = Some(294), frameOf(WeaponIconScene.symbolSprite(WeaponType.Bow)))

    @Test
    def testMagicFrame(): Unit \ Assert =
        Assert.assertEq(expected = Some(0), frameOf(WeaponIconScene.symbolSprite(WeaponType.Magic)))

    // ── texture（物理は item_weapons / 魔法のみ別シート item_skills） ──

    @Test
    def testPhysicalTexture(): Unit \ Assert =
        Assert.assertEq(expected = Some("item_weapons"), texOf(WeaponIconScene.symbolSprite(WeaponType.Axe)))

    @Test
    def testMagicTexture(): Unit \ Assert =
        Assert.assertEq(expected = Some("item_skills"), texOf(WeaponIconScene.symbolSprite(WeaponType.Magic)))

    // ── シート寸法（hframes は共通 20、vframes は物理 25 / 魔法 30） ──

    @Test
    def testHframes(): Unit \ Assert =
        Assert.assertEq(expected = Some(20), hframesOf(WeaponIconScene.symbolSprite(WeaponType.Sword)))

    @Test
    def testPhysicalVframes(): Unit \ Assert =
        Assert.assertEq(expected = Some(25), vframesOf(WeaponIconScene.symbolSprite(WeaponType.Bow)))

    @Test
    def testMagicVframes(): Unit \ Assert =
        Assert.assertEq(expected = Some(30), vframesOf(WeaponIconScene.symbolSprite(WeaponType.Magic)))
}
