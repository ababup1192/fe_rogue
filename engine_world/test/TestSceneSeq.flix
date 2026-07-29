// SceneSeq の逐次消化を、特定ゲームと無関係な玩具 World（Int32）で pin する。
// カット型も進捗型も多相であること、Done で次のカットへ進むこと、Skip と打ち切りが
// notes に言葉で残ること（fail-open だが無音ではない）を具体値で固定する。

mod TestSceneSeq {

    // 玩具 perform: カットは Int32。n > 0 なら「n コマ演じたら Done」、n < 0 なら Skip。
    // 演じるたびに World（Int32）を +1 する — 何コマ演じたかが World の値で分かる。
    def act(cut: Int32, prog: Option[Int32], _dt: Float64, w: Int32): (SceneSeq.Status[Int32], Int32) =
        if (cut < 0) (SceneSeq.Status.Skip("neg"), w)
        else {
            let n = Option.getWithDefault(0, prog) + 1;
            if (n >= cut) (SceneSeq.Status.Done, w + 1)
            else (SceneSeq.Status.Running(n), w + 1)
        }

    // 玩具 perform: 終われないカット（常に Running）。打ち切りの安全弁を試す用。
    def never(_cut: Int32, prog: Option[Int32], _dt: Float64, w: Int32): (SceneSeq.Status[Int32], Int32) =
        (SceneSeq.Status.Running(Option.getWithDefault(0, prog) + 1), w + 1)

    // 玩具 idle: カットが尽きたあとは World を動かさない（値の変化 = perform の回数になる）。
    def still(_dt: Float64, w: Int32): Int32 = w

    /// Done で次のカットへ進む: 2 コマのカット + 1 コマのカット = perform 3 回。
    /// frames は w0 を先頭に含み、1 コマごとの姿が並ぶ。notes は空。
    @Test
    def testDoneAdvancesToNextCut(): Unit \ Assert =
        let played = SceneSeq.play(act, still, 10, 1.0, 2 :: 1 :: Nil, 0);
        Assert.assertEq(
            expected = (0 :: 1 :: 2 :: 3 :: Nil, (Nil: List[String])),
            (played#frames, played#notes))

    /// Skip したカットは番号つきで notes に残り、続きのカットはそのまま演じられる。
    @Test
    def testSkipIsNotedWithCutNumber(): Unit \ Assert =
        let played = SceneSeq.play(act, still, 10, 1.0, 1 :: -1 :: 1 :: Nil, 0);
        Assert.assertEq(
            expected = ("カット2 を飛ばした: neg" :: Nil, 2),
            (played#notes, SceneSeq.finalWorld(act, still, 10, 1.0, 1 :: -1 :: 1 :: Nil, 0)))

    /// 終われないカットがいても maxFrames で必ず戻り、打ち切ったことを notes で報せる。
    @Test
    def testMaxFramesCutoffIsNoted(): Unit \ Assert =
        let played = SceneSeq.play(never, still, 3, 1.0, 99 :: Nil, 0);
        Assert.assertEq(
            expected = (4, 1),
            (List.length(played#frames), List.length(played#notes)))

    /// カットが尽きたら idle が時間だけを流す（tick は止まらない）。
    @Test
    def testIdleAfterCutsExhausted(): Unit \ Assert =
        let s0 = SceneSeq.start((Nil: List[Int32]));
        let (s1, w1) = SceneSeq.tick(act, (_, w) -> w + 100, 1.0, s0, 0);
        Assert.assertEq(expected = (true, 100), (SceneSeq.done(s1), w1))
}
