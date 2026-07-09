/// MoveRangeScene の移動範囲が **ターン開始位置（origin）に固定**されることを検証する。
///
/// 無限移動バグの回帰テスト: ユニットを動かしてからメニューをキャンセルすると
/// `refresh`（= clear + add + buildFor）が走るが、範囲は現在位置でなく `MovedFrom`
/// ドラフトの開始位置を原点に再構築されなければならない（現在位置基準だと無限移動になる）。
///
/// - 結線テスト(A): World に floor 盤面 + 移動後の主人公 + MovedFrom ドラフトを仕込んで `refresh`
///   を実行し、`isInRange` が origin 基準か（current 基準でないか）を区別できるセルで pin する。
/// - 純粋テスト(B): origin 選択ロジック `chooseMoveOrigin` の分岐。`originOf` 自体は
///   `TestMoveDraft` で網羅済みなので、ここは「移動後でも MovedFrom を返す」核と fallback だけ。
mod TestMoveRangeScene {

    // ════════════════════════════════════════════════════════
    // ヘルパー
    // ════════════════════════════════════════════════════════

    def cell(x: Int32, y: Int32): {x = Int32, y = Int32} = {x = x, y = y}
    def cellT(c: {x = Int32, y = Int32}): (Int32, Int32) = (c#x, c#y)

    /// 壁なし 13×13 床の盤面 + 主人公(id=0, `curPos`) を仕込んだ World。
    /// `curPos` は「移動後の現在位置」を表す。moveTiles=4 の素直な spec を使う（unitSpec 既定＝Fs 不要）。
    def worldWithPlayerAt(curPos: {x = Int32, y = Int32}): World =
        TestWorldFixtures.worldOf(List.flatten(
            TestWorldFixtures.boardCmds({w = 13, h = 13}, None)
                :: TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, curPos))
                :: Nil))

    // ════════════════════════════════════════════════════════
    // (A) 結線テスト — refresh は origin 基準で範囲を組む（無限移動の回帰ピン）
    // ════════════════════════════════════════════════════════

    /// origin O=(5,5)・移動後 current C=(7,5)（moveTiles=4 の範囲内＝現実的な移動後）で
    /// `refresh` すると、範囲は **O 基準**になる:
    ///   - (1,5): O から距離4＝範囲内 / C から距離6＝範囲外 → true
    ///   - (11,5): O から距離6＝範囲外 / C から距離4＝範囲内 → false
    /// current 基準（修正前）なら (false, true) になり、このテストは失敗する。
    @Test
    def testRefreshAnchorsRangeToOriginNotCurrentPos(): Unit \ Assert =
        region rc {
            let world = worldWithPlayerAt(cell(7, 5));
            let sel = ({id = Some(0),
                        drafts = MoveDraft.DraftAction.MovedFrom(0, cell(5, 5)) :: Nil,
                        gatherActive = false}: SelectedPlayer.Selection);
            TestUnitFixtures.withRangeOverlay(rc, () ->
            TestUnitFixtures.withSelectionRef(rc, sel, () ->
            TestUnitFixtures.withWorldQuery(world, () -> {
                MoveRangeScene.refresh();
                Assert.assertEq(
                    expected = (true, false),
                    (MoveRangeScene.isInRange(cell(1, 5)),
                     MoveRangeScene.isInRange(cell(11, 5))))
            })))
        }

    // ════════════════════════════════════════════════════════
    // (B) 純粋 — chooseMoveOrigin の origin 選択
    // ════════════════════════════════════════════════════════

    /// MovedFrom があれば、現在位置(9,9)と違っても開始位置(3,4)を返す（移動後もターン頭に固定）。
    @Test
    def testChooseOriginUsesMovedFromWhenPresent(): Unit \ Assert =
        let drafts = MoveDraft.DraftAction.MovedFrom(2, cell(3, 4)) :: Nil;
        Assert.assertEq(expected = (3, 4),
            cellT(MoveRangeScene.chooseMoveOrigin(2, cell(9, 9), drafts)))

    /// id の MovedFrom が無ければ現在位置を使う（初回構築・選択前のフォールバック）。
    @Test
    def testChooseOriginFallsBackToCurrentWhenNoDraft(): Unit \ Assert =
        let drafts: List[MoveDraft.DraftAction] = Nil;
        Assert.assertEq(expected = (9, 9),
            cellT(MoveRangeScene.chooseMoveOrigin(2, cell(9, 9), drafts)))
}
