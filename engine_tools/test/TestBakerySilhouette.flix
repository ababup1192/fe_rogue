// シルエット焼きの純関数部分のテスト。焼き（PNG 書き出し）は renderPng の既存経路に
// 流すだけなので、ここでは「絞り」と「黒化」だけを見る。
mod TestBakerySilhouette {

    /// z に置いた最小の Drawable。シルエット化で消えるべき情報（色・半透明・Add）を持たせる。
    def drawableAt(z: Int32): GameEngine.Drawable =
        { texture = "", position = { x = 0.0, y = 0.0 }, scale = { x = 8.0, y = 8.0 },
          rotation = 0.0, color = { r = 1.0f32, g = 0.0f32, b = 0.0f32 }, alpha = 0.5f32,
          centered = false, uvOffset = { x = 0.0, y = 0.0 }, uvScale = { x = 1.0, y = 1.0 },
          zIndex = z, style = None, clip = None, blend = DrawCmd.BlendMode.Add, mask = Nil }

    /// z に置いた最小の多角形。grad（頂点色）はシルエット化で外れるべき情報。
    def polygonAt(z: Int32): GameEngine.PolygonRenderCmd =
        { vertices = { x = 0.0, y = 0.0 } :: { x = 4.0, y = 0.0 } :: { x = 0.0, y = 4.0 } :: Nil,
          color = { r = 0.2f32, g = 0.8f32, b = 0.4f32 }, alpha = 0.5f32, zIndex = z,
          clip = None, blend = DrawCmd.BlendMode.Add,
          grad = Some({ color = { r = 1.0f32, g = 1.0f32, b = 1.0f32 }, alpha = 1.0f32 } :: Nil) }

    @Test
    def testWorldBandDropsUiAndHud(): Unit \ Assert =
        // 既定の絞り = world 帯（z < UI 層の底）だけが残る。UI 層と HUD 帯は形の検査の対象外。
        let (drawables, polygons) = Bakery.silhouette(Bakery.SilhouetteScope.WorldBand,
            drawableAt(5) :: drawableAt(CanvasLayer.layerStride()) :: drawableAt(ZBand.hudBase()) :: Nil,
            polygonAt(3) :: polygonAt(ZBand.hudBase()) :: Nil);
        Assert.assertEq(expected = ((1, Some(5)), (1, Some(3))),
            ((List.length(drawables), List.head(drawables) |> Option.map(d -> d#zIndex)),
             (List.length(polygons),  List.head(polygons)  |> Option.map(p -> p#zIndex))))

    @Test
    def testAllKeepsEverythingAndBlackens(): Unit \ Assert =
        // All は絞らず全アイテムを黒の不透明・Normal にする。多角形の grad（頂点色）も外れる。
        let (drawables, polygons) = Bakery.silhouette(Bakery.SilhouetteScope.All,
            drawableAt(ZBand.hudBase()) :: Nil, polygonAt(3) :: Nil);
        Assert.assertEq(
            expected = (Some(((0.0f32, 0.0f32, 0.0f32), 1.0f32, DrawCmd.BlendMode.Normal)),
                        Some(((0.0f32, 0.0f32, 0.0f32), 1.0f32, DrawCmd.BlendMode.Normal, true))),
            (List.head(drawables) |> Option.map(d -> (Color.channels(d#color), d#alpha, d#blend)),
             List.head(polygons)  |> Option.map(p ->
                 (Color.channels(p#color), p#alpha, p#blend, Option.isEmpty(p#grad)))))
}
