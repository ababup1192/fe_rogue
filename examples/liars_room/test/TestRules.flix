// TestRules — 発言の意味論（正規化・伝播・矛盾検出・文言）を具体値で固定する。
// ルールは Rules.flix にしか書かれていないので、ここが意味論の回帰の砦になる。
mod TestRules {

    use Stmt.Claim
    use Stmt.Stmt

    // ── normalize: 否定の偶奇潰し ──

    @Test
    def testNormalizeFoldsNegationParity(): Unit \ Assert =
        // 二重否定は消え、一重否定は主張の裏返しになる（同類⇔別類も対）。
        Assert.assertEq(
            expected = (Claim.IsLiar(2), Claim.IsHonest(2), Claim.DiffSide(0, 1)),
            (Stmt.normalize(Stmt.Not(Stmt.Not(Stmt.Say(Claim.IsLiar(2))))),
             Stmt.normalize(Stmt.Not(Stmt.Say(Claim.IsLiar(2)))),
             Stmt.normalize(Stmt.Not(Stmt.Say(Claim.SameSide(0, 1))))))

    // ── propagate: 部分知識からの導出 ──

    @Test
    def testPropagateAccuseFromHonest(): Unit \ Assert =
        // 0 が正直と分かっていて、0 が「1 は嘘つき」→ 1 は嘘つきと導ける。
        let derived = Rules.propagate(Set#{0}, Set.empty(), (0, Claim.IsLiar(1)) :: Nil);
        Assert.assertEq(expected = (Set#{0}, Set#{1}, false),
            (derived#honest, derived#liars, derived#contra))

    @Test
    def testPropagateSameSideCarriesKind(): Unit \ Assert =
        // 正直な 0 が「1 と 2 は同じ側」、1 が嘘つきと分かっている → 2 も嘘つき。
        let derived = Rules.propagate(Set#{0}, Set#{1}, (0, Claim.SameSide(1, 2)) :: Nil);
        Assert.assertEq(expected = (Set#{0}, Set#{1, 2}, false),
            (derived#honest, derived#liars, derived#contra))

    @Test
    def testPropagateDiffTwiceIsSame(): Unit \ Assert =
        // 正直な 0 が「1 と 2 は違う側」「2 と 3 は違う側」、1 が嘘つき
        // → 2 は正直（1 の逆）、3 は嘘つき（違う×違う = 同じ側で 1 と同類）。
        let claims = (0, Claim.DiffSide(1, 2)) :: (0, Claim.DiffSide(2, 3)) :: Nil;
        let derived = Rules.propagate(Set#{0}, Set#{1}, claims);
        Assert.assertEq(expected = (Set#{0, 2}, Set#{1, 3}, false),
            (derived#honest, derived#liars, derived#contra))

    @Test
    def testPropagateDetectsContradiction(): Unit \ Assert =
        // 正直と分かっている 0 が「わたしは嘘つき」と言うと矛盾が立つ。
        let derived = Rules.propagate(Set#{0}, Set.empty(), (0, Claim.IsLiar(0)) :: Nil);
        Assert.assertEq(expected = true, derived#contra)

    // ── consistent: 完全割り当ての判定 ──

    @Test
    def testConsistentAcceptsAndRejects(): Unit \ Assert =
        // 「0 が 1 を告発」: 0 正直・1 嘘つきは無矛盾、0 も 1 も正直は矛盾。
        let claims = (0, Claim.IsLiar(1)) :: Nil;
        Assert.assertEq(expected = (true, false),
            (Rules.consistent(0 :: Nil, 1 :: Nil, claims),
             Rules.consistent(0 :: 1 :: Nil, Nil, claims)))

    // ── Solver: 手組みの 3 人パズルで総当たりと仮置き経路の一致 ──

    @Test
    def testSolverThreePeopleClassic(): Unit \ Assert =
        // 3 人・嘘つき 1 人。「あお(0): みどり(1)は嘘つき」「みどり(1): あか(2)は嘘つき」
        //   嘘つき={1} だけが無矛盾（0 の告発は真、1 の告発は嘘で 2 は正直）。
        let puzzle = { npcCount = 3, liarCount = 1,
                       claims = (0, Claim.IsLiar(1)) :: (1, Claim.IsLiar(2)) :: Nil };
        Assert.assertEq(
            expected = (Some(Set#{1}), Some(1), Some(Set#{1}), Some(Set#{0, 2})),
            (Solver.uniqueSolution(puzzle), Solver.probeDepth(puzzle),
             Solver.probeSolution(puzzle), Solver.honestOf(puzzle)))

    @Test
    def testSolverRejectsAmbiguousPuzzle(): Unit \ Assert =
        // 発言が 1 本だけだと解が複数残り、uniqueSolution は None。
        // 「0 が 1 を告発」(3 人・嘘 1): 嘘つき={1}（0 正直・真）も {0}（0 嘘・1 正直）も無矛盾。
        let puzzle = { npcCount = 3, liarCount = 1, claims = (0, Claim.IsLiar(1)) :: Nil };
        Assert.assertEq(expected = (2, None),
            (List.length(Solver.solutions(puzzle)), Solver.uniqueSolution(puzzle)))

    // ── reachable: 部屋の到達性 ──

    @Test
    def testReachableWalksFloorsOnly(): Unit \ Assert =
        // L 字の床 3 マスはすべて届き、飛び地 (5,5) には届かない。
        let floors = Set#{(0, 0), (1, 0), (0, 1), (5, 5)};
        Assert.assertEq(expected = Set#{(0, 0), (1, 0), (0, 1)},
            Rules.reachable((0, 0), floors))

    // ── Stmt.text: 発言の日本語文言 ──

    @Test
    def testStmtSpeechPinsPhrases(): Unit \ Assert =
        // 発言 1 文の文言を素の文章で固定する: 告発 / 複数主張の「で、」結合 / 二重否定 /
        // 「わたしと」の言い方、そして話し手ごとの語尾（だよ/だね！/だぞ）。
        let say = stmts -> speakerId -> Stmt.speech(
            speaker = speakerId, suffix = LiarsRoom.suffixOf(speakerId), stmts)
            |> Stmt.segText(Palette.nameOf);
        Assert.assertEq(
            expected = ("みどりは嘘つきだよ",
                        "みどりは嘘つきで、あかは正直者だよ",
                        "『あおは正直者』というのは嘘だね！",
                        "わたしとあおは同じ側だぞ"),
            (say(Stmt.Say(Claim.IsLiar(1)) :: Nil)(0),
             say(Stmt.Say(Claim.IsLiar(1)) :: Stmt.Say(Claim.IsHonest(2)) :: Nil)(0),
             say(Stmt.Not(Stmt.Say(Claim.IsHonest(0))) :: Nil)(1),
             say(Stmt.Say(Claim.SameSide(2, 0)) :: Nil)(2)))
}
