// コマの回し方の宣言（sprite Doc の "loop"）— 宣言が Doc から読めること、
// 宣言ごとにコマ番号の並びが変わること。
mod TestPxSpriteLoop {

    def docText(loopField: String): String =
        "{\"version\":1,\"legend\":{\"a\":\"ink\"},\"sprites\":{\"grass\":{" +
        loopField + "\"frames\":{\"f0\":[\"a\"]}}}}"

    def loopOf(text: String): Option[PxSpriteDoc.Loop] =
        PxSpriteDoc.fromJson(text)
            |> Option.flatMap(doc -> Map.get("grass", doc#sprites))
            |> Option.map(sp -> sp#loop)

    @Test
    def testMissingLoopStaysForward(): Unit \ Assert =
        // 書いていない Doc は従来どおり順送り（既存の *.sprite.json を壊さない）。
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
}
