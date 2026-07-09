/// Camera の投影（`getViewTransform`）のテスト。
///
/// カメラは追従を持たない純投影の値なので、検証するのは「center を画面中央に、zoom 倍で映す」
/// ViewTransform の数式だけ:
///   offset = { center#x × zoom#x - viewport幅/2, center#y × zoom#y - viewport高/2 }, scale = zoom
mod TestCamera {

    def approx(a: Float64, b: Float64): Bool =
        let diff = a - b;
        let d = if (diff < 0.0) -1.0 * diff else diff;
        d < 0.0001

    def vp200x100(): {viewportWidth = Float64, viewportHeight = Float64} =
        {viewportWidth = 200.0, viewportHeight = 100.0}

    /// zoom 1, center (0,0) → offset = (0 - 100, 0 - 50) = (-100, -50)、scale = (1,1)
    @Test
    def testViewTransformAtOrigin(): Unit \ Assert =
        let cam = Camera.make({x = 0.0, y = 0.0});
        let t = Camera.getViewTransform(cam, {x = 0.0, y = 0.0}, vp200x100());
        Assert.assertEq(expected = true,
            approx(t#offset#x, -100.0) and approx(t#offset#y, -50.0)
                and approx(t#scale#x, 1.0) and approx(t#scale#y, 1.0))

    /// zoom 0.5, center (50,25) → offset = (50×0.5 - 100, 25×0.5 - 50) = (-75, -37.5)、scale = (0.5,0.5)
    @Test
    def testViewTransformWithZoomAndCenter(): Unit \ Assert =
        let cam = Camera.make({x = 0.0, y = 0.0}) |> Camera.setZoom({x = 0.5, y = 0.5});
        let t = Camera.getViewTransform(cam, {x = 50.0, y = 25.0}, vp200x100());
        Assert.assertEq(expected = true,
            approx(t#offset#x, -75.0) and approx(t#offset#y, -37.5)
                and approx(t#scale#x, 0.5) and approx(t#scale#y, 0.5))
}
