// 駒の描画位置 tween（World.moveUnit → World.stepWorld → World.renderPosOf）の単体テスト。
//
// 駒の見た目位置は World が唯一の権威で、`World.moveUnit` が (entity, Channel.Position) の
// tween を開始し、`World.stepWorld` が dt 秒ぶん進め、`World.renderPosOf` が現在の補間位置を返す。
// `World.isAnimating` は当該 (entity, channel) が進行中かの入力ゲート。
//
// 検証する観点:
//   - moveUnit は renderPos を span の start へ即座にスナップし、isAnimating を true にする
//   - tween を持たない entity は isAnimating が false
//   - stepWorld は duration を超える dt でも overshoot せず target に snap する
//   - 同一 (entity, channel) への再 moveUnit は進行中の tween を置換する
//   - 別 entity の tween は互いに独立して進む
//
// 補間の基本性質（半分で lerp・ちょうど duration で snap）は
// `test/ecs/TestWorld.flix` の `testStepWorldReportsMovedThroughCompletion` と
// `engine_world/test/TestEcsTween.flix` が担保するため、ここでは重複させない。
// cancel と「対象が scene から消えたら自動停止」は、EcsTween が (entity, channel) キーの
// Map だけを持ち cancel 操作も entity 存在チェックも持たない設計のため、対応する検証は無い。
mod TestTween {

    /// (startX,startY)→(targetX,targetY) の VecLerp。
    def span(startX: Float64, startY: Float64, targetX: Float64, targetY: Float64): EcsTween.VecLerp =
        {start = {x = startX, y = startY}, target = {x = targetX, y = targetY}}

    /// `w0` に対して `ref` への moveUnit を 1 回発行した後の World を返す（region は呼び出し側で開く）。
    def afterMoveUnit(rc: Region[r], w0: World, ref: World.EntityRef,
                       vl: EcsTween.VecLerp, sec: Float64): World \ r =
        let wref = Ref.fresh(rc, w0);
        run { World.moveUnit(ref, vl, sec) }
            with handler World.Command {
                def emit(c, k) = { Ref.put(World.applyCmd(c, Ref.get(wref)), wref); k() }
            };
        Ref.get(wref)

    /// renderPos を (x, y) タプルで読む。
    def renderPosT(ref: World.EntityRef, w: World): Option[(Float64, Float64)] =
        World.renderPosOf(ref, w) |> Option.map(p -> (p#x, p#y))

    // ========================================================================
    // moveUnit — 発行直後に renderPos を start へスナップし isAnimating を立てる
    // ========================================================================

    @Test
    def testMoveUnitSnapsRenderPosToSpanStartAndMarksAnimating(): Unit \ Assert =
        region rc {
            let ref = World.EntityRef.Player(0);
            let w   = afterMoveUnit(rc, World.empty(), ref, span(0.0, 0.0, 10.0, 0.0), 1.0);
            Assert.assertEq(
                expected = (Some((0.0, 0.0)), true),
                (renderPosT(ref, w), World.isAnimating(ref, w)))
        }

    // ========================================================================
    // isAnimating — tween を持たない entity は false
    // ========================================================================

    @Test
    def testIsAnimatingFalseWhenNoTweenScheduled(): Unit \ Assert =
        Assert.assertEq(expected = false, World.isAnimating(World.EntityRef.Player(0), World.empty()))

    // ========================================================================
    // stepWorld — duration を超える dt でも overshoot せず target に snap する
    // ========================================================================

    @Test
    def testStepWorldSnapsAtOvershootAfterMoveUnit(): Unit \ Assert =
        region rc {
            let ref = World.EntityRef.Enemy(0);
            let w0  = afterMoveUnit(rc, World.empty(), ref, span(0.0, 0.0, 10.0, 0.0), 0.5);
            // duration (0.5s) の 20 倍の dt でも target で止まる。
            let (w1, _) = World.stepWorld(w0, 10.0);
            Assert.assertEq(
                expected = (Some((10.0, 0.0)), false),
                (renderPosT(ref, w1), World.isAnimating(ref, w1)))
        }

    // ========================================================================
    // moveUnit の再登録 — 同一 (entity, channel) は古い tween を置換する
    // ========================================================================

    @Test
    def testMoveUnitReregisterReplacesInFlightTween(): Unit \ Assert =
        region rc {
            let ref = World.EntityRef.Player(0);
            let w1  = afterMoveUnit(rc, World.empty(), ref, span(0.0, 0.0, 10.0, 0.0), 1.0);
            // 違う target で再登録（古い tween は置換され、新しい target だけへ進む）。
            let w2  = afterMoveUnit(rc, w1, ref, span(0.0, 0.0, 0.0, 20.0), 1.0);
            let (w3, _) = World.stepWorld(w2, 1.0);
            Assert.assertEq(expected = Some((0.0, 20.0)), renderPosT(ref, w3))
        }

    // ========================================================================
    // 複数 entity の tween は互いに独立して進む
    // ========================================================================

    @Test
    def testMoveUnitTweensMultipleEntitiesIndependently(): Unit \ Assert =
        region rc {
            let a  = World.EntityRef.Player(0);
            let b  = World.EntityRef.Enemy(1);
            let w1 = afterMoveUnit(rc, World.empty(), a, span(0.0, 0.0, 10.0, 0.0), 1.0);
            let w2 = afterMoveUnit(rc, w1, b, span(0.0, 0.0, 0.0, 20.0), 1.0);
            let (w3, _) = World.stepWorld(w2, 0.5);
            Assert.assertEq(
                expected = (Some((5.0, 0.0)), Some((0.0, 10.0))),
                (renderPosT(a, w3), renderPosT(b, w3)))
        }
}
