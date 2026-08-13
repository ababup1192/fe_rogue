// Daylight（一日の空気の色）— 節の間で滑らかに混ざること、日をまたいでも飛ばないこと。
mod TestDaylight {

    def keys(): List[Daylight.Key] =
        { at = 0.0, color = { r = 0.0, g = 0.0, b = 1.0 }, strength = 1.0 }
     :: { at = 0.5, color = { r = 1.0, g = 1.0, b = 1.0 }, strength = 0.0 } :: Nil

    @Test
    def testSampleHitsTheKeyExactly(): Unit \ Assert =
        Assert.assertEq(expected = 1.0, Daylight.sample(keys(), 0.0)#strength)

    @Test
    def testSampleBlendsBetweenKeys(): Unit \ Assert =
        // 真ん中では濃さもちょうど半分。
        Assert.assertEq(expected = 0.5, Daylight.sample(keys(), 0.25)#strength)

    @Test
    def testSampleWrapsAroundMidnight(): Unit \ Assert =
        // 0.75 は「0.5 の節から 1.0（= 次の日の 0.0）の節へ」の中間。
        Assert.assertEq(expected = 0.5, Daylight.sample(keys(), 0.75)#strength)

    @Test
    def testEmptyKeysLetTheColourThrough(): Unit \ Assert =
        Assert.assertEq(expected = 0.0, Daylight.sample(Nil, 0.3)#strength)

    @Test
    def testOverlayVanishesWhenAirIsClear(): Unit \ Assert =
        // 昼（濃さ 0）は 1 枚も置かない — 無駄な描画物を出さない。
        let items = Daylight.overlay({ keys = keys(), at = Vec2.zero(), size = { x = 10.0, y = 10.0 }, z = 5 }, 0.5);
        Assert.assertEq(expected = true, List.isEmpty(items))

    @Test
    def testOverlayIsOneSheetWhenAirIsThick(): Unit \ Assert =
        let items = Daylight.overlay({ keys = keys(), at = Vec2.zero(), size = { x = 10.0, y = 10.0 }, z = 5 }, 0.0);
        Assert.assertEq(expected = 1, List.length(items))
}
