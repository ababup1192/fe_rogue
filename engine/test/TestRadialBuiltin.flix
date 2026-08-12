// RadialBuiltin の画素を具体値で釘打ちする。GL と SoftRaster が同じ列から絵を作る
// 前提なので、ここの値が変わる = 全ゲームの lightAt / darkAt の見た目が変わる。
//
//   横一列（y=128）を左から右へ見た断面のイメージ（alpha はどちらも常に 255）:
//     light の rgb :   0 ……  62 …… 255 ……  62 ……   0 （中心が白く縁で黒 = Add で素通し）
//     dark  の rgb : 255 …… 129 ……   0 …… 129 …… 255 （中心が黒く縁で白 = Multiply で素通し）
mod TestRadialBuiltin {

    /// 比較は (a, r, g, b) のタプルで行う（負の ARGB int を直接比べると読みにくい）。
    def channels(p: Int32): (Int32, Int32, Int32, Int32) =
        let c = shift -> Int32.bitwiseAnd(Int32.logicalRightShift(dist = shift, p), 255);
        (c(24), c(16), c(8), c(0))

    /// 画素 (x, y) を行優先の列から引く。
    def pixelAt(v: Vector[Int32], x: Int32, y: Int32): (Int32, Int32, Int32, Int32) =
        channels(Vector.get(y * RadialBuiltin.size() + x, v))

    // 明かり: alpha は常に 255 のまま、中心 (128,128) = 白、縁 (255,128) = rgb 0 まで
    // 滑らかに消える（Add で rgb 0 = 素通し。縁が 0 で終わらないと、正方形テクスチャの
    // 切れ目が四角い輪郭として見える）。
    @Test
    def testLightPixelsCenterAndEdge(): Unit \ Assert =
        let v = RadialBuiltin.lightPixels();
        Assert.assertEq(expected = (255, 255, 255, 255) :: (255, 0, 0, 0) :: Nil,
            pixelAt(v, 128, 128) :: pixelAt(v, 255, 128) :: Nil)

    // 明かり: 中間半径 (192,128)（t ≈ 0.504）は smoothstep 減衰 126 の 2 乗を生成した値で
    // round(126²/255) = 62。
    @Test
    def testLightPixelsMidRadius(): Unit \ Assert =
        Assert.assertEq(expected = (255, 62, 62, 62),
            pixelAt(RadialBuiltin.lightPixels(), 192, 128))

    // 翳り: alpha は常に 255 のまま、rgb が中心 (128,128) = 黒 → 中間 (192,128) = 129 →
    // 縁 (255,128) = 白（Multiply で「素通し」）へ明ける。light と同じ curve の裏返しなので
    // 中間は 255 − 126 = 129 になる。
    @Test
    def testDarkPixelsCenterMidEdge(): Unit \ Assert =
        let v = RadialBuiltin.darkPixels();
        Assert.assertEq(
            expected = (255, 0, 0, 0) :: (255, 129, 129, 129) :: (255, 255, 255, 255) :: Nil,
            pixelAt(v, 128, 128) :: pixelAt(v, 192, 128) :: pixelAt(v, 255, 128) :: Nil)
}
