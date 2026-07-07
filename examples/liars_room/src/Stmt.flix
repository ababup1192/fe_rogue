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

    /// 発言の日本語文言。nameOf は NPC id → 呼び名（「あお」など）。
    /// 角括弧は使わない（引用は 『』 で表す）。
    pub def text(speaker: {speaker = Int32}, nameOf: Int32 -> String, stmt: Stmt): String =
        "${phrase(speaker#speaker, nameOf, stmt)}だよ"

    /// 「だよ」を付ける前の名詞句。Not は再帰的に 『…』というのは嘘 で包む。
    def phrase(speaker: Int32, nameOf: Int32 -> String, stmt: Stmt): String = match stmt {
        case Stmt.Say(claim) => claimPhrase(speaker, nameOf, claim)
        case Stmt.Not(inner) => "『${phrase(speaker, nameOf, inner)}』というのは嘘"
    }

    /// 主張 1 件の名詞句。話し手自身が対象に含まれるときは「わたし」と言う。
    def claimPhrase(speaker: Int32, nameOf: Int32 -> String, claim: Claim): String =
        match claim {
            case Claim.IsLiar(t)      => "${subject(speaker, nameOf, t)}は嘘つき"
            case Claim.IsHonest(t)    => "${subject(speaker, nameOf, t)}は正直者"
            case Claim.SameSide(a, b) => "${pairSubject(speaker, nameOf, a, b)}は同じ側"
            case Claim.DiffSide(a, b) => "${pairSubject(speaker, nameOf, a, b)}は違う側"
        }

    /// 対象 1 人の言い方（「みどりの人」/「わたし」）。
    def subject(speaker: Int32, nameOf: Int32 -> String, target: Int32): String =
        if (target == speaker) "わたし" else "${nameOf(target)}の人"

    /// 対象 2 人の言い方。話し手自身が含まれるなら「わたしと◯の人」の順で言う。
    def pairSubject(speaker: Int32, nameOf: Int32 -> String, a: Int32, b: Int32): String =
        if (a == speaker)      "わたしと${nameOf(b)}の人"
        else if (b == speaker) "わたしと${nameOf(a)}の人"
        else                   "${nameOf(a)}の人と${nameOf(b)}の人"
}
