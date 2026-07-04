// Replay の fold を、特定ゲームと無関係な玩具 World で pin する。多相性を示すのが狙い:
// tick の World 型も入力型も自由に選べること（ここでは Int32 の World を Bool 入力で、
// Float64 の World を dt 積算で駆動）を具体値で固定する。

mod TestReplay {

    // 玩具 tick #1: Int32 の状態を Bool 入力で駆動する。true なら +1、false なら据え置き。
    // dt は無視 — 入力型が Bool でも fold が成立することを示す。
    def bump(input: Bool, _dt: Float64, w: Int32): Int32 =
        if (input) w + 1 else w

    // 玩具 tick #2: dt が各フレームへ確かに流れることを示す。on のあいだ dt を積む。
    def integ(on: Bool, dt: Float64, w: Float64): Float64 =
        if (on) w + dt else w

    /// play は Trace を畳んで終端の World を返す。true×3・false×2・true×1 で +4。
    @Test
    def testPlayDrivesToyWorld(): Unit \ Assert =
        let cues =
            { input = true, frames = 3 } ::
            { input = false, frames = 2 } ::
            { input = true, frames = 1 } :: Nil;
        Assert.assertEq(expected = 4, Replay.play(bump, 1.0, cues, 0))

    /// timeline は各フレーム後の World を最古から順に並べる（initial は含まない）。
    @Test
    def testTimelineRecordsEveryFrame(): Unit \ Assert =
        let cues =
            { input = true, frames = 2 } ::
            { input = false, frames = 1 } :: Nil;
        Assert.assertEq(
            expected = 1 :: 2 :: 2 :: Nil,
            Replay.timeline(bump, 1.0, cues, 0))

    /// 空の Trace は initial をそのまま返し、フレームを 1 つも積まない。
    @Test
    def testEmptyTraceIsInitial(): Unit \ Assert =
        Assert.assertEq(
            expected = (7, Nil),
            (Replay.play(bump, 1.0, Nil, 7),
             Replay.timeline(bump, 1.0, (Nil: List[Replay.Cue[Bool]]), 7)))

    /// dt は各フレームの tick へ渡る: 0.25 を 4 フレーム積んで 1.0。
    @Test
    def testDtIsThreaded(): Unit \ Assert =
        let cues = { input = true, frames = 4 } :: Nil;
        Assert.assertEq(expected = 1.0, Replay.play(integ, 0.25, cues, 0.0))

    /// play と timeline の終端は一致する（timeline の最後のフレーム == play の結果）。
    @Test
    def testTimelineEndsWherePlayEnds(): Unit \ Assert =
        let cues =
            { input = true, frames = 3 } ::
            { input = false, frames = 2 } :: Nil;
        let film = Replay.timeline(bump, 1.0, cues, 0);
        Assert.assertEq(
            expected = Replay.play(bump, 1.0, cues, 0),
            List.last(film) |> Option.getWithDefault(-1))
}
