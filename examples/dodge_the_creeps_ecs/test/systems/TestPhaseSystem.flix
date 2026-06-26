// PhaseSystem のテスト（純粋）— スコア加算 / Get Ready 中の停止 / HUD 同期

mod TestPhaseSystem {

    /// Playing（startDelay 経過済み）で 1 秒経つとスコア +1
    @Test
    def testScoreIncrements(): Unit \ Assert =
        let World.World(w0) = World.empty();
        let playing = World.World({phase = GamePhase.Playing | w0});  // startDelay=0
        let after = PhaseSystem.phaseSystem(1.0, playing);
        let World.World(wa) = after;
        Assert.assertEq(expected = 1, wa#score)

    /// Get Ready（startDelay>0）中はスコアが増えない
    @Test
    def testGetReadyHoldsScore(): Unit \ Assert =
        let World.World(w0) = World.empty();
        let playing = World.World({phase = GamePhase.Playing,
                                   timers = {startDelay = 2.0 | w0#timers} | w0});
        let after = PhaseSystem.phaseSystem(0.5, playing);
        let World.World(wa) = after;
        Assert.assertEq(expected = 0, wa#score)

    /// hudSync: Score HUD entity のテキストが score を反映する
    @Test
    def testHudSyncScoreText(): Unit \ Assert =
        let World.World(w0) = World.empty();
        let hud: HudComp = {kind = HudKind.Score, text = "0",
                            pos = {x = 0.0, y = 0.0}, size = {x = 0.0, y = 0.0}, visible = true};
        let playing = World.World({phase = GamePhase.Playing, score = 5,
                                   huds = Map#{ 100 => hud } | w0});
        let after = PhaseSystem.phaseSystem(0.0, playing);
        let World.World(wa) = after;
        let txt = Map.get(100, wa#huds) |> Option.map(h -> h#text) |> Option.getWithDefault("?");
        Assert.assertEq(expected = "5", txt)
}
