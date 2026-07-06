// TestSfx — 「このフレームで何が鳴るか」を具体値で固定する。衝突音は Step が盤に記録した
// 事実から、局面音（サーブ・ミス・クリア・ゲームオーバー）は局面の変わり目から導かれる。
// World を 1 歩だけ進め、その前後を Sfx.events に渡して名前の列を pin する。

mod TestSfx {

    /// 1 歩進めて、その前後から鳴る音を導く。
    def soundsAfterStep(input: Field.Input, world: Field.World): List[String] =
        Sfx.events(world, Step.update(input, Trace.dt(), world))

    /// ブロック 1 個の真下にボールを重ねて上向きに置いた World（update 1 回で確実に当たる）。
    def overlapWorld(durability: Option[Field.Durability]): Field.World =
        Trace.mkWorld({
            statics = (Trace.blockId(), Trace.vec(160.0, 60.0), Trace.rect(30.0, 12.0)) :: Nil,
            ball = { pos = Trace.vec(160.0, 68.0), vel = Trace.vec(0.0, -130.0) },
            blocks = (Trace.blockId(), 0) :: Nil,
            durabilities = durability |> Option.map(d -> (Trace.blockId(), d)) |> Option.toList })

    // ハードブロックが耐えた: chip が 1 つ鳴る。
    @Test
    def testChipSound(): Unit \ Assert =
        Assert.assertEq(expected = "chip" :: Nil,
            soundsAfterStep(Field.noInput(), overlapWorld(Some({ hp = 2, maxHp = 2 }))))

    // 最後の 1 個を壊すと勝ち: 破壊音でなくクリアのファンファーレが鳴る
    // （凍結した盤の記録は読まない —— 読むと毎フレーム鳴り続けてしまう）。
    @Test
    def testClearSoundSupersedesBreak(): Unit \ Assert =
        Assert.assertEq(expected = "clear" :: Nil,
            soundsAfterStep(Field.noInput(), overlapWorld(Some({ hp = 1, maxHp = 1 }))))

    // 壊れないブロック: 跳ね返るだけで何も鳴らない。
    @Test
    def testUnbreakableIsSilent(): Unit \ Assert =
        Assert.assertEq(expected = Nil,
            soundsAfterStep(Field.noInput(), overlapWorld(None)))

    // サーブ: 待機で launch を押した瞬間に serve が鳴る。
    @Test
    def testServeSound(): Unit \ Assert =
        let waiting = Step.update({ enter = true | Field.noInput() }, Trace.dt(), Field.titleWorld());
        Assert.assertEq(expected = "serve" :: Nil,
            soundsAfterStep({ launch = true | Field.noInput() }, waiting))

    // パドルに当たる: paddle が鳴る（すぐ上から落として 1 歩で接触する高さに置く）。
    @Test
    def testPaddleSound(): Unit \ Assert =
        let world = Trace.mkWorld({
            statics = Nil,
            ball = { pos = Trace.vec(160.0, 214.0), vel = Trace.vec(0.0, 130.0) },
            blocks = Nil,
            durabilities = Nil });
        Assert.assertEq(expected = "paddle" :: Nil,
            soundsAfterStep(Field.noInput(), world))
}
