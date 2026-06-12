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
}
