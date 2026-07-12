// Anim のテスト。frameAt は (clip, t) だけで決まる純関数なので、境界の値を
// 丸めの出ない入力で固定する。regionOf は矩形の位置・サイズをそのまま検算する。

mod TestAnim {

    def loopClip(): Anim.Clip = { row = 0, frames = 4, fps = 8.0, looping = true }

    /// ループ: 4 コマ 8fps。t=0.125 でコマが 1 つ進み、t=0.5（4 コマぶん）で 1 周して 0 に戻る。
    @Test
    def testFrameAtLoopsAcrossBoundaries(): Unit \ Assert =
        let clip = loopClip();
        Assert.assertEq(expected = (0, 0, 1, 0, 0),
            (Anim.frameAt(clip, 0.0), Anim.frameAt(clip, 0.124),
             Anim.frameAt(clip, 0.125), Anim.frameAt(clip, 0.5), Anim.frameAt(clip, 1.0)))

    /// 単発: looping=false は最終コマ（frames-1）で止まり、それ以上進まない。
    @Test
    def testFrameAtOneShotClampsAtLastFrame(): Unit \ Assert =
        let clip = { row = 0, frames = 3, fps = 10.0, looping = false };
        Assert.assertEq(expected = (0, 1, 2, 2, 2),
            (Anim.frameAt(clip, 0.0), Anim.frameAt(clip, 0.1),
             Anim.frameAt(clip, 0.2), Anim.frameAt(clip, 100.0), Anim.frameAt(clip, 9999.0)))

    /// 負の t とコマ数 0 は安全側の 0 に倒す。
    @Test
    def testFrameAtNegativeTimeAndZeroFramesFallBackToZero(): Unit \ Assert =
        let normal = loopClip();
        let empty = { row = 0, frames = 0, fps = 8.0, looping = true };
        Assert.assertEq(expected = (0, 0),
            (Anim.frameAt(normal, -1.0), Anim.frameAt(empty, 1.0)))

    /// regionOf: 段 2・コマ 3・24x24 は position (72, 48)・size (24, 24)。
    @Test
    def testRegionOfComputesExactRect(): Unit \ Assert =
        let clip = { row = 2, frames = 6, fps = 8.0, looping = true };
        let rect = Anim.regionOf(24.0, 24.0, clip, 3);
        Assert.assertEq(expected = ((72.0, 48.0), (24.0, 24.0)),
            ((rect#position#x, rect#position#y), (rect#size#x, rect#size#y)))

    /// regionAt は frameAt で求めたコマを regionOf に渡すのと同じ結果になる。
    @Test
    def testRegionAtMatchesFrameAtThenRegionOf(): Unit \ Assert =
        let clip = { row = 1, frames = 4, fps = 8.0, looping = true };
        let t = 0.5;
        let expectedRect = Anim.regionOf(16.0, 16.0, clip, Anim.frameAt(clip, t));
        let actualRect = Anim.regionAt(16.0, 16.0, clip, t);
        Assert.assertEq(expected = (expectedRect#position#x, expectedRect#position#y),
                        (actualRect#position#x, actualRect#position#y))

    /// fps 0 は 0 除算せず floor(t*0)=0 で自然にコマ 0 に固定される。
    @Test
    def testFrameAtZeroFpsStaysAtFrameZero(): Unit \ Assert =
        let clip = { row = 0, frames = 5, fps = 0.0, looping = true };
        Assert.assertEq(expected = (0, 0), (Anim.frameAt(clip, 0.0), Anim.frameAt(clip, 50.0)))
}
