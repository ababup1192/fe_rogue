/// WeaponCatalog の decode / Saveable round-trip を固定する。
///
/// 観点:
///   - decode が必須フィールドそろった JSON から WeaponResource を返す
///   - weaponType 省略時に Physical にフォールバックする (旧 weapons.json への後方互換)
///   - weaponType 未知文字列 (例: "Foo") も Physical にフォールバックする
///   - round-trip: 1 件 catalog を Saveable.toJson → fromJson で同じ値が戻る
///   - lookup 境界: 存在する id で正しい武器、未定義 id で panic させずに済む API は無いため
///     `WeaponCatalog.weaponsOf` ↔ `Map.get` で確認する
mod TestWeaponCatalog {

    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JNumber}
    use WeaponCatalog.{WeaponCatalog, WeaponResource, WeaponRange, WeaponType, WeaponSpriteResource}

    // ════════════════════════════════════════════════════════
    // フィクスチャ
    // ════════════════════════════════════════════════════════

    /// 「くんれんやり」風の最小武器。range 1-1、Lance（槍）、durability 41。
    def trainingSpear(): WeaponResource = {
        name       = "くんれんやり",
        attack     = 2,
        hit        = 70,
        durability = 41,
        range      = ({min = 1, max = 1}: WeaponRange),
        weaponType = WeaponType.Lance,
        sprite     = testSprite(),
        description = "くんれん用の槍"
    }

    def testSprite(): WeaponSpriteResource = {
        texture = "weapons_atlas",
        hframes = 4, vframes = 1, frame = 0,
        offset  = ({x = 0.0, y = 0.0}: Vec2.Vec2),
        scale   = ({x = 1.0, y = 1.0}: Vec2.Vec2),
        flipForFacing = false
    }

    /// 1 件 (trainingSpear) を含む weapons.json 相当の minimum JSON。
    def trainingSpearJson(): Json =
        JObject(Map#{
            "name"       => JString("くんれんやり"),
            "attack"     => JNumber(JsonCodec.intToBd(2)),
            "durability" => JNumber(JsonCodec.intToBd(41)),
            "range"      => JObject(Map#{
                "min" => JNumber(JsonCodec.intToBd(1)),
                "max" => JNumber(JsonCodec.intToBd(1))
            }),
            "weaponType" => JString("Physical"),
            "sprite"     => spriteJson()
        })

    def spriteJson(): Json =
        JObject(Map#{
            "texture" => JString("weapons_atlas"),
            "hframes" => JNumber(JsonCodec.intToBd(4)),
            "vframes" => JNumber(JsonCodec.intToBd(1)),
            "frame"   => JNumber(JsonCodec.intToBd(0)),
            "offset"  => JObject(Map#{
                "x" => JNumber(JsonCodec.floatToBd(0.0)),
                "y" => JNumber(JsonCodec.floatToBd(0.0))
            }),
            "scale"   => JObject(Map#{
                "x" => JNumber(JsonCodec.floatToBd(1.0)),
                "y" => JNumber(JsonCodec.floatToBd(1.0))
            })
        })

    // ════════════════════════════════════════════════════════
    // decode: 完全な JSON から WeaponResource が組み立てられる
    // ════════════════════════════════════════════════════════

    /// 必須フィールド (name / attack / durability / range / weaponType / sprite) が
    /// 揃った JSON から WeaponResource を取り出すと、name / attack / durability /
    /// range#max / weaponType がそれぞれ期待値に一致する
    @Test
    def testDecodeWeaponFromCompleteJson(): Unit \ Assert =
        match WeaponCatalogCodec.decodeWeapon(trainingSpearJson()) {
            case Some(weapon) =>
                Assert.assertEq(
                    expected = ("くんれんやり", 2, 41, 1, true),
                    (weapon#name, weapon#attack, weapon#durability, weapon#range#max,
                     WeaponCatalog.isPhysical(weapon#weaponType)))
            case None => bug!("expected weapon decode to succeed")
        }

    /// description フィールドが無い JSON は空文字にフォールバックする。
    /// （旧 weapons.json / 旧セーブへの後方互換。trainingSpearJson は description を持たない）
    @Test
    def testDecodeWeaponDefaultsDescriptionEmptyWhenMissing(): Unit \ Assert =
        match WeaponCatalogCodec.decodeWeapon(trainingSpearJson()) {
            case Some(weapon) =>
                Assert.assertEq(expected = "", weapon#description)
            case None => bug!("expected weapon decode to succeed")
        }

    // ════════════════════════════════════════════════════════
    // weaponType の後方互換 / フォールバック
    // ════════════════════════════════════════════════════════

    /// weaponType フィールドが無い JSON は剣 (Sword) にフォールバックする
    /// (旧 weapons.json への後方互換。Sword は物理武器なので isPhysical = true)
    @Test
    def testDecodeWeaponDefaultsToPhysicalWhenWeaponTypeMissing(): Unit \ Assert =
        let json = JObject(Map#{
            "name"       => JString("test"),
            "attack"     => JNumber(JsonCodec.intToBd(1)),
            "durability" => JNumber(JsonCodec.intToBd(10)),
            "range"      => JObject(Map#{
                "min" => JNumber(JsonCodec.intToBd(1)),
                "max" => JNumber(JsonCodec.intToBd(1))
            }),
            "sprite"     => spriteJson()
        });
        match WeaponCatalogCodec.decodeWeapon(json) {
            case Some(weapon) =>
                Assert.assertEq(expected = true,
                                  WeaponCatalog.isPhysical(weapon#weaponType))
            case None => bug!("expected weapon decode to succeed without weaponType")
        }

    /// weaponType 文字列が未知 ("Foo") の場合も剣 (Sword) にフォールバックする
    /// (schema が enum を強制するため通常は到達しないが、JSON 直編集の typo 対策)
    @Test
    def testDecodeWeaponFallsBackToPhysicalForUnknownType(): Unit \ Assert =
        let json = JObject(Map#{
            "name"       => JString("test"),
            "attack"     => JNumber(JsonCodec.intToBd(1)),
            "durability" => JNumber(JsonCodec.intToBd(10)),
            "range"      => JObject(Map#{
                "min" => JNumber(JsonCodec.intToBd(1)),
                "max" => JNumber(JsonCodec.intToBd(1))
            }),
            "weaponType" => JString("Foo"),
            "sprite"     => spriteJson()
        });
        match WeaponCatalogCodec.decodeWeapon(json) {
            case Some(weapon) =>
                Assert.assertEq(expected = true,
                                  WeaponCatalog.isPhysical(weapon#weaponType))
            case None => bug!("expected weapon decode to succeed with unknown weaponType")
        }

    // ════════════════════════════════════════════════════════
    // Magic weaponType: フォールバックではなく明示指定が反映される
    // ════════════════════════════════════════════════════════

    /// weaponType "Magic" の JSON は Magic 武器として decode される
    @Test
    def testDecodeWeaponPreservesMagicType(): Unit \ Assert =
        let json = JObject(Map#{
            "name"       => JString("staff"),
            "attack"     => JNumber(JsonCodec.intToBd(3)),
            "durability" => JNumber(JsonCodec.intToBd(20)),
            "range"      => JObject(Map#{
                "min" => JNumber(JsonCodec.intToBd(1)),
                "max" => JNumber(JsonCodec.intToBd(2))
            }),
            "weaponType" => JString("Magic"),
            "sprite"     => spriteJson()
        });
        match WeaponCatalogCodec.decodeWeapon(json) {
            case Some(weapon) =>
                Assert.assertEq(expected = false,
                                  WeaponCatalog.isPhysical(weapon#weaponType))
            case None => bug!("expected weapon decode to succeed with Magic type")
        }

    // ════════════════════════════════════════════════════════
    // WeaponCatalog round-trip (Saveable 経由)
    // ════════════════════════════════════════════════════════

    /// 1 件の武器 (trainingSpear) を含む catalog を Saveable.toJson → fromJson すると
    /// 元の name / attack / durability が戻る
    @Test
    def testCatalogRoundTripPreservesWeapon(): Unit \ Assert =
        let container = CatalogContainer.CatalogContainer({
            containerKey = "weapons",
            entries      = Map#{"trainingSpear" => trainingSpear()},
            meta         = (Map.empty(): Map[String, Json])
        });
        let catalog = WeaponCatalog.WeaponCatalog.WeaponCatalog(container);
        let encoded = Saveable.toJson(catalog);
        let decoded: Option[WeaponCatalog] = Saveable.fromJson(encoded);
        match decoded {
            case Some(restored) =>
                match Map.get("trainingSpear", WeaponCatalog.weaponsOf(restored)) {
                    case Some(weapon) =>
                        Assert.assertEq(
                            expected = ("くんれんやり", 2, 41),
                            (weapon#name, weapon#attack, weapon#durability))
                    case None => bug!("expected trainingSpear in restored catalog")
                }
            case None => bug!("expected weapon catalog round-trip to succeed")
        }
}
