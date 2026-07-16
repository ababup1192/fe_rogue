// TestPreviewFx — /preview/fx のキャンバス自動決定 (純粋な部分) を固定する。
// 描画そのもの (PNG の中身) は curl + 目視検品に任せ、ここでは
// 「粒がどこまで飛ぶか」の閉形式見積もりだけを見る。
// 一辺 = clamp(128, 2048, ceil(2 × (speedMax × lifeMax × 積分の最大値 + size × sizeOver の最大値)))

mod TestPreviewFx {

    /// 速度・寿命・カーブだけ差し替えられる最小 emitter (他は canvas 計算に効かない値)。
    def emitterOf(speed: {base = Float64, vary = Float64, over = FxDoc.CurveSpec},
                  life: {base = Float64, vary = Float64},
                  size: Float64, sizeOver: FxDoc.CurveSpec): FxDoc.Emitter =
        { name = "e", count = 1, shape = FxDoc.Shape.Circle, size = size,
          color = ({r = 1.0f32, g = 1.0f32, b = 1.0f32}: Color) :: Nil,
          life = life, speed = { base = speed#base, vary = speed#vary, over = speed#over },
          dir = { base = 0.0, spread = 360.0 },
          sizeOver = sizeOver, alphaOver = FxDoc.CurveSpec.Constant,
          blend = DrawCmd.BlendMode.Normal, zIndex = 0 }

    /// 等速 (constant)・vary 無しの emitter (見積もりの基本形)。
    def constEmitter(speedBase: Float64, size: Float64): FxDoc.Emitter =
        emitterOf({ base = speedBase, vary = 0.0, over = FxDoc.CurveSpec.Constant },
                  { base = 1.0, vary = 0.0 }, size, FxDoc.CurveSpec.Constant)

    def specOf(emitters: List[FxDoc.Emitter]): FxDoc.Spec =
        { name = "t", duration = 1.0, note = None, emitters = emitters }

    // ════════════════════════════════════════════════════════
    // designSideOf: 一辺の決定
    // ════════════════════════════════════════════════════════

    /// 等速: 到達 = speed×life×1。一辺 = 2×(200×1×1 + 4) = 408。
    /// 近すぎる粒 (2×(20+3)=46) は最小 128 に、遠すぎる粒 (speed 100000) は上限 2048 に収まる。
    @Test
    def testDesignSideConstantAndClamps(): Unit \ Assert =
        Assert.assertEq(
            expected = (408, 128, 2048),
            (PreviewFx.designSideOf(specOf(constEmitter(200.0, 4.0) :: Nil)),
             PreviewFx.designSideOf(specOf(constEmitter(20.0, 3.0) :: Nil)),
             PreviewFx.designSideOf(specOf(constEmitter(100000.0, 3.0) :: Nil))))

    /// vary は base×(1+vary) の最悪値で見積もる:
    /// speed 100×1.5 × life 1×1.2 = 180 → 一辺 = 2×(180+2) = 364。
    @Test
    def testDesignSideUsesVaryWorstCase(): Unit \ Assert =
        let emitter = emitterOf({ base = 100.0, vary = 0.5, over = FxDoc.CurveSpec.Constant },
                                { base = 1.0, vary = 0.2 }, 2.0, FxDoc.CurveSpec.Constant);
        Assert.assertEq(expected = 364, PreviewFx.designSideOf(specOf(emitter :: Nil)))

    /// 複数 emitter は最遠のものが勝つ (近い方は canvas を縮めない)。
    @Test
    def testDesignSideTakesFarthestEmitter(): Unit \ Assert =
        Assert.assertEq(
            expected = 408,
            PreviewFx.designSideOf(specOf(constEmitter(50.0, 4.0) :: constEmitter(200.0, 4.0) :: Nil)))

    /// sizeOver が 1.0 を超える linear は、膨らんだ粒の径ぶん余白が広がる:
    /// 一辺 = 2×(100 + 10×3) = 260。
    @Test
    def testDesignSideGrowsWithSizeOver(): Unit \ Assert =
        let emitter = emitterOf({ base = 100.0, vary = 0.0, over = FxDoc.CurveSpec.Constant },
                                { base = 1.0, vary = 0.0 }, 10.0,
                                FxDoc.CurveSpec.Linear({ fromV = 1.0, toV = 3.0 }));
        Assert.assertEq(expected = 260, PreviewFx.designSideOf(specOf(emitter :: Nil)))

    // ════════════════════════════════════════════════════════
    // integralPeak: 速度カーブごとの到達距離倍率
    // ════════════════════════════════════════════════════════

    /// 単調カーブの最遠は u=1: constant=1、easeOut(power=3)=1/4、peak=1/2。
    @Test
    def testIntegralPeakMonotone(): Unit \ Assert =
        Assert.assertEq(
            expected = (1.0, 0.25, 0.5),
            (PreviewFx.integralPeak(FxDoc.CurveSpec.Constant),
             PreviewFx.integralPeak(FxDoc.CurveSpec.EaseOut({ power = 3.0 })),
             PreviewFx.integralPeak(FxDoc.CurveSpec.Peak({ at = 0.25 }))))

    /// 行って戻る linear (1 → -1): u=1 では原点に戻る (積分 0) が、
    /// 折り返し点 u=0.5 の往路 1/4 が最遠 — 端点だけ見ると canvas が 0 になってしまう形。
    @Test
    def testIntegralPeakTurningLinear(): Unit \ Assert =
        Assert.assertEq(
            expected = 0.25,
            PreviewFx.integralPeak(FxDoc.CurveSpec.Linear({ fromV = 1.0, toV = -1.0 })))
}
