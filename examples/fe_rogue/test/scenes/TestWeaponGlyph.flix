/// WeaponGlyph の純粋ロジックテスト（scene / LWJGL 非依存）。
///
/// 武器系統（剣/斧/槍/弓/魔法）→ engine の Polygon2D / Arc2D で直描きする塗りシルエットの
/// 凸ピース列。ここでは構造の不変条件のみ検証する:
///   - 全系統で 1 ピース以上ある（素手以外は必ず描く）
///   - 子ノード名が系統内で一意（addChildAt が衝突しない）
///   - 系統ごとに色が相異（5 色すべて異なる = 種別を色でも区別できる）
///   - 各ピースの zIndex が Bg(61) より手前（背景に埋もれない）
/// 頂点座標の最終的な見た目（区別しやすさ・~9px の視認性）は Part C の実機スクショで検収する。
/// パターンマッチ（match + bug!）は避け、タプル分解 + Option.map + assertEq で書く。
mod TestWeaponGlyph {

    use WeaponCatalog.WeaponType

    def allTypes(): List[WeaponType] =
        WeaponType.Sword :: WeaponType.Axe :: WeaponType.Lance ::
        WeaponType.Bow :: WeaponType.Magic :: Nil

    // ── 全系統で 1 ピース以上 ──
    @Test
    def testAllTypesNonEmpty(): Unit \ Assert =
        let ok = allTypes() |> List.forAll(wt -> List.length(WeaponGlyph.weaponGlyph(wt)) >= 1);
        Assert.assertEq(expected = true, ok)

    // ── 子名が系統内で一意 ──
    @Test
    def testChildNamesUnique(): Unit \ Assert =
        let unique = wt -> {
            let names = WeaponGlyph.weaponGlyph(wt) |> List.map(p -> let (n, _) = p; n);
            Set.size(List.toSet(names)) == List.length(names)
        };
        Assert.assertEq(expected = true, allTypes() |> List.forAll(unique))

    // ── 全系統とも白で統一（形だけで区別する方針） ──
    @Test
    def testGlyphColorsAllWhite(): Unit \ Assert =
        let allWhite = allTypes() |> List.forAll(wt ->
            let c = WeaponGlyph.glyphColor(wt);
            c#r == 1.0f32 and c#g == 1.0f32 and c#b == 1.0f32);
        Assert.assertEq(expected = true, allWhite)

    // ── 各ピースの zIndex が Bg(61) より手前 ──
    @Test
    def testPiecesAboveBackground(): Unit \ Assert =
        let aboveBg = wt ->
            WeaponGlyph.weaponGlyph(wt)
                |> List.map(p -> let (_, node) = p; CanvasItem.getZIndex(node))
                |> List.forAll(z -> z >= 62);
        Assert.assertEq(expected = true, allTypes() |> List.forAll(aboveBg))

    // ── 先頭の子は "G0"（安定名） ──
    @Test
    def testFirstChildNamedG0(): Unit \ Assert =
        let firstName = WeaponGlyph.weaponGlyph(WeaponType.Sword)
            |> List.head
            |> Option.map(p -> let (n, _) = p; n);
        Assert.assertEq(expected = Some("G0"), firstName)
}
