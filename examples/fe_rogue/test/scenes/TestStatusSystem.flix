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

    /// sumOf は防御的に同種を合計する（通常 add が重複を防ぐので 1 件以下だが、合算ロジック自体を確認）。
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

    /// 重ねがけ無し: 同種が既にあれば積まず既存を据え置く（最初の magnitude=4 / remaining=2 が残る）。
    @Test
    def testAddIgnoresDuplicateEffect(): Unit \ Assert =
        let xs = StatusSystem.add(st(StatusEffect.AtkUp, 4, 2), Nil);
        let after = StatusSystem.add(st(StatusEffect.AtkUp, 9, 5), xs);
        Assert.assertEq(
            expected = (1, 4, 2),
            (List.length(after),
             after |> List.map(s -> s#magnitude) |> List.sum,
             after |> List.map(s -> s#remaining) |> List.sum))

    /// 別種の効果は共存する（重ねがけ無しは同種だけ）。
    @Test
    def testAddDifferentEffectsCoexist(): Unit \ Assert =
        let xs = StatusSystem.add(st(StatusEffect.AtkUp, 4, 2), Nil);
        let after = StatusSystem.add(st(StatusEffect.SpdUp, 5, 3), xs);
        Assert.assertEq(expected = 2, List.length(after))

    // ════════════════════════════════════════════════════════
    // Immobilized（完全停止）— 5 ターンで自然解除、被攻撃 / 被投擲でも即時解除
    // ════════════════════════════════════════════════════════

    /// tick は完全停止も時限効果と同じく減算する。1 回の tick で停止は残り（remaining 5→4）、
    /// 同居する AtkUp も remaining 2→1 に減る。件数 2・停止保持・AtkUp の残り 1。
    @Test
    def testTickDecrementsImmobilizedAndOthers(): Unit \ Assert =
        let after = StatusSystem.tick(
            StatusSystem.immobilize() :: st(StatusEffect.AtkUp, 4, 2) :: Nil);
        Assert.assertEq(
            expected = (2, true, 1 :: Nil),
            (List.length(after),
             StatusSystem.isImmobilized(after),
             after |> List.filter(s -> s#effect == StatusEffect.AtkUp) |> List.map(s -> s#remaining)))

    /// 完全停止は 5 ターン（5 回の tick）で自然解除される。4 回までは停止が残り、5 回目で消える。
    @Test
    def testImmobilizedExpiresAfterFiveTicks(): Unit \ Assert =
        let tickN = n -> List.foldLeft((acc, _) -> StatusSystem.tick(acc), StatusSystem.immobilize() :: Nil, List.range(0, n));
        Assert.assertEq(
            expected = (true, false),
            (StatusSystem.isImmobilized(tickN(4)), StatusSystem.isImmobilized(tickN(5))))

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
