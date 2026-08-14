// TestFxSample — Fx.sample（fx.json の閉形式サンプリング）を固定する。
// Item は Eq を持たないので、Render.draw で Drawable に落としてタプルに射影して比べる。
// ばらつきを消した spec（vary=0）で位置の式そのものを数値で pin する。
mod TestFxSample {

    // ── 道具 ──

    def white(): Color = { r = 1.0, g = 1.0, b = 1.0 }
    def black(): Color = { r = 0.0, g = 0.0, b = 0.0 }

    /// ばらつきゼロの基準 emitter（全粒が同じ姿 = 式の検算がしやすい）。
    /// dir 90 度 = 真右（0 度が真上・時計回り）。
    def baseEmitter(): FxDoc.Emitter =
        { name = "sparks", count = 4, shape = FxDoc.Shape.Circle, size = 2.0,
          color = white() :: Nil,
          life = { base = 1.0, vary = 0.0 },
          speed = { base = 10.0, vary = 0.0, over = FxDoc.CurveSpec.Constant },
          dir = { base = 90.0, spread = 0.0, mode = FxDoc.DirMode.Random },
          turn = { base = 0.0, spread = 0.0, spin = 0.0, spinSpread = 0.0 },
          mode = FxDoc.Mode.Burst, spawnArea = { w = 0.0, h = 0.0 }, accel = Vec2.zero(),
          wobble = { amp = Vec2.zero(), freq = Vec2.zero(), vary = 0.0 }, stretch = 0.05, seed = 0,
          sizeOver = FxDoc.CurveSpec.Constant, alphaOver = FxDoc.CurveSpec.Constant,
          blend = DrawCmd.BlendMode.Normal, zIndex = 3 }

    def specOf(emitter: FxDoc.Emitter): FxDoc.Spec =
        { name = "test", duration = 1.0, note = None, emitters = emitter :: Nil }

    /// 置き場所だけの射影。
    def ats(items: List[Render.PlacedItem]): List[(Float64, Float64)] =
        List.map(p -> (p#at#x, p#at#y), items)

    /// Drawable へ落として (位置, サイズ, 色, alpha, blend, zIndex) に射影（絵の全属性の指紋）。
    def fingerprints(items: List[Render.PlacedItem]):
            List[(Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64, String, Int32)] =
        let (drawables, _) = Render.draw(items);
        List.map(d -> (d#position#x, d#position#y, d#scale#x, d#scale#y,
                       d#color#r, d#color#g, d#color#b, d#alpha,
                       match d#blend { case DrawCmd.BlendMode.Normal => "normal" case DrawCmd.BlendMode.Add => "add" case DrawCmd.BlendMode.Multiply => "multiply" },
                       d#zIndex), drawables)

    // ════════════════════════════════════════════════════════
    // 決定論
    // ════════════════════════════════════════════════════════

    /// 同じ (spec, seed, t) は絵の全属性まで完全一致（保存ゼロでも巻き戻しで揺れない土台）。
    @Test
    def testDeterministic(): Unit \ Assert =
        let em = { life = { base = 0.5, vary = 0.2 }, speed = { base = 140.0, vary = 0.3, over = FxDoc.CurveSpec.EaseOut({ power = 2.4 }) },
                   dir = { base = 0.0, spread = 360.0, mode = FxDoc.DirMode.Random } | baseEmitter() };
        Assert.assertEq(
            expected = fingerprints(Fx.sample(specOf(em), 7i64, 0.3)),
            fingerprints(Fx.sample(specOf(em), 7i64, 0.3)))

    /// seed が違えば別の姿（撃つたびに表情が変わる）。
    @Test
    def testSeedChangesShape(): Unit \ Assert =
        let em = { dir = { base = 0.0, spread = 360.0, mode = FxDoc.DirMode.Random },
                   speed = { base = 100.0, vary = 0.5, over = FxDoc.CurveSpec.Constant } | baseEmitter() };
        Assert.assertEq(expected = false,
            ats(Fx.sample(specOf(em), 1i64, 0.3)) == ats(Fx.sample(specOf(em), 2i64, 0.3)))

    // ════════════════════════════════════════════════════════
    // 位置の式（閉形式の積分）を数値で pin
    // ════════════════════════════════════════════════════════

    /// 等速（constant）: 移動距離 = speed × t。t=0.5 で真右 (5, 0)。
    /// circle の置き場所は外接正方形の左上なので (5-r, 0-r) = (4, -1) が 4 粒ぶん並ぶ。
    ///
    ///   原点 ●───────→ ○ (5,0)   ← dir 90 度 = 真右
    @Test
    def testConstantSpeedPosition(): Unit \ Assert =
        Assert.assertEq(
            expected = List.repeat(4, (4.0, -1.0)),
            ats(Fx.sample(specOf(baseEmitter()), 0i64, 0.5)))

    /// easeOut(power=1) の速度カーブ (1-u): 距離 = speed × life × (1-(1-u)²)/2。
    /// u=0.5 → 10 × 0.375 = 3.75。前半で距離の 3/4 を稼ぐ = 減速が式に出る。
    @Test
    def testEaseOutIntegralPosition(): Unit \ Assert =
        let em = { speed = { base = 10.0, vary = 0.0, over = FxDoc.CurveSpec.EaseOut({ power = 1.0 }) } | baseEmitter() };
        Assert.assertEq(
            expected = List.repeat(4, (3.75 - 1.0, -1.0)),
            ats(Fx.sample(specOf(em), 0i64, 0.5)))

    /// 減速の性質: 同じ時間幅でも後半の伸びは前半より小さい（easeOut = 速く出て弱まる）。
    @Test
    def testEaseOutDecelerates(): Unit \ Assert =
        let em = { speed = { base = 100.0, vary = 0.0, over = FxDoc.CurveSpec.EaseOut({ power = 2.4 }) } | baseEmitter() };
        let xAt = (t: Float64) -> Fx.sample(specOf(em), 0i64, t) |> ats |> List.head
            |> Option.map(fst) |> Option.getWithDefault(-999.0);
        let firstHalf = xAt(0.5) - xAt(0.0);
        let secondHalf = xAt(0.99) - xAt(0.5);
        Assert.assertEq(expected = true, firstHalf > secondHalf and secondHalf >= 0.0)

    // ════════════════════════════════════════════════════════
    // 寿命と duration
    // ════════════════════════════════════════════════════════

    /// t=0 は全粒生存（count ぶん出る）・寿命 1.0 に達した粒は消える・duration 超えは空。
    @Test
    def testLifeAndDuration(): Unit \ Assert =
        let spec = specOf(baseEmitter());
        Assert.assertEq(expected = (4, 0, 0, 0),
            (List.length(Fx.sample(spec, 0i64, 0.0)),
             List.length(Fx.sample(spec, 0i64, 1.0)),
             List.length(Fx.sample(spec, 0i64, 1.5)),
             List.length(Fx.sample(spec, 0i64, -0.1))))

    /// life の vary: ばらつかせると寿命の途中で粒数が減っていく（全滅ではなく個別に消える）。
    @Test
    def testVariedLifeThinsOut(): Unit \ Assert =
        let em = { count = 32, life = { base = 0.5, vary = 0.5 } | baseEmitter() };
        let alive = (t: Float64) -> List.length(Fx.sample(specOf(em), 5i64, t));
        // 0.26 秒は最短寿命 0.25 を過ぎている → 何粒かは消え、何粒かは残る。
        Assert.assertEq(expected = (32, true),
            (alive(0.0), alive(0.26) < 32 and alive(0.26) > 0))

    // ════════════════════════════════════════════════════════
    // 見た目の属性（サイズ・alpha・色・blend・zIndex）
    // ════════════════════════════════════════════════════════

    /// sizeOver=peak(at=0.25): u=0 は大きさ 0 で描かれない。u=0.25 で満尺 = 直径 size。
    @Test
    def testSizeOverPeak(): Unit \ Assert =
        let em = { size = 3.0, sizeOver = FxDoc.CurveSpec.Peak({ at = 0.25 }) | baseEmitter() };
        let scaleAt = (t: Float64) -> fingerprints(Fx.sample(specOf(em), 0i64, t)) |> List.head
            |> Option.map(fp -> { let (_, _, sx, sy, _, _, _, _, _, _) = fp; (sx, sy) });
        Assert.assertEq(expected = (0, Some((3.0, 3.0))),
            (List.length(Fx.sample(specOf(em), 0i64, 0.0)), scaleAt(0.25)))

    /// alphaOver=fadeOut(=linear 1→0): u=0.5 で alpha 0.5。blend=add と zIndex も Drawable へ届く。
    @Test
    def testAlphaBlendZIndexPropagate(): Unit \ Assert =
        let em = { alphaOver = FxDoc.CurveSpec.Linear({ fromV = 1.0, toV = 0.0 }),
                   blend = DrawCmd.BlendMode.Add | baseEmitter() };
        let got = fingerprints(Fx.sample(specOf(em), 0i64, 0.5)) |> List.head
            |> Option.map(fp -> { let (_, _, _, _, _, _, _, a, blend, z) = fp; (a, blend, z) });
        Assert.assertEq(expected = Some((0.5, "add", 3)), got)

    /// 色グラデ: 黒 → 白 の 2 色は u=0.5 でちょうど灰色 (0.5, 0.5, 0.5)。
    @Test
    def testColorGradientMidpoint(): Unit \ Assert =
        let em = { color = black() :: white() :: Nil | baseEmitter() };
        let got = fingerprints(Fx.sample(specOf(em), 0i64, 0.5)) |> List.head
            |> Option.map(fp -> { let (_, _, _, _, r, g, b, _, _, _) = fp; (r, g, b) });
        Assert.assertEq(expected = Some((0.5, 0.5, 0.5)), got)

    /// box 形: 一辺 size の正方形 Drawable（scale = (size, size)）。中心置き → 左上 (5-1, 0-1)。
    @Test
    def testBoxShape(): Unit \ Assert =
        let em = { shape = FxDoc.Shape.Box | baseEmitter() };
        let got = fingerprints(Fx.sample(specOf(em), 0i64, 0.5)) |> List.head
            |> Option.map(fp -> { let (x, y, sx, sy, _, _, _, _, _, _) = fp; (x, y, sx, sy) });
        Assert.assertEq(expected = Some((4.0, -1.0, 2.0, 2.0)), got)

    /// glow 形: 1 粒が同心円の重ねになる。外側の輪は circle と同じ置き場所・同じ大きさ
    /// （中心置き → 左上 (5-1, 0-1)・直径 = size）で、内へ向かって半径が等分に縮む。
    /// alpha は縁（外の輪）ほど薄く中心ほど濃い — ふわっとした減衰の向きを固定する。
    ///
    ///   ┌───────┐← 半径 1.0 の輪（circle と同じ外形・いちばん薄い）
    ///   │ ◎◎◎ │   内側ほど小さく濃い輪が重なる（半径 0.75, 0.5, 0.25）
    ///   └───────┘
    @Test
    def testGlowShape(): Unit \ Assert =
        let em = { count = 1, shape = FxDoc.Shape.Glow | baseEmitter() };
        let fps = fingerprints(Fx.sample(specOf(em), 0i64, 0.5));
        let posSizes = List.map(fp -> { let (x, y, sx, sy, _, _, _, _, _, _) = fp; (x, y, sx, sy) }, fps);
        let alphas = List.map(fp -> { let (_, _, _, _, _, _, _, a, _, _) = fp; a }, fps);
        let increasing = List.zip(alphas, List.drop(1, alphas))
            |> List.forAll(pair -> { let (outer, inner) = pair; outer < inner });
        Assert.assertEq(
            expected = ((4.0, -1.0, 2.0, 2.0) :: (4.25, -0.75, 1.5, 1.5)
                        :: (4.5, -0.5, 1.0, 1.0) :: (4.75, -0.25, 0.5, 0.5) :: Nil, true),
            (posSizes, increasing))

    /// parse → sample の通し: 相談で承認した explosion スペックが t=0.15 で絵を出す。
    @Test
    def testParsedExplosionSamples(): Unit \ Assert =
        let doc = "{ \"name\": \"explosion\", \"duration\": 0.9, \"emitters\": ["
            + " { \"name\": \"sparks\", \"count\": 20, \"shape\": \"circle\", \"size\": 3,"
            + " \"color\": [\"#fff7c0\", \"#ff8a3d\", \"#69323a\"],"
            + " \"life\": { \"base\": 0.5, \"vary\": 0.2 },"
            + " \"speed\": { \"base\": 140, \"vary\": 0.3, \"over\": {\"kind\": \"easeOut\", \"power\": 2.4} },"
            + " \"dir\": { \"base\": 0, \"spread\": 360 },"
            + " \"sizeOver\": {\"kind\": \"peak\", \"at\": 0.25},"
            + " \"alphaOver\": {\"kind\": \"fadeOut\"},"
            + " \"blend\": \"add\" } ] }";
        let count = DocJson.parse(doc)
            |> Option.flatMap(json -> FxDoc.parse(json) |> Result.toOption)
            |> Option.map(spec -> List.length(Fx.sample(spec, 1i64, 0.15)))
            |> Option.getWithDefault(-1);
        Assert.assertEq(expected = true, count > 0 and count <= 20)
}
