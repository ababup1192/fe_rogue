/// AnimationPlayer モジュールのテスト
///
/// 検証する観点:
///   - position track の線形補間が正しく scene に書き戻る
///   - alpha track が Sprite2D の alpha に書き戻る
///   - method イベントが指定時刻で発火し drainEvents で取り出せる
///   - finished イベントがアニメーション完了時に発火し drainEvents に乗る
///   - **auto-stop**: owner ノードが scene から消えると tickAll が playback を破棄する
///     （古い playback が再生成された同名ノードに古い座標を書き戻す事故を防ぐ）
///   - drainEvents が呼び出し後にバッファをクリアする
///
/// `withScheduler` は polymorphic 戻り値なので、`run { ... } with AnimationPlayer.withScheduler(rc)`
/// の形で結果を直接取り出せる。

mod TestAnimationPlayer {

    use AnimationPlayer.{Animation, Track, MethodKey, Event, EventBundle,
                          PosKey, AlphaKey, Property}

    // ════════════════════════════════════════════════════════
    // ヘルパー
    // ════════════════════════════════════════════════════════

    /// テスト用に Marker2D を name のノードとして scene に登録する
    /// （子 Sprite を持たない最小ノード。alpha 系は別 helper で組む）
    def sceneWithMarker(name: String, pos: Vec2.Vec2): Scene[NodeTag] =
        let marker = Marker2D.make(pos);
        Scene.empty()
            |> Scene.addNode(name,
                EngineNode.Marker2DWithState(marker, NodeTag.NoTag))

    /// テスト用に Sprite2D を name のノードとして scene に登録する（alpha 補間用）
    def sceneWithSprite(name: String): Scene[NodeTag] =
        let sprite = Sprite2D.make("test", Vec2.zero(), Vec2.one());
        Scene.empty()
            |> Scene.addNode(name,
                EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))

    def nodePath(name: String): NodePath = name :: Nil

    /// Position 2 keyframe (start, end) のシンプルな Animation を作る
    def posAnimation(name: String, target: NodePath, start: Vec2.Vec2,
                      end_: Vec2.Vec2, length: Duration.Duration): Animation =
        let keys: List[PosKey] =
            ({time = 0.0, pos = start}: PosKey) ::
            ({time = 1.0, pos = end_}: PosKey) :: Nil;
        let track: Track = {target = target, prop = Property.Position(keys)};
        {name = name, length = length, tracks = track :: Nil, methods = Nil}

    /// Sprite alpha 2 keyframe の Animation
    def alphaAnimation(name: String, target: NodePath, fromA: Float32,
                        toA: Float32, length: Duration.Duration): Animation =
        let keys: List[AlphaKey] =
            ({time = 0.0, alpha = fromA}: AlphaKey) ::
            ({time = 1.0, alpha = toA}: AlphaKey) :: Nil;
        let track: Track = {target = target, prop = Property.Alpha(keys)};
        {name = name, length = length, tracks = track :: Nil, methods = Nil}

    /// 中点 (length/2) で 1 つの method を発火する Position Animation
    def methodAnimation(name: String, target: NodePath, methodName: String,
                         length: Duration.Duration): Animation =
        let keys: List[PosKey] =
            ({time = 0.0, pos = Vec2.zero()}: PosKey) ::
            ({time = 1.0, pos = Vec2.zero()}: PosKey) :: Nil;
        let track: Track = {target = target, prop = Property.Position(keys)};
        let m: MethodKey = {time = Duration.divBy(length, 2.0), name = methodName};
        {name = name, length = length, tracks = track :: Nil, methods = m :: Nil}

    // ════════════════════════════════════════════════════════
    // 補間: position が tickAll で進む
    // ════════════════════════════════════════════════════════

    /// 0.5 秒で半分進む（duration=1.0、from (0,0) → to (10,0)、t=0.5 → x=5.0）
    @Test
    def testTickAllPositionLerpsHalfway(): Unit \ Assert =
        region rc {
            let result = run {
                let scene = sceneWithMarker("p", Vec2.zero());
                let anim = posAnimation("test", nodePath("p"), Vec2.zero(),
                                         {x = 10.0, y = 0.0}, 1.0 |> Duration.seconds);
                AnimationPlayer.play(nodePath("p"), anim);
                let advanced = AnimationPlayer.tickAll(0.5 |> Duration.seconds, scene);
                Scene.globalPositionAt(nodePath("p"), advanced)
            } with AnimationPlayer.withScheduler(rc);
            Assert.assertEq(expected = (5.0, 0.0), (result#x, result#y))
        }

    /// 完了後は最終値に snap し、isPlaying = false に戻る
    @Test
    def testTickAllPositionSnapsAtCompletion(): Unit \ Assert =
        region rc {
            let result = run {
                let scene = sceneWithMarker("p", Vec2.zero());
                let anim = posAnimation("test", nodePath("p"), Vec2.zero(),
                                         {x = 10.0, y = 0.0}, 0.5 |> Duration.seconds);
                AnimationPlayer.play(nodePath("p"), anim);
                let advanced = AnimationPlayer.tickAll(0.5 |> Duration.seconds, scene);
                let pos = Scene.globalPositionAt(nodePath("p"), advanced);
                let stillPlaying = AnimationPlayer.Scheduler.isPlaying(nodePath("p"));
                (stillPlaying, pos#x, pos#y)
            } with AnimationPlayer.withScheduler(rc);
            Assert.assertEq(expected = (false, 10.0, 0.0), result)
        }

    // ════════════════════════════════════════════════════════
    // alpha 補間: Sprite2D の alpha が tickAll で更新される
    // ════════════════════════════════════════════════════════

    /// Sprite alpha が 0.0 → 1.0 で半分進む
    @Test
    def testTickAllAlphaLerpsHalfway(): Unit \ Assert =
        region rc {
            let result = run {
                let scene = sceneWithSprite("s");
                let anim = alphaAnimation("fade", nodePath("s"), 0.0f32, 1.0f32,
                                           1.0 |> Duration.seconds);
                AnimationPlayer.play(nodePath("s"), anim);
                let advanced = AnimationPlayer.tickAll(0.5 |> Duration.seconds, scene);
                match Scene.getEngineNode(nodePath("s"), advanced) {
                    case Some(EngineNode.Sprite2DWithState(sprite, _)) =>
                        let Sprite2D.Sprite2D(r) = sprite;
                        r#alpha
                    case _ => -1.0f32
                }
            } with AnimationPlayer.withScheduler(rc);
            Assert.assertEq(expected = 0.5f32, result)
        }

    // ════════════════════════════════════════════════════════
    // method イベント: 指定時刻で 1 回だけ発火する
    // ════════════════════════════════════════════════════════

    /// 中点 (length/2) を超えて tick したら method が drainEvents.methods に乗る
    @Test
    def testMethodFiresAfterMidpoint(): Unit \ Assert =
        region rc {
            let result = run {
                let scene = sceneWithMarker("p", Vec2.zero());
                let anim = methodAnimation("a", nodePath("p"), "hit",
                                            1.0 |> Duration.seconds);
                AnimationPlayer.play(nodePath("p"), anim);
                // 0.6 秒進める → 中点 0.5 を超えたので "hit" が発火するはず
                discard AnimationPlayer.tickAll(0.6 |> Duration.seconds, scene);
                let bundle = AnimationPlayer.Scheduler.drainEvents();
                List.length(bundle#methods)
            } with AnimationPlayer.withScheduler(rc);
            Assert.assertEq(expected = 1, result)
        }

    /// 中点に達する前は method はまだ発火していない
    @Test
    def testMethodNotFiredBeforeMidpoint(): Unit \ Assert =
        region rc {
            let result = run {
                let scene = sceneWithMarker("p", Vec2.zero());
                let anim = methodAnimation("a", nodePath("p"), "hit",
                                            1.0 |> Duration.seconds);
                AnimationPlayer.play(nodePath("p"), anim);
                // 0.4 秒（中点 0.5 未満）
                discard AnimationPlayer.tickAll(0.4 |> Duration.seconds, scene);
                let bundle = AnimationPlayer.Scheduler.drainEvents();
                List.length(bundle#methods)
            } with AnimationPlayer.withScheduler(rc);
            Assert.assertEq(expected = 0, result)
        }

    // ════════════════════════════════════════════════════════
    // finished イベント: 完了時に 1 回だけ発火する
    // ════════════════════════════════════════════════════════

    @Test
    def testFinishedEventFiresOnCompletion(): Unit \ Assert =
        region rc {
            let result = run {
                let scene = sceneWithMarker("p", Vec2.zero());
                let anim = posAnimation("done", nodePath("p"), Vec2.zero(),
                                         {x = 1.0, y = 0.0}, 1.0 |> Duration.seconds);
                AnimationPlayer.play(nodePath("p"), anim);
                discard AnimationPlayer.tickAll(1.0 |> Duration.seconds, scene);
                let bundle = AnimationPlayer.Scheduler.drainEvents();
                let names = bundle#finished |> List.map(e -> e#name);
                names
            } with AnimationPlayer.withScheduler(rc);
            Assert.assertEq(expected = "done" :: Nil, result)
        }

    /// drainEvents は呼び出し後にバッファをクリアする
    @Test
    def testDrainEventsClearsBuffer(): Unit \ Assert =
        region rc {
            let result = run {
                let scene = sceneWithMarker("p", Vec2.zero());
                let anim = posAnimation("done", nodePath("p"), Vec2.zero(),
                                         {x = 1.0, y = 0.0}, 1.0 |> Duration.seconds);
                AnimationPlayer.play(nodePath("p"), anim);
                discard AnimationPlayer.tickAll(1.0 |> Duration.seconds, scene);
                discard AnimationPlayer.Scheduler.drainEvents();
                // 2 回目の drain は空のはず
                let second = AnimationPlayer.Scheduler.drainEvents();
                (List.length(second#methods), List.length(second#finished))
            } with AnimationPlayer.withScheduler(rc);
            Assert.assertEq(expected = (0, 0), result)
        }

    // ════════════════════════════════════════════════════════
    // auto-stop: owner ノードが scene から消えると playback も破棄される
    // ════════════════════════════════════════════════════════

    /// owner 削除 → tickAll → activeOwners が空になり、isPlaying も false になる。
    /// この保証により、ゲームオーバーリセットで cancelAll を呼ばなくても
    /// 古い playback が再生成された同名ノードに悪さをすることがない。
    @Test
    def testAutoStopWhenOwnerRemoved(): Unit \ Assert =
        region rc {
            let result = run {
                let scene = sceneWithMarker("p", Vec2.zero());
                let anim = posAnimation("ghost", nodePath("p"), Vec2.zero(),
                                         {x = 100.0, y = 0.0}, 10.0 |> Duration.seconds);
                AnimationPlayer.play(nodePath("p"), anim);
                // owner ノードを scene から削除
                let removed = Scene.removeAt(nodePath("p"), scene);
                // 短い tick → auto-stop が発火するはず（property update は出ないが stop はかかる）
                discard AnimationPlayer.tickAll(0.1 |> Duration.seconds, removed);
                AnimationPlayer.Scheduler.isPlaying(nodePath("p"))
            } with AnimationPlayer.withScheduler(rc);
            Assert.assertEq(expected = false, result)
        }

    /// owner が居る間は通常通り再生継続する（auto-stop は誤発火しない）
    @Test
    def testNoAutoStopWhileOwnerExists(): Unit \ Assert =
        region rc {
            let result = run {
                let scene = sceneWithMarker("p", Vec2.zero());
                let anim = posAnimation("ok", nodePath("p"), Vec2.zero(),
                                         {x = 100.0, y = 0.0}, 10.0 |> Duration.seconds);
                AnimationPlayer.play(nodePath("p"), anim);
                discard AnimationPlayer.tickAll(0.1 |> Duration.seconds, scene);
                AnimationPlayer.Scheduler.isPlaying(nodePath("p"))
            } with AnimationPlayer.withScheduler(rc);
            Assert.assertEq(expected = true, result)
        }

    // ════════════════════════════════════════════════════════
    // 同 owner 再生 → 旧 playback を置換
    // ════════════════════════════════════════════════════════

    /// 同じ owner で play すると古い playback は破棄される（Godot 同様）
    @Test
    def testSameOwnerReplayReplacesOld(): Unit \ Assert =
        region rc {
            let result = run {
                let scene = sceneWithMarker("p", Vec2.zero());
                let anim1 = posAnimation("a1", nodePath("p"), Vec2.zero(),
                                          {x = 100.0, y = 0.0}, 1.0 |> Duration.seconds);
                let anim2 = posAnimation("a2", nodePath("p"), Vec2.zero(),
                                          {x = 0.0, y = 50.0}, 1.0 |> Duration.seconds);
                AnimationPlayer.play(nodePath("p"), anim1);
                AnimationPlayer.play(nodePath("p"), anim2);
                // 1.0 秒進めると anim2 が完了。anim1 は置換されてるので走らない
                let advanced = AnimationPlayer.tickAll(1.0 |> Duration.seconds, scene);
                let pos = Scene.globalPositionAt(nodePath("p"), advanced);
                let bundle = AnimationPlayer.Scheduler.drainEvents();
                let finishedNames = bundle#finished |> List.map(e -> e#name);
                (pos#x, pos#y, finishedNames)
            } with AnimationPlayer.withScheduler(rc);
            Assert.assertEq(expected = (0.0, 50.0, "a2" :: Nil), result)
        }

    // ════════════════════════════════════════════════════════
    // cancelAll: 全 playback と未配送イベントを破棄する
    // ════════════════════════════════════════════════════════

    /// cancelAll の後は isPlaying = false、drainEvents も空
    @Test
    def testCancelAllStopsEverything(): Unit \ Assert =
        region rc {
            let result = run {
                let scene = sceneWithMarker("p", Vec2.zero());
                let anim = posAnimation("a", nodePath("p"), Vec2.zero(),
                                         {x = 1.0, y = 0.0}, 1.0 |> Duration.seconds);
                AnimationPlayer.play(nodePath("p"), anim);
                discard AnimationPlayer.tickAll(1.0 |> Duration.seconds, scene);
                AnimationPlayer.Scheduler.cancelAll();
                let stillPlaying = AnimationPlayer.Scheduler.isPlaying(nodePath("p"));
                let bundle = AnimationPlayer.Scheduler.drainEvents();
                (stillPlaying, List.length(bundle#methods),
                                  List.length(bundle#finished))
            } with AnimationPlayer.withScheduler(rc);
            Assert.assertEq(expected = (false, 0, 0), result)
        }
}
