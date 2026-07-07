// TestSolver — 出題プール全体（実際に出題され得る全問題）の機械証明。
// ① 全 (ステージ, シード) が「一意解 + 狙った仮置きの深さで人間が必ず正答に辿り着ける」
// ② 総当たり（Stmt.holds の直接評価）と Datalog（Rules）が同じ答え・同じ解集合を出す
//    — 意味論の独立した 2 実装が互いの oracle になる
// ③ 生成は決定論的（やり直しで同じ問題が出ることの土台）
mod TestSolver {

    def stages(): List[Int32] = List.range(1, Stage.stageCount() + 1)

    /// (ステージ, シード) の全組み合わせ = 出題プール全体。
    def allDeals(): List[(Int32, Int64)] =
        stages() |> List.flatMap(n -> Stage.seedPool(n) |> List.map(seed -> (n, seed)))

    /// 各ステージのプール先頭シード（重い oracle 比較の代表値）。
    def poolHead(n: Int32): Int64 =
        match List.head(Stage.seedPool(n)) {
            case Some(seed) => seed
            case None       => bug!("TestSolver.poolHead: プールが空（ステージ ${n}）")
        }

    // ── ① 出題プール全体の証明 ──

    @Test
    def testEveryDealIsSolvableAsIntended(): Unit \ Assert =
        // プールの全シードについて「解が一意 + 狙った深さの仮置きで全員確定できる」を
        // Gen.validated（生成器と同じ検査 = 総当たりの一意性 + Datalog 伝播の深さ測定）で
        // やり直す。落ちた (ステージ, シード) は差分にそのまま並ぶ。
        let failing = allDeals() |> List.filter(deal -> {
            let (n, seed) = deal;
            Option.isEmpty(Gen.validated(seed, Stage.difficultyOf(n)))
        });
        Assert.assertEq(expected = (Nil: List[(Int32, Int64)]), failing)

    @Test
    def testStage1Seed1IsPinned(): Unit \ Assert =
        // 挙動テスト（TestLiarsRoom）が舞台にする (ステージ 1, シード 1) の唯一解を具体値で固定。
        Assert.assertEq(expected = Some(Set#{1}), Solver.uniqueSolution(Stage.puzzleWith(1, 1i64)))

    // ── ② 独立 2 実装の oracle 一致（各ステージの代表シード） ──

    @Test
    def testProbeSolutionMatchesBruteForce(): Unit \ Assert =
        // 仮置き経路（Datalog 伝播 + failed-literal）の答えが総当たりの唯一解と一致する。
        let probe = stages() |> List.map(n -> Solver.probeSolution(Stage.puzzleWith(n, poolHead(n))));
        let brute = stages() |> List.map(n -> Solver.uniqueSolution(Stage.puzzleWith(n, poolHead(n))));
        Assert.assertEq(expected = brute, probe)

    @Test
    def testFoldAndDatalogSolversAgree(): Unit \ Assert =
        // 解の集合そのものが一致する（唯一解の場面だけでなく列挙ごと比較）。
        let fold = stages() |> List.map(n -> Solver.solutions(Stage.puzzleWith(n, poolHead(n))));
        let datalog = stages() |> List.map(n -> Solver.solutionsDatalog(Stage.puzzleWith(n, poolHead(n))));
        Assert.assertEq(expected = fold, datalog)

    // ── ③ 決定論と体裁 ──

    @Test
    def testGenerationIsDeterministic(): Unit \ Assert =
        // 同じ (ステージ, シード) を 2 回組み立てると発言列まで同一（やり直しの決定論の土台）。
        let a = allDeals() |> List.map(deal -> { let (n, seed) = deal; Stage.generatedWith(n, seed)#stmts });
        let b = allDeals() |> List.map(deal -> { let (n, seed) = deal; Stage.generatedWith(n, seed)#stmts });
        Assert.assertEq(expected = a, b)

    @Test
    def testNoDuplicateStatements(): Unit \ Assert =
        // どの出題にも「同じセリフを言う人」は居ない（正規化後の主張が全発言で相異なる）。
        let duped = allDeals() |> List.filter(deal -> {
            let (n, seed) = deal;
            let claims = Stage.puzzleWith(n, seed)#claims |> List.map(snd);
            List.length(claims) != Set.size(List.toSet(claims))
        });
        Assert.assertEq(expected = (Nil: List[(Int32, Int64)]), duped)

    @Test
    def testEveryNpcSpeaksAtLeastOnce(): Unit \ Assert =
        // どの出題でも全員が最低 1 回しゃべる（黙っている NPC は推理の材料にならない）。
        let silent = allDeals() |> List.filter(deal -> {
            let (n, seed) = deal;
            let speakers = Stage.generatedWith(n, seed)#stmts |> List.map(fst) |> List.toSet;
            Set.size(speakers) < Stage.difficultyOf(n)#npcCount
        });
        Assert.assertEq(expected = (Nil: List[(Int32, Int64)]), silent)
}
