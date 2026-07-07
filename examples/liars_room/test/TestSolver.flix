// TestSolver — 全 10 ステージの機械証明。
// ① 各ステージが一意解を持ち、嘘つき集合が pin した具体値と一致する
// ② 総当たり（Stmt.holds の直接評価）と Datalog（Rules.consistent）が同じ解集合を出す
//    — 意味論の独立した 2 実装が互いの oracle になる
// ③ 仮置きの深さ（probeDepth）が難易度カーブどおりに並ぶ
// ④ 生成は決定論的（同じ seed → 同じ問題）
mod TestSolver {

    /// pin: 各ステージの唯一解（SeedSearch の出力を貼った具体値）。
    def pinnedLiars(n: Int32): Set[Int32] = match n {
        case 1  => Set#{1}
        case 2  => Set#{1}
        case 3  => Set#{2}
        case 4  => Set#{2, 3}
        case 5  => Set#{2, 3}
        case 6  => Set#{2, 3}
        case 7  => Set#{3, 4}
        case 8  => Set#{3, 4, 5}
        case 9  => Set#{3, 5, 6}
        case 10 => Set#{0, 2, 4}
        case _  => bug!("TestSolver.pinnedLiars: ステージ ${n} は未定義")
    }

    def stages(): List[Int32] = List.range(1, Stage.stageCount() + 1)

    // ── ① 一意解と pin の一致 ──

    @Test
    def testAllStagesHavePinnedUniqueSolution(): Unit \ Assert =
        // uniqueSolution（総当たり）と生成器の答え（generated#liars）と pin の三者一致。
        let got = stages() |> List.map(n -> Solver.uniqueSolution(Stage.puzzleOf(n)));
        let fromGen = stages() |> List.map(n -> Some(Stage.generated(n)#liars));
        let expected = stages() |> List.map(n -> Some(pinnedLiars(n)));
        Assert.assertEq(expected = (expected, expected), (got, fromGen))

    // ── ② 総当たり（直接評価）と Datalog の解集合一致（oracle） ──

    @Test
    def testFoldAndDatalogSolversAgree(): Unit \ Assert =
        // 解の集合そのものが全ステージで一致する（唯一解の場面だけでなく列挙ごと比較）。
        let fold = stages() |> List.map(n -> Solver.solutions(Stage.puzzleOf(n)));
        let datalog = stages() |> List.map(n -> Solver.solutionsDatalog(Stage.puzzleOf(n)));
        Assert.assertEq(expected = fold, datalog)

    // ── ③ 難易度カーブ ──

    @Test
    def testDifficultyCurveIsPinned(): Unit \ Assert =
        // 仮置きの深さ: ステージ 1〜8 は深さ 1、9〜10 は深さ 2。
        let got = stages() |> List.map(n -> Solver.probeDepth(Stage.puzzleOf(n)));
        let expected =
            Some(1) :: Some(1) :: Some(1) :: Some(1) :: Some(1) ::
            Some(1) :: Some(1) :: Some(1) :: Some(2) :: Some(2) :: Nil;
        Assert.assertEq(expected = expected, got)

    @Test
    def testProbeSolutionMatchesBruteForce(): Unit \ Assert =
        // 仮置き経路（Datalog 伝播 + failed-literal）の答えが総当たりの唯一解と一致する。
        let probe = stages() |> List.map(n -> Solver.probeSolution(Stage.puzzleOf(n)));
        let expected = stages() |> List.map(n -> Some(pinnedLiars(n)));
        Assert.assertEq(expected = expected, probe)

    // ── ④ 決定論と規模 ──

    @Test
    def testGenerationIsDeterministic(): Unit \ Assert =
        // 同じステージを 2 回組み立てると発言列まで同一（リトライの決定論の土台）。
        let a = stages() |> List.map(n -> Stage.generated(n)#stmts);
        let b = stages() |> List.map(n -> Stage.generated(n)#stmts);
        Assert.assertEq(expected = a, b)

    @Test
    def testEveryNpcSpeaksAtLeastOnce(): Unit \ Assert =
        // どのステージでも全員が最低 1 回しゃべる（黙っている NPC は推理の材料にならない）。
        let silentCounts = stages() |> List.map(n -> {
            let d = Stage.difficultyOf(n);
            let speakers = Stage.generated(n)#stmts |> List.map(fst) |> List.toSet;
            d#npcCount - Set.size(speakers)
        });
        Assert.assertEq(expected = List.map(_ -> 0, stages()), silentCounts)
}
