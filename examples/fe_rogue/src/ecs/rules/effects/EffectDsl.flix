/// EffectDsl — 特殊効果 DSL のコア型と Layer1 純粋ロジック
///
/// 武器・指輪・杖・消費アイテム・敵特殊行動の「特殊効果」を、戦闘コードへの
/// ベタ書き match ではなくデータ（JSON）として宣言し、interpreter が解釈する設計の中核。
/// このモジュールは World / effect / Java 呼び出しに依存しない純粋ロジックだけを置く:
///   - 効果量の解決      `resolveAmount` / `baseFor`
///   - 述語（ガード条件） `evalPredicate` / `evalAtom`
///   - 数値レンジ検証      `validateChance` / `validateMul` / `validateTurns` / ...
///                       （= 構文的には通るが何もしない「論理死」効果を弾く）
///
/// 実際の副作用（HP 書き換え・状態付与・演出）は別レイヤ（runPlan）が担い、
/// ここは数値・真偽だけで完結するためテストが純粋値で書ける。
mod EffectDsl {

    // ════════════════════════════════════════════════════════
    // 効果量 Amount — 「いくつ」を表す。op によって意味（回復量/ダメージ/倍率/マス）が変わる。
    // ════════════════════════════════════════════════════════

    /// 効果量の参照元。割合（pctOf）が何に対する割合かを表す。
    ///   - `Max`      : 対象の最大 HP（死神の HP 割合しきい値など）
    ///   - `Dealt`    : 直前に与えたダメージ（血吸いの吸収など）
    ///   - `Incoming` : 直前に受けたダメージ（反射など）
    pub enum AmountBase with Eq, ToString {
        case Max
        case Dealt
        case Incoming
    }

    /// statPlus が参照するステータス種別。現状は魔力のみ（杖回復の「魔力+10」）。
    /// 他ステータスを参照する効果が出たら case と `AmountCtx` を増やす。
    pub enum Stat with Eq, ToString {
        case Magic
    }

    /// 効果量の種類。
    ///   - `Flat(n)`         : 固定値 n
    ///   - `Pct(base, n)`    : base の n%（pctOf）
    ///   - `Mul(n)`          : 倍率 n/100（×1.5 = `Mul(150)`）。実体は estimate へ渡す
    ///   - `Tiles(n)`        : マス数。0 は無制限（ノックバック）
    ///   - `Count(n)`        : 個数
    ///   - `StatPlus(s, n)`  : ステータス s の値 + n（杖回復の「魔力+10」）
    pub enum Amount with Eq, ToString {
        case Flat(Int32)
        case Pct(AmountBase, Int32)
        case Mul(Int32)
        case Tiles(Int32)
        case Count(Int32)
        case StatPlus(Stat, Int32)
    }

    /// 効果量解決に必要な文脈。投射系の量計算だけが見る（`roll` や速さは持たない＝
    /// 追撃判定の値を量計算が誤参照することを型で封じる）。
    pub type alias AmountCtx = {
        max      = Int32,
        dealt    = Int32,
        incoming = Int32,
        magic    = Int32
    }

    /// 割合の参照元の実値を引く。
    pub def baseFor(base: AmountBase, ctx: AmountCtx): Int32 = match base {
        case AmountBase.Max      => ctx#max
        case AmountBase.Dealt    => ctx#dealt
        case AmountBase.Incoming => ctx#incoming
    }

    /// ステータス値を引く。
    def statOf(s: Stat, ctx: AmountCtx): Int32 = match s {
        case Stat.Magic => ctx#magic
    }

    /// 効果量を実数へ解決する。倍率（Mul）は割らずにそのまま返し、×N/100 の割り算は
    /// 受け手（estimate 等）が行う。割合（Pct）はここで base × n / 100 まで確定する。
    pub def resolveAmount(a: Amount, ctx: AmountCtx): Int32 = match a {
        case Amount.Flat(v)        => v
        case Amount.Pct(b, v)      => (baseFor(b, ctx) * v) / 100
        case Amount.Mul(v)         => v
        case Amount.Tiles(v)       => v
        case Amount.Count(v)       => v
        case Amount.StatPlus(s, v) => statOf(s, ctx) + v
    }

    // ════════════════════════════════════════════════════════
    // 述語 Predicate — 効果の発動ガード条件（if）。allOf/anyOf の木で AND/OR を表す。
    // ════════════════════════════════════════════════════════

    /// 述語の葉（個々の判定）。35 件の if で実際に使うものだけを持つ。
    ///   - `TargetAlive`          : 対象が生存（盗人ドロップの前提）
    ///   - `SelfHpPctAtMost(n)`   : 自分の HP が最大の n% 以下（背水）
    ///   - `TargetHpPctAtMost(n)` : 対象の HP が最大の n% 以下（死神）
    ///   - `EquippedIsRogue`      : 装備者がローグ（盗人の剣）
    ///   - `Adjacent`             : 対象に隣接（RingMan）
    pub enum Atom with Eq, ToString {
        case TargetAlive
        case SelfHpPctAtMost(Int32)
        case TargetHpPctAtMost(Int32)
        case EquippedIsRogue
        case Adjacent
    }

    /// 述語の木。葉 / AND（allOf）/ OR（anyOf）。評価器は任意深さを畳めるが、
    /// IDE 側は深さ 1 に制限する（実用ケースを全被覆しつつ編集 UI を単純に保つ）。
    pub enum Pred with Eq, ToString {
        case PAtom(Atom)
        case AllOf(List[Pred])
        case AnyOf(List[Pred])
    }

    /// 述語評価に必要な文脈。述語評価だけが見る（量計算の値を持たない）。
    pub type alias PredCtx = {
        selfHpPct       = Int32,
        targetHpPct     = Int32,
        targetAlive     = Bool,
        equippedIsRogue = Bool,
        adjacent        = Bool
    }

    /// 葉述語を評価する。
    pub def evalAtom(a: Atom, ctx: PredCtx): Bool = match a {
        case Atom.TargetAlive          => ctx#targetAlive
        case Atom.SelfHpPctAtMost(n)   => ctx#selfHpPct   <= n
        case Atom.TargetHpPctAtMost(n) => ctx#targetHpPct <= n
        case Atom.EquippedIsRogue      => ctx#equippedIsRogue
        case Atom.Adjacent             => ctx#adjacent
    }

    /// 述語の木を畳んで真偽を返す。`AllOf` は短絡 AND（空は true）、
    /// `AnyOf` は短絡 OR（空は false）。配列 if（暗黙 allOf）は decode 段で `AllOf` に正規化する。
    pub def evalPredicate(p: Pred, ctx: PredCtx): Bool = match p {
        case Pred.PAtom(a)  => evalAtom(a, ctx)
        case Pred.AllOf(ps) => List.forAll(q -> evalPredicate(q, ctx), ps)
        case Pred.AnyOf(ps) => List.exists(q -> evalPredicate(q, ctx), ps)
    }

    // ════════════════════════════════════════════════════════
    // 数値レンジ検証 — 「構文 OK だが何もしない（論理死）」効果を弾く（設計 §3.9）。
    //   IDE はスライダでレンジ外を入力させないが、JSON 直編集を起動時に弾く二重防御。
    // ════════════════════════════════════════════════════════

    /// 数値フィールドの検証結果。`Warn` は保存可だが「何もしません」と表示する境界値。
    pub enum Verdict with Eq, ToString {
        case Good
        case Warn(String)
        case Reject(String)
    }

    /// 確率は 1..100。0 は必ず不発（論理死）、>100 は範囲外。
    pub def validateChance(c: Int32): Verdict =
        if (c < 1)        Verdict.Reject("chance は 1..100。${c} は必ず不発で論理死")
        else if (c > 100) Verdict.Reject("chance は 1..100。${c} は範囲外")
        else              Verdict.Good

    /// 倍率は 101 以上（×1.01〜）。100 は等倍＝無効果なので warn、100 未満は弱体/無効で reject。
    pub def validateMul(v: Int32): Verdict =
        if (v < 100)       Verdict.Reject("mul は 101 以上。${v} は等倍未満で無効/弱体")
        else if (v == 100) Verdict.Warn("mul=100 は等倍。この効果は何もしません")
        else               Verdict.Good

    /// 継続ターンは 1 以上。0 は即消滅（論理死）。
    pub def validateTurns(n: Int32): Verdict =
        if (n < 1) Verdict.Reject("turns は 1 以上。${n} は即消滅で論理死")
        else       Verdict.Good

    /// 割合は 1..100。0 は無効果。
    pub def validatePct(v: Int32): Verdict =
        if (v < 1)        Verdict.Reject("pct は 1..100。${v} は無効果で論理死")
        else if (v > 100) Verdict.Reject("pct は 1..100。${v} は範囲外")
        else              Verdict.Good

    /// マス数は 0 以上（0 = 無制限）。負は不正。
    pub def validateTiles(v: Int32): Verdict =
        if (v < 0) Verdict.Reject("tiles は 0 以上（0=無制限）。${v} は不正")
        else       Verdict.Good

    /// ステータス加算量は 1 以上。
    pub def validateStatPlus(v: Int32): Verdict =
        if (v < 1) Verdict.Reject("statPlus は 1 以上。${v} は無効果")
        else       Verdict.Good
}
