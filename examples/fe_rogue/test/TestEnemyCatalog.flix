/// EnemyCatalog の decode / Saveable round-trip を固定する（味方 UnitCatalog から分離した敵カタログ）。
///
/// 観点:
///   - decode が必須フィールドそろった敵 JSON から EnemyResource を返す（成長率は読まない）
///   - 敵 JSON に紛れた `growthRates`（player JSON からのコピペ等）は **無害に無視** される
///     ＝敵は成長率の概念を持たない、という構造分離を振る舞いで固定する
///   - round-trip: 1 件 catalog を Saveable.toJson → fromJson で同じ値が戻る
///
/// ファイル I/O は介さない（起動時の `CatalogContainer.loadWithCheck` が schema 整合性を担保する）。
mod TestEnemyCatalog {

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber, JsonArray}
    use EnemyCatalog.{EnemyCatalog, EnemyResource}

    // ════════════════════════════════════════════════════════
    // フィクスチャ
    // ════════════════════════════════════════════════════════

    /// 武器 1 本持ちの goblin（成長率なし）。round-trip 用の in-memory リソース。
    def goblin(): EnemyResource = {
        moveTiles    = 3,
        level        = 4,
        hp           = 6,
        attack       = 3,
        defense      = 1,
        magicAttack  = 0,
        magicDefense = 0,
        speed        = 4,
        skill        = 2,
        luck         = 1,
        initialInventory =
            ({kind = UnitBase.ItemKind.Weapon, id = "trainingSword"}:
               UnitBase.InventoryEntry) :: Nil,
        description  = "ゴブリン",
        sprite       = {
            texture = "character_sheet",
            hframes = 5, vframes = 2, frame = 4,
            offset  = ({x = 0.0, y = 0.0}: Vec2.Vec2),
            scale   = ({x = 1.0, y = 1.0}: Vec2.Vec2)
        },
        spriteFrames = None
    }

    def spriteJson(): JsonElement =
        JsonObject(Map#{
            "texture" => JsonString("character_sheet"),
            "hframes" => JsonNumber(JsonCodec.intToBd(5)),
            "vframes" => JsonNumber(JsonCodec.intToBd(2)),
            "frame"   => JsonNumber(JsonCodec.intToBd(4))
        })

    def inventoryJson(): JsonElement =
        JsonArray(Vector#{
            JsonObject(Map#{
                "kind" => JsonString("weapon"),
                "id"   => JsonString("trainingSword")
            })
        })

    /// 敵 1 種ぶんの完全な JSON（成長率なし）。
    def goblinJson(): JsonElement =
        JsonObject(Map#{
            "moveTiles"        => JsonNumber(JsonCodec.intToBd(3)),
            "level"            => JsonNumber(JsonCodec.intToBd(4)),
            "hp"               => JsonNumber(JsonCodec.intToBd(6)),
            "attack"           => JsonNumber(JsonCodec.intToBd(3)),
            "defense"          => JsonNumber(JsonCodec.intToBd(1)),
            "speed"            => JsonNumber(JsonCodec.intToBd(4)),
            "skill"            => JsonNumber(JsonCodec.intToBd(2)),
            "luck"             => JsonNumber(JsonCodec.intToBd(1)),
            "description"      => JsonString("ゴブリン"),
            "initialInventory" => inventoryJson(),
            "sprite"           => spriteJson()
        })

    // ════════════════════════════════════════════════════════
    // decode: 完全な JSON から EnemyResource が組み立てられる
    // ════════════════════════════════════════════════════════

    /// 必須 + 任意フィールドが揃った敵 JSON から EnemyResource を取り出すと、
    /// level / hp / attack / defense / speed がそれぞれ期待値に一致する。
    @Test
    def testDecodeEnemyFromCompleteJson(): Unit \ Assert =
        match EnemyCatalogCodec.decodeEnemy(goblinJson()) {
            case Some(e) =>
                Assert.assertEq(
                    expected = (4, 6, 3, 1, 4),
                    (e#level, e#hp, e#attack, e#defense, e#speed))
            case None => bug!("expected enemy decode to succeed")
        }

    // ════════════════════════════════════════════════════════
    // 敵は成長率を持たない: 紛れ込んだ growthRates は無視される
    // ════════════════════════════════════════════════════════

    /// 敵 JSON に `growthRates`（player からのコピペ等）が混ざっていても、
    /// 敵デコーダはそれを読まずに通常どおり decode する（成長率は敵の型に存在しない）。
    /// growthRates の有無で結果が変わらないこと ＝ 敵に成長率が無いことの振る舞い確認。
    @Test
    def testEnemyDecodeIgnoresGrowthRates(): Unit \ Assert =
        let withGrowth = match goblinJson() {
            case JsonObject(m) =>
                JsonObject(Map.insert("growthRates", JsonObject(Map#{
                    "hp"           => JsonNumber(JsonCodec.intToBd(80)),
                    "attack"       => JsonNumber(JsonCodec.intToBd(50)),
                    "defense"      => JsonNumber(JsonCodec.intToBd(40)),
                    "magicAttack"  => JsonNumber(JsonCodec.intToBd(20)),
                    "magicDefense" => JsonNumber(JsonCodec.intToBd(30)),
                    "speed"        => JsonNumber(JsonCodec.intToBd(45))
                }), m))
            case other => other
        };
        match (EnemyCatalogCodec.decodeEnemy(goblinJson()),
               EnemyCatalogCodec.decodeEnemy(withGrowth)) {
            case (Some(plain), Some(spiked)) =>
                // growthRates の有無に関わらず同じステータスが decode される
                Assert.assertEq(
                    expected = (plain#level, plain#hp, plain#attack),
                    (spiked#level, spiked#hp, spiked#attack))
            case _ => bug!("expected both enemy decodes to succeed")
        }

    // ════════════════════════════════════════════════════════
    // EnemyCatalog round-trip (Saveable 経由)
    // ════════════════════════════════════════════════════════

    /// 1 件の敵 (goblin) を含む catalog を Saveable.toJson → fromJson すると、
    /// 元の level / hp / description が戻る。
    @Test
    def testCatalogRoundTripPreservesEnemy(): Unit \ Assert =
        let container = CatalogContainer.CatalogContainer({
            containerKey = "enemies",
            entries      = Map#{"goblin" => goblin()},
            meta         = (Map.empty(): Map[String, JsonElement])
        });
        let catalog = EnemyCatalog.EnemyCatalog(container);
        let encoded = Saveable.toJson(catalog);
        let decoded: Option[EnemyCatalog] = Saveable.fromJson(encoded);
        match decoded {
            case Some(restored) =>
                match EnemyCatalog.get("goblin", restored) {
                    case Some(e) =>
                        Assert.assertEq(
                            expected = (4, 6, "ゴブリン"),
                            (e#level, e#hp, e#description))
                    case None => bug!("expected goblin in restored catalog")
                }
            case None => bug!("expected enemy catalog round-trip to succeed")
        }
}
