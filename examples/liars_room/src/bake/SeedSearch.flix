// SeedSearch — 各ステージについて「一意解 + 狙った仮置きの深さ」に合格する seed を
// 小さい方から探す。実行: bin/flix run --entrypoint SeedSearch.search
// 出力の seed を Stage.seedOf に、liars をテスト（TestSolver）の pin 値に貼る。
mod SeedSearch {

    pub def search(): Unit \ IO =
        List.range(1, Stage.stageCount() + 1) |> List.forEach(n -> {
            let difficulty = Stage.difficultyOf(n);
            let (seed, generated) = searchFrom(1i64, difficulty);
            println("stage ${n}: seed = ${seed}i64, liars = ${generated#liars}, stmts = ${List.length(generated#stmts)}")
        })

    /// デバッグ用: 各ステージ、最初の数 seed の組み立て・検証結果を覗く。
    pub def probe(): Unit \ IO =
        List.range(1, Stage.stageCount() + 1) |> List.forEach(n -> {
            let d = Stage.difficultyOf(n);
            List.range(1, 4) |> List.forEach(i -> {
                let seed = Int32.toInt64(i);
                let built = Gen.tryBuild(seed, d);
                let stmts = built |> Option.map(g -> List.length(g#stmts));
                let liars = built |> Option.map(g -> g#liars);
                let puzzle = built |> Option.map(g -> Gen.puzzleOf(d, g));
                let unique = puzzle |> Option.flatMap(Solver.uniqueSolution);
                let depth = puzzle |> Option.flatMap(Solver.probeDepth);
                println("stage ${n} seed ${seed}: stmts=${stmts} liars=${liars} unique=${unique} depth=${depth}")
            })
        })

    /// validated が Some を返す最小の seed（1 から順に当たる）。
    def searchFrom(seed: Int64, difficulty: Gen.Difficulty): (Int64, Gen.Generated) \ IO =
        if (Int64.modulo(seed, 200i64) == 0i64)
            println("  ... seed ${seed} まで不合格")
        else
            ();
        match Gen.validated(seed, difficulty) {
            case Some(generated) => (seed, generated)
            case None            => searchFrom(seed + 1i64, difficulty)
        }
}
