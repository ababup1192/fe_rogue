/// Staff の純粋ロジックと staves.json デコードの検証。
///
/// 検証する観点:
///   - `consume` の境界（耐久 1 → 壊れる、3 → 残る）
///   - `parseEffect` の 3 値往復と未知文字列のエラー
///   - `toVec2i` で 4 方向それぞれが期待通りの単位ベクトルを返す
///   - `staves.json` 相当の JSON 文字列を `Saveable.fromJson` で round-trip デコードできる
mod TestStaff {

    // ════════════════════════════════════════════════════════
    // Staff.consume — 耐久度減少と「壊れたか」の境界
    // ════════════════════════════════════════════════════════

    /// 耐久 3 の杖を 1 回使うと耐久 2 で残る
    @Test
    def testConsumeDecrementsDurability(): Unit \ Assert =
        let staff = sampleStaff(Staff.StaffEffect.Heal, 3);
        // 耐久 3 を 1 回使うと Some(耐久 2) が残る（壊れず Some のまま）
        Assert.assertEq(expected = Some(2), Staff.consume(staff) |> Option.map(s -> s#durability))

    /// 耐久 1 の杖を 1 回使うと壊れる（None）
    /// 「最後の 1 回で壊れる」境界条件
    @Test
    def testConsumeBreaksAtZero(): Unit \ Assert =
        let staff = sampleStaff(Staff.StaffEffect.Heal, 1);
        let result = Staff.consume(staff);
        Assert.assertEq(expected = true, Option.isEmpty(result))

    // ════════════════════════════════════════════════════════
    // Staff.parseEffect / effectToString — 文字列との往復
    // ════════════════════════════════════════════════════════

    /// "Heal" / "Blowback" / "Swap" の 3 値が enum と相互変換できる
    @Test
    def testParseEffectKnownValues(): Unit \ Assert =
        Assert.assertEq(
            expected = (Ok(Staff.StaffEffect.Heal),
                         Ok(Staff.StaffEffect.Blowback),
                         Ok(Staff.StaffEffect.Swap)),
            (Staff.parseEffect("Heal"),
             Staff.parseEffect("Blowback"),
             Staff.parseEffect("Swap")))

    /// 未知文字列はそのまま `Err` で返る（schema が typo を起動時に発覚させる用途）
    @Test
    def testParseEffectUnknownReturnsErr(): Unit \ Assert =
        Assert.assertEq(expected = Err("Bogus"), Staff.parseEffect("Bogus"))

    /// `effectToString` → `parseEffect` で同じ enum に戻る
    @Test
    def testEffectStringRoundTrip(): Unit \ Assert =
        let heal     = Staff.parseEffect(Staff.effectToString(Staff.StaffEffect.Heal));
        let blowback = Staff.parseEffect(Staff.effectToString(Staff.StaffEffect.Blowback));
        let swap     = Staff.parseEffect(Staff.effectToString(Staff.StaffEffect.Swap));
        Assert.assertEq(
            expected = (Ok(Staff.StaffEffect.Heal),
                         Ok(Staff.StaffEffect.Blowback),
                         Ok(Staff.StaffEffect.Swap)),
            (heal, blowback, swap))

    // ════════════════════════════════════════════════════════
    // Staff.toVec2i — 4 方向の単位ベクトル
    // ════════════════════════════════════════════════════════

    /// 画面座標系（y 軸下向き）に従う 4 方向の {x, y}
    /// Up は y = -1、Down は y = +1。Left/Right は x のみ動く。
    /// {x, y} record には ToString が無いので (x, y) Int32 タプルに変換して比較する。
    @Test
    def testToVec2iFourDirections(): Unit \ Assert =
        Assert.assertEq(
            expected = ((0, -1), (0, 1), (-1, 0), (1, 0)),
            (vecToTuple(Staff.toVec2i(Staff.Direction.Up)),
             vecToTuple(Staff.toVec2i(Staff.Direction.Down)),
             vecToTuple(Staff.toVec2i(Staff.Direction.Left)),
             vecToTuple(Staff.toVec2i(Staff.Direction.Right))))

    /// `{x, y}` record を `(x, y)` Int32 タプルに変換するヘルパー。
    def vecToTuple(v: {x = Int32, y = Int32}): (Int32, Int32) = (v#x, v#y)

    // ════════════════════════════════════════════════════════
    // Staff.deltaToDirection — 差分ベクトルを 4 方位に丸める
    // ════════════════════════════════════════════════════════

    /// 主軸（絶対値が大きい方）を採用する。横と縦が同じ大きさのときは横を優先する。
    ///   ( 3,  0) → 右 / (-2, 1) → 左（|x|=2 >= |y|=1 なので横、x<0 で左）
    ///   ( 0, -4) → 上（縦で y<0）/ (1, 5) → 下（|x|=1 < |y|=5 なので縦、y>0 で下）
    @Test
    def testDeltaToDirectionPicksDominantAxis(): Unit \ Assert =
        Assert.assertEq(
            expected = (Staff.Direction.Right, Staff.Direction.Left,
                         Staff.Direction.Up, Staff.Direction.Down),
            (Staff.deltaToDirection(3, 0),
             Staff.deltaToDirection(-2, 1),
             Staff.deltaToDirection(0, -4),
             Staff.deltaToDirection(1, 5)))

    // ════════════════════════════════════════════════════════
    // Staff.pickHealDirection — 構える方位の選択
    // ════════════════════════════════════════════════════════

    /// 同じ行/列に並ぶ（射線が届く）位置を、近いだけの斜め位置より優先する。
    /// 原点(0,0)に対し、整列した遠い味方(0,5)＝下 と 近いが斜めの味方(1,1)。
    /// 整列優先なので Down を選ぶ。
    @Test
    def testPickHealDirectionPrefersAligned(): Unit \ Assert =
        let dir = Staff.pickHealDirection({x = 0, y = 0},
                    {x = 1, y = 1} :: {x = 0, y = 5} :: Nil);
        Assert.assertEq(expected = Some(Staff.Direction.Down), dir)

    /// 候補が空なら None（呼び出し側は既定 Up のまま構える）。
    @Test
    def testPickHealDirectionEmptyIsNone(): Unit \ Assert =
        let none: Option[Staff.Direction] = None;
        Assert.assertEq(expected = none,
            Staff.pickHealDirection({x = 0, y = 0}, Nil))

    // ════════════════════════════════════════════════════════
    // Staff.load round-trip — staves.json 文字列リテラルからのデコード
    // ════════════════════════════════════════════════════════

    /// staves.json と同じ構造の JSON 文字列リテラル。3 種類の杖をすべて含む。
    /// 杖は射程を持たない（壁/駒に当たるまで飛ぶ）ので `range` フィールドは持たない。
    def sampleStavesJson(): String = String.unlines(
        "{" ::
        "  \"staves\": {" ::
        "    \"live_staff\": {" ::
        "      \"name\": \"ライブのつえ\"," ::
        "      \"effect\": \"Heal\"," ::
        "      \"durability\": 8," ::
        "      \"sprite\": { \"texture\": \"item_skills\", \"hframes\": 20, \"vframes\": 30, \"frame\": 40 }" ::
        "    }," ::
        "    \"blowback_staff\": {" ::
        "      \"name\": \"ふきとばしのつえ\"," ::
        "      \"effect\": \"Blowback\"," ::
        "      \"durability\": 5," ::
        "      \"sprite\": { \"texture\": \"item_skills\", \"hframes\": 20, \"vframes\": 30, \"frame\": 41 }" ::
        "    }," ::
        "    \"swap_staff\": {" ::
        "      \"name\": \"いれかえのつえ\"," ::
        "      \"effect\": \"Swap\"," ::
        "      \"durability\": 5," ::
        "      \"sprite\": { \"texture\": \"item_skills\", \"hframes\": 20, \"vframes\": 30, \"frame\": 42 }" ::
        "    }" ::
        "  }" ::
        "}" :: Nil)

    /// 3 つの杖がすべて id でひけて、effect が期待通りに enum に解決される
    @Test
    def testDecodeSampleCatalog(): Unit \ Assert =
        let parsed = JsonCompat.parse(sampleStavesJson());
        let decoded: Option[Staff.StaffCatalog] =
            Option.flatMap(Saveable.fromJson, parsed);
        match decoded {
            case None          => bug!("sample staves catalog failed to decode")
            case Some(catalog) =>
                let staves = Staff.stavesOf(catalog);
                let liveOpt    = Map.get("live_staff", staves);
                let blowOpt    = Map.get("blowback_staff", staves);
                let swapOpt    = Map.get("swap_staff", staves);
                let effectsTriple = match (liveOpt, blowOpt, swapOpt) {
                    case (Some(live), Some(blow), Some(swap)) =>
                        (live#effect, blow#effect, swap#effect)
                    case _ => bug!("expected three staves in sample catalog")
                };
                Assert.assertEq(
                    expected = (3,
                                 Staff.StaffEffect.Heal,
                                 Staff.StaffEffect.Blowback,
                                 Staff.StaffEffect.Swap),
                    (Map.size(staves),
                     fst3(effectsTriple), snd3(effectsTriple), trd3(effectsTriple)))
        }

    /// `durability` / `sprite#frame` の値が期待通りに読み取られる
    @Test
    def testDecodeDurabilityAndSprite(): Unit \ Assert =
        let parsed = JsonCompat.parse(sampleStavesJson());
        let decoded: Option[Staff.StaffCatalog] =
            Option.flatMap(Saveable.fromJson, parsed);
        match decoded {
            case None          => bug!("sample staves catalog failed to decode")
            case Some(catalog) =>
                match Map.get("live_staff", Staff.stavesOf(catalog)) {
                    case None        => bug!("live_staff missing in sample catalog")
                    case Some(staff) =>
                        Assert.assertEq(
                            expected = (8, 40),
                            (staff#durability, staff#sprite#frame))
                }
        }

    // ════════════════════════════════════════════════════════
    // テスト用ヘルパー
    // ════════════════════════════════════════════════════════

    /// 効果と耐久を指定して最小限の杖を作る。`consume` テストでだけ使う。
    def sampleStaff(effect: Staff.StaffEffect, durability: Int32): Staff.StaffResource =
        {name = "テスト",
         effect = effect,
         durability = durability,
         sprite = ({texture = "t", hframes = 1, vframes = 1, frame = 0,
                     offset = {x = 0.0, y = 0.0},
                     scale = {x = 1.0, y = 1.0}, flipForFacing = false}: Sprite.SpriteResource),
         description = ""}

    /// 3 タプルの要素取り出し（Flix 標準には 3 タプル用 fst/snd/trd がないため局所定義）
    def fst3(t: (a, b, c)): a = match t { case (a, _, _) => a }
    def snd3(t: (a, b, c)): b = match t { case (_, b, _) => b }
    def trd3(t: (a, b, c)): c = match t { case (_, _, c) => c }
}
