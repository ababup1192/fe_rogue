/// Consumable の純粋ロジックと consumables.json デコードの検証。
///
/// 検証する観点:
///   - `consume` の境界（耐久 3 → 残る、1 → 使い切る = None）の段階遷移
///   - `consumables.json` 相当の JSON 文字列を `Saveable.fromJson` で round-trip デコードできる
///   - `healAmount` / `durability` / `sprite#frame` が期待通りに読み取られる
mod TestConsumable {

    // ════════════════════════════════════════════════════════
    // Consumable.consume — 使用回数の減少と「使い切ったか」の境界
    // ════════════════════════════════════════════════════════

    /// 耐久（使用回数）3 のアイテムを 1 回使うと耐久 2 で残る
    @Test
    def testConsumeDecrementsDurability(): Unit \ Assert =
        let item = sampleConsumable(10, 3);
        match Consumable.consume(item) {
            case Some(c) => Assert.assertEq(expected = 2, c#durability)
            case None    => bug!("耐久 3 のアイテムは 1 回使っても壊れず残るはず")
        }

    /// 耐久 1 のアイテムを 1 回使うと使い切る（None）。「最後の 1 回」境界条件。
    @Test
    def testConsumeBreaksAtZero(): Unit \ Assert =
        let item = sampleConsumable(10, 1);
        let result = Consumable.consume(item);
        Assert.assertEq(expected = true, Option.isEmpty(result))

    /// 3 → 2 → 1 → None の段階遷移（きずぐすりは 3 回使える）
    @Test
    def testConsumeThreeUsesThenGone(): Unit \ Assert =
        let item = sampleConsumable(10, 3);
        let after1 = Consumable.consume(item);
        let after2 = Option.flatMap(Consumable.consume, after1);
        let after3 = Option.flatMap(Consumable.consume, after2);
        let dur = c -> Option.map(x -> x#durability, c) |> Option.getWithDefault(-1);
        Assert.assertEq(
            expected = (2, 1, true),
            (dur(after1), dur(after2), Option.isEmpty(after3)))

    // ════════════════════════════════════════════════════════
    // Consumable.load round-trip — consumables.json 文字列リテラルからのデコード
    // ════════════════════════════════════════════════════════

    /// consumables.json と同じ構造の JSON 文字列リテラル。
    def sampleConsumablesJson(): String = String.unlines(
        "{" ::
        "  \"consumables\": {" ::
        "    \"vulnerary\": {" ::
        "      \"name\": \"きずぐすり\"," ::
        "      \"healAmount\": 10," ::
        "      \"durability\": 3," ::
        "      \"sprite\": { \"texture\": \"item_icons\", \"hframes\": 16, \"vframes\": 39, \"frame\": 240 }" ::
        "    }" ::
        "  }" ::
        "}" :: Nil)

    /// vulnerary が id でひけて、healAmount / durability / sprite#frame が期待通りに読める
    @Test
    def testDecodeSampleCatalog(): Unit \ Assert =
        // デコード → consumables Map 取得までを Option チェーンで 1 本にして、
        // 期待ケース（vulnerary が引ける）だけにマッチさせる。
        let items = JsonCompat.parse(sampleConsumablesJson())
            |> Option.flatMap(Saveable.fromJson)
            |> Option.map(Consumable.consumablesOf)
            |> Option.getWithDefault(Map.empty());
        // vulnerary を Option のまま (healAmount, durability, sprite#frame) に写し、
        // 期待値 Some(...) と直接比較する（引けなければ None として落ちる）。
        let found = Map.get("vulnerary", items)
            |> Option.map(item -> (item#healAmount, item#durability, item#sprite#frame));
        Assert.assertEq(
            expected = (1, Some((10, 3, 240))),
            (Map.size(items), found))

    // ════════════════════════════════════════════════════════
    // テスト用ヘルパー
    // ════════════════════════════════════════════════════════

    /// 回復量と耐久を指定して最小限の消費アイテムを作る。`consume` テストでだけ使う。
    def sampleConsumable(healAmount: Int32, durability: Int32): Consumable.ConsumableResource =
        {name = "テスト",
         healAmount = healAmount,
         durability = durability,
         sprite = ({texture = "t", hframes = 1, vframes = 1, frame = 0,
                     offset = {x = 0.0, y = 0.0},
                     scale = {x = 1.0, y = 1.0}, flipForFacing = false}: Sprite.SpriteResource),
         description = ""}
}
