// Tween モジュールの単体テスト
//
// 検証する観点:
//   - tweenPosition でスケジュールした entry が tickAll で advance されること
//   - 進行中は isActive が true、duration 経過後（snap）で false に戻ること
//   - 同パス再登録で古い tween が置換されること
//   - cancel で entry が即除去されること
//   - target Node が scene に無い場合、tickAll が auto-stop すること（Godot の Node バインド相当）
//
// `withScheduler` は polymorphic 戻り値なので、`run { ... } with Tween.withScheduler(rc)` の
// 形で結果を取り出せる。

mod TestTween {

    // ========================================================================
    // ヘルパー
    // ========================================================================

    /// テスト用に CharacterBody2D を name のノードとして scene に登録する
    def sceneWithBody(name: String, pos: Vec2.Vec2): Scene[NodeTag] =
        let body = CharacterBody2D.make(pos, {moveSpeed = 0.0});
        Scene.empty()
            |> Scene.addNode(name,
                EngineNode.Body2DWithState(body, NodeTag.NoTag))

    /// path 文字列 1 段だけの NodePath
    def nodePath(name: String): NodePath = name :: Nil

    /// path のノードのワールド座標
    def posOf(path: NodePath, scene: Scene[NodeTag]): Vec2.Vec2 =
        Scene.globalPositionAt(path, scene)

    // ========================================================================
    // tickAll で線形補間が進む
    // ========================================================================

    /// 0.5 秒で半分進む（duration=1.0、from (0,0) → to (10,0)、t=0.5 → x=5.0）
    @Test
    def testTickAllLerpsHalfway(): Unit \ Assert =
        region rc {
            let result = run {
                let scene = sceneWithBody("p", Vec2.zero());
                Tween.tweenPosition(nodePath("p"),
                    Vec2.zero(), {x = 10.0, y = 0.0}, 1.0 |> Duration.seconds);
                let advanced = Tween.tickAll(0.5 |> Duration.seconds, scene);
                let pos = posOf(nodePath("p"), advanced);
                let active = Tween.Scheduler.isActive(nodePath("p"));
                (active, pos#x, pos#y)
            } with Tween.withScheduler(rc);
            Assert.assertEq(expected = (true, 5.0, 0.0), result)
        }

    /// duration 経過後は snap して isActive = false に戻る
    @Test
    def testTickAllSnapsAtCompletion(): Unit \ Assert =
        region rc {
            let result = run {
                let scene = sceneWithBody("p", Vec2.zero());
                Tween.tweenPosition(nodePath("p"),
                    Vec2.zero(), {x = 10.0, y = 0.0}, 0.5 |> Duration.seconds);
                // 0.5 秒経過 → 完了
                let advanced = Tween.tickAll(0.5 |> Duration.seconds, scene);
                let pos = posOf(nodePath("p"), advanced);
                let active = Tween.Scheduler.isActive(nodePath("p"));
                (active, pos#x, pos#y)
            } with Tween.withScheduler(rc);
            Assert.assertEq(expected = (false, 10.0, 0.0), result)
        }

    /// duration を超える delta でも overshoot せず target に snap する
    @Test
    def testTickAllSnapsAtOvershoot(): Unit \ Assert =
        region rc {
            let result = run {
                let scene = sceneWithBody("p", Vec2.zero());
                Tween.tweenPosition(nodePath("p"),
                    Vec2.zero(), {x = 10.0, y = 0.0}, 0.5 |> Duration.seconds);
                // 10.0 秒（duration の 20 倍）でも target で止まる
                let advanced = Tween.tickAll(10.0 |> Duration.seconds, scene);
                let pos = posOf(nodePath("p"), advanced);
                let active = Tween.Scheduler.isActive(nodePath("p"));
                (active, pos#x, pos#y)
            } with Tween.withScheduler(rc);
            Assert.assertEq(expected = (false, 10.0, 0.0), result)
        }

    // ========================================================================
    // isActive — スケジュール状態の問い合わせ
    // ========================================================================

    /// 初期状態は isActive = false
    @Test
    def testIsActiveFalseInitially(): Unit \ Assert =
        region rc {
            let result = run {
                Tween.Scheduler.isActive(nodePath("p"))
            } with Tween.withScheduler(rc);
            Assert.assertEq(expected = false, result)
        }

    /// schedule 後は isActive = true
    @Test
    def testIsActiveTrueAfterSchedule(): Unit \ Assert =
        region rc {
            let result = run {
                Tween.tweenPosition(nodePath("p"),
                    Vec2.zero(), {x = 10.0, y = 0.0}, 1.0 |> Duration.seconds);
                Tween.Scheduler.isActive(nodePath("p"))
            } with Tween.withScheduler(rc);
            Assert.assertEq(expected = true, result)
        }

    // ========================================================================
    // 同パス再登録による置換（Godot 同様）
    // ========================================================================

    /// 同じ path に再登録すると古い tween が置換される（最新のターゲットへ向かう）
    @Test
    def testReregisterReplacesOldTween(): Unit \ Assert =
        region rc {
            let result = run {
                let scene = sceneWithBody("p", Vec2.zero());
                Tween.tweenPosition(nodePath("p"),
                    Vec2.zero(), {x = 10.0, y = 0.0}, 1.0 |> Duration.seconds);
                // 違う target で再登録
                Tween.tweenPosition(nodePath("p"),
                    Vec2.zero(), {x = 0.0, y = 20.0}, 1.0 |> Duration.seconds);
                // 1.0 秒で 2 つ目の tween が完了するはず（古い tween は置換されたので走らない）
                let advanced = Tween.tickAll(1.0 |> Duration.seconds, scene);
                let pos = posOf(nodePath("p"), advanced);
                (pos#x, pos#y)
            } with Tween.withScheduler(rc);
            Assert.assertEq(expected = (0.0, 20.0), result)
        }

    // ========================================================================
    // cancel — 進行中の tween を即除去
    // ========================================================================

    /// cancel 後は isActive = false、tickAll しても動かない
    @Test
    def testCancelRemovesTween(): Unit \ Assert =
        region rc {
            let result = run {
                let scene = sceneWithBody("p", Vec2.zero());
                Tween.tweenPosition(nodePath("p"),
                    Vec2.zero(), {x = 10.0, y = 0.0}, 1.0 |> Duration.seconds);
                Tween.Scheduler.cancel(nodePath("p"));
                let advanced = Tween.tickAll(0.5 |> Duration.seconds, scene);
                let pos = posOf(nodePath("p"), advanced);
                let active = Tween.Scheduler.isActive(nodePath("p"));
                (active, pos#x, pos#y)
            } with Tween.withScheduler(rc);
            Assert.assertEq(expected = (false, 0.0, 0.0), result)
        }

    // ========================================================================
    // auto-stop — target Node が scene から消えたら tween を破棄（Godot の Node バインド）
    // ========================================================================

    /// scene に存在しない path への tween は tickAll で auto-cancel される
    @Test
    def testAutoStopForMissingTarget(): Unit \ Assert =
        region rc {
            let result = run {
                // scene には node "p" を入れない
                let scene = Scene.empty();
                Tween.tweenPosition(nodePath("ghost"),
                    Vec2.zero(), {x = 10.0, y = 0.0}, 1.0 |> Duration.seconds);
                let _ = Tween.tickAll(0.5 |> Duration.seconds, scene);
                // tickAll 後に entry が消えているはず
                Tween.Scheduler.isActive(nodePath("ghost"))
            } with Tween.withScheduler(rc);
            Assert.assertEq(expected = false, result)
        }

    // ========================================================================
    // 複数 tween の並列進行
    // ========================================================================

    /// 異なる path の 2 つの tween は同時並行で進む
    @Test
    def testMultipleTweensInParallel(): Unit \ Assert =
        region rc {
            let result = run {
                let scene = sceneWithBody("a", Vec2.zero())
                    |> Scene.addNode("b",
                        EngineNode.Body2DWithState(
                            CharacterBody2D.make(Vec2.zero(), {moveSpeed = 0.0}),
                            NodeTag.NoTag));
                Tween.tweenPosition(nodePath("a"),
                    Vec2.zero(), {x = 10.0, y = 0.0}, 1.0 |> Duration.seconds);
                Tween.tweenPosition(nodePath("b"),
                    Vec2.zero(), {x = 0.0, y = 20.0}, 1.0 |> Duration.seconds);
                let advanced = Tween.tickAll(0.5 |> Duration.seconds, scene);
                let posA = posOf(nodePath("a"), advanced);
                let posB = posOf(nodePath("b"), advanced);
                (posA#x, posA#y, posB#x, posB#y)
            } with Tween.withScheduler(rc);
            Assert.assertEq(expected = (5.0, 0.0, 0.0, 10.0), result)
        }
}
