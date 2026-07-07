// TestLiarsRoom — フェーズ機械とメモの挙動を具体値で固定する。
// ステージ 1（seed 固定・TestSolver が唯一解 Set#{1} を機械証明済み）を舞台に、
// Trace の入力列を tick に流して要点の状態を pin する。
//
//   小部屋のレイアウト（RoomMap.small）:
//     NPC0 = (1,1)  NPC1 = (7,1)  NPC2 = (1,5)  プレイヤー初期位置 = (4,3)
//   ステージ 1 の唯一解: 嘘つき = {1}、正直者 = {0, 2}
mod TestLiarsRoom {

    def state(w: Room.World): Room.State =
        let Room.World.World(s) = w;
        s

    /// ステージ 1 をシード 1 で直接開いた World（挙動テストの舞台を固定する —
    /// タイトル経由だと entropy のくじ引きでプールのどれが出るか揺れる）。
    def freshGame(): Room.World =
        Room.stageWorld(1, Map.empty(), 1i64)

    /// NPC id の目の前で発言を読み終えて確認メニューまで進めた World
    /// （話しかけ → 文字送りの早送り → 決定、の 3 タップ）。
    def atConfirm(id: Int32, w: Room.World): Room.World =
        w
            |> Trace.facingNpcBelow(id)
            |> Trace.step(Trace.talkTap())
            |> Trace.step(Trace.talkTap())
            |> Trace.step(Trace.talkTap())

    // ── タイトルと開始 ──

    @Test
    def testTitleEnterStartsStage1(): Unit \ Assert =
        // Enter でステージ 1 の探索が始まり、その遷移が BGM の火入れの合図になる。
        // 出題シードはステージ 1 のプールから選ばれている。
        let before = Room.titleWorld();
        let after = Trace.step(Trace.enterTap(), before);
        Assert.assertEq(expected = (Room.Phase.Exploring, 1, true, true),
            (state(after)#phase, state(after)#stage, LiarsRoom.bgmStarts(before, after),
             List.memberOf(state(after)#puzzleSeed, Stage.seedPool(1))))

    @Test
    def testRetryKeepsSeedAndNextStageRedraws(): Unit \ Assert =
        // 不正解のやり直しは同じシード（同じ発言）、正解後の次ステージはそのステージの
        // プールから引き直す。
        let wrong = freshGame()
            |> atConfirm(1) |> Trace.step(Trace.upOnce()) |> Trace.step(Trace.talkTap());
        let retried = wrong |> Trace.step(Trace.enterTap());
        let advanced = freshGame()
            |> atConfirm(0) |> Trace.step(Trace.upOnce()) |> Trace.step(Trace.talkTap())
            |> Trace.step(Trace.enterTap());
        Assert.assertEq(expected = (1i64, true),
            (state(retried)#puzzleSeed,
             List.memberOf(state(advanced)#puzzleSeed, Stage.seedPool(2))))

    @Test
    def testHintMarksOneLiarOncePerStage(): Unit \ Assert =
        // M でヒント: 嘘つき 1 人（ステージ 1 シード 1 では NPC1）にメモの「うそ」が付き、
        // メモが開いてカーソルが当たる。2 回目は何も増えない（1 ステージ 1 回だけ）。
        let hinted = freshGame() |> Trace.step(Trace.hintTap());
        let again = hinted
            |> Trace.step(Trace.memoTap())
            |> Trace.step(Trace.hintTap());
        Assert.assertEq(
            expected = (Some(Room.Mark.LiarMark), true, 1, true, 1),
            (Map.get(1, state(hinted)#memo), state(hinted)#memoOpen, state(hinted)#memoSel,
             state(again)#hintUsed, Map.size(state(again)#memo)))

    // ── 移動 ──

    @Test
    def testWalkHopsOneCellAndSlides(): Unit \ Assert =
        // 右を押すとセルは即座に変わり、絵のスライドが始まる。8 フレームで着地。
        let hopped = freshGame() |> Trace.step(Trace.rightHold());
        let landed = hopped |> Trace.stepN(8, Room.noKeys());
        Assert.assertEq(expected = ((5, 3), true, false),
            (state(hopped)#player,
             not Option.isEmpty(state(hopped)#slide),
             not Option.isEmpty(state(landed)#slide)))

    @Test
    def testWalkIntoWallOnlyTurns(): Unit \ Assert =
        // 壁に向かって歩くと向きだけ変わり、セルもスライドも生まれない。
        let blocked = freshGame()
            |> Trace.placePlayer((1, 2), Dir4.Down)
            |> Trace.step(Trace.leftHold());
        Assert.assertEq(expected = ((1, 2), Dir4.Left, true),
            (state(blocked)#player, state(blocked)#facing,
             Option.isEmpty(state(blocked)#slide)))

    @Test
    def testWalkIntoNpcIsBlocked(): Unit \ Assert =
        // NPC の立つセルへは入れない（向きだけ変わる）。NPC0 は (1,1)、プレイヤーはその下。
        let blocked = freshGame()
            |> Trace.facingNpcBelow(0)
            |> Trace.step(Trace.upOnce());
        Assert.assertEq(expected = ((1, 2), Dir4.Up),
            (state(blocked)#player, state(blocked)#facing))

    // ── 会話 ──

    @Test
    def testTalkOpensDialogAndNpcTurns(): Unit \ Assert =
        // 正面の NPC に Z → 会話が開き、相手を覚え、NPC がこちら（下）を向く。
        let talking = freshGame() |> Trace.facingNpcBelow(1) |> Trace.step(Trace.talkTap());
        let npc1Facing = state(talking)#npcs
            |> List.findLeft(npc -> npc#id == 1)
            |> Option.map(npc -> npc#facing);
        Assert.assertEq(
            expected = (Room.Phase.Talking, Some(1), true, Some(Dir4.Down)),
            (state(talking)#phase, state(talking)#talkingTo,
             UiDialog.isOpen(state(talking)#dialog), npc1Facing))

    @Test
    def testTalkAwayFromNpcDoesNothing(): Unit \ Assert =
        // 正面に誰も居なければ Z は空振り（探索のまま）。
        let idle = freshGame() |> Trace.step(Trace.talkTap());
        Assert.assertEq(expected = Room.Phase.Exploring, state(idle)#phase)

    @Test
    def testTalkFlowReachesConfirmWithSafeDefault(): Unit \ Assert =
        // 発言を読み終えて Z → 確認メニュー。カーソルは「やっぱりやめる」（誤爆防止の既定）。
        let confirm = freshGame() |> atConfirm(1);
        Assert.assertEq(expected = (Room.Phase.Confirming, 1),
            (state(confirm)#phase, state(confirm)#confirmSel))

    @Test
    def testCancelClosesDialog(): Unit \ Assert =
        // 会話中の X はウィンドウを閉じて探索に戻す。
        let closed = freshGame()
            |> Trace.facingNpcBelow(1)
            |> Trace.step(Trace.talkTap())
            |> Trace.step(Trace.cancelTap());
        Assert.assertEq(expected = (Room.Phase.Exploring, None, false),
            (state(closed)#phase, state(closed)#talkingTo, UiDialog.isOpen(state(closed)#dialog)))

    // ── 回答 ──

    @Test
    def testTrustingLiarIsWrongAndRetryKeepsMemo(): Unit \ Assert =
        // メモを 1 つ付けてから嘘つき（NPC1）を信じる → 不正解 → Enter で同じステージを
        // やり直し。発言は同一のまま、メモは残る。
        let marked = freshGame()
            |> Trace.step(Trace.memoTap())
            |> Trace.step(Trace.talkTap())
            |> Trace.step(Trace.memoTap());
        let wrong = marked
            |> atConfirm(1)
            |> Trace.step(Trace.upOnce())
            |> Trace.step(Trace.talkTap());
        let retried = wrong |> Trace.step(Trace.enterTap());
        Assert.assertEq(
            expected = (Room.Phase.Wrong, true,
                        Room.Phase.Exploring, 1,
                        Some(Room.Mark.LiarMark), state(marked)#stmts),
            (state(wrong)#phase, state(wrong)#shakeT > 0.0,
             state(retried)#phase, state(retried)#stage,
             Map.get(0, state(retried)#memo), state(retried)#stmts))

    @Test
    def testTrustingHonestClearsAndAdvances(): Unit \ Assert =
        // 正直者（NPC0）を信じる → 正解 → Enter で次のステージ、メモは白紙に戻る。
        let cleared = freshGame()
            |> Trace.step(Trace.memoTap())
            |> Trace.step(Trace.talkTap())
            |> Trace.step(Trace.memoTap())
            |> atConfirm(0)
            |> Trace.step(Trace.upOnce())
            |> Trace.step(Trace.talkTap());
        let advanced = cleared |> Trace.step(Trace.enterTap());
        Assert.assertEq(
            expected = (Room.Phase.Cleared, Room.Phase.Exploring, 2, Map.empty()),
            (state(cleared)#phase, state(advanced)#phase,
             state(advanced)#stage, state(advanced)#memo))

    @Test
    def testConfirmNoClosesDialog(): Unit \ Assert =
        // 「やっぱりやめる」で決定すると会話ごと閉じて探索に戻る（Z の往復で閉じられなくなるのを防ぐ）。
        let backed = freshGame() |> atConfirm(1) |> Trace.step(Trace.talkTap());
        Assert.assertEq(expected = (Room.Phase.Exploring, false),
            (state(backed)#phase, UiDialog.isOpen(state(backed)#dialog)))

    // ── メモ ──

    @Test
    def testMemoCycleAndNavigation(): Unit \ Assert =
        // C で開き、Z がマークを 未定 → 嘘つき → 本物 と巡回、下でカーソル移動、C で閉じる。
        let open = freshGame() |> Trace.step(Trace.memoTap());
        let cycled = open |> Trace.step(Trace.talkTap()) |> Trace.step(Trace.talkTap());
        let moved = cycled |> Trace.step(Trace.downOnce());
        let closed = moved |> Trace.step(Trace.memoTap());
        Assert.assertEq(
            expected = (true, Some(Room.Mark.HonestMark), 1, false),
            (state(open)#memoOpen, Map.get(0, state(cycled)#memo),
             state(moved)#memoSel, state(closed)#memoOpen))

    @Test
    def testDebugHoldFillsAllMemos(): Unit \ Assert =
        // デバッグ: D を 5 秒（dt=1/64 × 320 フレーム）押し続けると全メモが正解で埋まる。
        // 319 フレーム（5 秒未満）では何も書かれず、途中で離すと数え直しになる。
        let debugHold = ({ debug = true | Room.noKeys() });
        let almost = freshGame() |> Trace.stepN(319, debugHold);
        let filled = almost |> Trace.step(debugHold);
        let released = almost |> Trace.step(Room.noKeys());
        Assert.assertEq(
            expected = (Map.empty(),
                        Map#{0 => Room.Mark.HonestMark, 1 => Room.Mark.LiarMark, 2 => Room.Mark.HonestMark},
                        0.0),
            (state(almost)#memo, state(filled)#memo, state(released)#debugHold))

    // ── 音の投影 ──

    @Test
    def testSfxEventsPinned(): Unit \ Assert =
        // 会話開始 = 話し手の声（NPC1 は高い声）、不正解 = wrong、確定した 1 マス移動 = move。
        let base = freshGame();
        let talking = base |> Trace.facingNpcBelow(1) |> Trace.step(Trace.talkTap());
        let confirm = base |> atConfirm(1) |> Trace.step(Trace.upOnce());
        let wrong = confirm |> Trace.step(Trace.talkTap());
        let moved = base |> Trace.step(Trace.rightHold());
        Assert.assertEq(
            expected = (Some("talk_high"), Some("wrong"), Some("move")),
            (LiarsRoom.sfxEvent(base |> Trace.facingNpcBelow(1), talking),
             LiarsRoom.sfxEvent(confirm, wrong),
             LiarsRoom.sfxEvent(base, moved)))
}
