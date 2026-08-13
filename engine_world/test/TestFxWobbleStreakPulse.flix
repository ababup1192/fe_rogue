// TestFxWobbleStreakPulse — fx.json に足した 3 語彙（wobble = 位置の正弦揺らぎ /
// shape: streak = 速度方向の筋 / pulse = 正弦の明滅カーブ）を固定する。
// 確かめるのは規約だけ: 閉形式が式どおりの値を出すこと、既定値なら既存の絵が
// 1 ビットも動かないこと、JSON を読み取れること・範囲外を loud に断ること。
mod TestFxWobbleStreakPulse {

    def white(): Color = { r = 1.0f32, g = 1.0f32, b = 1.0f32 }

    /// ばらつきゼロ・等速 10px/s・真右向きの基準 emitter（TestFxVocab と同じ）。
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

    def ats(items: List[Render.PlacedItem]): List[(Float64, Float64)] =
        List.map(p -> (p#at#x, p#at#y), items)

    /// 箱の (左上 x, 左上 y, 幅, 高さ, 傾き)。箱でない粒は全 0。
    def boxes(items: List[Render.PlacedItem]): List[(Float64, Float64, Float64, Float64, Float64)] =
        items |> List.map(p -> match p#item {
            case Render.Item.Box(b) => (p#at#x, p#at#y, b#size#x, b#size#y, b#rotation)
            case _                  => (0.0, 0.0, 0.0, 0.0, 0.0)
        })

    // ════════════════════════════════════════════════════════
    // wobble（位置の正弦揺らぎ）
    // ════════════════════════════════════════════════════════

    /// amp が 0 なら freq・vary が何であれ既存の絵とビット単位で一致する（後方互換）。
    @Test
    def testWobbleZeroAmpKeepsSampleUnchanged(): Unit \ Assert =
        let em = { wobble = { amp = Vec2.zero(), freq = Vec2.v2(3.0, 5.0), vary = 0.7 } | baseEmitter() };
        Assert.assertEq(expected = ats(Fx.sample(specOf(baseEmitter()), 0i64, 0.5)),
            ats(Fx.sample(specOf(em), 0i64, 0.5)))

    /// 揺らぎは amp × sin(2π × freq × 経過) の閉形式:
    /// amp.x=2, freq.x=1Hz, t=0.25 → sin(π/2)=1 で x に +2。
    /// 中心 = (10×0.25 + 2, 0) = (4.5, 0) → 左上 = (3.5, -1)。vary 0 なら全粒そろう。
    @Test
    def testWobbleSineOffsetClosedForm(): Unit \ Assert =
        let em = { wobble = { amp = Vec2.v2(2.0, 0.0), freq = Vec2.v2(1.0, 0.0), vary = 0.0 } | baseEmitter() };
        Assert.assertEq(expected = List.repeat(4, (3.5, -1.0)),
            ats(Fx.sample(specOf(em), 0i64, 0.25)))

    /// vary > 0 は粒ごとに位相を散らす（全粒が同じタイミングで揺れて画面が脈打つ、が起きない）。
    @Test
    def testWobbleVaryScattersPhases(): Unit \ Assert =
        let em = { wobble = { amp = Vec2.v2(5.0, 0.0), freq = Vec2.v2(2.0, 0.0), vary = 1.0 },
                   count = 8 | baseEmitter() };
        let xs = ats(Fx.sample(specOf(em), 0i64, 0.3)) |> List.map(fst) |> List.distinct;
        Assert.assertEq(expected = true, List.length(xs) > 1)

    // ════════════════════════════════════════════════════════
    // shape: streak（速度方向に伸びた筋）
    // ════════════════════════════════════════════════════════

    /// 真右 10px/s・stretch 0.5 の筋は、太さ = size(2)・長さ = 2 + 10×0.5 = 7 の箱が
    /// 右向き（0.25 回転）に倒れる。t=0.5 の中心 (5, 0) → 左上 = (4, -3.5)。
    @Test
    def testStreakStretchesAlongVelocity(): Unit \ Assert =
        let em = { shape = FxDoc.Shape.Streak, stretch = 0.5 | baseEmitter() };
        Assert.assertEq(expected = List.repeat(4, (4.0, -3.5, 2.0, 7.0, 0.25)),
            boxes(Fx.sample(specOf(em), 0i64, 0.5)))

    /// 初速ゼロでも重力で落ち始めた粒の筋は下（0.5 回転）を向く:
    /// accel y=8, t=0.5 → 速度 (0, 4)・長さ = 2 + 4×0.5 = 4・中心 (0, ½·8·0.25) = (0, 1)。
    @Test
    def testStreakPointsAlongGravity(): Unit \ Assert =
        let em = { shape = FxDoc.Shape.Streak, stretch = 0.5,
                   speed = { base = 0.0, vary = 0.0, over = FxDoc.CurveSpec.Constant },
                   accel = Vec2.v2(0.0, 8.0) | baseEmitter() };
        Assert.assertEq(expected = List.repeat(4, (-1.0, -1.0, 2.0, 4.0, 0.5)),
            boxes(Fx.sample(specOf(em), 0i64, 0.5)))

    /// 止まった粒（速度ゼロ）は射出方向を向き、尾は伸びない（size 角の箱に退化）。
    @Test
    def testStationaryStreakFacesEmissionDir(): Unit \ Assert =
        let em = { shape = FxDoc.Shape.Streak, stretch = 0.5,
                   speed = { base = 0.0, vary = 0.0, over = FxDoc.CurveSpec.Constant } | baseEmitter() };
        Assert.assertEq(expected = List.repeat(4, (-1.0, -1.0, 2.0, 2.0, 0.25)),
            boxes(Fx.sample(specOf(em), 0i64, 0.5)))

    // ════════════════════════════════════════════════════════
    // pulse（正弦の明滅カーブ）
    // ════════════════════════════════════════════════════════

    /// pulse は u=0 で 1 から始まる（生まれた瞬間に暗い粒を出さない）:
    /// t=0 の絵は既定カーブと同じ（中心 (0,0)・半径 1 → 左上 (-1,-1)）。
    @Test
    def testPulseStartsAtFull(): Unit \ Assert =
        let em = { sizeOver = FxDoc.CurveSpec.Pulse({ rate = 1.0, minV = 0.2 }) | baseEmitter() };
        Assert.assertEq(expected = ats(Fx.sample(specOf(baseEmitter()), 0i64, 0.0)),
            ats(Fx.sample(specOf(em), 0i64, 0.0)))

    /// rate 1 は寿命の半分（u=0.5・cos π = -1）で min まで沈む:
    /// min 0.2 × size 2 = 直径 0.4 → 中心 (5, 0) から左上 = (4.8, -0.2)。
    @Test
    def testPulseDipsToMinAtHalfPeriod(): Unit \ Assert =
        let em = { sizeOver = FxDoc.CurveSpec.Pulse({ rate = 1.0, minV = 0.2 }) | baseEmitter() };
        Assert.assertEq(expected = List.repeat(4, (4.8, -0.2)),
            ats(Fx.sample(specOf(em), 0i64, 0.5)))

    /// alphaOver の pulse min 0 は谷（u=0.5）で粒を消し、それ以外では出す
    ///（点滅 = 粒の出入りとして自然につながる）。
    @Test
    def testPulseMinZeroDropsParticleAtTrough(): Unit \ Assert =
        let em = { alphaOver = FxDoc.CurveSpec.Pulse({ rate = 1.0, minV = 0.0 }) | baseEmitter() };
        Assert.assertEq(expected = (0, 4),
            (List.length(Fx.sample(specOf(em), 0i64, 0.5)),
             List.length(Fx.sample(specOf(em), 0i64, 0.25))))

    // ════════════════════════════════════════════════════════
    // parse（新語彙の JSON）
    // ════════════════════════════════════════════════════════

    def parseText(text: String): Result[Util.Json.JsonError, FxDoc.Spec] =
        Util.Json.parse(text) |> Result.flatMap(FxDoc.parse)

    def firstEmitter(text: String): Option[FxDoc.Emitter] =
        match parseText(text) {
            case Ok(spec) => List.head(spec#emitters)
            case Err(_)   => None
        }

    /// wobble / shape: streak / stretch が Spec へ読み取られる（蛍と雨の宣言の代表形）。
    @Test
    def testParseWobbleAndStreak(): Unit \ Assert =
        let text = "{ \"name\": \"rain\", \"duration\": 60, \"emitters\": [ {" +
            " \"name\": \"drops\", \"count\": 30, \"mode\": \"loop\", \"shape\": \"streak\"," +
            " \"size\": 1.5, \"stretch\": 0.08, \"color\": [\"#9fb8d8\"]," +
            " \"life\": { \"base\": 0.8 }," +
            " \"wobble\": { \"amp\": { \"x\": 4 }, \"freq\": { \"x\": 0.5, \"y\": 2 }, \"vary\": 0.3 } } ] }";
        let got = firstEmitter(text) |> Option.map(em ->
            (em#shape == FxDoc.Shape.Streak, em#stretch,
             em#wobble#amp#x, em#wobble#amp#y, em#wobble#freq#x, em#wobble#freq#y, em#wobble#vary));
        Assert.assertEq(expected = Some((true, 0.08, 4.0, 0.0, 0.5, 2.0, 0.3)), got)

    /// 新キー省略時の既定（揺れない・stretch 0.05）— 既存の fx.json は書き換え不要。
    @Test
    def testParseDefaultsKeepNewVocabOff(): Unit \ Assert =
        let text = "{ \"name\": \"x\", \"duration\": 1, \"emitters\": [ {" +
            " \"name\": \"e\", \"count\": 1, \"size\": 1," +
            " \"color\": [\"#ffffff\"], \"life\": { \"base\": 1 } } ] }";
        let got = firstEmitter(text) |> Option.map(em ->
            (em#wobble#amp#x, em#wobble#amp#y, em#wobble#freq#x, em#wobble#freq#y,
             em#wobble#vary, em#stretch));
        Assert.assertEq(expected = Some((0.0, 0.0, 0.0, 0.0, 0.0, 0.05)), got)

    /// JSON の pulse（min 省略時 0.5 指定）が絵まで通る: u=0.5 で倍率 0.5 →
    /// 直径 2 × 0.5 = 1 → 左上 = (-0.5, -0.5)（speed 無し = 中心は原点のまま）。
    @Test
    def testParsePulseCurveReachesTheDrawing(): Unit \ Assert =
        let text = "{ \"name\": \"firefly\", \"duration\": 1, \"emitters\": [ {" +
            " \"name\": \"glow\", \"count\": 1, \"size\": 2," +
            " \"color\": [\"#ffe9a8\"], \"life\": { \"base\": 1 }," +
            " \"sizeOver\": { \"kind\": \"pulse\", \"rate\": 1, \"min\": 0.5 } } ] }";
        let got = parseText(text) |> Result.map(spec -> ats(Fx.sample(spec, 0i64, 0.5)));
        Assert.assertEq(expected = Ok((-0.5, -0.5) :: Nil), got)

    /// pulse の min は 0..1 の外を loud に断る（黙って丸めない）。
    @Test
    def testParsePulseMinOutOfRangeIsErr(): Unit \ Assert =
        let bad = "{ \"name\": \"x\", \"duration\": 1, \"emitters\": [ {" +
            " \"name\": \"e\", \"count\": 1, \"size\": 1," +
            " \"color\": [\"#ffffff\"], \"life\": { \"base\": 1 }," +
            " \"alphaOver\": { \"kind\": \"pulse\", \"rate\": 2, \"min\": 1.5 } } ] }";
        Assert.assertEq(expected = true, Result.isErr(parseText(bad)))

    /// speed.over の pulse は断る（明滅は明るさ・大きさの語彙 — 速度に混ぜない）。
    @Test
    def testParsePulseOnSpeedIsErr(): Unit \ Assert =
        let bad = "{ \"name\": \"x\", \"duration\": 1, \"emitters\": [ {" +
            " \"name\": \"e\", \"count\": 1, \"size\": 1," +
            " \"color\": [\"#ffffff\"], \"life\": { \"base\": 1 }," +
            " \"speed\": { \"base\": 5, \"over\": { \"kind\": \"pulse\", \"rate\": 2 } } } ] }";
        Assert.assertEq(expected = true, Result.isErr(parseText(bad)))

    /// 負の wobble.amp は Err（揺れ幅は非負 — 逆位相は位相で書く）。
    @Test
    def testParseNegativeWobbleAmpIsErr(): Unit \ Assert =
        let bad = "{ \"name\": \"x\", \"duration\": 1, \"emitters\": [ {" +
            " \"name\": \"e\", \"count\": 1, \"size\": 1," +
            " \"color\": [\"#ffffff\"], \"life\": { \"base\": 1 }," +
            " \"wobble\": { \"amp\": { \"x\": -1 } } } ] }";
        Assert.assertEq(expected = true, Result.isErr(parseText(bad)))

    /// 負の stretch は Err（尾の長さは非負）。
    @Test
    def testParseNegativeStretchIsErr(): Unit \ Assert =
        let bad = "{ \"name\": \"x\", \"duration\": 1, \"emitters\": [ {" +
            " \"name\": \"e\", \"count\": 1, \"size\": 1, \"shape\": \"streak\"," +
            " \"color\": [\"#ffffff\"], \"life\": { \"base\": 1 }," +
            " \"stretch\": -1 } ] }";
        Assert.assertEq(expected = true, Result.isErr(parseText(bad)))
}
