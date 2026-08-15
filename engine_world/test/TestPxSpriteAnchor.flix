// PxSprite の置き方の規約（anchor までのずれ）— 反転で左右の逆側へ写る。
mod TestPxSpriteAnchor {

    def doc(): PxSpriteDoc.Doc =
        { version = 1, note = None, legend = Map#{ 'm' => "metal" },
          sprites = Map#{ "tool" => { anchor = { x = 0.0, y = 3.0 }, loop = PxSpriteDoc.Loop.Forward,
                                      frames = Map#{ "idle" => "m..." :: "m..." :: "m..." :: "m..." :: Nil } } } }

    @Test
    def testFlipMirrorsTheOffset(): Unit \ Assert =
        // 幅 4 の絵で左端（0 列）を握る。真ん中から見て握るところは左に 2px。
        // 反転すると絵は握るところの左へ伸びるので、真ん中から見て右に 1px になる。
        let plain = PxSprite.anchorOffsetOf(doc(), "tool", "idle", false, 1);
        let flipped = PxSprite.anchorOffsetOf(doc(), "tool", "idle", true, 1);
        Assert.assertEq(expected = (-2.0, 1.0), (plain#x, flipped#x))

    @Test
    def testScaleMultipliesTheOffset(): Unit \ Assert =
        let one = PxSprite.anchorOffsetOf(doc(), "tool", "idle", false, 1);
        let three = PxSprite.anchorOffsetOf(doc(), "tool", "idle", false, 3);
        Assert.assertEq(expected = (one#x * 3.0, one#y * 3.0), (three#x, three#y))

    @Test
    def testUnknownSpriteHasNoOffset(): Unit \ Assert =
        let off = PxSprite.anchorOffsetOf(doc(), "nope", "idle", false, 1);
        Assert.assertEq(expected = (0.0, 0.0), (off#x, off#y))
}
