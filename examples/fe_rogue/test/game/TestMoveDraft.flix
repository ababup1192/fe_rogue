/// MoveDraft の純粋ロジックテスト。
///
/// - `originOf`: id 一致の `MovedFrom` 起点を引く（個別=1件 / 集合=複数 / 不一致=None）。
/// - `anyMovedFromOrigin`: ドラフトで誰かが origin から動いたか（0歩=false / 1歩=true /
///   未選択ユニットは寄与しない）。「敵に見つかったら強制たいき」の誤発火ガードの核。
mod TestMoveDraft {

    def cell(x: Int32, y: Int32): {x = Int32, y = Int32} = {x = x, y = y}

    def punit(id: Int32, x: Int32, y: Int32): {id = Int32, gridPos = {x = Int32, y = Int32}} =
        {id = id, gridPos = cell(x, y)}

    /// {x,y} レコードは ToString 非導出なので、assertEq 用にタプルへ射影する。
    def optCellT(o: Option[{x = Int32, y = Int32}]): Option[(Int32, Int32)] =
        Option.map(c -> (c#x, c#y), o)

    // ── originOf ─────────────────────────────────────────────

    /// 個別移動: 選択ユニットの MovedFrom 起点を引く。
    @Test
    def testOriginOfFound(): Unit \ Assert =
        let drafts = MoveDraft.DraftAction.MovedFrom(2, cell(3, 4)) :: Nil;
        Assert.assertEq(expected = Some((3, 4)), optCellT(MoveDraft.originOf(2, drafts)))

    /// id 不一致 → None。
    @Test
    def testOriginOfNoneForOtherId(): Unit \ Assert =
        let drafts = MoveDraft.DraftAction.MovedFrom(2, cell(3, 4)) :: Nil;
        Assert.assertEq(expected = (None: Option[(Int32, Int32)]),
            optCellT(MoveDraft.originOf(5, drafts)))

    /// 集合移動: 全員分の MovedFrom が積まれていても id ごとに正しい起点を引く。
    @Test
    def testOriginOfGatherMultiple(): Unit \ Assert =
        let drafts = MoveDraft.DraftAction.MovedFrom(0, cell(1, 1))
                  :: MoveDraft.DraftAction.MovedFrom(1, cell(2, 2))
                  :: MoveDraft.DraftAction.GatherWaited(1)
                  :: Nil;
        Assert.assertEq(expected = Some((2, 2)), optCellT(MoveDraft.originOf(1, drafts)))

    // ── anyMovedFromOrigin ───────────────────────────────────

    /// 0歩（live == origin）→ false（ターン頭の誤発火を防ぐ）。
    @Test
    def testAnyMovedFalseAtTurnStart(): Unit \ Assert =
        let drafts = MoveDraft.DraftAction.MovedFrom(2, cell(3, 4)) :: Nil;
        Assert.assertEq(expected = false,
            MoveDraft.anyMovedFromOrigin(punit(2, 3, 4) :: Nil, drafts))

    /// 1歩動いた（live != origin）→ true。
    @Test
    def testAnyMovedTrueAfterStep(): Unit \ Assert =
        let drafts = MoveDraft.DraftAction.MovedFrom(2, cell(3, 4)) :: Nil;
        Assert.assertEq(expected = true,
            MoveDraft.anyMovedFromOrigin(punit(2, 4, 4) :: Nil, drafts))

    /// MovedFrom を持たない（未選択）ユニットは寄与しない → false。
    @Test
    def testAnyMovedIgnoresUnselected(): Unit \ Assert =
        let drafts = MoveDraft.DraftAction.MovedFrom(2, cell(3, 4)) :: Nil;
        Assert.assertEq(expected = false,
            MoveDraft.anyMovedFromOrigin(punit(9, 99, 99) :: Nil, drafts))
}
