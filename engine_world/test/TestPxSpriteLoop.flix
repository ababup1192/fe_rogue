// 動き（clips）の回し方の宣言 — 宣言が Doc から読めること、宣言ごとにコマ番号の
// 並びが変わること、経った秒数からコマの名前が引けること。
mod TestPxSpriteLoop {

    def docText(loopField: String): String =
        "{\"version\":1,\"legend\":{\"a\":\"ink\"},\"sprites\":{\"grass\":{" +
        "\"frames\":{\"f0\":[\"a\"]},\"clips\":{\"go\":{\"frames\":[\"f0\"]," + loopField + "\"fps\":8}}}}}"

    def loopOf(text: String): Option[PxSpriteDoc.Loop] =
        PxSpriteDoc.fromJson(text)
            |> Option.flatMap(doc -> Map.get("grass", doc#sprites))
            |> Option.flatMap(sp -> Map.get("go", sp#clips))
            |> Option.map(c -> c#loop)

    @Test
    def testMissingLoopStaysForward(): Unit \ Assert =
        // 書いていない動きは順送り。
        Assert.assertEq(expected = Some(PxSpriteDoc.Loop.Forward), loopOf(docText("")))

    @Test
    def testPingPongIsRead(): Unit \ Assert =
        Assert.assertEq(expected = Some(PxSpriteDoc.Loop.PingPong),
            loopOf(docText("\"loop\":\"pingpong\",")))

    @Test
    def testUnknownLoopFallsBackToForward(): Unit \ Assert =
        // 書き損じは既定へ落とす（Doc 規約の fail-open）。
        Assert.assertEq(expected = Some(PxSpriteDoc.Loop.Forward),
            loopOf(docText("\"loop\":\"zigzag\",")))

    def walk(kind: PxSpriteDoc.Loop): List[Int32] =
        List.range(0, 8) |> List.map(s -> PxSpriteDoc.frameIndexAt(kind, 3, s))

    @Test
    def testForwardWrapsAround(): Unit \ Assert =
        Assert.assertEq(expected = 0 :: 1 :: 2 :: 0 :: 1 :: 2 :: 0 :: 1 :: Nil,
            walk(PxSpriteDoc.Loop.Forward))

    @Test
    def testPingPongTurnsBackWithoutRepeatingTheEnd(): Unit \ Assert =
        // 折り返しのコマを 2 度出すと、端で 1 コマぶん止まって見える。
        Assert.assertEq(expected = 0 :: 1 :: 2 :: 1 :: 0 :: 1 :: 2 :: 1 :: Nil,
            walk(PxSpriteDoc.Loop.PingPong))

    @Test
    def testOnceStopsAtTheLastFrame(): Unit \ Assert =
        Assert.assertEq(expected = 0 :: 1 :: 2 :: 2 :: 2 :: 2 :: 2 :: 2 :: Nil,
            walk(PxSpriteDoc.Loop.Once))

    @Test
    def testSingleFrameNeverMoves(): Unit \ Assert =
        Assert.assertEq(expected = (0, 0),
            (PxSpriteDoc.frameIndexAt(PxSpriteDoc.Loop.PingPong, 1, 5),
             PxSpriteDoc.frameIndexAt(PxSpriteDoc.Loop.Forward, 0, 5)))

    def clipDoc(): String =
        "{\"version\":1,\"legend\":{\"a\":\"ink\"},\"sprites\":{\"hero\":{" +
        "\"frames\":{\"down\":[\"a\"],\"down_walk\":[\"a\"]}," +
        "\"clips\":{\"walk_down\":{\"frames\":[\"down\",\"down_walk\"],\"fps\":4}}}}}"

    def frameAt(seconds: Float64): Option[String] =
        PxSpriteDoc.fromJson(clipDoc())
            |> Option.flatMap(doc -> PxSpriteDoc.clipFrameAt(doc, "hero", "walk_down", seconds))

    @Test
    def testClipStartsAtFirstFrame(): Unit \ Assert =
        Assert.assertEq(expected = Some("down"), frameAt(0.0))

    @Test
    def testClipAdvancesWithFps(): Unit \ Assert =
        // 4fps なので 0.25 秒で次のコマ。
        Assert.assertEq(expected = Some("down_walk"), frameAt(0.25))

    @Test
    def testClipWrapsAround(): Unit \ Assert =
        Assert.assertEq(expected = Some("down"), frameAt(0.5))

    @Test
    def testUnknownClipIsNone(): Unit \ Assert =
        // 知らない動きは None。呼ぶ側は自分でコマの名前を選ぶ道が残る。
        let got = PxSpriteDoc.fromJson(clipDoc())
            |> Option.flatMap(doc -> PxSpriteDoc.clipFrameAt(doc, "hero", "fly", 0.0));
        Assert.assertEq(expected = None, got)

    @Test
    def testNegativeSecondsStaysAtFirstFrame(): Unit \ Assert =
        Assert.assertEq(expected = Some("down"), frameAt(-3.0))

}
