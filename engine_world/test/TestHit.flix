// Hit / HitDoc / JsonCompat.sheetAt のテスト。3 ケース（円×円・円×箱・箱×箱）の境界と
// 複数形の意味論、エンジンの円判定（CollisionShape2D）とのパリティ、codec の文言を固定する。
// 境界の線引きは「ちょうど接するのは当たりに入れない」。

mod TestHit {
    use Util.Json.Json
    use Util.Json.JsonError

    def at(x: Float64, y: Float64): Vec2.Vec2 = { x = x, y = y }

    def circle(dx: Float64, dy: Float64, r: Float64): Hit.HitShape =
        Hit.HitShape.CircleH({ dx = dx, dy = dy, r = r })

    def box(dx: Float64, dy: Float64, w: Float64, h: Float64): Hit.HitShape =
        Hit.HitShape.BoxH({ dx = dx, dy = dy, w = w, h = h })

    /// 形 1 個どうしの重なりを聞く近道。
    def hit1(pa: Vec2.Vec2, a: Hit.HitShape, pb: Vec2.Vec2, b: Hit.HitShape): Bool =
        Hit.overlaps(pa, a :: Nil, pb, b :: Nil)

    /// 円×円: 離れ・ちょうど接する（半径の和 = 距離）は外、重なり・内包は当たり。
    @Test
    def testCircleCircleBounds(): Unit \ Assert =
        let me = circle(0.0, 0.0, 5.0);
        let other = circle(0.0, 0.0, 3.0);
        Assert.assertEq(expected = (false, false, true, true),
            (hit1(at(0.0, 0.0), me, at(100.0, 0.0), other),
             hit1(at(0.0, 0.0), me, at(8.0, 0.0), other),
             hit1(at(0.0, 0.0), me, at(7.9, 0.0), other),
             hit1(at(0.0, 0.0), me, at(0.0, 0.0), other)))

    /// 円×箱の辺: 辺にちょうど接するのは外、食い込めば当たり。
    @Test
    def testCircleBoxEdge(): Unit \ Assert =
        let c = circle(0.0, 0.0, 2.0);
        let b = box(0.0, 0.0, 10.0, 6.0);
        // 箱の左辺は x=2（中心 7 - 半分幅 5）。円の右端がちょうど x=2 → 接するだけ。
        Assert.assertEq(expected = (false, true),
            (hit1(at(0.0, 0.0), c, at(7.0, 0.0), b),
             hit1(at(0.0, 0.0), c, at(6.9, 0.0), b)))

    /// 円×箱の角: 最近点は角になる。角までの距離が半径以上なら外、未満なら当たり。
    @Test
    def testCircleBoxCorner(): Unit \ Assert =
        let c = circle(0.0, 0.0, 2.0);
        let b = box(0.0, 0.0, 4.0, 4.0);
        // 箱は (10,10) 中心 → 最寄りの角は (8,8)。(6.5,6.5) からは √4.5 ≈ 2.12 で外。
        Assert.assertEq(expected = (false, true),
            (hit1(at(6.5, 6.5), c, at(10.0, 10.0), b),
             hit1(at(7.0, 7.0), c, at(10.0, 10.0), b)))

    /// 円×箱の内包: 円の中心が箱の中なら最近点は中心自身（距離 0）で必ず当たり。
    @Test
    def testCircleBoxContained(): Unit \ Assert =
        Assert.assertEq(expected = true,
            hit1(at(10.5, 9.5), circle(0.0, 0.0, 1.0), at(10.0, 10.0), box(0.0, 0.0, 4.0, 4.0)))

    /// 箱×円（引数を入れ替えた組）も円×箱と同じ答えになる。
    @Test
    def testBoxCircleOrderIrrelevant(): Unit \ Assert =
        let c = circle(0.0, 0.0, 2.0);
        let b = box(0.0, 0.0, 10.0, 6.0);
        Assert.assertEq(expected = (true, false),
            (hit1(at(6.9, 0.0), b, at(0.0, 0.0), c),
             hit1(at(7.0, 0.0), b, at(0.0, 0.0), c)))

    /// 箱×箱（AABB）: 離れ・辺でちょうど接するのは外、重なり・内包は当たり。
    @Test
    def testBoxBoxBounds(): Unit \ Assert =
        let a = box(0.0, 0.0, 6.0, 4.0);
        let b = box(0.0, 0.0, 4.0, 4.0);
        Assert.assertEq(expected = (false, false, true, true),
            (hit1(at(0.0, 0.0), a, at(100.0, 0.0), b),
             hit1(at(0.0, 0.0), a, at(5.0, 0.0), b),
             hit1(at(0.0, 0.0), a, at(4.9, 0.0), b),
             hit1(at(0.0, 0.0), a, at(0.5, 0.5), box(0.0, 0.0, 2.0, 2.0))))

    /// 点×箱: 縁の上は外・中は当たり（boxBox の点版という契約を固定する）。
    @Test
    def testPointBoxEdgeIsOut(): Unit \ Assert =
        Assert.assertEq(expected = (false, true),
            (Hit.pointBox({ x = 3.0, y = 0.0 }, { x = 0.0, y = 0.0 }, 6.0, 4.0),
             Hit.pointBox({ x = 2.9, y = 0.0 }, { x = 0.0, y = 0.0 }, 6.0, 4.0)))

    /// 複数箱の意味論: 全長 24 の見た目のミサイルでも、当たりが先端の 6×6 だけなら
    /// 胴体・尾部への接触は外れで、先端だけが当たる。
    @Test
    def testMissileNoseOnly(): Unit \ Assert =
        // ミサイル中心 (100,100)・見た目は x 88..112。当たりは先端の箱（x 106..112）のみ。
        let missile = box(9.0, 0.0, 6.0, 6.0) :: Nil;
        let probe = circle(0.0, 0.0, 2.0) :: Nil;
        let mpos = at(100.0, 100.0);
        Assert.assertEq(expected = (false, false, false, true),
            (Hit.overlaps(at(100.0, 100.0), probe, mpos, missile),  // 胴体の中心
             Hit.overlaps(at(89.0, 100.0), probe, mpos, missile),   // 尾部
             Hit.overlaps(at(104.0, 100.0), probe, mpos, missile),  // 先端に接するだけ
             Hit.overlaps(at(109.0, 100.0), probe, mpos, missile))) // 先端のど真ん中

    /// 形の列はどれか 1 個に触れれば当たり（左右のポッドの間のすき間は外れ）。
    @Test
    def testMultiShapeEitherPodHits(): Unit \ Assert =
        let pods = circle(-8.0, 0.0, 3.0) :: circle(8.0, 0.0, 3.0) :: Nil;
        let probe = circle(0.0, 0.0, 1.0) :: Nil;
        let ppos = at(100.0, 100.0);
        Assert.assertEq(expected = (false, true, true),
            (Hit.overlaps(at(100.0, 100.0), probe, ppos, pods),
             Hit.overlaps(at(92.0, 100.0), probe, ppos, pods),
             Hit.overlaps(at(108.0, 100.0), probe, ppos, pods)))

    /// 円パリティ: エンジンの円判定（CollisionShape2D）と同じ答えになる
    /// （境界ちょうども含めて突き合わせる）。
    @Test
    def testCircleParityWithEngine(): Unit \ Assert =
        let cases =
               (3.0, 6.0, 0.0)  :: (3.0, 6.0, 8.99) :: (3.0, 6.0, 9.0) :: (3.0, 6.0, 12.0)
            :: (5.0, 2.5, 7.49) :: (5.0, 2.5, 7.5)  :: (5.0, 8.0, 12.9) :: (5.0, 8.0, 13.0)
            :: Nil;
        Assert.assertEq(
            expected = List.map(match (ra, rb, d) -> engineCircle(ra, rb, d), cases),
            List.map(match (ra, rb, d) -> Hit.circleCircle(at(0.0, 0.0), ra, at(d, 0.0), rb), cases))

    /// エンジン側の円×円判定（同じ線引きであることの突き合わせ相手）。
    def engineCircle(ra: Float64, rb: Float64, d: Float64): Bool =
        CollisionShape2D.checkOverlap(
            at(0.0, 0.0), CollisionShape2D.CircleShape2D({ radius = ra }),
            at(d, 0.0), CollisionShape2D.CircleShape2D({ radius = rb }))

    // ── toCollisionShape（宣言 → Physics2D 系の形への橋） ──

    /// 円→CircleShape2D・箱→RectShape2D に、dx/dy はオフセットとして写る。
    @Test
    def testToCollisionShape(): Unit \ Assert =
        Assert.assertEq(
            expected = ("(1.0, 2.0) circle r=3.0", "(4.0, 5.0) rect 6.0x7.0"),
            (bridgeSummary(Hit.toCollisionShape(circle(1.0, 2.0, 3.0))),
             bridgeSummary(Hit.toCollisionShape(box(4.0, 5.0, 6.0, 7.0)))))

    /// 変換結果を 1 行に落とす（enum の比較を平らにするため）。
    def bridgeSummary(pair: (Vec2.Vec2, CollisionShape2D)): String =
        let (off, shape) = pair;
        match shape {
            case CollisionShape2D.CircleShape2D(c) => "(${off#x}, ${off#y}) circle r=${c#radius}"
            case CollisionShape2D.RectShape2D(r)   => "(${off#x}, ${off#y}) rect ${r#width}x${r#height}"
            case _                                 => "other"
        }

    // ── HitDoc（codec） ──

    /// 知らない形はキーと位置付き（hit.player[0]）で断られる。
    @Test
    def testUnknownShapeErrorHasPosition(): Unit \ Assert =
        let text = "{ \"hit\": { \"player\": [ { \"shape\": \"circl\", \"dx\": 0, \"dy\": 0, \"r\": 5.0 } ] } }";
        Assert.assertEq(
            expected = "at hit.player[0]: unknown shape 'circl' (known: circle, box)",
            parseMessage(text))

    /// text を Sheet として読んだ結果を 1 行に落とす（成功なら "ok"）。
    def parseMessage(text: String): String =
        JsonCompat.parse(text)
            |> Option.toOk(JsonCompat.jsonError(JsonCompat.PathTag.Root, Set#{"parse failed"}))
            |> Result.flatMap(HitDoc.parse)
            |> messageOf

    def messageOf(r: Result[JsonError, HitDoc.Sheet]): String =
        match r {
            case Ok(_)  => "ok"
            case Err(e) => JsonCompat.describe(e)
        }

    /// "//" で始まる名前はコメントとして飛ばされ、sheet に載らない。
    @Test
    def testCommentKeyIsSkipped(): Unit \ Assert =
        let text = "{ \"hit\": { \"//memo\": \"自由に書ける\", \"player\": [ { \"shape\": \"circle\", \"dx\": 0, \"dy\": 0, \"r\": 5.0 } ] } }";
        let summary = JsonCompat.parse(text)
            |> Option.toOk(JsonCompat.jsonError(JsonCompat.PathTag.Root, Set#{"parse failed"}))
            |> Result.flatMap(HitDoc.parse)
            |> Result.map(sheet -> "keys=${Map.size(sheet)} player=${List.length(HitDoc.shapesOf("player", sheet))}")
            |> Result.getWithDefault("error");
        Assert.assertEq(expected = "keys=1 player=1", summary)

    /// キーはあるのに形が 0 個 — 「当たらないゲーム」は gaps が欠け扱いで止める。
    @Test
    def testEmptyShapeListIsGap(): Unit \ Assert =
        let sheet = Map#{ "player" => (Nil: List[Hit.HitShape]) };
        Assert.assertEq(
            expected = true,
            HitDoc.gaps("player" :: Nil, sheet) |> List.exists(msg ->
                String.contains(substr = "player' must have at least 1 shape", msg)))

    /// 負・ゼロの寸法は loud に断る（黙って判定が縮まない）。
    @Test
    def testNegativeSizeIsLoud(): Unit \ Assert =
        let neg  = "{ \"hit\": { \"player\": [ { \"shape\": \"circle\", \"dx\": 0, \"dy\": 0, \"r\": -3.0 } ] } }";
        let zero = "{ \"hit\": { \"player\": [ { \"shape\": \"box\", \"dx\": 0, \"dy\": 0, \"w\": 0, \"h\": 4 } ] } }";
        Assert.assertEq(
            expected = ("at hit.player[0]: r must be positive (got -3.0)",
                        "at hit.player[0]: w must be positive (got 0.0)"),
            (parseMessage(neg), parseMessage(zero)))

    /// リロードの意味論: 読めて欠け無しなら差し替え、Err・欠けありなら今の sheet を守る。
    @Test
    def testReloadedKeepsCurrentOnBrokenJson(): Unit \ Assert =
        let current = fullSheet(5.0);
        let fresh   = fullSheet(9.0);
        let broken  = Err(JsonCompat.jsonError(JsonCompat.PathTag.Root, Set#{"boom"}));
        let gapped  = Ok(Map#{ "player" => (Nil: List[Hit.HitShape]) });
        Assert.assertEq(
            expected = (freshR(), 5.0, 5.0),
            (headR(HitDoc.reloaded(requiredKeys(), Ok(fresh), current)),
             headR(HitDoc.reloaded(requiredKeys(), broken, current)),
             headR(HitDoc.reloaded(requiredKeys(), gapped, current))))

    def freshR(): Float64 = 9.0

    /// 必須キーの表はゲームが渡す（このテストでは 2 キーの小さな表）。
    def requiredKeys(): List[String] = "player" :: "enemy" :: Nil

    /// 必須キーを全部持つ sheet（player の円半径だけ r で変える）。
    def fullSheet(r: Float64): HitDoc.Sheet =
        requiredKeys()
            |> List.map(key -> {
                let radius = if (key == "player") r else 1.0;
                (key, Hit.HitShape.CircleH({ dx = 0.0, dy = 0.0, r = radius }) :: Nil)
            })
            |> List.toMap

    /// sheet の player 先頭の円の半径（テストの比較用）。
    def headR(sheet: HitDoc.Sheet): Float64 =
        HitDoc.shapesOf("player", sheet)
            |> List.head
            |> Option.flatMap(shape -> match shape {
                case Hit.HitShape.CircleH(c) => Some(c#r)
                case _                       => None
            })
            |> Option.getWithDefault(-1.0)

    // ── JsonCompat.sheetAt（単体） ──

    /// text の一番外のオブジェクトを Map にする（テスト入力用の近道）。
    def topOf(text: String): Map[String, Json] =
        JsonCompat.parse(text)
            |> Option.flatMap(json -> JsonCompat.asObject("top", json) |> Result.toOption)
            |> Option.getWithDefault(Map.empty())

    /// 結果のエラーを一文にする（成功なら "ok"）。
    def describeErr(r: Result[JsonError, a]): String =
        match r {
            case Ok(_)  => "ok"
            case Err(e) => JsonCompat.describe(e)
        }

    /// 名前ごとの配列が要素パーサでリストになり、"//" の名前は飛ばされる。
    @Test
    def testSheetAtReadsNamedLists(): Unit \ Assert =
        let top = topOf("{ \"s\": { \"a\": [10, 20], \"//memo\": \"comment\", \"b\": [] } }");
        Assert.assertEq(
            expected = Some(("a", 1 :: 1 :: Nil) :: ("b", (Nil: List[Int32])) :: Nil),
            JsonCompat.sheetAt("s", _json -> Ok(1), top)
                |> Result.toOption
                |> Option.map(Map.toList))

    /// field が無い・オブジェクトでないときは field 名入りの一文で断る。
    @Test
    def testSheetAtMissingFieldIsLoud(): Unit \ Assert =
        let top = topOf("{ \"other\": 1 }");
        Assert.assertEq(
            expected = "s must be an object of name -> lists",
            describeErr(JsonCompat.sheetAt("s", _json -> (Ok(1): Result[JsonError, Int32]), top)))

    /// 要素パーサのエラーには "field.名前[i]" の位置が付く。
    @Test
    def testSheetAtTagsItemErrors(): Unit \ Assert =
        let top = topOf("{ \"s\": { \"a\": [true] } }");
        let itemAt = _json -> (Err(JsonCompat.jsonError(JsonCompat.PathTag.Root, Set#{"boom here"})): Result[JsonError, Int32]);
        Assert.assertEq(
            expected = "at s.a[0]: boom here",
            describeErr(JsonCompat.sheetAt("s", itemAt, top)))
}
