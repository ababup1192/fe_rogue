/// EffectDsl のコア純粋ロジック（効果量解決・述語評価・数値レンジ検証）を固定する。
/// すべて Scene 非依存の純関数なので数値・真偽の assertEq だけで完結する。
mod TestEffectDsl {

    use EffectDsl.{Amount, AmountBase, Stat, Atom, Pred, Verdict}

    // 量計算用の固定文脈（max=30, dealt=20, incoming=12, magic=7）。
    def amtCtx(): EffectDsl.AmountCtx =
        {max = 30, dealt = 20, incoming = 12, magic = 7}

    // ════════════════════════════════════════════════════════
    // resolveAmount / baseFor
    // ════════════════════════════════════════════════════════

    /// Flat はそのまま。
    @Test
    def testResolveFlat(): Unit \ Assert =
        Assert.assertEq(expected = 15, EffectDsl.resolveAmount(Amount.Flat(15), amtCtx()))

    /// Pct(Dealt, 30) は dealt(20) の 30% = 6（血吸いの吸収量）。
    @Test
    def testResolvePctDealt(): Unit \ Assert =
        Assert.assertEq(expected = 6,
            EffectDsl.resolveAmount(Amount.Pct(AmountBase.Dealt, 30), amtCtx()))

    /// Pct の base は Max/Dealt/Incoming で切り替わる。
    @Test
    def testBaseForAllThree(): Unit \ Assert =
        let c = amtCtx();
        Assert.assertEq(expected = (30, 20, 12),
            (EffectDsl.baseFor(AmountBase.Max, c),
             EffectDsl.baseFor(AmountBase.Dealt, c),
             EffectDsl.baseFor(AmountBase.Incoming, c)))

    /// Mul は割らずにそのまま（倍率は受け手が /100 する）。
    @Test
    def testResolveMulPassThrough(): Unit \ Assert =
        Assert.assertEq(expected = 150, EffectDsl.resolveAmount(Amount.Mul(150), amtCtx()))

    /// StatPlus(Magic, 10) は magic(7) + 10 = 17（杖回復の「魔力+10」）。
    @Test
    def testResolveStatPlusMagic(): Unit \ Assert =
        Assert.assertEq(expected = 17,
            EffectDsl.resolveAmount(Amount.StatPlus(Stat.Magic, 10), amtCtx()))

    // ════════════════════════════════════════════════════════
    // evalPredicate / evalAtom（AND-OR の木）
    // ════════════════════════════════════════════════════════

    // 述語文脈: 自HP 25%, 敵HP 40%, 生存, ローグ, 隣接。
    def predCtx(): EffectDsl.PredCtx =
        {selfHpPct = 25, targetHpPct = 40, targetAlive = true,
         equippedIsRogue = true, adjacent = true}

    /// SelfHpPctAtMost(30) は 自HP25% で発火（背水の境界「以下」）。
    @Test
    def testAtomSelfHpAtMost(): Unit \ Assert =
        Assert.assertEq(expected = (true, false),
            (EffectDsl.evalAtom(Atom.SelfHpPctAtMost(30), predCtx()),
             EffectDsl.evalAtom(Atom.SelfHpPctAtMost(24), predCtx())))

    /// TargetHpPctAtMost(30) は 敵HP40% では発火しない（死神の境界）。
    @Test
    def testAtomTargetHpAtMost(): Unit \ Assert =
        Assert.assertEq(expected = false,
            EffectDsl.evalAtom(Atom.TargetHpPctAtMost(30), predCtx()))

    /// allOf は全真で true、1つでも偽で false（盗人: ローグ かつ 生存）。
    @Test
    def testAllOf(): Unit \ Assert =
        let p = Pred.AllOf(Pred.PAtom(Atom.EquippedIsRogue) :: Pred.PAtom(Atom.TargetAlive) :: Nil);
        Assert.assertEq(expected = true, EffectDsl.evalPredicate(p, predCtx()))

    /// anyOf は 1つでも真で true。targetHp40%(死神条件偽) または selfHp25%以下(背水条件真) → true。
    @Test
    def testAnyOf(): Unit \ Assert =
        let p = Pred.AnyOf(
            Pred.PAtom(Atom.TargetHpPctAtMost(30)) ::      // 偽
            Pred.PAtom(Atom.SelfHpPctAtMost(30))   ::      // 真
            Nil);
        Assert.assertEq(expected = true, EffectDsl.evalPredicate(p, predCtx()))

    /// 深さ1の積和: allOf[ targetAlive, anyOf[ 死神条件(偽), 背水条件(真) ] ] → true。
    @Test
    def testNestedDepth1(): Unit \ Assert =
        let inner = Pred.AnyOf(
            Pred.PAtom(Atom.TargetHpPctAtMost(30)) ::
            Pred.PAtom(Atom.SelfHpPctAtMost(30))   :: Nil);
        let p = Pred.AllOf(Pred.PAtom(Atom.TargetAlive) :: inner :: Nil);
        Assert.assertEq(expected = true, EffectDsl.evalPredicate(p, predCtx()))

    /// 空 allOf は true、空 anyOf は false（短絡の単位元）。
    @Test
    def testEmptyFolds(): Unit \ Assert =
        Assert.assertEq(expected = (true, false),
            (EffectDsl.evalPredicate(Pred.AllOf(Nil), predCtx()),
             EffectDsl.evalPredicate(Pred.AnyOf(Nil), predCtx())))

    // ════════════════════════════════════════════════════════
    // 数値レンジ検証（論理死封じ §3.9）
    // ════════════════════════════════════════════════════════

    /// chance: 0 は reject、1 と 100 は Good、200 は reject。
    @Test
    def testValidateChance(): Unit \ Assert =
        Assert.assertEq(
            expected = (true, true, true, true),
            (isReject(EffectDsl.validateChance(0)),
             isGood(EffectDsl.validateChance(1)),
             isGood(EffectDsl.validateChance(100)),
             isReject(EffectDsl.validateChance(200))))

    /// mul: 100 は warn（等倍＝無効果）、101 は Good、99 は reject。
    @Test
    def testValidateMul(): Unit \ Assert =
        Assert.assertEq(
            expected = (true, true, true),
            (isWarn(EffectDsl.validateMul(100)),
             isGood(EffectDsl.validateMul(101)),
             isReject(EffectDsl.validateMul(99))))

    /// turns: 0 は reject、1 は Good。tiles: -1 は reject、0 は Good（無制限）。
    @Test
    def testValidateTurnsAndTiles(): Unit \ Assert =
        Assert.assertEq(
            expected = (true, true, true, true),
            (isReject(EffectDsl.validateTurns(0)),
             isGood(EffectDsl.validateTurns(1)),
             isReject(EffectDsl.validateTiles(-1)),
             isGood(EffectDsl.validateTiles(0))))

    // Verdict の判別ヘルパ（テストでパターンマッチ＋bug! を避け、Bool に畳んで assertEq する）。
    def isGood(v: Verdict): Bool = match v {
        case Verdict.Good => true
        case _            => false
    }
    def isWarn(v: Verdict): Bool = match v {
        case Verdict.Warn(_) => true
        case _               => false
    }
    def isReject(v: Verdict): Bool = match v {
        case Verdict.Reject(_) => true
        case _                 => false
    }
}
