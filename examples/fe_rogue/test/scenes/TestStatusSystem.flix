// StatusSystem の純粋ロジック検証。
//
// 時限ステータス（バフ/デバフ）の add / tick / sumOf / combatMods を値だけで確認する。
// Scene[NodeTag] / effect には依存しない。

mod TestStatusSystem {

    use StatusSystem.StatusEffect

    /// テスト用 Status を作る短縮ヘルパ。
    def st(effect: StatusSystem.StatusEffect, magnitude: Int32, remaining: Int32): StatusSystem.Status =
        {effect = effect, magnitude = magnitude, remaining = remaining}

    // ════════════════════════════════════════════════════════
    // tick — remaining を 1 減らし、0 以下を除去する
    // ════════════════════════════════════════════════════════

    /// remaining=2 の効果は tick で remaining=1 になり残る。
    @Test
    def testTickDecrements(): Unit \ Assert =
        let after = StatusSystem.tick(st(StatusEffect.AtkUp, 4, 2) :: Nil);
        Assert.assertEq(expected = 1 :: Nil, after |> List.map(s -> s#remaining))

    /// remaining=1 の効果は tick で remaining=0 となり除去される（空リスト）。
    @Test
    def testTickDropsExpired(): Unit \ Assert =
        let after = StatusSystem.tick(st(StatusEffect.HitDown, 25, 1) :: Nil);
        Assert.assertEq(expected = 0, List.length(after))

    /// 複数効果を同時に tick: 残るものは減算され、尽きたものは消える。
    @Test
    def testTickMixed(): Unit \ Assert =
        let after = StatusSystem.tick(
            st(StatusEffect.AtkUp, 4, 3) :: st(StatusEffect.SpdUp, 5, 1) :: Nil);
        Assert.assertEq(expected = 2 :: Nil, after |> List.map(s -> s#remaining))

    // ════════════════════════════════════════════════════════
    // sumOf — 同種効果量の合計
    // ════════════════════════════════════════════════════════

    /// 同種の重ねがけは合算される。
    @Test
    def testSumOfAggregates(): Unit \ Assert =
        let xs = st(StatusEffect.AtkUp, 4, 3) :: st(StatusEffect.AtkUp, 2, 1)
                  :: st(StatusEffect.HitDown, 25, 5) :: Nil;
        Assert.assertEq(expected = 6, StatusSystem.sumOf(StatusEffect.AtkUp, xs))

    /// 該当種別が無ければ 0。
    @Test
    def testSumOfMissingIsZero(): Unit \ Assert =
        let xs = st(StatusEffect.AtkUp, 4, 3) :: Nil;
        Assert.assertEq(expected = 0, StatusSystem.sumOf(StatusEffect.SpdUp, xs))

    // ════════════════════════════════════════════════════════
    // combatMods — 戦闘ビューへ渡す補正のまとめ
    // ════════════════════════════════════════════════════════

    /// AtkUp は攻撃加算、SpdUp − SpdDown が速さ増減、HitDown は命中へ負補正になる。
    @Test
    def testCombatMods(): Unit \ Assert =
        let xs = st(StatusEffect.AtkUp, 4, 2) :: st(StatusEffect.SpdUp, 5, 1)
                  :: st(StatusEffect.SpdDown, 2, 1) :: st(StatusEffect.HitDown, 25, 5) :: Nil;
        let m = StatusSystem.combatMods(xs);
        Assert.assertEq(expected = (4, 3, -25), (m#atkBonus, m#spdDelta, m#hitMod))

    /// 効果なしなら全て 0。
    @Test
    def testCombatModsEmpty(): Unit \ Assert =
        let m = StatusSystem.combatMods(Nil);
        Assert.assertEq(expected = (0, 0, 0), (m#atkBonus, m#spdDelta, m#hitMod))

    // ════════════════════════════════════════════════════════
    // add — 先頭追加
    // ════════════════════════════════════════════════════════

    /// add は効果を 1 件積む。
    @Test
    def testAddPrepends(): Unit \ Assert =
        let after = StatusSystem.add(st(StatusEffect.AtkUp, 4, 2), Nil);
        Assert.assertEq(expected = 1, List.length(after))

    // ════════════════════════════════════════════════════════
    // Immobilized（完全停止）— ターンで解けず、被攻撃 / 被投擲でのみ解除
    // ════════════════════════════════════════════════════════

    /// tick は完全停止を減らさず保持する（remaining=0 でも消えない）。一方、同居する
    /// 時限効果はちゃんと減算される（停止だけ別扱いになっていることを 1 度で確認する）。
    @Test
    def testTickKeepsImmobilizedAndDecrementsOthers(): Unit \ Assert =
        let after = StatusSystem.tick(
            StatusSystem.immobilize() :: st(StatusEffect.AtkUp, 4, 2) :: Nil);
        // 停止は残り、AtkUp は remaining 2→1 に減る。件数 2・停止保持・AtkUp の残り 1。
        Assert.assertEq(
            expected = (2, true, 1 :: Nil),
            (List.length(after),
             StatusSystem.isImmobilized(after),
             after |> List.filter(s -> s#effect == StatusEffect.AtkUp) |> List.map(s -> s#remaining)))

    /// isImmobilized は完全停止を含むかどうかを返す。
    @Test
    def testIsImmobilized(): Unit \ Assert =
        Assert.assertEq(
            expected = (true, false),
            (StatusSystem.isImmobilized(StatusSystem.immobilize() :: Nil),
             StatusSystem.isImmobilized(st(StatusEffect.AtkUp, 4, 2) :: Nil)))

    /// clearImmobilized は完全停止だけを取り除き、他の時限効果は残す。
    @Test
    def testClearImmobilizedKeepsOthers(): Unit \ Assert =
        let xs = StatusSystem.immobilize() :: st(StatusEffect.SpdDown, 2, 3) :: Nil;
        let after = StatusSystem.clearImmobilized(xs);
        Assert.assertEq(
            expected = (false, 1),
            (StatusSystem.isImmobilized(after), List.length(after)))

    /// combatMods は完全停止に影響されない（全補正 0）。停止は移動・行動を止めるだけで戦闘値は変えない。
    @Test
    def testCombatModsIgnoresImmobilized(): Unit \ Assert =
        let m = StatusSystem.combatMods(StatusSystem.immobilize() :: Nil);
        Assert.assertEq(expected = (0, 0, 0), (m#atkBonus, m#spdDelta, m#hitMod))
}
