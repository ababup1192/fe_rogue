// TestFxBurst — Fx の burst 管理 3 点セット（burst / expire / drawAll）と sampleAt、
// FxDoc.empty を固定する。Item は Eq を持たないので、置き場所 (at) の実値で比べる。
// ばらつきゼロ・等速・真右向きの emitter で、平行移動の足し算がそのまま数値に出るようにする。
mod TestFxBurst {

    // ── 道具 ──

    def white(): Color = { r = 1.0f32, g = 1.0f32, b = 1.0f32 }

    /// ばらつきゼロの基準 emitter。等速 10px/s・dir 90 度 = 真右（0 度が真上・時計回り）。
    /// t 秒後の粒の中心は (10t, 0)、円（直径 2）の置き場所は左上なので (10t - 1, -1)。
    def baseEmitter(): FxDoc.Emitter =
        { name = "sparks", count = 4, shape = FxDoc.Shape.Circle, size = 2.0,
          color = white() :: Nil,
          life = { base = 1.0, vary = 0.0 },
          speed = { base = 10.0, vary = 0.0, over = FxDoc.CurveSpec.Constant },
          dir = { base = 90.0, spread = 0.0 },
          sizeOver = FxDoc.CurveSpec.Constant, alphaOver = FxDoc.CurveSpec.Constant,
          blend = DrawCmd.BlendMode.Normal, zIndex = 3 }

    /// duration を選べる 1 emitter の spec（寿命回収の題材）。
    def specOf(duration: Float64): FxDoc.Spec =
        { name = "test", duration = duration, note = None, emitters = baseEmitter() :: Nil }

    /// 置き場所だけの射影。
    def ats(items: List[Render.PlacedItem]): List[(Float64, Float64)] =
        List.map(p -> (p#at#x, p#at#y), items)

    // ════════════════════════════════════════════════════════
    // burst（発生）
    // ════════════════════════════════════════════════════════

    /// burst はゲームの Int32 通し番号をそのまま種にできる（Int64 化は burst が済ませる）。
    /// 発生の 4 値（種・位置・生まれた時刻）がそのまま器に入る。
    @Test
    def testBurstKeepsFields(): Unit \ Assert =
        let b = Fx.burst(specOf(1.0), 5, { x = 1.0, y = 2.0 }, 3.0);
        Assert.assertEq(expected = (5i64, 1.0, 2.0, 3.0), (b#seed, b#at#x, b#at#y, b#bornAt))

    // ════════════════════════════════════════════════════════
    // expire（寿命回収）
    // ════════════════════════════════════════════════════════

    /// 寿命内は残り、duration を過ぎたら消える。境界「経過 = duration」は
    /// sample がまだ絵を出す側なので、器も残る。
    ///
    ///   bornAt=2.0 ──────────── 3.0(=duration 後) ──→
    ///        now=2.5: 残る    now=3.0: 残る    now=3.01: 消える
    @Test
    def testExpireBoundary(): Unit \ Assert =
        let bursts = Fx.burst(specOf(1.0), 7, { x = 0.0, y = 0.0 }, 2.0) :: Nil;
        Assert.assertEq(expected = (1, 1, 0),
            (List.length(Fx.expire(2.5, bursts)),
             List.length(Fx.expire(3.0, bursts)),
             List.length(Fx.expire(3.01, bursts))))

    /// 複数 spec 混在: 寿命は各 burst が値で持つ spec の duration で個別に判定される。
    /// now=1.0 では duration 0.5 の方だけ消え、duration 2.0 の方（seed 2）が残る。
    @Test
    def testExpireMixedDurations(): Unit \ Assert =
        let bursts = Fx.burst(specOf(0.5), 1, { x = 0.0, y = 0.0 }, 0.0)
                  :: Fx.burst(specOf(2.0), 2, { x = 0.0, y = 0.0 }, 0.0) :: Nil;
        Assert.assertEq(expected = (2, 2i64 :: Nil, 0),
            (List.length(Fx.expire(0.4, bursts)),
             List.map(b -> b#seed, Fx.expire(1.0, bursts)),
             List.length(Fx.expire(2.5, bursts))))

    // ════════════════════════════════════════════════════════
    // sampleAt / drawAll（平行移動）
    // ════════════════════════════════════════════════════════

    /// sampleAt: 原点生まれの絵（0.3 秒 × 10px/s = 中心 (3, 0)・円の左上 (2, -1)）を
    /// (7, -2) へ平行移動 → (9, -3) が粒数ぶん並ぶ。
    @Test
    def testSampleAtTranslates(): Unit \ Assert =
        Assert.assertEq(expected = List.repeat(4, (9.0, -3.0)),
            ats(Fx.sampleAt(specOf(1.0), 9i64, 0.3, { x = 7.0, y = -2.0 })))

    /// sampleAt は「sample + 各 at への足し算」と完全に一致する（絵の中身は変えない）。
    @Test
    def testSampleAtMatchesSamplePlusOffset(): Unit \ Assert =
        let spec = specOf(1.0);
        Assert.assertEq(
            expected = List.map(xy -> { let (x, y) = xy; (x + 7.0, y - 2.0) },
                                ats(Fx.sample(spec, 9i64, 0.3))),
            ats(Fx.sampleAt(spec, 9i64, 0.3, { x = 7.0, y = -2.0 })))

    /// drawAll: 生後 0.5 秒（now 1.5 - bornAt 1.0）の絵（円の左上 (4, -1)）を
    /// 発生位置 (100, 50) へ平行移動した (104, 49) が粒数ぶん並ぶ。
    @Test
    def testDrawAllTranslates(): Unit \ Assert =
        let bursts = Fx.burst(specOf(1.0), 0, { x = 100.0, y = 50.0 }, 1.0) :: Nil;
        Assert.assertEq(expected = List.repeat(4, (104.0, 49.0)), ats(Fx.drawAll(1.5, bursts)))

    /// 複数 burst: 絵はそれぞれの生まれた時刻からの経過で出る。now=1.5 で
    /// bornAt=0.0 の方は経過 1.5 > duration 1.0 なので絵ゼロ（expire 前でも安全）、
    /// bornAt=1.0 の方は経過 0.5 の絵が (10, 0) 起点で出る。
    @Test
    def testDrawAllPerBurstClock(): Unit \ Assert =
        let bursts = Fx.burst(specOf(1.0), 0, { x = 0.0, y = 0.0 }, 0.0)
                  :: Fx.burst(specOf(1.0), 0, { x = 10.0, y = 0.0 }, 1.0) :: Nil;
        Assert.assertEq(expected = List.repeat(4, (14.0, -1.0)), ats(Fx.drawAll(1.5, bursts)))

    // ════════════════════════════════════════════════════════
    // FxDoc.empty（何も出さない spec）
    // ════════════════════════════════════════════════════════

    /// 空の spec は t=0 でも粒 0（sample も sampleAt も空）。
    @Test
    def testEmptySpecSamplesNothing(): Unit \ Assert =
        Assert.assertEq(expected = (0, 0),
            (List.length(Fx.sample(FxDoc.empty(), 0i64, 0.0)),
             List.length(Fx.sampleAt(FxDoc.empty(), 0i64, 0.0, { x = 5.0, y = 5.0 }))))

    /// 空の spec の burst は duration 0 なので、生まれた瞬間を過ぎたら expire が即回収する。
    @Test
    def testEmptyBurstExpiresImmediately(): Unit \ Assert =
        let bursts = Fx.burst(FxDoc.empty(), 0, { x = 0.0, y = 0.0 }, 1.0) :: Nil;
        Assert.assertEq(expected = (1, 0),
            (List.length(Fx.expire(1.0, bursts)),
             List.length(Fx.expire(1.01, bursts))))
}
