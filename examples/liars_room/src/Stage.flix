// Stage — 全 10 ステージの難易度カーブと生成シードの表。
// パズルの中身はここに書かない: (seed, 難易度) から Gen が決定論的に再構成する。
// seed は bake/SeedSearch で「唯一解 + 狙った深さ」に合格する値を探して定数化し、
// テスト（TestSolver）が嘘つき集合ごと固定する。
mod Stage {

    /// ステージ数（HUD の「ステージ n ／ 10」の分母）。
    pub def stageCount(): Int32 = 10

    /// 全ステージ共通の出発点（ステージ 1 の姿）。以降は差分だけ上書きする。
    def base(): Gen.Difficulty =
        { npcCount = 3, liarCount = 1,
          useAccuse = true, useVouch = false, useSame = false, useDiff = false,
          doubleNegation = false, extraStatements = 0, requiredDepth = 1 }

    /// ステージ n の難易度。人数・嘘つき数・発言タイプ・二重否定・冗長発言・深さが段階的に増える。
    pub def difficultyOf(n: Int32): Gen.Difficulty = match n {
        case 1  => base()
        case 2  => { useVouch = true                                                  | base() }
        case 3  => { npcCount = 4, useVouch = true, extraStatements = 1               | base() }
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

    /// ステージ n の生成シード（SeedSearch の出力を貼った定数。
    /// 一意解と狙った深さに合格することは TestSolver が機械証明する）。
    def seedOf(n: Int32): Int64 = match n {
        case 1  => 1i64
        case 2  => 1i64
        case 3  => 1i64
        case 4  => 1i64
        case 5  => 1i64
        case 6  => 1i64
        case 7  => 1i64
        case 8  => 1i64
        case 9  => 1i64
        case 10 => 78i64
        case _  => bug!("Stage.seedOf: ステージ ${n} は未定義")
    }

    /// ステージ n の問題（発言と唯一解）。同じ n からは常に同じ問題が出る。
    pub def generated(n: Int32): Gen.Generated =
        Gen.build(seedOf(n), difficultyOf(n))

    /// ステージ n を Solver の形で（テスト・ヒントが使う）。
    pub def puzzleOf(n: Int32): Solver.Puzzle =
        Gen.puzzleOf(difficultyOf(n), generated(n))
}
