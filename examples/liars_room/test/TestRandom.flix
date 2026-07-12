// TestRandom — Random 層が静かに壊れる箇所を pin で塞ぐ。合成子は名前が正しくても
// 種の受け渡しがズレると結果だけ変わって気づけないので、具体値と二層の一致で守る。
mod TestRandom {

    // Seed は Eq を持たないので、(値, 次の種) の値だけ取り出して比較できるようにする。
    def value(gen: Random.Generator[a], s: Int64): a =
        fst(Random.step(gen, Random.initialSeed(s)))

    // ── ① 低層ドローの具体値 pin ──

    @Test
    def testIntPinned(): Unit \ Assert =
        // 具体値でないと splitmix64 や int の式の変化を検知できない（回帰の砦）。
        Assert.assertEq(expected = 56, value(Random.int(lo = 0, hi = 100), 1i64))

    @Test
    def testListPinned(): Unit \ Assert =
        // 引き順が変わると別の並びになるので、順序ごと固定して崩れを捕まえる。
        Assert.assertEq(expected = 3 :: 0 :: 9 :: 5 :: 4 :: Nil, value(Random.list(5, Random.int(lo = 0, hi = 10)), 7i64))

    // ── ② コンビネータの法則 ──

    @Test
    def testMapIdentity(): Unit \ Assert =
        // map が状態に触らず値だけ変換している担保。種を余計に進めたら落ちる。
        let g = Random.int(lo = 0, hi = 1000);
        Assert.assertEq(expected = value(g, 3i64), value(Random.map(identity, g), 3i64))

    @Test
    def testAndThenConstant(): Unit \ Assert =
        // andThen が constant を挟んでも余計に種を進めていない担保（右単位元）。
        let g = Random.int(lo = 0, hi = 1000);
        Assert.assertEq(expected = value(g, 3i64), value(Random.andThen(x -> Random.constant(x), g), 3i64))

    @Test
    def testMapEqualsAndThenConstant(): Unit \ Assert =
        // ここがズレたら map か andThen のどちらかが種を二重に進めている。
        let g = Random.int(lo = 0, hi = 1000);
        let f = x -> x * 2;
        Assert.assertEq(
            expected = value(Random.map(f, g), 5i64),
            value(Random.andThen(x -> Random.constant(f(x)), g), 5i64))

    // ── ② コンビネータの構造（長さ・範囲） ──

    @Test
    def testListLength(): Unit \ Assert =
        Assert.assertEq(expected = 200, List.length(value(Random.list(200, Random.int(lo = 0, hi = 7)), 42i64)))

    @Test
    def testIntRange(): Unit \ Assert =
        // 上限は排他 [hi)。1 回では境界越えを見逃すので多数回引いて上限漏れを炙り出す。
        let draws = value(Random.list(200, Random.int(lo = 0, hi = 7)), 42i64);
        Assert.assertEq(expected = true, List.forAll(x -> x >= 0 and x < 7, draws))

    @Test
    def testUniformStaysInSet(): Unit \ Assert =
        // uniform が範囲外 index を踏むと候補外の値が出る。多数回引いて全て候補内で境界を守る。
        let xs = 10 :: 20 :: 30 :: Nil;
        let draws = value(Random.list(300, Random.uniform(10, 20 :: 30 :: Nil)), 3i64);
        Assert.assertEq(expected = true, List.forAll(x -> List.memberOf(x, xs), draws))

    @Test
    def testOneOfEmptyIsNone(): Unit \ Assert =
        // 空リストで crash や不正 index にせず None を返す、という境界を固定する。
        let empty = (Nil: List[Int32]);
        Assert.assertEq(expected = (None: Option[Int32]), value(Random.oneOf(empty), 1i64))

    // ── ③ 値層とエフェクト層の一致（種受け渡しの正しさ） ──

    @Test
    def testValueEqualsEffectSingle(): Unit \ Assert =
        // 別実装に見える二層が同結果、を保証。片方だけ直すと静かにズレるのを止める。
        let s = 12i64;
        let viaValue = value(Random.int(lo = 0, hi = 50), s);
        let viaEffect = fst(Random.withSeed(Random.initialSeed(s), () -> Random.sample(Random.int(lo = 0, hi = 50))));
        Assert.assertEq(expected = viaValue, viaEffect)

    @Test
    def testEffectThreadsSeedLikeList(): Unit \ Assert =
        // 1 回一致では順序ズレを見逃す。3 連続で並びごと一致させ、handler の種前進が
        // list の引き順と食い違わないことを守る。
        let s = 7i64;
        let viaValue = value(Random.list(3, Random.int(lo = 0, hi = 9)), s);
        let viaEffect = fst(Random.withSeed(Random.initialSeed(s), threeDraws));
        Assert.assertEq(expected = viaValue, viaEffect)

    // :: の評価順に結果を依存させないよう、let で引く順を固定する。
    def threeDraws(): List[Int32] \ Random.Rng =
        let a = Random.sample(Random.int(lo = 0, hi = 9));
        let b = Random.sample(Random.int(lo = 0, hi = 9));
        let c = Random.sample(Random.int(lo = 0, hi = 9));
        a :: b :: c :: Nil

    @Test
    def testWithSeedRunForm(): Unit \ Assert =
        // withSeed は最後の引数が thunk なので、直接呼びと run{}with 形式が同じ結果になる。
        let s = Random.initialSeed(12i64);
        let direct = fst(Random.withSeed(s, () -> Random.sample(Random.int(lo = 0, hi = 50))));
        let runForm = fst(run {
            Random.sample(Random.int(lo = 0, hi = 50))
        } with Random.withSeed(s));
        Assert.assertEq(expected = direct, runForm)

    @Test
    def testMap2MatchesAndThen(): Unit \ Assert =
        // map2 が ga→gb の順で引くこと（andThen 版と同値）を pin。
        let paired = Random.map2(a -> b -> (a, b),
            Random.int(lo = 0, hi = 100),
            Random.int(lo = 0, hi = 100));
        let manual = Random.int(lo = 0, hi = 100)
            |> Random.andThen(a -> Random.int(lo = 0, hi = 100) |> Random.map(b -> (a, b)));
        Assert.assertEq(expected = value(manual, 5i64), value(paired, 5i64))

    @Test
    def testToGenMatchesAndThen(): Unit \ Assert =
        // toGen で平らに書いた依存ドローが、andThen の入れ子版と同じ列を引く（橋が draw 順を保つ担保）。
        let flat = Random.toGen(() -> {
            let n = Random.sample(Random.int(lo = 1, hi = 5));
            Random.sample(Random.list(n, Random.int(lo = 0, hi = 9)))
        });
        let nested = Random.int(lo = 1, hi = 5) |> Random.andThen(n -> Random.list(n, Random.int(lo = 0, hi = 9)));
        Assert.assertEq(expected = value(nested, 4i64), value(flat, 4i64))

}
