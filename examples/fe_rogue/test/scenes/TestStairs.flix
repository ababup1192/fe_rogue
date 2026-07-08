// Stairs のテスト
//
// 階段は床のランダムセルに 1 つ置かれ、味方がそのセルに乗ると「かいだん」コマンドが
// 出る。階段の位置は World の `stairsPosOf` が唯一の権威（`Stairs.placeAt` は
// `Cmd.SetStairs` を emit するだけ）。ここでは配置とその後の問い合わせの性質を固定する:
//   - 配置前は stairsPosOf が None
//   - placeAt したセルだけ stairsPosOf が Some、別セルには一致しない
//
// ランダム配置 (placeRandom) は実マップ (LDTK) を要求するためここでは扱わず、
// セルを固定した placeAt で「配置 → 問い合わせ」の論理だけを検証する。

mod TestStairs {

    // ========================================================================
    // 配置前: stairsPosOf は None
    // ========================================================================

    /// 何も置いていない World は、階段が無い扱い（stairsPosOf = None）。
    @Test
    def testStairsPosOfNoneBeforePlacement(): Unit \ Assert =
        Assert.assertEq(expected = (None: Option[(Int32, Int32)]),
            World.stairsPosOf(World.empty()) |> Option.map(p -> (p#x, p#y)))

    // ========================================================================
    // 配置後: placeAt は Cmd.SetStairs を emit し、それが World.stairsPosOf を権威化する
    // ========================================================================

    /// placeAt が emit した Cmd を region Ref[World] へ applyCmd すると、World.stairsPosOf は
    /// 置いたセルだけを返し、別セルには一致しない（gameplay reader が読む権威が World である証跡）。
    @Test
    def testPlaceAtDrivesWorldStairsPos(): Unit \ Assert =
        region rc {
            let wref = Ref.fresh(rc, World.empty());
            run { Stairs.placeAt({x = 3, y = 4}) }
                with handler World.Command {
                    def emit(c, k) = { Ref.put(World.applyCmd(c, Ref.get(wref)), wref); k() }
                };
            Assert.assertEq(
                expected = (Some((3, 4)), false),
                (World.stairsPosOf(Ref.get(wref)) |> Option.map(pos -> (pos#x, pos#y)),
                 World.stairsPosOf(Ref.get(wref)) |> Option.exists(pos -> pos#x == 3 and pos#y == 5)))
        }
}
