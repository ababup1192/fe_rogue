// TestFxTurn — fx.json に足した「方向の等分（dir.mode: even）」と「粒の回転（turn）」を固定する。
// 確かめるのは規約だけ: 等分は乱数に依らず粒番号で決まること、回転は初期の向き +
// 回る速さ × 経過であること、既定値なら既存の絵が 1 ビットも動かないこと。
mod TestFxTurn {

    def white(): Color = { r = 1.0f32, g = 1.0f32, b = 1.0f32 }

    /// ばらつきゼロ・等速 10px/s・全方位に開いた基準 emitter（粒は箱 = 回転が見える形）。
    def baseEmitter(): FxDoc.Emitter =
        { name = "chips", count = 4, shape = FxDoc.Shape.Box, size = 2.0,
          color = white() :: Nil,
          life = { base = 1.0, vary = 0.0 },
          speed = { base = 10.0, vary = 0.0, over = FxDoc.CurveSpec.Constant },
          dir = { base = 0.0, spread = 360.0, mode = FxDoc.DirMode.Random },
          turn = { base = 0.0, spread = 0.0, spin = 0.0, spinSpread = 0.0 },
          mode = FxDoc.Mode.Burst, spawnArea = { w = 0.0, h = 0.0 }, accel = Vec2.zero(),
          wobble = { amp = Vec2.zero(), freq = Vec2.zero(), vary = 0.0 }, stretch = 0.05, seed = 0,
          sizeOver = FxDoc.CurveSpec.Constant, alphaOver = FxDoc.CurveSpec.Constant,
          blend = DrawCmd.BlendMode.Normal, zIndex = 3 }

    def specOf(emitter: FxDoc.Emitter): FxDoc.Spec =
        { name = "test", duration = 1.0, note = None, emitters = emitter :: Nil }

    /// 粒の中心（左上 + 半辺 1px）。
    def centers(items: List[Render.PlacedItem]): List[(Float64, Float64)] =
        List.map(p -> (p#at#x + 1.0, p#at#y + 1.0), items)

    /// 粒の傾き（回転数）。箱でない粒は 0。
    def turns(items: List[Render.PlacedItem]): List[Float64] =
        items |> List.map(p -> match p#item {
            case Render.Item.Box(b) => b#rotation
            case _                  => 0.0
        })

    def round3(x: Float64): Float64 =
        Float64.round(x * 1000.0) / 1000.0

    // ════════════════════════════════════════════════════════
    // dir.mode: even（方向を等分する）
    // ════════════════════════════════════════════════════════

    /// even は 360 度を粒の数で割り切って配る: 4 粒の中心の合計は原点に戻る（左右上下が対称）。
    /// random は乱数で偏るので合計は原点に戻らない。
    @Test
    def testEvenSpreadsDirectionsSymmetrically(): Unit \ Assert =
        let sumOf = em -> centers(Fx.sample(specOf(em), 0i64, 0.5))
            |> List.foldLeft((acc, c) -> { let (x, y) = c; let (ax, ay) = acc; (ax + x, ay + y) }, (0.0, 0.0));
        let (ex, ey) = sumOf({ dir = { base = 0.0, spread = 360.0, mode = FxDoc.DirMode.Even } | baseEmitter() });
        let (rx, ry) = sumOf(baseEmitter());
        Assert.assertEq(expected = (0.0, 0.0, true),
            (round3(ex), round3(ey), round3(rx) != 0.0 or round3(ry) != 0.0))

    /// even は乱数を引かないので、種を変えても粒の並びが変わらない（輪の形が毎回同じ）。
    @Test
    def testEvenIgnoresTheSeed(): Unit \ Assert =
        let em = { dir = { base = 0.0, spread = 360.0, mode = FxDoc.DirMode.Even } | baseEmitter() };
        Assert.assertEq(expected = centers(Fx.sample(specOf(em), 0i64, 0.5)),
            centers(Fx.sample(specOf(em), 99i64, 0.5)))

    /// even でも全粒は同じ距離を飛ぶ（等速・ばらつきゼロなら輪になる）。
    @Test
    def testEvenKeepsEveryParticleOnOneRing(): Unit \ Assert =
        let em = { dir = { base = 0.0, spread = 360.0, mode = FxDoc.DirMode.Even } | baseEmitter() };
        let dists = centers(Fx.sample(specOf(em), 0i64, 0.5))
            |> List.map(c -> { let (x, y) = c; round3(Vec2.length({ x = x, y = y })) })
            |> List.distinct;
        Assert.assertEq(expected = 5.0 :: Nil, dists)

    // ════════════════════════════════════════════════════════
    // turn（粒の傾きと回る速さ・単位は回転数 = 1 周 1.0）
    // ════════════════════════════════════════════════════════

    /// turn 既定（すべて 0）の粒は傾かない。
    @Test
    def testDefaultTurnLeavesParticlesUpright(): Unit \ Assert =
        Assert.assertEq(expected = List.repeat(4, 0.0),
            turns(Fx.sample(specOf(baseEmitter()), 0i64, 0.5)))

    /// turn.base はばらつき無しなら全粒に同じ傾きを与える。
    @Test
    def testTurnBaseTiltsEveryParticleAlike(): Unit \ Assert =
        let em = { turn = { base = 0.125, spread = 0.0, spin = 0.0, spinSpread = 0.0 } | baseEmitter() };
        Assert.assertEq(expected = List.repeat(4, 0.125),
            turns(Fx.sample(specOf(em), 0i64, 0.5)))

    /// turn.spin は経過秒に比例して回す: 2 回転/秒なら 0.25 秒で 0.5 回転ぶん進む。
    @Test
    def testSpinAdvancesWithElapsedSeconds(): Unit \ Assert =
        let em = { turn = { base = 0.0, spread = 0.0, spin = 2.0, spinSpread = 0.0 } | baseEmitter() };
        let at = t -> turns(Fx.sample(specOf(em), 0i64, t)) |> List.map(round3) |> List.distinct;
        Assert.assertEq(expected = (0.5 :: Nil, 1.0 :: Nil), (at(0.25), at(0.5)))

    /// spread / spinSpread は粒ごとに傾きと回る向きをばらす（全粒が同じ姿にならない）。
    @Test
    def testSpreadMakesParticlesDiffer(): Unit \ Assert =
        let em = { turn = { base = 0.0, spread = 1.0, spin = 0.0, spinSpread = 4.0 },
                   count = 8 | baseEmitter() };
        let n = turns(Fx.sample(specOf(em), 0i64, 0.5)) |> List.map(round3) |> List.distinct |> List.length;
        Assert.assertEq(expected = 8, n)

    /// 円は回しても同じ絵なので傾けない（粒ごとの回転を描画部へ送るだけ無駄になる）。
    @Test
    def testCirclesAreNotTurned(): Unit \ Assert =
        let em = { shape = FxDoc.Shape.Circle,
                   turn = { base = 0.25, spread = 0.0, spin = 3.0, spinSpread = 0.0 } | baseEmitter() };
        Assert.assertEq(expected = List.repeat(4, 0.0),
            turns(Fx.sample(specOf(em), 0i64, 0.5)))

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

    /// dir.mode: "even" と turn が Spec に畳まれる。
    @Test
    def testParseEvenAndTurn(): Unit \ Assert =
        let text = "{ \"name\": \"ring\", \"duration\": 1, \"emitters\": [ {" +
            " \"name\": \"e\", \"count\": 12, \"shape\": \"box\", \"size\": 2," +
            " \"color\": [\"#ffffff\"], \"life\": { \"base\": 1 }," +
            " \"dir\": { \"base\": 0, \"spread\": 360, \"mode\": \"even\" }," +
            " \"turn\": { \"base\": 0.1, \"spread\": 0.5, \"spin\": 1.5, \"spinSpread\": 2 } } ] }";
        let got = firstEmitter(text) |> Option.map(em ->
            (em#dir#mode == FxDoc.DirMode.Even, em#turn#base, em#turn#spread,
             em#turn#spin, em#turn#spinSpread));
        Assert.assertEq(expected = Some((true, 0.1, 0.5, 1.5, 2.0)), got)

    /// 省略時の既定は「乱数で散らす・回らない」（古い fx.json の絵が動かない）。
    @Test
    def testParseDefaultsToRandomAndNoTurn(): Unit \ Assert =
        let text = "{ \"name\": \"x\", \"duration\": 1, \"emitters\": [ {" +
            " \"name\": \"e\", \"count\": 1, \"size\": 1," +
            " \"color\": [\"#ffffff\"], \"life\": { \"base\": 1 } } ] }";
        let got = firstEmitter(text) |> Option.map(em ->
            (em#dir#mode == FxDoc.DirMode.Random, em#turn#base, em#turn#spin));
        Assert.assertEq(expected = Some((true, 0.0, 0.0)), got)

    /// 知らない dir.mode は loud に断る（黙って random へ倒すと、綴り違いに気付けない）。
    @Test
    def testParseUnknownDirModeIsErr(): Unit \ Assert =
        let bad = "{ \"name\": \"x\", \"duration\": 1, \"emitters\": [ {" +
            " \"name\": \"e\", \"count\": 1, \"size\": 1," +
            " \"color\": [\"#ffffff\"], \"life\": { \"base\": 1 }," +
            " \"dir\": { \"mode\": \"ring\" } } ] }";
        Assert.assertEq(expected = true, Result.isErr(parseText(bad)))

    /// 負の spread は Err（幅は非負）。
    @Test
    def testParseNegativeTurnSpreadIsErr(): Unit \ Assert =
        let bad = "{ \"name\": \"x\", \"duration\": 1, \"emitters\": [ {" +
            " \"name\": \"e\", \"count\": 1, \"size\": 1," +
            " \"color\": [\"#ffffff\"], \"life\": { \"base\": 1 }," +
            " \"turn\": { \"spread\": -1 } } ] }";
        Assert.assertEq(expected = true, Result.isErr(parseText(bad)))

    /// 知らないキーは黙って捨てる（fail-open — 新しい語彙で書いた fx.json を古い engine が
    /// 読んでも、既定値のまま絵が出る）。
    @Test
    def testUnknownKeysAreIgnored(): Unit \ Assert =
        let text = "{ \"name\": \"x\", \"duration\": 1, \"emitters\": [ {" +
            " \"name\": \"e\", \"count\": 1, \"size\": 1, \"shimmer\": 3," +
            " \"color\": [\"#ffffff\"], \"life\": { \"base\": 1 }," +
            " \"turn\": { \"base\": 0.25, \"tumble\": 9 } } ] }";
        let got = firstEmitter(text) |> Option.map(em -> em#turn#base);
        Assert.assertEq(expected = Some(0.25), got)
}
