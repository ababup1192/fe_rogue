/// 武器カタログ (`resources/weapons.json` + `resources/weapons.schema.json`)。
///
/// 段階 6 のリファクタで UnitCatalog 内に同居していた weapons 部分を独立 catalog として
/// 抽出した。engine の `CatalogContainer[WeaponResource]` + `Saveable` 単相 instance の
/// パターンに従う。
///
/// JSON 形状 (`resources/weapons.json`):
///   {
///     "weapons": {
///       "trainingSpear": { "name": "くんれんやり", "attack": 2, "durability": 41,
///                            "range": {"min":1, "max":1}, "weaponType": "Physical",
///                            "sprite": {...} },
///       ...
///     }
///   }
///
/// **設計メモ**:
///   - `WeaponSpriteResource` は中立な `Sprite.SpriteResource` の alias。
///     sprite 型は `Sprite` mod に集約済みで、Unit/Weapon/Staff が共有する (逆向き依存なし)
///   - encode は `Saveable[WeaponCatalog]` 経由で pure シグネチャ
///     (内部の `JsonCodec.floatToBd` / `intToBd` が `unsafe IO` を隠蔽)
///   - decode は完全 pure。エラーは Option で伝播し、`load` で panic に上げる
mod WeaponCatalog {

    use Json.JsonElement
    use Json.JsonElement.{JsonObject}

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// 武器カタログ全体。`CatalogContainer[WeaponResource]` を wrap して `Saveable` を持たせる。
    /// containerKey は `"weapons"` 固定。
    /// **配置順の注意**: companion enum (= モジュール名と同名 enum) は Flix の規約により
    /// 必ずモジュール先頭に置く必要がある。
    pub enum WeaponCatalog {
        case WeaponCatalog(CatalogContainer[WeaponResource])
    }

    /// 武器の属性 (物理 / 魔法)。
    /// 物理は `力 vs 防御`、魔法は `魔力 vs 魔防` で計算される。
    /// JSON では `"Physical"` / `"Magic"` の文字列でシリアライズされる。
    pub enum WeaponType with Eq, ToString {
        case Physical
        case Magic
    }

    /// `WeaponType` が物理武器か。Combat 系の分岐で使う薄いヘルパ。
    pub def isPhysical(weaponType: WeaponType): Bool = match weaponType {
        case WeaponType.Physical => true
        case WeaponType.Magic    => false
    }

    /// 攻撃可能な距離の範囲。`min..max` inclusive のマンハッタン距離で判定する。
    pub type alias WeaponRange = {
        min = Int32,
        max = Int32
    }

    /// 武器カタログの sprite メタ情報。中立な `Sprite.SpriteResource` の alias として共有する。
    /// 段階 6c の共通化で実体を `Sprite` mod に切り出し、UnitCatalog への逆向き依存を断った。
    pub type alias WeaponSpriteResource = Sprite.SpriteResource

    /// 武器 1 種類ぶんのデータ。
    /// `name` は表示用の和名。`attack` は武器の攻撃力ボーナス、`durability` は耐久度。
    /// `range` は攻撃可能距離。`weaponType` は物理 / 魔法。`sprite` は ItemMenu アイコン用。
    pub type alias WeaponResource = {
        name       = String,
        attack     = Int32,
        durability = Int32,
        range      = WeaponRange,
        weaponType = WeaponType,
        sprite     = WeaponSpriteResource
    }

    // ────────────────────────────────────────────────────────
    // (B) アクセサ / ロード
    // ────────────────────────────────────────────────────────

    /// weapons 部 (id → WeaponResource) を取り出す。
    pub def weaponsOf(catalog: WeaponCatalog): Map[String, WeaponResource] =
        let WeaponCatalog.WeaponCatalog(container) = catalog;
        CatalogContainer.entriesOf(container)

    /// `resources/weapons.json` をロードし、`resources/weapons.schema.json` で整合検査する。
    /// 起動時の `Game.start` で 1 度だけ呼ぶ想定。失敗は panic で即可視化。
    pub def load(): WeaponCatalog \ Fs.FileRead =
        let container = CatalogContainer.loadWithCheck({
            dataPath       = "resources/weapons.json",
            schemaPath     = "resources/weapons.schema.json",
            containerKey   = "weapons",
            expectedFields = expectedFields(),
            decodeEntry    = WeaponCatalogCodec.decodeWeapon
        });
        WeaponCatalog.WeaponCatalog(container)

    /// 武器 id を引いて `WeaponResource` を返す。未定義 id は起動時 typo として panic。
    pub def lookup(id: String, catalog: WeaponCatalog): WeaponResource =
        let WeaponCatalog.WeaponCatalog(container) = catalog;
        match CatalogContainer.get(id, container) {
            case Some(weapon) => weapon
            case None         => bug!("WeaponCatalog.lookup: weapon '${id}' not in catalog")
        }

    /// 空の `WeaponCatalog` (entries 0 件) を返す。`UnitCatalog` の Saveable.fromJson が
    /// placeholder として使う (実際の weapons は `loadFromString` 経由で後段で組み込まれる)。
    pub def empty(): WeaponCatalog =
        WeaponCatalog.WeaponCatalog(CatalogContainer.CatalogContainer({
            containerKey = "weapons",
            entries      = (Map.empty(): Map[String, WeaponResource]),
            meta         = (Map.empty(): Map[String, Json.JsonElement])
        }))

    /// `WeaponResource` のフィールド名集合。`weapons.schema.json` との整合性検査に使う。
    pub def expectedFields(): Set[String] =
        Set#{"name", "attack", "durability", "range", "weaponType", "sprite"}
}

// ════════════════════════════════════════════════════════════════════════
// Saveable[WeaponCatalog] — weapons.json の round-trip 実装 (薄い wrap)
// ════════════════════════════════════════════════════════════════════════

instance Saveable[WeaponCatalog.WeaponCatalog] {
    pub def toJson(value: WeaponCatalog.WeaponCatalog): Json.JsonElement =
        let WeaponCatalog.WeaponCatalog.WeaponCatalog(container) = value;
        CatalogContainer.encode(WeaponCatalogCodec.encodeWeapon, container)

    pub def fromJson(element: Json.JsonElement): Option[WeaponCatalog.WeaponCatalog] =
        CatalogContainer.decode("weapons", WeaponCatalogCodec.decodeWeapon, element)
            |> Option.map(WeaponCatalog.WeaponCatalog.WeaponCatalog)
}

/// WeaponResource 1 件分の encode / decode。container 巡回は `CatalogContainer.encode/decode` に委譲する。
mod WeaponCatalogCodec {

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber}
    use JsonCodec.{expectObject, expectString, expectInt, expectFloat, floatToBd, intToBd}
    use WeaponCatalog.{WeaponResource, WeaponRange, WeaponType, WeaponSpriteResource}

    // ── エンコード ──

    pub def encodeWeapon(weapon: WeaponResource): JsonElement =
        JsonObject(Map#{
            "name"       => JsonString(weapon#name),
            "attack"     => JsonNumber(intToBd(weapon#attack)),
            "durability" => JsonNumber(intToBd(weapon#durability)),
            "range"      => encodeRange(weapon#range),
            "weaponType" => JsonString(weaponTypeToString(weapon#weaponType)),
            "sprite"     => encodeSprite(weapon#sprite)
        })

    def encodeRange(range: WeaponRange): JsonElement =
        JsonObject(Map#{
            "min" => JsonNumber(intToBd(range#min)),
            "max" => JsonNumber(intToBd(range#max))
        })

    def weaponTypeToString(weaponType: WeaponType): String = match weaponType {
        case WeaponType.Physical => "Physical"
        case WeaponType.Magic    => "Magic"
    }

    def encodeSprite(sprite: WeaponSpriteResource): JsonElement =
        JsonObject(Map#{
            "texture" => JsonString(sprite#texture),
            "hframes" => JsonNumber(intToBd(sprite#hframes)),
            "vframes" => JsonNumber(intToBd(sprite#vframes)),
            "frame"   => JsonNumber(intToBd(sprite#frame)),
            "offset"  => JsonCodec.encodeVec2(sprite#offset),
            "scale"   => JsonCodec.encodeVec2(sprite#scale)
        })

    // ── デコード ──

    pub def decodeWeapon(element: JsonElement): Option[WeaponResource] =
        forM (
            obj    <- expectObject(element);
            nameJ  <- Map.get("name", obj);
            atkJ   <- Map.get("attack", obj);
            durJ   <- Map.get("durability", obj);
            rngJ   <- Map.get("range", obj);
            spJ    <- Map.get("sprite", obj);
            name   <- expectString(nameJ);
            atk    <- expectInt(atkJ);
            dur    <- expectInt(durJ);
            rng    <- decodeRange(rngJ);
            sp     <- decodeSprite(spJ)
        ) yield {
            // weaponType は省略可能。欠落 / 未知文字列は Physical (旧 weapons.json への後方互換)
            let wt = Map.get("weaponType", obj)
                        |> Option.flatMap(expectString)
                        |> Option.map(parseWeaponType)
                        |> Option.getWithDefault(WeaponType.Physical);
            ({name = name, attack = atk, durability = dur, range = rng,
              weaponType = wt, sprite = sp}: WeaponResource)
        }

    /// `"Physical"` / `"Magic"` 文字列から `WeaponType` に。未知文字列は Physical にフォールバック。
    def parseWeaponType(text: String): WeaponType = match text {
        case "Magic" => WeaponType.Magic
        case _       => WeaponType.Physical
    }

    def decodeRange(element: JsonElement): Option[WeaponRange] =
        forM (
            obj    <- expectObject(element);
            minJ   <- Map.get("min", obj);
            maxJ   <- Map.get("max", obj);
            mn     <- expectInt(minJ);
            mx     <- expectInt(maxJ)
        ) yield ({min = mn, max = mx}: WeaponRange)

    def decodeSprite(element: JsonElement): Option[WeaponSpriteResource] =
        forM (
            obj    <- expectObject(element);
            texJ   <- Map.get("texture", obj);
            hfJ    <- Map.get("hframes", obj);
            vfJ    <- Map.get("vframes", obj);
            frJ    <- Map.get("frame", obj);
            tex    <- expectString(texJ);
            hf     <- expectInt(hfJ);
            vf     <- expectInt(vfJ);
            fr     <- expectInt(frJ)
        ) yield {
            // offset / scale は省略可能。欠落 / 不正は (0,0) / (1,1) にフォールバック
            let off = JsonCodec.decodeVec2OrDefault(Map.get("offset", obj), 0.0);
            let sc  = JsonCodec.decodeVec2OrDefault(Map.get("scale", obj),  1.0);
            ({texture = tex, hframes = hf, vframes = vf, frame = fr,
              offset = off, scale = sc}: WeaponSpriteResource)
        }
}
