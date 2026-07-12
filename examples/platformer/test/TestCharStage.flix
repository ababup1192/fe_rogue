// TestCharStage — キャラクターラボの演技台本の pin: 区分境界の位置連続性（瞬間移動しない）・
// mode タイムラインの時刻ピン・基準キャラ Char01 の全 mode 描画網羅。

mod TestCharStage {

    // 全区分境界（周回境界 6.0 を含む）で x が連続 — 境界の前後 1ms で 5px 以上飛ばない。
    // 左走りの実速度は「開始点へちょうど戻る」閉形式なので、周回境界もこの検査が守る。
    @Test
    def testXContinuityAtBoundaries(): Unit \ Assert =
        let eps = 0.001;
        let jumps = CharStage.boundaries() |> List.forAll(b -> {
            let before = CharStage.stageAt(b - eps);
            let after = CharStage.stageAt(b + eps);
            Float64.abs(after#pos#x - before#pos#x) < 5.0
        });
        Assert.assertEq(expected = true, jumps)

    // mode タイムラインの時刻ピン: 各区分の中ほどの時刻で mode を突く。
    @Test
    def testModeTimelinePins(): Unit \ Assert =
        let modeAt = t -> (CharStage.stageAt(t))#mode;
        Assert.assertEq(
            expected = (CharStage.Mode.RunMode, CharStage.Mode.DashMode, CharStage.Mode.SkidMode,
                        CharStage.Mode.RunMode, CharStage.Mode.JumpMode, CharStage.Mode.LandMode,
                        CharStage.Mode.IdleMode),
            (modeAt(0.4), modeAt(1.5), modeAt(2.2), modeAt(3.0), modeAt(4.0), modeAt(4.6), modeAt(5.5)))

    // 基準キャラ Char01 は全 mode（落下 4.3 を含む 8 サンプル）で必ずパーツを返す。
    @Test
    def testChar01DrawIsTotal(): Unit \ Assert =
        let ts = 0.4 :: 1.5 :: 2.2 :: 3.0 :: 4.0 :: 4.3 :: 4.6 :: 5.5 :: Nil;
        let total = ts |> List.forAll(t ->
            List.length(Char01.draw(CharStage.stageAt(t))) > 0);
        Assert.assertEq(expected = true, total)
}
