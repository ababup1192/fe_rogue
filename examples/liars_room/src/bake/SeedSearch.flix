// SeedSearch — 各ステージについて「一意解 + 狙った仮置きの深さ」に合格する seed を
// 小さい方から探す。実行: bin/flix run --entrypoint SeedSearch.search
// 出力の seed を Stage.seedOf に、liars をテスト（TestSolver）の pin 値に貼る。
mod SeedSearch {

    pub def search(): Unit \ IO =
        List.range(1, Stage.stageCount() + 1) |> List.forEach(n -> {
            let difficulty = Stage.difficultyOf(n);
            let pool = searchPool(1i64, difficulty, Stage.poolSize(), Nil);
            let literals = pool |> List.map(seed -> "${seed}i64") |> List.intersperse(" :: ")
                |> List.foldLeft(String.concat, "");
            println("stage ${n}: ${literals} :: Nil")
        })

    /// 合格 seed を count 本集める（1 から昇順に当たる）。
    def searchPool(seed: Int64, difficulty: Gen.Difficulty, count: Int32,
                   acc: List[Int64]): List[Int64] \ IO =
        if (List.length(acc) >= count)
            List.reverse(acc)
        else
            match Gen.validated(seed, difficulty) {
                case Some(_) => searchPool(seed + 1i64, difficulty, count, seed :: acc)
                case None    => searchPool(seed + 1i64, difficulty, count, acc)
            }

    /// デバッグ用: 各ステージのプール先頭 seed の出題を文章で表示する
    /// （バランス調整・攻略解説・レビュー用の資料）。
    pub def reveal(): Unit \ IO =
        List.range(1, Stage.stageCount() + 1) |> List.forEach(n -> {
            let seed = match List.head(Stage.seedPool(n)) {
                case Some(s) => s
                case None    => bug!("SeedSearch.reveal: プールが空")
            };
            let generated = Stage.generatedWith(n, seed);
            println("── ステージ ${n}（seed ${seed}） 嘘つき = ${generated#liars} ──");
            generated#stmts |> List.forEach(said -> {
                let (speaker, stmt) = said;
                let line = Stmt.speech(speaker = speaker, suffix = LiarsRoom.suffixOf(speaker),
                                       stmt :: Nil) |> Stmt.segText(Palette.nameOf);
                println("  ${Palette.nameOf(speaker)}: ${line}")
            })
        })

    /// デバッグ用: 定数化済みプールの各 seed の唯一解と発言数を覗く
    /// （テストの舞台に使う seed を選ぶときの資料）。
    pub def probe(): Unit \ IO =
        List.range(1, Stage.stageCount() + 1) |> List.forEach(n -> {
            Stage.seedPool(n) |> List.forEach(seed -> {
                let generated = Stage.generatedWith(n, seed);
                println("stage ${n} seed ${seed}: liars=${generated#liars} stmts=${List.length(generated#stmts)}")
            })
        })

}
