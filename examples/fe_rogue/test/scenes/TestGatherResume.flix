/// 集合モードのターン跨ぎ自動継続の判定（`EnemyTurnDriverScene.shouldResumeGather`）の検証。
///
/// 検証する責務:
///   - 3 条件すべて成立（前ターン集合の自発全員待機 ∧ 主人公健在 ∧ 敵が画面内にいない）でのみ復帰する
///   - いずれか 1 つでも欠ければ復帰しない
///
/// `lordReadyToGather` / `anyVisibleEnemy` は scene 依存の effectful なので、判定の核は純粋な
/// `shouldResumeGather` に切り出してある（ここをテストする）。
mod TestGatherResume {

    /// resume × lordReady × anyVisibleEnemy の真理値表（true は 1 通りだけ）。
    @Test
    def testShouldResumeGatherTruthTable(): Unit \ Assert =
        let f = EnemyTurnDriverScene.shouldResumeGather;
        let checks =
            f(true,  true,  false) ::   // 3 条件成立 → 復帰
            f(false, true,  false) ::   // 前ターンが集合自発待機でない → 復帰しない
            f(true,  false, false) ::   // 主人公が退場/戦闘不能 → 復帰しない
            f(true,  true,  true)  ::   // 画面内に敵がいる → 復帰しない
            Nil;
        Assert.assertEq(expected = true :: false :: false :: false :: Nil, checks)
}
