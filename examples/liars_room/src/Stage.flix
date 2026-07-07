// Stage — 全 10 ステージの難易度カーブと生成シードの表。
// パズルの中身はここに書かない: (seed, 難易度) から Gen が決定論的に再構成する。
// seed は bake/SeedSearch で「唯一解 + 狙った深さ」に合格する値を探して定数化し、
// テスト（TestSolver）が嘘つき集合ごと固定する。
mod Stage {

    /// ステージ数（HUD の「ステージ n ／ 10」の分母）。
    pub def stageCount(): Int32 = 10

    /// 全ステージ共通の出発点（ステージ 1 の姿）。以降は差分だけ上書きする。
    /// 注意: 発言の重複禁止のため「告発のみ」は成り立たない（正直者が真実として言える告発は
    /// 嘘つきの人数ぶんしかなく、正直者どうしで候補が尽きる）。最初から擁護も混ぜる。
    def base(): Gen.Difficulty =
        { npcCount = 3, liarCount = 1,
          useAccuse = true, useVouch = true, useSame = false, useDiff = false,
          doubleNegation = false, extraStatements = 0, requiredDepth = 1 }

    /// ステージ n の難易度。人数・嘘つき数・発言タイプ・二重否定・冗長発言・深さが段階的に増える。
    pub def difficultyOf(n: Int32): Gen.Difficulty = match n {
        case 1  => base()
        case 2  => { npcCount = 4                                                     | base() }
        case 3  => { npcCount = 4, extraStatements = 1                                | base() }
        // 注意: 告発・擁護だけの構成では「嘘つきが人数のちょうど半分」は一意解にできない
        // （全員の種別を反転した割り当ても整合するため）。半々にするなら同類/別類を入れること。
        case 4  => { npcCount = 5, liarCount = 2, useVouch = true                     | base() }
        case 5  => { npcCount = 5, liarCount = 2, useVouch = true, useSame = true,
                     extraStatements = 1                                              | base() }
        case 6  => { npcCount = 5, liarCount = 2, useVouch = true, useSame = true,
                     useDiff = true, doubleNegation = true, extraStatements = 1       | base() }
        case 7  => { npcCount = 6, liarCount = 2, useVouch = true, useSame = true,
                     useDiff = true, doubleNegation = true, extraStatements = 1       | base() }
        case 8  => { npcCount = 6, liarCount = 3, useVouch = true, useSame = true,
                     useDiff = true, doubleNegation = true, extraStatements = 2       | base() }
        case 9  => { npcCount = 7, liarCount = 3, useVouch = true, useSame = true,
                     useDiff = true, doubleNegation = true, extraStatements = 2,
                     requiredDepth = 2                                                | base() }
        case 10 => { npcCount = 7, liarCount = 3, useVouch = true, useSame = true,
                     useDiff = true, doubleNegation = true, extraStatements = 3,
                     requiredDepth = 2                                                | base() }
        case _  => bug!("Stage.difficultyOf: ステージ ${n} は未定義")
    }

    /// 1 ステージあたりの出題プールの本数（SeedSearch が採掘し、TestSolver が全数証明する）。
    pub def poolSize(): Int32 = 6

    /// ステージ n の出題プール（SeedSearch の出力を貼った定数）。プールのどのシードも
    /// 「一意解 + 狙った仮置きの深さ」に合格することを TestSolver が機械証明する。
    pub def seedPool(n: Int32): List[Int64] = match n {
        case 1  => 1i64 :: 2i64 :: 3i64 :: 4i64 :: 5i64 :: 6i64 :: Nil
        case 2  => 1i64 :: 2i64 :: 3i64 :: 4i64 :: 5i64 :: 6i64 :: Nil
        case 3  => 1i64 :: 3i64 :: 5i64 :: 7i64 :: 8i64 :: 9i64 :: Nil
        case 4  => 1i64 :: 2i64 :: 4i64 :: 6i64 :: 7i64 :: 8i64 :: Nil
        case 5  => 1i64 :: 2i64 :: 3i64 :: 4i64 :: 5i64 :: 6i64 :: Nil
        case 6  => 1i64 :: 2i64 :: 3i64 :: 4i64 :: 5i64 :: 6i64 :: Nil
        case 7  => 1i64 :: 2i64 :: 3i64 :: 4i64 :: 5i64 :: 6i64 :: Nil
        case 8  => 1i64 :: 2i64 :: 3i64 :: 5i64 :: 6i64 :: 7i64 :: Nil
        case 9  => 22i64 :: 28i64 :: 29i64 :: 70i64 :: 75i64 :: 85i64 :: Nil
        case 10 => 125i64 :: 144i64 :: 147i64 :: 171i64 :: 172i64 :: 190i64 :: Nil
        case _  => bug!("Stage.seedPool: ステージ ${n} は未定義")
    }

    /// プールから 1 本選ぶ。pick はタイトルからの経過フレーム数などの任意の整数 —
    /// 実時間で変わるので毎回違う問題が出るが、選んだ後の再構成は決定論的。
    pub def pickSeed(n: Int32, pick: Int32): Int64 =
        let pool = seedPool(n);
        let index = Int32.modulo(pick, List.length(pool));
        match List.nth(index, pool) {
            case Some(seed) => seed
            case None       => bug!("Stage.pickSeed: プールが空（ステージ ${n}）")
        }

    /// ステージ n をシード指定で生成する。同じ (n, seed) からは常に同じ問題が出る。
    /// 実行時は検証なしの build（軽い）。合格の機械証明はテスト側（Gen.validated）。
    pub def generatedWith(n: Int32, seed: Int64): Gen.Generated =
        Gen.build(seed, difficultyOf(n))

    /// (n, seed) を Solver の形で（テスト・ヒントが使う）。
    pub def puzzleWith(n: Int32, seed: Int64): Solver.Puzzle =
        Gen.puzzleOf(difficultyOf(n), generatedWith(n, seed))
}
