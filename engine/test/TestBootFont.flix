// 埋め込んだ組み込みフォント（生成物 BootFontData）が、そのまま使える形に戻ることを確かめる。
// 字形の見た目は見ない — 見た目は `make boot-font --preview` の PNG と実機の目視で見る。

mod TestBootFont {

    /// 起動画面が出す字（ASCII の見える範囲）が全部そろっている。
    /// 欠けると起動画面からその字が黙って消えるので、ここで捕まえる。
    @Test
    def testAsciiPrintableGlyphsPresent(): Unit \ Assert =
        let glyphs = BootFont.atlas()#glyphs;
        let missing = List.range(0x20, 0x7F) |> List.filter(cp -> Option.isEmpty(Map.get(cp, glyphs)));
        Assert.assertEq(expected = (Nil: List[Int32]), missing)

    /// 字の切り出し位置がアトラスの外を指していない（外を指すと別の字が混じって出る）。
    @Test
    def testGlyphUvInsideAtlas(): Unit \ Assert =
        let atlas = BootFont.atlas();
        let outside = atlas#glyphs |> Map.toList |> List.filter(pair -> {
            let (_cp, gm) = pair;
            gm#s0 < 0.0 or gm#t0 < 0.0 or gm#s1 > 1.0 or gm#t1 > 1.0 or gm#s1 <= gm#s0 or gm#t1 <= gm#t0
        });
        Assert.assertEq(expected = 0, List.length(outside))

    /// 画素の数がアトラスの一辺と食い違わない（食い違うと絵がずれて出る）。
    @Test
    def testPixelCountMatchesAtlasSide(): Unit \ Assert =
        let side = BootFontData.side();
        Assert.assertEq(expected = side * side, Vector.length(BootFont.pixelsArgb()));
        let logoSide = BootFont.logoSide();
        Assert.assertEq(expected = logoSide * logoSide, Vector.length(BootFont.logoArgb()))

    /// ロゴの四隅は透明（素材の PNG は角が地色で塗ってあるので、抜けていないと白い角が出る）。
    @Test
    def testLogoCornersAreTransparent(): Unit \ Assert =
        let side = BootFont.logoSide();
        let logo = BootFont.logoArgb();
        let at = (x, y) -> Vector.get(y * side + x, logo);
        Assert.assertEq(expected = 0, at(0, 0));
        Assert.assertEq(expected = 0, at(side - 1, 0));
        Assert.assertEq(expected = 0, at(0, side - 1));
        Assert.assertEq(expected = 0, at(side - 1, side - 1))

    /// テクスチャ名が "font_" で始まらない。始めると描画側が距離場（SDF）として塗ってしまい、
    /// 素の白黒ビットマップであるこの字が滲む。
    @Test
    def testTextureNameIsNotSdfNamespace(): Unit \ Assert =
        Assert.assertEq(expected = false,
                        String.startsWith({ prefix = "font_" }, BootFont.textureName()))
}
