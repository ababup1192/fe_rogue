// Perspectiveのサンプラー境界だけを確認する。画面座標の見た目はbakeで守る。
mod TestPerspective {

    /// Sliceのmetaには、カメラ位置ではなく前方断面の付帯情報が届く。
    @Test
    def testCarriesForwardSectionMeta(): Unit \ Assert =
        let baseProgress = 10.0;
        let sampleAt = progress ->
            { centerX = 160.0,
              width = 100.0,
              meta = progress > baseProgress };
        let slice = Perspective.atDepth(
            1.0, baseProgress, sampleAt, fixture());
        Assert.assertTrue(slice#meta)

    /// 曲がるサンプラーでは、前方断面と基準断面の差が画面上の曲がりになる。
    @Test
    def testBendFollowsSampleDifference(): Unit \ Assert =
        let sampleAt = progress ->
            { centerX = 160.0 + progress,
              width = 100.0,
              meta = false };
        let slice = Perspective.atDepth(0.5, 0.0, sampleAt, fixture());
        Assert.assertTrue(slice#centerX > fixture()#screenWidth / 2.0)

    /// 一連の断面は両端を含み、手前から奥へ進行度が増える。
    @Test
    def testSlicesCoverViewDepth(): Unit \ Assert =
        let sampleAt = progress ->
            { centerX = 160.0,
              width = 100.0,
              meta = progress };
        let slices = Perspective.slices(0.0, sampleAt, fixture());
        let endpoints =
            forM (first <- List.head(slices);
                  last <- List.last(slices))
            yield (first#depth, last#depth, first#progress < last#progress);
        Assert.assertEq(
            expected = (Perspective.sliceCount() + 1, Some((0.0, 1.0, true))),
            (List.length(slices), endpoints))

    def fixture(): Perspective.Config =
        { screenWidth = 320.0,
          horizonY = 60.0,
          nearY = 244.0,
          viewDistance = 100.0 }
}
