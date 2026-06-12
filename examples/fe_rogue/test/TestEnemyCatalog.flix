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

    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JNumber, JArray}
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
            ({kind = UnitBase.ItemKind.Weapon, id = "iron_sword"}:
               UnitBase.InventoryEntry) :: Nil,
        description  = "ゴブリン",
        sprite       = {
            texture = "character_sheet",
            hframes = 5, vframes = 2, frame = 4,
            offset  = ({x = 0.0, y = 0.0}: Vec2.Vec2),
            scale   = ({x = 1.0, y = 1.0}: Vec2.Vec2),
            flipForFacing = false
        },
        spriteFrames = None,
        aiType       = EnemyAI.AiType.Wanderer,
        ring         = None
    }

    def spriteJson(): Json =
        JObject(Map#{
            "texture" => JString("character_sheet"),
            "hframes" => JNumber(JsonCodec.intToBd(5)),
            "vframes" => JNumber(JsonCodec.intToBd(2)),
            "frame"   => JNumber(JsonCodec.intToBd(4))
        })

    def inventoryJson(): Json =
        JArray(Vector#{
            JObject(Map#{
                "kind" => JString("weapon"),
                "id"   => JString("iron_sword")
            })
        })

    /// 敵 1 種ぶんの完全な JSON フィールド（成長率なし）。aiType を差し込みたいテストが
    /// パターンマッチせず `Map.insert` で 1 フィールド足せるよう、Map を直接返す。
    def goblinFields(): Map[String, Json] =
        Map#{
            "moveTiles"        => JNumber(JsonCodec.intToBd(3)),
            "level"            => JNumber(JsonCodec.intToBd(4)),
            "hp"               => JNumber(JsonCodec.intToBd(6)),
            "attack"           => JNumber(JsonCodec.intToBd(3)),
            "defense"          => JNumber(JsonCodec.intToBd(1)),
            "speed"            => JNumber(JsonCodec.intToBd(4)),
            "skill"            => JNumber(JsonCodec.intToBd(2)),
            "luck"             => JNumber(JsonCodec.intToBd(1)),
            "description"      => JString("ゴブリン"),
            "initialInventory" => inventoryJson(),
            "sprite"           => spriteJson()
        }

    /// 敵 1 種ぶんの完全な JSON（成長率なし）。
    def goblinJson(): Json = JObject(goblinFields())

    /// goblin JSON に `aiType` 文字列を 1 つ足したもの（パターンマッチ不要）。
    def goblinJsonWith(aiType: String): Json =
        JObject(Map.insert("aiType", JString(aiType), goblinFields()))

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

    /// aiType を指定しない JSON は Aggressive にフォールバックし、明示した文字列は対応 case に decode、
    /// 未知文字列も Aggressive に落ちる（後方互換 + 安全側）。
    @Test
    def testDecodeAiTypeDefaultsAndParses(): Unit \ Assert =
        // decode 結果から aiType を Option のまま取り出す（マッチせず Option.map で射影）。
        let typeOf = (j: Json) -> EnemyCatalogCodec.decodeEnemy(j) |> Option.map(e -> e#aiType);
        // 欠落 → Aggressive / 既知 → 対応 case / 未知 → Aggressive
        Assert.assertEq(expected = Some(EnemyAI.AiType.Aggressive),        typeOf(goblinJson()));
        Assert.assertEq(expected = Some(EnemyAI.AiType.GuardUntilInRange), typeOf(goblinJsonWith("GuardUntilInRange")));
        Assert.assertEq(expected = Some(EnemyAI.AiType.Wanderer),          typeOf(goblinJsonWith("Wanderer")));
        Assert.assertEq(expected = Some(EnemyAI.AiType.Aggressive),        typeOf(goblinJsonWith("Bogus")))

    /// catalog round-trip で aiType が保存される（goblin = Wanderer）。
    @Test
    def testCatalogRoundTripPreservesAiType(): Unit \ Assert =
        let container = CatalogContainer.CatalogContainer({
            containerKey = "enemies",
            entries      = Map#{"goblin" => goblin()},
            meta         = (Map.empty(): Map[String, Json])
        });
        let encoded = Saveable.toJson(EnemyCatalog.EnemyCatalog(container));
        let decoded: Option[EnemyCatalog] = Saveable.fromJson(encoded);
        // restore → goblin 取得 → aiType を Option チェーンで射影し、Option ごと比較（マッチ不要）。
        let aiType = decoded
            |> Option.flatMap(restored -> EnemyCatalog.get("goblin", restored))
            |> Option.map(e -> e#aiType);
        Assert.assertEq(expected = Some(EnemyAI.AiType.Wanderer), aiType)

    // ════════════════════════════════════════════════════════
    // 敵は成長率を持たない: 紛れ込んだ growthRates は無視される
    // ════════════════════════════════════════════════════════

    /// 敵 JSON に `growthRates`（player からのコピペ等）が混ざっていても、
    /// 敵デコーダはそれを読まずに通常どおり decode する（成長率は敵の型に存在しない）。
    /// growthRates の有無で結果が変わらないこと ＝ 敵に成長率が無いことの振る舞い確認。
    @Test
    def testEnemyDecodeIgnoresGrowthRates(): Unit \ Assert =
        let withGrowth = match goblinJson() {
            case JObject(m) =>
                JObject(Map.insert("growthRates", JObject(Map#{
                    "hp"           => JNumber(JsonCodec.intToBd(80)),
                    "attack"       => JNumber(JsonCodec.intToBd(50)),
                    "defense"      => JNumber(JsonCodec.intToBd(40)),
                    "magicAttack"  => JNumber(JsonCodec.intToBd(20)),
                    "magicDefense" => JNumber(JsonCodec.intToBd(30)),
                    "speed"        => JNumber(JsonCodec.intToBd(45))
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
            meta         = (Map.empty(): Map[String, Json])
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
