// Rules — 発言の意味論の唯一の置き場（Datalog ルールパック）。
// 「正直者の発言内容は真、嘘つきの発言内容は偽」という規則をそのままルールとして書き、
// 総当たりソルバー（Solver.consistent 経由）と部分知識からの伝播（propagate）が
// まったく同じルールセットを共有する。意味論がここ以外に存在しないことが要点。
mod Rules {

    /// 発言 1 件 = (話し手の id, 正規化済みの主張)。
    pub type alias SaidClaim = (Int32, Stmt.Claim)

    /// このモジュールの Datalog の語彙。
    /// 事実: AccuseLiar(s,t)=「s が『t は嘘つき』と言った」/ ClaimHonest / SaysSame / SaysDiff。
    /// 導出: Honest / Liar（種別の確定）、Same / Diff（同じ側・違う側）、Contra（矛盾の目印）。
    /// Out(x, k) は propagate の読み戻し用（k = 0 正直 / 1 嘘つき / 2 矛盾）。
    /// 1 回の query で全部を回収するための出口述語で、意味論そのものではない。
    pub type alias Db = #{
        Honest(Int32), Liar(Int32),
        AccuseLiar(Int32, Int32), ClaimHonest(Int32, Int32),
        SaysSame(Int32, Int32, Int32), SaysDiff(Int32, Int32, Int32),
        Same(Int32, Int32), Diff(Int32, Int32),
        Contra(Int32),
        Out(Int32, Int32)
    }

    /// 部分知識から導けた結論。contra = 矛盾が出た（その知識はあり得ない）。
    pub type alias Derived = { honest = Set[Int32], liars = Set[Int32], contra = Bool }

    // ========================================================================
    // ルールパック（発言タイプごと）
    // ========================================================================

    /// 全発言タイプの意味論。発言タイプを増やすときはパックを足してここで合成する。
    def semantics(): Db =
        accusePack() <+> vouchPack() <+> sidePack() <+> contraPack()

    /// 告発「t は嘘つき」: 正直者が言えばそのまま、嘘つきが言えば逆。
    def accusePack(): Db = #{
        Liar(t)   :- Honest(s), AccuseLiar(s, t).
        Honest(t) :- Liar(s),   AccuseLiar(s, t).
    }

    /// 擁護「t は正直者」: 正直者が言えばそのまま、嘘つきが言えば逆。
    def vouchPack(): Db = #{
        Honest(t) :- Honest(s), ClaimHonest(s, t).
        Liar(t)   :- Liar(s),   ClaimHonest(s, t).
    }

    /// 同じ側・違う側: 発言から Same / Diff を確定し、対称・推移（違う×違う=同じ）で閉じ、
    /// どちらか一方の種別が分かれば相方へ伝える。
    def sidePack(): Db = #{
        Same(a, b) :- Honest(s), SaysSame(s, a, b).
        Diff(a, b) :- Liar(s),   SaysSame(s, a, b).
        Diff(a, b) :- Honest(s), SaysDiff(s, a, b).
        Same(a, b) :- Liar(s),   SaysDiff(s, a, b).
        Same(b, a) :- Same(a, b).
        Diff(b, a) :- Diff(a, b).
        Same(a, c) :- Same(a, b), Same(b, c).
        Same(a, c) :- Diff(a, b), Diff(b, c).
        Diff(a, c) :- Same(a, b), Diff(b, c).
        Honest(b)  :- Same(a, b), Honest(a).
        Liar(b)    :- Same(a, b), Liar(a).
        Honest(b)  :- Diff(a, b), Liar(a).
        Liar(b)    :- Diff(a, b), Honest(a).
    }

    /// 矛盾の検出: 同じ人が正直者かつ嘘つき、または自分自身と違う側。
    def contraPack(): Db = #{
        Contra(x) :- Honest(x), Liar(x).
        Contra(x) :- Diff(x, x).
    }

    // ========================================================================
    // 事実の注入と公開 API
    // ========================================================================

    /// 発言の列を Datalog の事実へ振り分ける。
    def claimFacts(claims: List[SaidClaim]): Db =
        let accuse = claims |> List.filterMap(said -> match said {
            case (s, Stmt.Claim.IsLiar(t)) => Some((s, t))
            case _                         => None
        });
        let vouch = claims |> List.filterMap(said -> match said {
            case (s, Stmt.Claim.IsHonest(t)) => Some((s, t))
            case _                           => None
        });
        let same = claims |> List.filterMap(said -> match said {
            case (s, Stmt.Claim.SameSide(a, b)) => Some((s, a, b))
            case _                              => None
        });
        let diff = claims |> List.filterMap(said -> match said {
            case (s, Stmt.Claim.DiffSide(a, b)) => Some((s, a, b))
            case _                              => None
        });
        inject accuse, vouch, same, diff into AccuseLiar/2, ClaimHonest/2, SaysSame/3, SaysDiff/3

    /// 完全な割り当て（正直者と嘘つきの名簿）が全発言と矛盾しないか。
    /// Solver が 2^N の総当たり側から 1 候補ずつ聞きにくる。
    pub def consistent(honest: List[Int32], liars: List[Int32], claims: List[SaidClaim]): Bool =
        let db = (inject honest, liars into Honest/1, Liar/1) <+> claimFacts(claims) <+> semantics();
        let hits = query db select x from Contra(x);
        Vector.isEmpty(hits)

    /// 部分知識（確定済みの正直者・嘘つき）から導ける結論をすべて集める。
    /// 難易度の実測（Solver.probeDepth）と、メモ連動のヒントに使う。
    /// 導出は Out(x, k) に束ね、Datalog の解決を 1 回で済ませる（ここが全体の hot path）。
    pub def propagate(knownHonest: Set[Int32], knownLiars: Set[Int32],
                      claims: List[SaidClaim]): Derived =
        let db = (inject Set.toList(knownHonest), Set.toList(knownLiars) into Honest/1, Liar/1)
            <+> claimFacts(claims) <+> semantics() <+> #{
                Out(x, 0) :- Honest(x).
                Out(x, 1) :- Liar(x).
                Out(x, 2) :- Contra(x).
            };
        let rows = (query db select (x, k) from Out(x, k)) |> Vector.toList;
        { honest = rows |> List.filterMap(row -> { let (x, k) = row; if (k == 0) Some(x) else None }) |> List.toSet,
          liars = rows |> List.filterMap(row -> { let (x, k) = row; if (k == 1) Some(x) else None }) |> List.toSet,
          contra = rows |> List.exists(row -> { let (_, k) = row; k == 2 }) }

    /// 床セルの集合の中で、start から歩いて届くセルの集合（4 近傍の推移閉包）。
    /// ステージ検証（全 NPC の前まで歩けるか）に使う。
    /// 述語の引数はセルのタプルでなく x, y を並べた平坦な形にする（エンジンの索引と相性が良い）。
    pub def reachable(start: (Int32, Int32), floors: Set[(Int32, Int32)]): Set[(Int32, Int32)] =
        let adjacent = floors |> Set.toList |> List.flatMap(cell -> {
            let (x, y) = cell;
            ((x + 1, y) :: (x - 1, y) :: (x, y + 1) :: (x, y - 1) :: Nil)
                |> List.filter(next -> Set.memberOf(next, floors))
                |> List.map(next -> { let (nx, ny) = next; (x, y, nx, ny) })
        });
        let db = (inject (start :: Nil), adjacent into Reach/2, Adj/4) <+> #{
            Reach(x2, y2) :- Reach(x1, y1), Adj(x1, y1, x2, y2).
        };
        let cells = query db select (x, y) from Reach(x, y);
        cells |> Vector.toList |> List.toSet
}
