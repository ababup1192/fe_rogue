// TestHeadlessRun — ECS固有 payoff の証明（決定論ゴールデンテスト）
//
// seeded Random ＋ no-input mock Game ＋ 固定 dt で Game.runHeadless を回し、
// 「ゲーム全体を値として」再現する。プレイヤーへ確実に当たるコースの mob を置き、
// 16 フレーム後に phase=GameOver かつ score=1（ゴールデン値）になることを正確にアサートする。
// グラフィック無しでゲーム全体の挙動を検証できる＝可変状態のノード版には無い ECS の売り。

mod TestHeadlessRun {

    // ── mock handlers ──

    /// 全乱数を 0.5 に固定（spawn を決定的に）。
    def withSeededRandom(f: Unit -> a \ ef + Math.Random): a \ ef =
        run f() with handler Math.Random {
            def randomFloat64(k) = k(0.5)
            def randomInt64(k)   = k(42i64)
        }

    /// 入力ゼロの mock Game（runHeadless が触るのは isKeyPressed のみだが handler は全 op 必要）。
    def withMockGame(f: Unit -> a \ ef + GameEngine.Game): a \ ef =
        run f() with handler GameEngine.Game {
            def renderCommands(_, _, _, k)  = k(())
            def initTileBuffer(_, k)        = k((0i32, 0i32))
            def shouldClose(k)              = k(false)
            def getDeltaTime(k)             = k(Duration.seconds(0.1))
            def isKeyPressed(_, k)          = k(false)
            def getMousePosition(k)         = k({x = 0.0, y = 0.0})
            def isMouseButtonPressed(_, k)  = k(false)
            def consumeScrollDelta(k)       = k(0.0)
            def getFontAtlas(_, k)          = k(testFontAtlas())
            def getViewportRect(k)          = k({position = Vec2.zero(), size = {x = 480.0, y = 720.0}})
            def getTextureInfo(_, k)        = k(None)
            def setCursor(_, k)             = k(())
        }

    def testFontAtlas(): FontAtlas = {
        textureName = "font_test", fontSize = 32.0, textureSize = 512.0,
        ascent = 0.0, descent = 0.0, lineGap = 0.0, glyphs = Map.empty()
    }

    // ── 決定論シナリオ ──
    // player を中央(240,450)に置き、(240,100) から真下(0,+200/s)へ向かう mob を 1 体置く。
    // dt=0.1 で 15 フレーム目に mobY=400 → 距離50<60 で衝突 → GameOver。
    // score は +1（dt の FP 累積で実質 11 フレーム目）。衝突(15)より前なので score=1 で確定。

    def scenario(): World =
        let World.World(w0) = World.empty();
        let playing = World.World({phase = GamePhase.Playing | w0});
        let withPlayer = World.spawnPlayer({x = 240.0, y = 450.0}, 30.0, playing);
        let mobSc = World.mobSprite("fly", "enemyFlyingAlt_1", "enemyFlyingAlt_2");
        World.addMob({x = 240.0, y = 100.0}, {x = 0.0, y = 200.0}, mobSc, 30.0, withPlayer)

    @Test
    def testHeadlessGoldenRun(): Unit \ Assert =
        let final = withSeededRandom(() -> withMockGame(() ->
            Game.runHeadless(0.1, 16, scenario())));
        let World.World(w) = final;
        Assert.assertEq(
            expected = (true, 1),
            (w#phase == GamePhase.GameOver, w#score))

    /// 同じ入力なら同じ結果（決定論）。両 run がゴールデン (GameOver, 1) に一致することまで見る。
    @Test
    def testHeadlessDeterministic(): Unit \ Assert =
        let run1 = withSeededRandom(() -> withMockGame(() -> Game.runHeadless(0.1, 16, scenario())));
        let run2 = withSeededRandom(() -> withMockGame(() -> Game.runHeadless(0.1, 16, scenario())));
        let World.World(w1) = run1;
        let World.World(w2) = run2;
        let g1 = (w1#phase == GamePhase.GameOver, w1#score);
        let g2 = (w2#phase == GamePhase.GameOver, w2#score);
        Assert.assertEq(expected = ((true, 1), (true, 1)), (g1, g2))
}
