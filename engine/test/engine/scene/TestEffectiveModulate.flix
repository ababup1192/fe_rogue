// Tests for Scene.effectiveModulateAt — 祖先 modulate の乗算伝播（Godot CanvasItem 準拠）
//
// toDrawables を経由しない描画パス（Polygon2D / Arc2D 収集）が、待機/行動済みの暗転を
// 尊重できるよう、祖先 modulate × 自ノード modulate を返すヘルパ。effectiveZIndexAt と対。
// 純粋（GameEngine.Game 不要）なので mock ハンドラ無しで直接検証する。
// Color は素の record で Eq/ToString を持たないため、各チャンネル（Float32）を個別に assertEq する。

mod TestEffectiveModulate {

    /// engine 単体テスト用の最小 tag enum
    pub enum Tag with Eq, ToString { case NoTag }

    /// modulate を持つ Marker2D ノードを作る
    def markerWithMod(color: Color): EngineNode[Tag] =
        let m = Marker2D.make(Vec2.zero()) |> CanvasItem.setModulate(color);
        EngineNode.Marker2DWithState(m, Tag.NoTag)

    /// Color をチャンネルごとに突き合わせる（record の Eq 不在を回避）
    def assertColor(exp: Color, got: Color): Unit \ Assert =
        Assert.assertEq(expected = exp#r, got#r);
        Assert.assertEq(expected = exp#g, got#g);
        Assert.assertEq(expected = exp#b, got#b)

    // ── 祖先 modulate が子に乗算される ──
    @Test
    def testAncestorMultipliesChild(): Unit \ Assert =
        let parentMod: Color = {r = 0.5f32, g = 0.5f32, b = 0.5f32};
        let childMod:  Color = {r = 0.8f32, g = 0.4f32, b = 1.0f32};
        let scene = Scene.empty()
            |> Scene.addNode("P", markerWithMod(parentMod))
            |> Scene.addChildAt("P" :: Nil, "C", markerWithMod(childMod));
        // 祖先(0.5,0.5,0.5) × 自(0.8,0.4,1.0) = (0.4, 0.2, 0.5)
        assertColor({r = 0.4f32, g = 0.2f32, b = 0.5f32},
            Scene.effectiveModulateAt("P" :: "C" :: Nil, scene))

    // ── 祖先が無ければ自ノードの modulate そのまま ──
    @Test
    def testRootReturnsOwnModulate(): Unit \ Assert =
        let selfMod: Color = {r = 0.3f32, g = 0.6f32, b = 0.9f32};
        let scene = Scene.empty() |> Scene.addNode("P", markerWithMod(selfMod));
        assertColor(selfMod, Scene.effectiveModulateAt("P" :: Nil, scene))

    // ── 祖先 2 段の乗算が連鎖する ──
    @Test
    def testTwoAncestorsChain(): Unit \ Assert =
        let g: Color = {r = 0.5f32, g = 0.5f32, b = 0.5f32};   // 祖父
        let p: Color = {r = 0.5f32, g = 0.5f32, b = 0.5f32};   // 親
        let c: Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32};   // 自
        let scene = Scene.empty()
            |> Scene.addNode("G", markerWithMod(g))
            |> Scene.addChildAt("G" :: Nil, "P", markerWithMod(p))
            |> Scene.addChildAt("G" :: "P" :: Nil, "C", markerWithMod(c));
        // 0.5 × 0.5 × 1.0 = 0.25
        assertColor({r = 0.25f32, g = 0.25f32, b = 0.25f32},
            Scene.effectiveModulateAt("G" :: "P" :: "C" :: Nil, scene))
}
