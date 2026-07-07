// Solver — パズルを 2 通りの独立な解き方で解く。
// ① solutions: 嘘つき集合の候補を総当たりし、Rules.consistent で残ったものを数える（正しさの正典）。
// ② probeDepth: 人間と同じ「仮に置いて矛盾したら逆」の深さで解けるかを測る（難易度の実測）。
// ①と②の答えが一致することをテストが機械証明する（独立実装どうしの相互 oracle）。
mod Solver {

    /// パズル 1 問。claims は正規化済み（Stmt.normalize 後）の発言列。
    pub type alias Puzzle = {
        npcCount = Int32,
        liarCount = Int32,
        claims = List[Rules.SaidClaim]
    }

    /// 確定済みの部分知識（probeDepth の作業メモ）。
    pub type alias Known = { honest = Set[Int32], liars = Set[Int32] }

    // ========================================================================
    // ① 総当たり（正しさの正典）
    // ========================================================================

    /// 全発言と矛盾しない嘘つき集合をすべて列挙する（人数は liarCount 固定）。
    /// 整合判定は Stmt.holds の直接評価（発言の真偽 = 話し手が正直か、の一致）。
    /// Datalog 側の意味論（Rules）とは独立の実装で、一致は solutionsDatalog 経由でテストが証明する。
    pub def solutions(puzzle: Puzzle): List[Set[Int32]] =
        subsetsOf(puzzle#liarCount, List.range(0, puzzle#npcCount))
            |> List.filter(liars -> puzzle#claims |> List.forAll(said -> {
                let (speaker, claim) = said;
                Stmt.holds(liars, claim) == (not Set.memberOf(speaker, liars))
            }))

    /// solutions と同じ列挙を Rules.consistent（Datalog）で行う版。テスト専用の oracle。
    pub def solutionsDatalog(puzzle: Puzzle): List[Set[Int32]] =
        subsetsOf(puzzle#liarCount, List.range(0, puzzle#npcCount))
            |> List.filter(liars -> {
                let honest = List.range(0, puzzle#npcCount)
                    |> List.filter(id -> not Set.memberOf(id, liars));
                Rules.consistent(honest, Set.toList(liars), puzzle#claims)
            })

    /// 解がちょうど 1 つのときだけ、その嘘つき集合を返す。
    pub def uniqueSolution(puzzle: Puzzle): Option[Set[Int32]] =
        match solutions(puzzle) {
            case one :: Nil => Some(one)
            case _          => None
        }

    /// 唯一解の正直者集合（uniqueSolution の補集合）。
    pub def honestOf(puzzle: Puzzle): Option[Set[Int32]] =
        uniqueSolution(puzzle) |> Option.map(liars ->
            List.range(0, puzzle#npcCount)
                |> List.filter(id -> not Set.memberOf(id, liars))
                |> List.toSet)

    /// ids から k 人を選ぶ組み合わせをすべて列挙する。
    def subsetsOf(k: Int32, ids: List[Int32]): List[Set[Int32]] =
        if (k == 0)
            Set.empty() :: Nil
        else
            match ids {
                case Nil       => Nil
                case id :: rest =>
                    let withId = subsetsOf(k - 1, rest) |> List.map(Set.insert(id));
                    List.append(withId, subsetsOf(k, rest))
            }

    // ========================================================================
    // ② 仮置きの深さ（難易度の実測）
    // ========================================================================

    /// このパズルが「仮置きの深さ d」で解けるかの最小 d（1 か 2）。
    /// 深さ 1 = 「x を仮に置いて伝播が矛盾したら逆で確定」の繰り返しで全員確定。
    /// 深さ 2 = その仮置きの中でさらにもう 1 段の仮置きが要る。
    /// None = 深さ 2 でも確定しない（そういうステージは出荷しない）。
    pub def probeDepth(puzzle: Puzzle): Option[Int32] =
        if (solvedAt(1, puzzle)) Some(1)
        else if (solvedAt(2, puzzle)) Some(2)
        else None

    /// probeDepth の経路で確定した嘘つき集合（oracle テスト用）。解けなければ None。
    pub def probeSolution(puzzle: Puzzle): Option[Set[Int32]] =
        probeDepth(puzzle)
            |> Option.flatMap(depth -> failedLiteralFix(depth, puzzle, emptyKnown()))
            |> Option.map(known -> known#liars)

    def emptyKnown(): Known = { honest = Set.empty(), liars = Set.empty() }

    def honestCount(puzzle: Puzzle): Int32 = puzzle#npcCount - puzzle#liarCount

    /// 全員の種別が確定したか。
    def determined(puzzle: Puzzle, known: Known): Bool =
        Set.size(known#honest) + Set.size(known#liars) == puzzle#npcCount

    /// まだどちらとも確定していない id の列。
    def undetermined(puzzle: Puzzle, known: Known): List[Int32] =
        List.range(0, puzzle#npcCount) |> List.filter(id ->
            not Set.memberOf(id, known#honest) and not Set.memberOf(id, known#liars))

    def addHonest(id: Int32, known: Known): Known =
        { honest = Set.insert(id, known#honest) | known }

    def addLiar(id: Int32, known: Known): Known =
        { liars = Set.insert(id, known#liars) | known }

    /// 深さ d で解けたか（failed-literal の不動点後に全員確定しているか）。
    def solvedAt(depth: Int32, puzzle: Puzzle): Bool =
        failedLiteralFix(depth, puzzle, emptyKnown())
            |> Option.map(known -> determined(puzzle, known))
            |> Option.getWithDefault(false)

    /// Datalog 伝播 + 人数勘定を不動点まで回す。矛盾（両側該当・人数超過）なら None。
    /// 人数勘定 = 嘘つきが定数ぶん揃ったら残り全員は正直者（逆も同じ）。
    def saturate(puzzle: Puzzle, known: Known): Option[Known] =
        let derived = Rules.propagate(known#honest, known#liars, puzzle#claims);
        if (derived#contra
            or Set.size(derived#liars) > puzzle#liarCount
            or Set.size(derived#honest) > honestCount(puzzle))
            None
        else {
            let rest = undetermined(puzzle, { honest = derived#honest, liars = derived#liars })
                |> List.toSet;
            let filled =
                if (Set.size(derived#liars) == puzzle#liarCount)
                    { honest = Set.union(derived#honest, rest), liars = derived#liars }
                else if (Set.size(derived#honest) == honestCount(puzzle))
                    { honest = derived#honest, liars = Set.union(derived#liars, rest) }
                else
                    { honest = derived#honest, liars = derived#liars };
            let grew = Set.size(filled#honest) + Set.size(filled#liars)
                > Set.size(known#honest) + Set.size(known#liars);
            if (grew) saturate(puzzle, filled) else Some(filled)
        }

    /// 部分知識が深さ d の目で見て破綻しているか。
    /// d = 0 は伝播（saturate）が矛盾するかだけ。d > 0 はさらに、ある未確定 x について
    /// 「正直と置いても嘘つきと置いても深さ d-1 で破綻する」なら破綻とみなす。
    def refuted(depth: Int32, puzzle: Puzzle, known: Known): Bool =
        match saturate(puzzle, known) {
            case None      => true
            case Some(sat) =>
                if (depth <= 0)
                    false
                else
                    undetermined(puzzle, sat) |> List.exists(id ->
                        refuted(depth - 1, puzzle, addHonest(id, sat))
                            and refuted(depth - 1, puzzle, addLiar(id, sat)))
        }

    /// failed-literal を不動点まで: 未確定 x の片側が深さ depth-1 で破綻するなら逆側で確定する。
    /// 1 掃引で見つかった確定を全部まとめて足してから伝播し直す（確定は知識が増えても
    /// 覆らないので一括で安全。1 件ずつやり直すより Datalog の呼び出しがずっと少ない）。
    /// 部分知識そのものが破綻していたら None。
    def failedLiteralFix(depth: Int32, puzzle: Puzzle, known: Known): Option[Known] =
        match saturate(puzzle, known) {
            case None      => None
            case Some(sat) => {
                let next = undetermined(puzzle, sat) |> List.foldLeft((acc, id) ->
                    if (refuted(depth - 1, puzzle, addHonest(id, sat)))
                        addLiar(id, acc)
                    else if (refuted(depth - 1, puzzle, addLiar(id, sat)))
                        addHonest(id, acc)
                    else
                        acc, sat);
                let grew = Set.size(next#honest) + Set.size(next#liars)
                    > Set.size(sat#honest) + Set.size(sat#liars);
                if (grew) failedLiteralFix(depth, puzzle, next) else Some(sat)
            }
        }
}
