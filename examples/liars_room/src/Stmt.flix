// Stmt — NPC の発言。表示用の形（二重否定を残す）と、推論に使う正規形（Claim）を分ける。
// 意味論に入る前に必ず normalize を通すので、Rules の Datalog には否定が一切現れない。
mod Stmt {

    /// 表示用の発言。Not は「『…』というのは嘘だよ」という言い回しのためだけに残す。
    /// （モジュール同名の companion なので先頭に置く。）
    pub enum Stmt with Eq, ToString {
        case Say(Claim)
        case Not(Stmt)
    }

    /// 正規化済みの主張。二重否定はここには現れない。
    pub enum Claim with Eq, Order, ToString {
        /// 「◯は嘘つきだ」
        case IsLiar(Int32)
        /// 「◯は正直者だ」
        case IsHonest(Int32)
        /// 「◯と◯は同じ側（両方正直 or 両方嘘つき）だ」
        case SameSide(Int32, Int32)
        /// 「◯と◯は違う側だ」
        case DiffSide(Int32, Int32)
    }

    /// 主張の裏返し（嘘つきが言うと結果的にこちらが真になる）。
    pub def complement(claim: Claim): Claim = match claim {
        case Claim.IsLiar(t)      => Claim.IsHonest(t)
        case Claim.IsHonest(t)    => Claim.IsLiar(t)
        case Claim.SameSide(a, b) => Claim.DiffSide(a, b)
        case Claim.DiffSide(a, b) => Claim.SameSide(a, b)
    }

    /// 否定を偶奇で畳んで正規形にする。Not(Not(x)) = x、Not(Say(c)) = complement(c)。
    pub def normalize(stmt: Stmt): Claim = match stmt {
        case Stmt.Say(claim) => claim
        case Stmt.Not(inner) => complement(normalize(inner))
    }

    /// 嘘つき集合を決めたときの主張の真偽（Datalog を使わない直接の意味論）。
    /// 生成器と総当たりソルバーが使い、Rules（Datalog 側の意味論）との一致を
    /// テストが機械証明する — 独立した 2 実装が互いの oracle になる。
    pub def holds(liars: Set[Int32], claim: Claim): Bool = match claim {
        case Claim.IsLiar(t)      => Set.memberOf(t, liars)
        case Claim.IsHonest(t)    => not Set.memberOf(t, liars)
        case Claim.SameSide(a, b) => Set.memberOf(a, liars) == Set.memberOf(b, liars)
        case Claim.DiffSide(a, b) => Set.memberOf(a, liars) != Set.memberOf(b, liars)
    }

    /// 発言の見た目の部品。文章は部品の列で持ち、描画側が Name を色付き・Strong を太字で描く。
    pub enum Seg with Eq, ToString {
        /// 素の字（「は」「で、」「』というのは嘘」など）。
        case Plain(String)
        /// NPC の呼び名（その NPC の色で描く）。
        case Name(Int32)
        /// 強調語（太字で描く。「嘘つき」「正直者」）。
        case Strong(String)
    }

    /// 1 人の発言ぜんぶを 1 つの文にした部品列。複数の主張は「で、」で繋ぎ、語尾は 1 回だけ。
    /// 例: (あお)は(嘘つき)で、(あか)は(正直者)だよ
    pub def speech(speaker: {speaker = Int32}, suffix: {suffix = String},
                   stmts: List[Stmt]): List[Seg] =
        let phrases = stmts |> List.map(stmt -> phraseSegs(speaker#speaker, stmt));
        let joined = phrases |> List.intersperse(Seg.Plain("で、") :: Nil) |> List.flatten;
        List.append(joined, Seg.Plain(suffix#suffix) :: Nil)

    /// 部品列の素の文章（テストの pin・幅の見積もりに使う）。nameOf は NPC id → 呼び名。
    pub def segText(nameOf: Int32 -> String, segs: List[Seg]): String =
        segs |> List.map(seg -> match seg {
            case Seg.Plain(text)  => text
            case Seg.Name(id)     => nameOf(id)
            case Seg.Strong(text) => text
        }) |> List.foldLeft(String.concat, "")

    /// 語尾を付ける前の 1 主張ぶんの部品列。Not は再帰的に 『…』というのは嘘 で包む。
    def phraseSegs(speaker: Int32, stmt: Stmt): List[Seg] = match stmt {
        case Stmt.Say(claim) => claimSegs(speaker, claim)
        case Stmt.Not(inner) => List.flatten(
            (Seg.Plain("『") :: Nil) ::
            phraseSegs(speaker, inner) ::
            (Seg.Plain("』というのは嘘") :: Nil) :: Nil)
    }

    /// 主張 1 件の部品列。話し手自身が対象に含まれるときは「わたし」と言う。
    def claimSegs(speaker: Int32, claim: Claim): List[Seg] = match claim {
        case Claim.IsLiar(t)      => List.append(subject(speaker, t),
            Seg.Plain("は") :: Seg.Strong("嘘つき") :: Nil)
        case Claim.IsHonest(t)    => List.append(subject(speaker, t),
            Seg.Plain("は") :: Seg.Strong("正直者") :: Nil)
        case Claim.SameSide(a, b) => List.append(pairSubject(speaker, a, b),
            Seg.Plain("は同じ側") :: Nil)
        case Claim.DiffSide(a, b) => List.append(pairSubject(speaker, a, b),
            Seg.Plain("は違う側") :: Nil)
    }

    def subject(speaker: Int32, target: Int32): List[Seg] =
        if (target == speaker) Seg.Plain("わたし") :: Nil else Seg.Name(target) :: Nil

    def pairSubject(speaker: Int32, a: Int32, b: Int32): List[Seg] =
        if (a == speaker)      Seg.Plain("わたしと") :: Seg.Name(b) :: Nil
        else if (b == speaker) Seg.Plain("わたしと") :: Seg.Name(a) :: Nil
        else                   Seg.Name(a) :: Seg.Plain("と") :: Seg.Name(b) :: Nil
}
