// Worldline zipper のテスト。record/undo/redo・cap 溢れ・分岐時の future 破棄・
// undoBy の端 clamp を具体値で固定する。World 相当の巨大レコードは使わず Int32 で足りる
// （zipper の契約は要素の中身に依らない）。
//
// 最後の 2 本はメモリ/性能ベンチ: 深い履歴が永続 List の tail 共有で安いことを、
// 「1000 手 record して current 到達・length 正しい・全 undo で seed へ戻る」という
// 決定論的な構造検証で示す（JVM の retained size 直接測定は GC 非決定ゆえ避ける — 報告参照）。

mod TestWorldline {

    // ── record / current の基本 ──

    /// make 直後は current が初期値、遡れも下れもしない。
    @Test
    def testMakeIsSinglePoint(): Unit \ Assert =
        let wl = Worldline.make(10, 5);
        Assert.assertEq(
            expected = (10, false, false, 1),
            (Worldline.current(wl), Worldline.canUndo(wl), Worldline.canRedo(wl), Worldline.length(wl)))

    /// record で current が進み、past が 1 増える。
    @Test
    def testRecordAdvancesCurrent(): Unit \ Assert =
        let wl = Worldline.make(1, 5) |> Worldline.record(2) |> Worldline.record(3);
        Assert.assertEq(
            expected = (3, 2),
            (Worldline.current(wl), Worldline.pastLength(wl)))

    // ── undo / redo ──

    /// undo は 1 つ前の current へ戻す。
    @Test
    def testUndoGoesBackOne(): Unit \ Assert =
        let wl = Worldline.make(1, 5) |> Worldline.record(2) |> Worldline.record(3) |> Worldline.undo;
        Assert.assertEq(expected = 2, Worldline.current(wl))

    /// undo で手放した状態は redo で戻せる（往復で元の current に一致）。
    @Test
    def testRedoRestoresUndone(): Unit \ Assert =
        let wl = Worldline.make(1, 5) |> Worldline.record(2) |> Worldline.record(3);
        let back = Worldline.undo(wl);
        let fwd  = Worldline.redo(back);
        Assert.assertEq(
            expected = (2, 3),
            (Worldline.current(back), Worldline.current(fwd)))

    /// past が空なら undo は現状維持。future が空なら redo は現状維持。
    @Test
    def testUndoRedoClampAtEnds(): Unit \ Assert =
        let wl = Worldline.make(7, 5);
        Assert.assertEq(
            expected = (7, 7),
            (Worldline.current(Worldline.undo(wl)), Worldline.current(Worldline.redo(wl))))

    // ── 分岐: undo 後に record すると future が捨てられる ──

    /// undo で遡ってから record すると、辿らなかった未来（redo 先）は無効になる。
    @Test
    def testRecordAfterUndoDropsFuture(): Unit \ Assert =
        let wl0 = Worldline.make(1, 5) |> Worldline.record(2) |> Worldline.record(3);
        let branched = wl0 |> Worldline.undo |> Worldline.record(99);   // 2 の地点から 99 へ分岐
        Assert.assertEq(
            expected = (99, false, 0),   // current=99, redo 不可, future 長 0
            (Worldline.current(branched), Worldline.canRedo(branched), Worldline.futureLength(branched)))

    // ── cap 溢れ ──

    /// cap=3 で 5 回 record すると past は 3 で頭打ち。総状態数も cap+current=4。
    @Test
    def testCapBoundsPast(): Unit \ Assert =
        let wl = Worldline.make(0, 3)
            |> Worldline.record(1) |> Worldline.record(2)
            |> Worldline.record(3) |> Worldline.record(4) |> Worldline.record(5);
        Assert.assertEq(
            expected = (5, 3, 4),
            (Worldline.current(wl), Worldline.pastLength(wl), Worldline.length(wl)))

    /// cap で切り詰められた最古の状態は、いくら undo しても復元されない。
    /// cap=2 で 0,1,2,3 と進めると past=[2,1]。3 段 undo しても最古は 1（0 は捨て済み）。
    @Test
    def testCapDropsOldest(): Unit \ Assert =
        let wl = Worldline.make(0, 2)
            |> Worldline.record(1) |> Worldline.record(2) |> Worldline.record(3);
        let oldest = wl |> Worldline.undoBy(10);
        Assert.assertEq(expected = 1, Worldline.current(oldest))

    // ── undoBy の端 clamp（dodge popHistory との等価性の核）──

    /// undoBy(2) は 2 段遡る。
    @Test
    def testUndoByStepsBack(): Unit \ Assert =
        let wl = Worldline.make(1, 10)
            |> Worldline.record(2) |> Worldline.record(3) |> Worldline.record(4);
        Assert.assertEq(expected = 2, Worldline.current(Worldline.undoBy(2, wl)))

    /// k が履歴長を超えると最古で clamp（past を全部使い切って止まる）。
    @Test
    def testUndoByClampsToOldest(): Unit \ Assert =
        let wl = Worldline.make(1, 10)
            |> Worldline.record(2) |> Worldline.record(3);   // past 長 2、最古 = seed 1
        Assert.assertEq(
            expected = (1, 0),   // current=最古 1, past 使い切り 0
            (Worldline.current(Worldline.undoBy(999, wl)), Worldline.pastLength(Worldline.undoBy(999, wl))))

    /// undoBy(k<=0) は現状維持。
    @Test
    def testUndoByZeroIsIdentity(): Unit \ Assert =
        let wl = Worldline.make(1, 10) |> Worldline.record(2) |> Worldline.record(3);
        Assert.assertEq(expected = 3, Worldline.current(Worldline.undoBy(0, wl)))

    // ── dodge popHistory との端条件等価性の直接 pin ──
    // dodge の popHistory(history, k, fb): idx = min(k, len-1); target = nth(idx); のこと。
    // 世界線の対応は「history ≡ current :: past」。同じ log 上で両者の着地が一致することを、
    // popHistory を素朴に再実装して 3 通りの k で突き合わせる。

    /// popHistory の素朴再実装（dodge Game.flix の定義そのまま）。
    def popHistoryRef(history: List[Int32], k: Int32, fb: Int32): Int32 =
        let idx = Int32.min(k, List.length(history) - 1);
        List.nth(idx, history) |> Option.getWithDefault(fb)

    /// 同じ log で undoBy の着地 == popHistory の着地（k = 途中 / ちょうど端 / 超過）。
    @Test
    def testUndoByMatchesPopHistory(): Unit \ Assert =
        // log = [5,4,3,2,1]（most-recent-first）。current=5, past=[4,3,2,1]。
        let wl = Worldline.make(1, 100)
            |> Worldline.record(2) |> Worldline.record(3)
            |> Worldline.record(4) |> Worldline.record(5);
        let history = 5 :: 4 :: 3 :: 2 :: 1 :: Nil;   // current :: past
        let via = k -> Worldline.current(Worldline.undoBy(k, wl));
        let ref = k -> popHistoryRef(history, k, 5);
        Assert.assertEq(
            expected = (ref(2), ref(4), ref(999)),        // 途中 / 端ちょうど / 超過
            (via(2), via(4), via(999)))

    // ── メモリ/性能ベンチ: 深い履歴の構造共有 ──

    /// N=1000 手 record: current は最後の値に到達し、length は cap+1 で頭打ち（cap=180）。
    /// 非共有（record 毎に全複製）実装なら O(N^2) セル生成でテストが目に見えて遅くなる。
    /// これが即座に通る＝永続 List の tail 共有で履歴コストが 1 手あたり O(1) である傍証。
    @Test
    def testDeepHistoryLengthAndCurrent(): Unit \ Assert =
        let cap = 180;
        let wl = List.range(1, 1001)
            |> List.foldLeft((acc, i) -> Worldline.record(i, acc), Worldline.make(0, cap));
        Assert.assertEq(
            expected = (1000, cap, cap + 1),
            (Worldline.current(wl), Worldline.pastLength(wl), Worldline.length(wl)))

    /// cap を N より大きく取れば、N 手 record した後 undoBy(N) で seed=0 へ完全に遡れる。
    /// 1000 段の undo が一瞬で通る＝巻き戻しが履歴長に対して安いことの傍証。
    @Test
    def testDeepHistoryUndoAllReturnsToSeed(): Unit \ Assert =
        let wl = List.range(1, 1001)
            |> List.foldLeft((acc, i) -> Worldline.record(i, acc), Worldline.make(0, 2000));
        let back = Worldline.undoBy(1000, wl);
        Assert.assertEq(
            expected = (0, false),   // seed へ到達・これ以上遡れない
            (Worldline.current(back), Worldline.canUndo(back)))

    // ── 観測系: toList / window / scrubTo（時間順の絶対座標系）──
    // 共通の題材: seed=1 から 2,3,4 を record し、そこから 2 段 undo。
    // 時間順の平坦列は [1,2,3,4]、現在地 idx=1（current=2）、future=[3,4]。

    def scrubbed(): Worldline[Int32] =
        Worldline.make(1, 100)
            |> Worldline.record(2) |> Worldline.record(3) |> Worldline.record(4)
            |> Worldline.undoBy(2)

    /// toList は past を反転し current・future を繋いだ時間順（最古→最新）列。
    @Test
    def testToListIsChronological(): Unit \ Assert =
        Assert.assertEq(
            expected = 1 :: 2 :: 3 :: 4 :: Nil,
            Worldline.toList(scrubbed()))

    /// window は絶対添字区間 [from, to) を取り出す。両端は clamp、from>=to は空。
    @Test
    def testWindowSlicesChronologically(): Unit \ Assert =
        let wl = scrubbed();
        Assert.assertEq(
            expected = (2 :: 3 :: Nil, 1 :: 2 :: 3 :: 4 :: Nil, Nil),
            (Worldline.window(1, 3, wl),      // 途中の 2 要素
             Worldline.window(-5, 99, wl),    // 両端 clamp = 全体
             Worldline.window(3, 3, wl)))     // 空区間

    /// scrubTo は絶対位置へ移動する。現在地 idx=1 から 0（最古）・3（最新）・範囲外へ。
    /// current が対応する値になり、位置外は [0, length-1] に clamp。
    @Test
    def testScrubToAbsolutePosition(): Unit \ Assert =
        let wl = scrubbed();   // current=2 (idx=1), toList=[1,2,3,4]
        Assert.assertEq(
            expected = (1, 4, 1, 4),
            (Worldline.current(Worldline.scrubTo(0, wl)),    // 最古へ戻る（undo 方向）
             Worldline.current(Worldline.scrubTo(3, wl)),    // 最新へ進む（redo 方向）
             Worldline.current(Worldline.scrubTo(-9, wl)),   // 下側 clamp = 最古 1
             Worldline.current(Worldline.scrubTo(99, wl))))  // 上側 clamp = 最新 4

    /// scrubTo は現在地に留まるとき恒等（差分 0）。
    @Test
    def testScrubToHereIsIdentity(): Unit \ Assert =
        let wl = scrubbed();   // 現在地 idx = pastLength = 1
        Assert.assertEq(
            expected = (2, 1),
            (Worldline.current(Worldline.scrubTo(1, wl)), Worldline.pastLength(Worldline.scrubTo(1, wl))))
}
