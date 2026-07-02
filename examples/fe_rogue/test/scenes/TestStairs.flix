// Stairs のテスト
//
// 階段は床のランダムセルに 1 つ置かれ、味方がそのセルに乗ると「かいだん」コマンドが
// 出る。ここでは配置とその後の問い合わせ（getPos）の性質を固定する:
//   - 配置前は getPos が None（placed ゲート）
//   - placeAt したセルだけ getPos が Some、別セルには一致しない
//
// ランダム配置 (placeRandom) は実マップ (LDTK) を要求するためここでは扱わず、
// セルを固定した placeAt で「配置 → 問い合わせ」の論理だけを検証する。

mod TestStairs {

    /// 階段ノード 1 つだけの最小シーン（JSON ロードを介さず Marker2D を直接構築）。
    /// 初期は placed = false（未配置）。
    def emptyStairsScene(): Scene[NodeTag] =
        let marker = Marker2D.make(Vec2.zero());
        Scene.empty()
            |> Scene.addNode("Stairs",
                EngineNode.Marker2DWithState(marker,
                    NodeTag.Stairs(({gridPos = {x = 0, y = 0},
                                      placed  = false}: Stairs.Data))))

    // ========================================================================
    // 配置前: placed ゲートで getPos は None
    // ========================================================================

    /// add 直後（未配置）は、どのセルを問い合わせても階段は無い扱い（getPos = None）。
    @Test
    def testUnplacedStairsHasNoPosition(): Unit \ Assert =
        let scene = emptyStairsScene();
        Assert.assertEq(
            expected = None,
            Stairs.getPos(scene) |> Option.map(pos -> (pos#x, pos#y)))

    // ========================================================================
    // 配置後: 置いたセルだけ getPos が Some を返す
    // ========================================================================

    /// placeAt は Cmd emit のみ（scene ノード書きは撤去）。getPos は StaffCast の warp と
    /// golden fixture が使う手組みノード用 seam ＝ placed=true の手組みノードで置いたセルだけを返し、
    /// 別セルには一致しないことを pin する。
    @Test
    def testPlaceAtMarksOnlyThatCell(): Unit \ Assert =
        let placed = Scene.empty()
            |> Scene.addNode("Stairs",
                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()),
                    NodeTag.Stairs(({gridPos = {x = 3, y = 4}, placed = true}: Stairs.Data))));
        Assert.assertEq(
            expected = (Some((3, 4)), true, false),
            (Stairs.getPos(placed) |> Option.map(pos -> (pos#x, pos#y)),
             Stairs.getPos(placed) |> Option.exists(pos -> pos#x == 3 and pos#y == 4),
             Stairs.getPos(placed) |> Option.exists(pos -> pos#x == 3 and pos#y == 5)))

    // ========================================================================
    // P3-a: placeAt は `Cmd.SetStairs` を emit し、それが World.stairsPosOf を権威化する
    // ========================================================================

    /// placeAt の emit した Cmd を region Ref[World] へ applyCmd し、World.stairsPosOf が
    /// 置いたセルを返すことを pin する（gameplay reader が読む権威が World である証跡）。
    @Test
    def testPlaceAtDrivesWorldStairsPos(): Unit \ Assert =
        region rc {
            let wref = Ref.fresh(rc, World.empty());
            run { discard Stairs.placeAt({x = 3, y = 4}, emptyStairsScene()) }
                with handler World.Command {
                    def emit(c, k) = { Ref.put(World.applyCmd(c, Ref.get(wref)), wref); k() }
                };
            Assert.assertEq(
                expected = Some((3, 4)),
                World.stairsPosOf(Ref.get(wref)) |> Option.map(pos -> (pos#x, pos#y)))
        }
}
