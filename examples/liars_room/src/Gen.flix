// Gen — 難易度パラメータから発言セットを作る生成器（generate-and-test）。
// 割り当てを乱数で引き、各 NPC が自分の種別に整合する発言（正直者は真・嘘つきは偽）を作り、
// 「解が一意」かつ「狙った仮置きの深さで解ける」ものだけを合格にする。
// 同じ seed からは常に同じ問題が出る（決定論的）。
mod Gen {

    use Stmt.Claim

    /// 難易度パラメータ。use◯◯ = その発言タイプを使うか。
    /// doubleNegation = 発言の一部を「『…』というのは嘘だよ」の言い回しに包むか（意味は変えない）。
    /// extraStatements = 1 人 1 発言に加えて誰かが余分にしゃべる本数。
    /// requiredDepth = このステージが要求する仮置きの深さ（Solver.probeDepth と一致させる）。
    pub type alias Difficulty = {
        npcCount = Int32,
        liarCount = Int32,
        useAccuse = Bool,
        useVouch = Bool,
        useSame = Bool,
        useDiff = Bool,
        doubleNegation = Bool,
        extraStatements = Int32,
        requiredDepth = Int32
    }

    /// 生成結果。stmts = 表示用の発言（話し手 id つき・Not 込み）、liars = 唯一解の嘘つき集合。
    pub type alias Generated = {
        stmts = List[(Int32, Stmt.Stmt)],
        liars = Set[Int32]
    }

    /// seed から問題を 1 つ組み立てる（検証なし・決定論的・軽い）。ゲーム実行時はこちらを呼ぶ。
    /// seed は SeedSearch が「一意解 + 狙った深さ」に合格するものを選んで Stage に定数化してあり、
    /// 合格の検証そのものはテスト（TestSolver）が validated で毎回やり直す。
    pub def build(seed: Int64, difficulty: Difficulty): Generated =
        match tryBuild(seed, difficulty) {
            case Some(generated) => generated
            case None            => bug!("Gen.build: seed ${seed} から問題を組み立てられない（発言候補が尽きた）")
        }

    /// build の失敗（発言候補が尽きた）を Option で返す版。
    pub def tryBuild(seed: Int64, difficulty: Difficulty): Option[Generated] =
        let (candidate, _) = tryOnce(Prng.seed(seed), difficulty);
        candidate

    /// 組み立て + 検証: 一意解で、かつ仮置きの深さが狙いどおりのときだけ Some。
    /// SeedSearch の seed 探しと、テストの機械証明が使う（検証は Datalog を回すので重い）。
    pub def validated(seed: Int64, difficulty: Difficulty): Option[Generated] =
        tryBuild(seed, difficulty) |> Option.filter(generated -> passes(difficulty, generated))

    /// 生成した問題を Solver の形に直す（正規化はここで一括して行う）。
    pub def puzzleOf(difficulty: Difficulty, generated: Generated): Solver.Puzzle =
        { npcCount = difficulty#npcCount,
          liarCount = difficulty#liarCount,
          claims = generated#stmts |> List.map(said -> {
              let (speaker, stmt) = said;
              (speaker, Stmt.normalize(stmt))
          }) }

    // ========================================================================
    // 生成本体
    // ========================================================================

    /// 1 回の組み立て: 割り当てを引く → 全員の発言を作る → 表示形に包む。検証はしない。
    def tryOnce(rng0: Prng.State, difficulty: Difficulty): (Option[Generated], Prng.State) =
        let (liars, rng1) = drawLiars(difficulty, rng0);
        let (baseOpt, rng2) = baseStatements(difficulty, liars, rng1);
        match baseOpt {
            case None       => (None, rng2)
            case Some(base) => {
                let (extraOpt, rng3) = extraStatements(difficulty, liars, base, rng2);
                match extraOpt {
                    case None        => (None, rng3)
                    case Some(extra) => {
                        let (stmts, rng4) = wrapNegations(difficulty, List.append(base, extra), rng3);
                        (Some({ stmts = stmts, liars = liars }), rng4)
                    }
                }
            }
        }

    /// 嘘つきを人数ぶんランダムに選ぶ。
    def drawLiars(difficulty: Difficulty, rng0: Prng.State): (Set[Int32], Prng.State) =
        drawLiarsLoop(difficulty, Set.empty(), rng0)

    def drawLiarsLoop(difficulty: Difficulty, acc: Set[Int32], rng0: Prng.State): (Set[Int32], Prng.State) =
        if (Set.size(acc) >= difficulty#liarCount)
            (acc, rng0)
        else {
            let (id, rng1) = Prng.nextIntRange(lo = 0, hi = difficulty#npcCount, rng0);
            drawLiarsLoop(difficulty, Set.insert(id, acc), rng1)
        }

    /// 全員が 1 発言ずつ（自分の種別に整合する主張）。候補が尽きたら None（作り直し）。
    /// すでに出た主張は候補から外す — 同じセリフを言う人を 2 人出さない。
    def baseStatements(difficulty: Difficulty, liars: Set[Int32],
                       rng0: Prng.State): (Option[List[(Int32, Claim)]], Prng.State) =
        List.range(0, difficulty#npcCount) |> List.foldLeft((acc, speaker) -> {
            let (listOpt, rngA) = acc;
            match listOpt {
                case None       => (None, rngA)
                case Some(list) => {
                    let used = list |> List.map(snd) |> List.toSet;
                    let (claimOpt, rngB) = claimFor(difficulty, liars, speaker, used, rngA);
                    (claimOpt |> Option.map(claim -> List.append(list, (speaker, claim) :: Nil)), rngB)
                }
            }
        }, (Some(Nil), rng0))

    /// 余分な発言: 話し手をランダムに選んで同じ整合ルールで作る（重複禁止も同じ）。
    def extraStatements(difficulty: Difficulty, liars: Set[Int32], base: List[(Int32, Claim)],
                        rng0: Prng.State): (Option[List[(Int32, Claim)]], Prng.State) =
        List.range(0, difficulty#extraStatements) |> List.foldLeft((acc, _) -> {
            let (listOpt, rngA) = acc;
            match listOpt {
                case None       => (None, rngA)
                case Some(list) => {
                    let used = List.append(base, list) |> List.map(snd) |> List.toSet;
                    let (speaker, rngB) = Prng.nextIntRange(lo = 0, hi = difficulty#npcCount, rngA);
                    let (claimOpt, rngC) = claimFor(difficulty, liars, speaker, used, rngB);
                    (claimOpt |> Option.map(claim -> List.append(list, (speaker, claim) :: Nil)), rngC)
                }
            }
        }, (Some(Nil), rng0))

    /// 話し手の種別に整合する主張を 1 つ引く（正直者は真の主張・嘘つきは偽の主張）。
    /// used に入っている主張は選ばない。
    def claimFor(difficulty: Difficulty, liars: Set[Int32], speaker: Int32,
                 used: Set[Claim], rng0: Prng.State): (Option[Claim], Prng.State) =
        let wanted = not Set.memberOf(speaker, liars);
        let candidates = candidateClaims(difficulty, speaker)
            |> List.filter(claim -> Stmt.holds(liars, claim) == wanted
                and not Set.memberOf(claim, used));
        Prng.pick(candidates, rng0)

    /// 話し手が言い得る主張の全候補。自分への告発・擁護は無情報なので除く
    /// （同じ側・違う側は自分を含んでよい —「わたしと◯」の言い方になる）。
    def candidateClaims(difficulty: Difficulty, speaker: Int32): List[Claim] =
        let others = List.range(0, difficulty#npcCount) |> List.filter(t -> t != speaker);
        let pairs = List.range(0, difficulty#npcCount) |> List.flatMap(a ->
            List.range(a + 1, difficulty#npcCount) |> List.map(b -> (a, b)));
        let accuse = if (difficulty#useAccuse) others |> List.map(t -> Claim.IsLiar(t)) else Nil;
        let vouch = if (difficulty#useVouch) others |> List.map(t -> Claim.IsHonest(t)) else Nil;
        let same = if (difficulty#useSame)
            pairs |> List.map(p -> { let (a, b) = p; Claim.SameSide(a, b) }) else Nil;
        let diff = if (difficulty#useDiff)
            pairs |> List.map(p -> { let (a, b) = p; Claim.DiffSide(a, b) }) else Nil;
        accuse ::: vouch ::: same ::: diff

    /// 表示形を作る: doubleNegation のステージでは半々の確率で
    /// 「『（裏返した主張）』というのは嘘だよ」に包む（normalize すると元の主張に戻る）。
    def wrapNegations(difficulty: Difficulty, claims: List[(Int32, Claim)],
                      rng0: Prng.State): (List[(Int32, Stmt.Stmt)], Prng.State) =
        claims |> List.foldLeft((acc, said) -> {
            let (list, rngA) = acc;
            let (speaker, claim) = said;
            if (difficulty#doubleNegation) {
                let (wrap, rngB) = Prng.nextBool(rngA);
                let stmt = if (wrap)
                    Stmt.Stmt.Not(Stmt.Stmt.Say(Stmt.complement(claim)))
                else
                    Stmt.Stmt.Say(claim);
                (List.append(list, (speaker, stmt) :: Nil), rngB)
            } else
                (List.append(list, (speaker, Stmt.Stmt.Say(claim)) :: Nil), rngA)
        }, (Nil, rng0))

    /// 合格条件: 引いた割り当てが唯一解で、仮置きの深さが狙いどおり。
    def passes(difficulty: Difficulty, generated: Generated): Bool =
        let puzzle = puzzleOf(difficulty, generated);
        Solver.uniqueSolution(puzzle) == Some(generated#liars)
            and Solver.probeDepth(puzzle) == Some(difficulty#requiredDepth)
}
