// FireShotFx（魔導書攻撃の炎 3 幕）のテスト。演出ぜんぶが (詠唱者, 対象, seed, elapsed) の
// 純粋な導出であること —— 幕の境界時刻・飛翔中点の位置・寿命外は空 —— と、World store の
// spawn→老化→cull ライフサイクルを固定する。境界時刻はモジュールの尺関数から導いて float の
// 端数ぶれを避ける。

mod TestFireShotFx {

    use FireShotFx.Phase

    /// 検証用の詠唱者・対象ワールド座標（頭上オフセット = tileSize 26px を計算に使う）。
    def caster(): Vec2.Vec2 = {x = 100.0, y = 100.0}
    def target(): Vec2.Vec2 = {x = 200.0, y = 100.0}

    // ── 幕の境界時刻 ─────────────────────────────────

    /// elapsed → 幕。詠唱[0,cast)→飛翔[cast,impact)→着弾[impact,total)→寿命外は Done（左閉右開）。
    @Test
    def testPhaseBoundaries(): Unit \ Assert =
        Assert.assertEq(expected = Phase.Cast,   FireShotFx.phaseAt(0.0));
        Assert.assertEq(expected = Phase.Cast,   FireShotFx.phaseAt(FireShotFx.castDuration() * 0.5));
        // 幕1→幕2 の境界（cast 開始時刻）は左閉右開ゆえ Flight 側。
        Assert.assertEq(expected = Phase.Flight, FireShotFx.phaseAt(FireShotFx.castDuration()));
        // 幕2→幕3 の境界（着弾開始時刻）は Impact 側＝ここでダメージ適用と拍が揃う。
        Assert.assertEq(expected = Phase.Impact, FireShotFx.phaseAt(FireShotFx.impactStart()));
        // 総寿命ちょうどは寿命外＝Done（右開）。
        Assert.assertEq(expected = Phase.Done,   FireShotFx.phaseAt(FireShotFx.totalDuration()));
        Assert.assertEq(expected = Phase.Done,   FireShotFx.phaseAt(FireShotFx.totalDuration() + 1.0))

    /// 飛翔の中点で火の玉は「詠唱者頭上」と「対象」のちょうど中間にいる。
    /// 頭上 = 詠唱者(100,100) の 1 タイル上(100,74)、対象 = (200,100)。中点 = (150, 87)。
    @Test
    def testFlightMidpointLerp(): Unit \ Assert =
        let mid = FireShotFx.castDuration() + FireShotFx.flightDuration() * 0.5;
        let c = FireShotFx.ballCenterAt(caster(), target(), mid);
        Assert.assertEq(expected = (150.0, 87.0), (c#x, c#y))

    /// 詠唱中は頭上に留まる（飛ばない）。着弾以降は対象に貼り付く。
    @Test
    def testBallAnchors(): Unit \ Assert =
        let castC = FireShotFx.ballCenterAt(caster(), target(), 0.1);
        let hitC  = FireShotFx.ballCenterAt(caster(), target(), FireShotFx.impactStart() + 0.1);
        Assert.assertEq(expected = (100.0, 74.0), (castC#x, castC#y));
        Assert.assertEq(expected = (200.0, 100.0), (hitC#x, hitC#y))

    /// 各幕は polygon を出し、寿命外（Done）は空。
    @Test
    def testQuadsPerPhase(): Unit \ Assert =
        let nonEmptyAt = e -> not List.isEmpty(FireShotFx.quads(caster(), target(), 1, e));
        Assert.assertEq(expected = true,  nonEmptyAt(0.1));                              // 幕1 詠唱
        Assert.assertEq(expected = true,  nonEmptyAt(FireShotFx.castDuration() + 0.05)); // 幕2 飛翔
        Assert.assertEq(expected = true,  nonEmptyAt(FireShotFx.impactStart() + 0.05));  // 幕3 着弾
        Assert.assertEq(expected = false, nonEmptyAt(FireShotFx.totalDuration() + 0.5))  // 寿命外

    // ── World store の spawn → 老化 → cull ─────────────────

    /// `Cmd.SpawnFireShot` は seq を seed に採番して +1。emit した瞬間 store に 1 件、seed=0。
    @Test
    def testSpawnAssignsSeed(): Unit \ Assert =
        let cmd = World.Cmd.SpawnFireShot({total = FireShotFx.totalDuration(), caster = caster(), target = target()});
        let w1  = World.applyCmd(cmd, World.empty());
        let w2  = World.applyCmd(cmd, w1);
        let seeds = World.fireShotsOf(w2) |> Map.valuesOf |> List.map(d -> d#seed) |> List.sort;
        Assert.assertEq(expected = 2, Map.size(World.fireShotsOf(w2)));
        Assert.assertEq(expected = 0 :: 1 :: Nil, seeds)

    /// stepWorld が remaining を dt 減算し、総寿命を越えたら cull（0 件に戻る）。
    @Test
    def testAgesAndCulls(): Unit \ Assert =
        let cmd = World.Cmd.SpawnFireShot({total = FireShotFx.totalDuration(), caster = caster(), target = target()});
        let w1  = World.applyCmd(cmd, World.empty());
        // 半分ほど進めても残っている。
        let (wMid, _) = World.stepWorld(w1, FireShotFx.totalDuration() * 0.5);
        // 総寿命を越えて進めると期限切れで落ちる。
        let (wDead, _) = World.stepWorld(wMid, FireShotFx.totalDuration());
        Assert.assertEq(expected = 1, Map.size(World.fireShotsOf(wMid)));
        Assert.assertEq(expected = 0, Map.size(World.fireShotsOf(wDead)))
}
