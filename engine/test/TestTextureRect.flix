// Tests for TextureRect module

mod TestTextureRect {

    def approx(a: Float64, b: Float64): Bool =
        Float64.abs(a - b) < 0.001

    // ========================================================================
    // make — デフォルト値
    // ========================================================================

    /// make で texture / position / size がセットされ、他はデフォルトに
    @Test
    def testMakeDefaults(): Unit \ Assert =
        let rect = TextureRect.make("icon", {x = 10.0, y = 20.0}, {x = 24.0, y = 32.0});
        let pos = Node2D.getPosition(rect);
        let sz = TextureRect.getSize(rect);
        Assert.assertTrue(approx(pos#x, 10.0) and approx(pos#y, 20.0));
        Assert.assertTrue(approx(sz#x, 24.0) and approx(sz#y, 32.0));
        Assert.assertTrue(TextureRect.getTexture(rect) == "icon");
        Assert.assertTrue(CanvasItem.isVisible(rect));
        Assert.assertTrue(CanvasItem.getZIndex(rect) == 0)

    // ========================================================================
    // setTexture / setSize / setVisible
    // ========================================================================

    @Test
    def testSetTexture(): Unit \ Assert =
        let rect = TextureRect.make("a", {x = 0.0, y = 0.0}, {x = 16.0, y = 16.0})
                   |> TextureRect.setTexture("b");
        Assert.assertTrue(TextureRect.getTexture(rect) == "b")

    @Test
    def testSetSize(): Unit \ Assert =
        let rect = TextureRect.make("a", {x = 0.0, y = 0.0}, {x = 16.0, y = 16.0})
                   |> TextureRect.setSize({x = 32.0, y = 48.0});
        let sz = TextureRect.getSize(rect);
        Assert.assertTrue(approx(sz#x, 32.0) and approx(sz#y, 48.0))

    @Test
    def testSetVisible(): Unit \ Assert =
        let rect = TextureRect.make("a", {x = 0.0, y = 0.0}, {x = 16.0, y = 16.0})
                   |> CanvasItem.setVisible(false);
        Assert.assertFalse(CanvasItem.isVisible(rect))

    // ========================================================================
    // EngineNode.getSize 経由で Layout から測定可能
    // ========================================================================

    /// EngineNode.getSize が TextureRect の size を返す (Layout.measureNode で使う)
    @Test
    def testEngineNodeGetSize(): Unit \ Assert =
        let rect = TextureRect.make("a", {x = 0.0, y = 0.0}, {x = 24.0, y = 24.0});
        let node = EngineNode.TextureRectWithState(rect, ());
        match EngineNode.getSize(node) {
            case Some(sz) =>
                Assert.assertTrue(approx(sz#x, 24.0) and approx(sz#y, 24.0))
            case None => Assert.assertTrue(false)
        }

}
