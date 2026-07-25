// SoftRaster.blendPixel の合成式を具体値で固定する。
// GL 側（RenderSprite.applyBlend + シェーダの premultiply）と同じ式であることの pin:
//   Normal   = ふつうの半透明合成（SrcOver）
//   Add      = 明るく足す（255 でクランプ）
//   Multiply = 暗く沈める（白は素通し・黒は黒・alpha 0 で何も変えない）
mod TestSoftRaster {

    /// ARGB int の組み立て（テスト入力用）。
    def argb(a: Int32, r: Int32, g: Int32, b: Int32): Int32 =
        Int32.leftShift(a, 24)
            |> Int32.bitwiseOr(Int32.leftShift(r, 16))
            |> Int32.bitwiseOr(Int32.leftShift(g, 8))
            |> Int32.bitwiseOr(b)

    /// 出力の比較は (a, r, g, b) のタプルで行う（負の ARGB int を直接比べると読みにくい）。
    def channels(p: Int32): (Int32, Int32, Int32, Int32) =
        let c = shift -> Int32.bitwiseAnd(Int32.logicalRightShift(dist = shift, p), 255);
        (c(24), c(16), c(8), c(0))

    // ── Add ──

    // 加算は dst + src×a/255。b は 240+25=265 → 255 にクランプされる。
    @Test
    def testAddSumsAndClamps(): Unit \ Assert =
        let out = SoftRaster.blendPixel(DrawCmd.BlendMode.Add,
            argb(128, 200, 100, 50), argb(255, 100, 200, 240));
        Assert.assertEq(expected = (255, 200, 250, 255), channels(out))

    // ── Multiply ──

    // 白は乗算の単位元 — 白い光を掛けても下の絵は変わらない。
    @Test
    def testMultiplyWhiteIsIdentity(): Unit \ Assert =
        let out = SoftRaster.blendPixel(DrawCmd.BlendMode.Multiply,
            argb(255, 255, 255, 255), argb(255, 12, 34, 56));
        Assert.assertEq(expected = (255, 12, 34, 56), channels(out))

    // 黒は全部を吸収する — 不透明な黒の暗幕は下の絵を真っ黒にする。
    @Test
    def testMultiplyBlackAbsorbs(): Unit \ Assert =
        let out = SoftRaster.blendPixel(DrawCmd.BlendMode.Multiply,
            argb(255, 0, 0, 0), argb(255, 200, 100, 50));
        Assert.assertEq(expected = (255, 0, 0, 0), channels(out))

    // alpha 0 は恒等 — 完全にフェードアウトした暗幕は絵を明るくも暗くもしない
    // （glBlendFunc の因子切替だけで作ると a=0 で逆に明るくなる。この pin がその再発防止）。
    @Test
    def testMultiplyZeroAlphaIsIdentity(): Unit \ Assert =
        let out = SoftRaster.blendPixel(DrawCmd.BlendMode.Multiply,
            argb(0, 0, 0, 0), argb(255, 77, 88, 99));
        Assert.assertEq(expected = (255, 77, 88, 99), channels(out))

    // 半透明の黒（a=128）は半分だけ暗くする。
    @Test
    def testMultiplyHalfAlphaDims(): Unit \ Assert =
        let out = SoftRaster.blendPixel(DrawCmd.BlendMode.Multiply,
            argb(128, 0, 0, 0), argb(255, 200, 100, 50));
        Assert.assertEq(expected = (255, 99, 49, 24), channels(out))

    // ── Normal（SrcOver）──

    // 半透明の赤を緑の上に重ねると、赤と緑が半々に混ざる。
    @Test
    def testNormalIsSrcOver(): Unit \ Assert =
        let out = SoftRaster.blendPixel(DrawCmd.BlendMode.Normal,
            argb(128, 200, 0, 0), argb(255, 0, 200, 0));
        Assert.assertEq(expected = (255, 100, 99, 0), channels(out))

    // ── 焼けない指定の報告（バックエンド同値の見張り） ──

    /// 最小の Drawable（属性は個々のテストで上書きする）。
    def drawable(texture: String, style: Option[GameEngine.BoxStyle]): GameEngine.Drawable =
        { texture = texture, position = { x = 0.0, y = 0.0 }, scale = { x = 1.0, y = 1.0 },
          rotation = 0.0, color = { r = 1.0f32, g = 1.0f32, b = 1.0f32 }, alpha = 1.0f32,
          centered = false, uvOffset = { x = 0.0, y = 0.0 }, uvScale = { x = 1.0, y = 1.0 },
          zIndex = 0, style = style, clip = None, blend = DrawCmd.BlendMode.Normal }

    def someStyle(): Option[GameEngine.BoxStyle] =
        Some(DrawCmd.defaultStyle({ r = 1.0f32, g = 1.0f32, b = 1.0f32 }))

    /// 単色の box に付けた style は焼ける（＝報告に出ない）。テクスチャと文字に付けた style は
    /// この経路では絵に出ないので、件数つきで報告される。
    @Test
    def testDroppedReportsStyleOnTexturedAndText(): Unit \ Assert =
        let ds = drawable("", someStyle()) ::
                 drawable("hero", someStyle()) ::
                 drawable("font_ui", someStyle()) ::
                 drawable("hero", None) :: Nil;
        let got = SoftRaster.dropped(ds) |> List.map(x -> (x#attr, x#count));
        Assert.assertEq(expected = ("style on textured sprite", 1) :: ("style on text", 1) :: Nil, got)

    /// 落とす物が無ければ報告は空（毎回の bake に無意味な行を出さない）。
    @Test
    def testDroppedIsEmptyWhenNothingLost(): Unit \ Assert =
        let ds = drawable("", someStyle()) :: drawable("hero", None) :: Nil;
        Assert.assertEq(expected = 0, List.length(SoftRaster.dropped(ds)))
}
