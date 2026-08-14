// TestFxVocab — R3 で足した fx.json 語彙（mode: loop / spawn / accel / seed / 色キー）を固定する。
// 既存 burst の絵が 1 ビットも動かないこと（後方互換）と、新語彙の閉形式が式どおりであることを
// 数値で pin する。粒は保存されない — すべて (spec, seed, t) の純関数。
mod TestFxVocab {
    use Util.Json.Json

    def white(): Color = { r = 1.0, g = 1.0, b = 1.0 }

    /// ばらつきゼロ・等速 10px/s・真右向きの基準 emitter（TestFxSample と同じ）。
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

    def specOf(duration: Float64, emitter: FxDoc.Emitter): FxDoc.Spec =
        { name = "test", duration = duration, note = None, emitters = emitter :: Nil }

    def ats(items: List[Render.PlacedItem]): List[(Float64, Float64)] =
        List.map(p -> (p#at#x, p#at#y), items)

    // ════════════════════════════════════════════════════════
    // 後方互換（新フィールドが既定値なら既存の絵と同一）
    // ════════════════════════════════════════════════════════

    /// spawn/accel/seed が既定値の burst は、従来の式（中心 = (10t, 0)・左上 = (10t-1, -1)）と
    /// ビット単位で一致する（スモーク: 加算した 0 が値を変えない）。
    @Test
    def testBurstUnchangedByDefaults(): Unit \ Assert =
        Assert.assertEq(expected = List.repeat(4, (4.0, -1.0)),
            ats(Fx.sample(specOf(1.0, baseEmitter()), 0i64, 0.5)))

    /// emitter#seed = 0 の乱数は「seed を混ぜない」従来と同一列（加算 0 は恒等）。
    /// seed ≠ 0 は別の散り方（spread 有りで位置が動く）。
    @Test
    def testEmitterSeedZeroIsIdentity(): Unit \ Assert =
        let spread = { dir = { base = 90.0, spread = 180.0, mode = FxDoc.DirMode.Random } | baseEmitter() };
        let s0 = ats(Fx.sample(specOf(1.0, spread), 7i64, 0.5));
        let s0b = ats(Fx.sample(specOf(1.0, { seed = 0 | spread }), 7i64, 0.5));
        let s1 = ats(Fx.sample(specOf(1.0, { seed = 1 | spread }), 7i64, 0.5));
        Assert.assertEq(expected = (true, true), (s0 == s0b, s0 != s1))

    // ════════════════════════════════════════════════════════
    // accel（重力/風 — 閉形式 ½at²）
    // ════════════════════════════════════════════════════════

    /// 重力 y=+8 px/s²: t=0.5 で中心 y = ½·8·0.5² = +1.0（速度成分は真右のまま）。
    @Test
    def testAccelGravityClosedForm(): Unit \ Assert =
        let em = { accel = ({ x = 0.0, y = 8.0 }: Vec2.Vec2) | baseEmitter() };
        Assert.assertEq(expected = List.repeat(4, (4.0, 0.0)),
            ats(Fx.sample(specOf(1.0, em), 0i64, 0.5)))

    /// 風 x=+4 px/s²: 速度ゼロの粒が t=1（寿命ぎわ手前）までに x = ½·4·t² だけ流される。
    @Test
    def testAccelWindOnStationary(): Unit \ Assert =
        let em = { speed = { base = 0.0, vary = 0.0, over = FxDoc.CurveSpec.Constant },
                   accel = ({ x = 4.0, y = 0.0 }: Vec2.Vec2) | baseEmitter() };
        // t=0.5: x = ½·4·0.25 = 0.5 → 左上 = (0.5-1, -1)
        Assert.assertEq(expected = List.repeat(4, (-0.5, -1.0)),
            ats(Fx.sample(specOf(1.0, em), 0i64, 0.5)))

    // ════════════════════════════════════════════════════════
    // spawn（発生源の広がり）
    // ════════════════════════════════════════════════════════

    /// spawn {w=10, h=6}: 全粒が原点中心の ±5 × ±3 の箱に収まり、粒ごとに位置が違う。
    @Test
    def testSpawnBoxBounds(): Unit \ Assert =
        let em = { speed = { base = 0.0, vary = 0.0, over = FxDoc.CurveSpec.Constant },
                   spawnArea = { w = 10.0, h = 6.0 }, count = 16 | baseEmitter() };
        let centers = Fx.sample(specOf(1.0, em), 0i64, 0.1)
            |> List.map(p -> (p#at#x + 1.0, p#at#y + 1.0));
        let inBox = centers |> List.forAll(c -> {
            let (x, y) = c;
            x >= -5.0 and x <= 5.0 and y >= -3.0 and y <= 3.0 });
        let distinct = List.distinct(centers);
        Assert.assertEq(expected = (true, true),
            (inBox, List.length(distinct) > 1))

    // ════════════════════════════════════════════════════════
    // mode: loop（粒が寿命ごとに生まれ直す）
    // ════════════════════════════════════════════════════════

    /// loop は寿命（1 秒）を過ぎても duration 内なら粒が出続ける（burst は消える）。
    @Test
    def testLoopKeepsEmittingPastLife(): Unit \ Assert =
        let burst = specOf(10.0, baseEmitter());
        let loop = specOf(10.0, { mode = FxDoc.Mode.Loop | baseEmitter() });
        Assert.assertEq(expected = (0, 4),
            (List.length(Fx.sample(burst, 0i64, 3.0)), List.length(Fx.sample(loop, 0i64, 3.0))))

    /// loop の粒は位相が粒ごとにずれる（全粒が同時に消えて画面が瞬く、が起きない）:
    /// ばらつきゼロでも t=3.0 の粒の x（= 10 × 経過）は 1 種類に揃わない。
    @Test
    def testLoopPhasesAreStaggered(): Unit \ Assert =
        let loop = specOf(10.0, { mode = FxDoc.Mode.Loop | baseEmitter() });
        let xs = ats(Fx.sample(loop, 0i64, 3.0)) |> List.map(fst) |> List.distinct;
        Assert.assertEq(expected = true, List.length(xs) > 1)

    /// loop は t の純関数（同じ t なら同じ絵 — 巻き戻し・リプレイでも揺れない）。
    @Test
    def testLoopIsDeterministic(): Unit \ Assert =
        let loop = specOf(10.0, { mode = FxDoc.Mode.Loop | baseEmitter() });
        Assert.assertEq(expected = ats(Fx.sample(loop, 5i64, 4.2)),
            ats(Fx.sample(loop, 5i64, 4.2)))

    /// 生まれ直した粒（周回が進んだ粒）は前の周回と別の個性を引く:
    /// spread 有りの loop で、t と t+寿命 の絵が一致しない（毎周そっくり同じ姿を避ける）。
    @Test
    def testLoopRerollsPerCycle(): Unit \ Assert =
        let loop = specOf(10.0, { mode = FxDoc.Mode.Loop,
            dir = { base = 90.0, spread = 180.0, mode = FxDoc.DirMode.Random } | baseEmitter() });
        Assert.assertEq(expected = true,
            ats(Fx.sample(loop, 0i64, 2.2)) != ats(Fx.sample(loop, 0i64, 3.2)))

    // ════════════════════════════════════════════════════════
    // parse（新語彙の JSON）
    // ════════════════════════════════════════════════════════

    def parseText(text: String): Result[Util.Json.JsonError, FxDoc.Spec] =
        Util.Json.parse(text) |> Result.flatMap(FxDoc.parse)

    def snowJson(): String =
        "{ \"name\": \"snow\", \"duration\": 60," +
        "  \"emitters\": [ { \"name\": \"flakes\", \"count\": 14, \"mode\": \"loop\"," +
        "    \"shape\": \"box\", \"size\": 1, \"color\": [\"#f0f4f8\"]," +
        "    \"life\": { \"base\": 20 }," +
        "    \"spawn\": { \"w\": 480, \"h\": 300 }," +
        "    \"accel\": { \"x\": -0.5, \"y\": 1.5 }," +
        "    \"seed\": 7, \"zIndex\": 502 } ] }"

    /// mode/spawn/accel/seed が Spec へ読み取られる（雪の宣言の代表形）。
    @Test
    def testParseLoopSnow(): Unit \ Assert =
        let got = match parseText(snowJson()) {
            case Ok(spec) => match spec#emitters {
                case em :: Nil => Some((em#mode == FxDoc.Mode.Loop, em#spawnArea#w, em#spawnArea#h,
                                        em#accel#x, em#accel#y, em#seed))
                case _ => None
            }
            case Err(_) => None
        };
        Assert.assertEq(expected = Some((true, 480.0, 300.0, -0.5, 1.5, 7)), got)

    /// 未知の mode は loud に断る（黙って burst に落とさない）。
    @Test
    def testParseUnknownModeIsErr(): Unit \ Assert =
        let bad = "{ \"name\": \"x\", \"duration\": 1, \"emitters\": [ {" +
            " \"name\": \"e\", \"count\": 1, \"mode\": \"stream\", \"size\": 1," +
            " \"color\": [\"#ffffff\"], \"life\": { \"base\": 1 } } ] }";
        Assert.assertEq(expected = true, Result.isErr(parseText(bad)))

    /// 負の spawn は Err（発生源の広がりは非負）。
    @Test
    def testParseNegativeSpawnIsErr(): Unit \ Assert =
        let bad = "{ \"name\": \"x\", \"duration\": 1, \"emitters\": [ {" +
            " \"name\": \"e\", \"count\": 1, \"size\": 1," +
            " \"color\": [\"#ffffff\"], \"life\": { \"base\": 1 }," +
            " \"spawn\": { \"w\": -3 } } ] }";
        Assert.assertEq(expected = true, Result.isErr(parseText(bad)))

    /// parseWith: 色キー "@smoke" がパレットから解決される。parse（パレット無し）では Err —
    /// 黙って白に落とさない。
    @Test
    def testParseWithColorKey(): Unit \ Assert =
        let text = "{ \"name\": \"smoke\", \"duration\": 60, \"emitters\": [ {" +
            " \"name\": \"puffs\", \"count\": 15, \"mode\": \"loop\", \"size\": 4," +
            " \"color\": [\"@smoke\", \"@pale\"], \"life\": { \"base\": 3 } } ] }";
        let palette = Map#{ "smoke" => ({ r = 0.5, g = 0.5, b = 0.55 }: Color),
                            "pale" => ({ r = 0.9, g = 0.92, b = 0.95 }: Color) };
        let withPalette = Util.Json.parse(text) |> Result.flatMap(FxDoc.parseWith(palette));
        let firstColor = match withPalette {
            case Ok(spec) => match spec#emitters {
                case em :: Nil => List.head(em#color) |> Option.map(c -> c#r)
                case _ => None
            }
            case Err(_) => None
        };
        let without = parseText(text);
        Assert.assertEq(expected = (Some(0.5), true), (firstColor, Result.isErr(without)))

    /// 新フィールド省略時の既定（burst・点発生・無加速・seed 0）。
    @Test
    def testParseDefaults(): Unit \ Assert =
        let text = "{ \"name\": \"x\", \"duration\": 1, \"emitters\": [ {" +
            " \"name\": \"e\", \"count\": 1, \"size\": 1," +
            " \"color\": [\"#ffffff\"], \"life\": { \"base\": 1 } } ] }";
        let got = match parseText(text) {
            case Ok(spec) => match spec#emitters {
                case em :: Nil => Some((em#mode == FxDoc.Mode.Burst,
                                        em#spawnArea#w, em#spawnArea#h, em#accel#x, em#accel#y, em#seed))
                case _ => None
            }
            case Err(_) => None
        };
        Assert.assertEq(expected = Some((true, 0.0, 0.0, 0.0, 0.0, 0)), got)
}
