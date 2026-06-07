/// UnitCatalog — 味方ユニットの定義カタログ（`resources/units.json`）。
///
/// 味方・敵で共有する戦闘ステータス・スプライト・持ち物の型と codec は `UnitBase` に集約済み。
/// 本 mod は **味方専用**（成長率 `growthRates`）を足した `PlayerResource` と units.json のロードを担う。
/// 敵は別カタログ `EnemyCatalog`（`resources/enemies.json`）に分離した。
///
/// JSON 形状（units.json）:
///   { "units": { "knight": {...}, ... }, "players": ["knight", "archer", "mage"] }
mod UnitCatalog {

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber, JsonArray}
    use UnitBase.{UnitBase, ItemKind, InventoryEntry}

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// カタログ全体。`Saveable` を持たせるため enum でラップする（companion 宣言）。
    /// `units` は味方 `PlayerResource` の container、`weapons` は別 catalog、`pools` は id 配列の参照。
    pub enum UnitCatalog {
        case UnitCatalog({
            units   = CatalogContainer[PlayerResource],
            weapons = WeaponCatalog.WeaponCatalog,
            pools   = Map[String, List[String]]
        })
    }

    /// 味方ユニット 1 種別ぶんのデータ = 共有 14 フィールド + 成長率 `growthRates`。
    /// （`UnitBase.UnitBase` の各フィールドをここに並べ、`growthRates` を加えた形。）
    pub type alias PlayerResource = {
        moveTiles        = Int32,
        level            = Int32,
        hp               = Int32,
        attack           = Int32,
        defense          = Int32,
        magicAttack      = Int32,
        magicDefense     = Int32,
        speed            = Int32,
        skill            = Int32,
        luck             = Int32,
        sprite           = Sprite.SpriteResource,
        initialInventory = List[InventoryEntry],
        description      = String,
        spriteFrames     = Option[SpriteFrames],
        // レベルアップ時のステータス成長率。旧 JSON に無い場合は decoder が全 0 を埋める。
        growthRates      = GrowthRates
    }

    /// 後方互換 alias。既存コードの `UnitCatalog.UnitResource` 参照はそのまま味方リソースを指す。
    pub type alias UnitResource = PlayerResource

    /// レベルアップ時の各ステータスの成長率 (%)。0..100 を想定。`moveTiles` は成長対象外。
    pub type alias GrowthRates = {
        hp           = Int32,
        attack       = Int32,
        defense      = Int32,
        magicAttack  = Int32,
        magicDefense = Int32,
        speed        = Int32,
        skill        = Int32,
        luck         = Int32
    }

    /// 成長率が全て 0 のデフォルト値（= 一切成長しない）。JSON に `growthRates` が無いときに使う。
    pub def zeroGrowthRates(): GrowthRates =
        {hp = 0, attack = 0, defense = 0, magicAttack = 0, magicDefense = 0,
         speed = 0, skill = 0, luck = 0}

    /// 武器の属性。`WeaponCatalog.WeaponType` の alias (後方互換)。
    pub type alias WeaponType = WeaponCatalog.WeaponType

    /// 武器 1 種別ぶんのデータ。`WeaponCatalog.WeaponResource` の alias (後方互換)。
    pub type alias WeaponResource = WeaponCatalog.WeaponResource

    /// 攻撃可能な距離の範囲。`WeaponCatalog.WeaponRange` の alias (後方互換)。
    pub type alias WeaponRange = WeaponCatalog.WeaponRange

    /// `WeaponType` が物理武器か。`WeaponCatalog.isPhysical` への薄い委譲 (後方互換)。
    pub def isPhysical(weaponType: WeaponType): Bool =
        WeaponCatalog.isPhysical(weaponType)

    // ────────────────────────────────────────────────────────
    // (B) 参照
    // ────────────────────────────────────────────────────────

    /// units 部 (id → PlayerResource の Map) を取り出す。
    pub def unitsOf(catalog: UnitCatalog): Map[String, PlayerResource] =
        let UnitCatalog.UnitCatalog(payload) = catalog;
        CatalogContainer.entriesOf(payload#units)

    /// `CatalogContainer[PlayerResource]` そのものを取り出す (IDE Resources タブ等で利用想定)。
    pub def unitsContainerOf(catalog: UnitCatalog): CatalogContainer[PlayerResource] =
        let UnitCatalog.UnitCatalog(payload) = catalog;
        payload#units

    /// weapons 部 (id → WeaponResource の Map) を取り出す。
    pub def weaponsOf(catalog: UnitCatalog): Map[String, WeaponResource] =
        let UnitCatalog.UnitCatalog(payload) = catalog;
        WeaponCatalog.weaponsOf(payload#weapons)

    /// `WeaponCatalog.WeaponCatalog` そのものを取り出す。
    pub def weaponCatalogOf(catalog: UnitCatalog): WeaponCatalog.WeaponCatalog =
        let UnitCatalog.UnitCatalog(payload) = catalog;
        payload#weapons

    /// pools 部を取り出す。
    pub def poolsOf(catalog: UnitCatalog): Map[String, List[String]] =
        let UnitCatalog.UnitCatalog(payload) = catalog;
        payload#pools

    // ────────────────────────────────────────────────────────
    // (C) ロード
    // ────────────────────────────────────────────────────────

    /// `resources/units.json` をロードして UnitCatalog を組む。weapons は事前に
    /// `WeaponCatalog.load()` で得た `weaponCatalog` を渡す。失敗は panic（即可視化）。
    /// `spriteFrames` は pure 経路では None のまま。`Game.start` で `resolveSpriteFrames` を続けて呼ぶ。
    pub def load(unitsPath: String, weaponCatalog: WeaponCatalog.WeaponCatalog):
            UnitCatalog \ Fs.FileRead =
        let unitsJson = readFile(unitsPath);
        let catalog = loadFromString(unitsJson, weaponCatalog);
        let schema = match Resource.loadSchemaDiagnostic("resources/units.schema.json") {
            case Ok(value) => value
            case Err(msg)  => bug!("UnitCatalog schema load failed: ${msg}")
        };
        match Resource.checkConsistency(expectedUnitFields(), schema) {
            case Ok(())    => catalog
            case Err(msg)  => bug!("UnitResource schema/type mismatch: ${msg}")
        }

    /// I/O から分離したデコード経路: JSON 文字列から `UnitCatalog` を組む。weapons を直接組み込む。
    pub def loadFromString(unitsJson: String, weaponCatalog: WeaponCatalog.WeaponCatalog): UnitCatalog =
        let catalog = decodeUnitsJson(unitsJson);
        let UnitCatalog.UnitCatalog(payload) = catalog;
        UnitCatalog.UnitCatalog({weapons = weaponCatalog | payload})

    /// `units.json` を再読し、各味方の `spriteFrames` を texture 実寸で格子→px に解決して埋め直す。
    /// 共有解決ロジックは `UnitBaseCodec.resolveEntriesSpriteFrames` に委譲する。
    pub def resolveSpriteFrames(unitsPath: String, catalog: UnitCatalog):
            UnitCatalog \ {Fs.FileRead, GameEngine.Game} =
        let unitsJson = readFile(unitsPath);
        let parsed = match Json.Parse.parse(unitsJson) {
            case None       => bug!("UnitCatalog units JSON re-parse failed during resolveSpriteFrames")
            case Some(json) => json
        };
        let UnitCatalog.UnitCatalog(payload) = catalog;
        let CatalogContainer.CatalogContainer(containerPayload) = payload#units;
        let resolved = UnitBaseCodec.resolveEntriesSpriteFrames(parsed, "units", containerPayload#entries);
        let newContainer = CatalogContainer.CatalogContainer({entries = resolved | containerPayload});
        UnitCatalog.UnitCatalog({units = newContainer | payload})

    /// JSON 文字列から `UnitCatalog` を decode する内部ヘルパ（spriteFrames は常に None）。
    def decodeUnitsJson(content: String): UnitCatalog =
        match Json.Parse.parse(content) {
            case None       => bug!("UnitCatalog units JSON parse failed")
            case Some(json) =>
                let decoded: Option[UnitCatalog] = Saveable.fromJson(json);
                match decoded {
                    case None    => bug!("UnitCatalog units decode failed (schema mismatch?)")
                    case Some(c) => c
                }
        }

    /// 指定 path をテキストとして読み、エラーなら即 panic する。
    def readFile(path: String): String \ Fs.FileRead =
        let readResult = run {
            Fs.ReadFile.read(path)
        } with Fs.ReadFile.runWithFileRead;
        match readResult {
            case Err(e)      => bug!("UnitCatalog file read failed: ${path} :: ${e}")
            case Ok(content) => content
        }

    /// プール名 → そのプールに属する `PlayerResource` のリスト。未定義 / id 不在は panic。
    pub def pool(name: String, catalog: UnitCatalog): List[PlayerResource] =
        match Map.get(name, poolsOf(catalog)) {
            case None     => bug!("UnitCatalog.pool: unknown pool name: ${name}")
            case Some(ids) =>
                let units = unitsOf(catalog);
                List.map(id -> match Map.get(id, units) {
                    case Some(u) => u
                    case None    => bug!("UnitCatalog.pool: unit '${id}' not in catalog")
                }, ids)
        }

    /// 武器 id を引いて `WeaponResource` を返す。未定義 id は起動時 typo として panic。
    pub def lookupWeapon(id: String, catalog: UnitCatalog): WeaponResource =
        WeaponCatalog.lookup(id, weaponCatalogOf(catalog))

    /// Z 戦略の整合性検査用に Flix 型のフィールド名集合を公開する（14 共有 + growthRates）。
    pub def expectedUnitFields(): Set[String] =
        Set#{"moveTiles", "level", "hp", "attack", "defense", "magicAttack", "magicDefense",
              "speed", "skill", "luck", "sprite", "initialInventory",
              "description", "spriteFrames", "growthRates"}

    /// `WeaponResource` のフィールド名集合（後方互換の委譲）。
    pub def expectedWeaponFields(): Set[String] =
        WeaponCatalog.expectedFields()
}

// ════════════════════════════════════════════════════════════════════════
// Saveable[UnitCatalog] — units.json の round-trip（weapons は別ファイル管理）
// ════════════════════════════════════════════════════════════════════════

instance Saveable[UnitCatalog.UnitCatalog] {
    pub def toJson(value: UnitCatalog.UnitCatalog): Json.JsonElement =
        UnitCatalogCodec.encode(value)

    pub def fromJson(element: Json.JsonElement): Option[UnitCatalog.UnitCatalog] =
        UnitCatalogCodec.decode(element)
}

mod UnitCatalogCodec {
    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber, JsonArray}
    use JsonCodec.{expectObject, expectString, expectInt}
    use UnitCatalog.{UnitCatalog, PlayerResource, GrowthRates}

    // ── エンコード ──

    /// units.json の round-trip 用エンコーダ。weapons は含めない（別ファイル）。
    /// pools を CatalogContainer の meta に投影してから encode する。
    pub def encode(c: UnitCatalog): JsonElement =
        let unitsContainer = UnitCatalog.unitsContainerOf(c);
        let poolsMeta = UnitCatalog.poolsOf(c)
            |> Map.foldLeftWithKey((acc, name, ids) ->
                Map.insert(name, JsonArray(List.map(JsonString, ids) |> List.toVector), acc),
                (Map.empty(): Map[String, JsonElement]));
        let CatalogContainer.CatalogContainer(containerPayload) = unitsContainer;
        let enrichedContainer = CatalogContainer.CatalogContainer({meta = poolsMeta | containerPayload});
        CatalogContainer.encode(encodePlayer, enrichedContainer)

    /// 味方 = 共有ベース（`UnitBaseCodec.encodeBase`）+ `growthRates`。
    def encodePlayer(u: PlayerResource): JsonElement =
        let base = UnitBaseCodec.encodeBase(u);
        JsonObject(Map.insert("growthRates", encodeGrowthRates(u#growthRates), base))

    def encodeGrowthRates(g: GrowthRates): JsonElement =
        JsonObject(Map#{
            "hp"           => JsonNumber(JsonCodec.intToBd(g#hp)),
            "attack"       => JsonNumber(JsonCodec.intToBd(g#attack)),
            "defense"      => JsonNumber(JsonCodec.intToBd(g#defense)),
            "magicAttack"  => JsonNumber(JsonCodec.intToBd(g#magicAttack)),
            "magicDefense" => JsonNumber(JsonCodec.intToBd(g#magicDefense)),
            "speed"        => JsonNumber(JsonCodec.intToBd(g#speed)),
            "skill"        => JsonNumber(JsonCodec.intToBd(g#skill)),
            "luck"         => JsonNumber(JsonCodec.intToBd(g#luck))
        })

    // ── デコード ──

    /// units.json をデコード。weapons は常に空（別ファイル管理）。pools は container の meta から再構築。
    pub def decode(element: JsonElement): Option[UnitCatalog] =
        forM (
            container <- CatalogContainer.decode("units", decodePlayer, element);
            pools     <- decodePoolsFromMeta(CatalogContainer.metaOf(container))
        ) yield UnitCatalog.UnitCatalog({
            units   = container,
            weapons = WeaponCatalog.empty(),
            pools   = pools
        })

    /// 味方 = 共有 14 フィールド（`UnitBaseCodec.decodeBase`）+ `growthRates`（省略時は全 0）。
    def decodePlayer(element: JsonElement): Option[PlayerResource] =
        forM (
            base <- UnitBaseCodec.decodeBase(element);
            obj  <- expectObject(element)
        ) yield {
            let growth = Map.get("growthRates", obj)
                            |> Option.flatMap(decodeGrowthRates)
                            |> Option.getWithDefault(UnitCatalog.zeroGrowthRates());
            ({moveTiles = base#moveTiles, level = base#level, hp = base#hp, attack = base#attack,
              defense = base#defense, magicAttack = base#magicAttack,
              magicDefense = base#magicDefense, speed = base#speed, skill = base#skill,
              luck = base#luck, sprite = base#sprite, initialInventory = base#initialInventory,
              description = base#description, spriteFrames = base#spriteFrames,
              growthRates = growth}: PlayerResource)
        }

    def decodeGrowthRates(element: JsonElement): Option[GrowthRates] =
        expectObject(element) |> Option.map(obj ->
            let rate = key -> Map.get(key, obj) |> Option.flatMap(expectInt) |> Option.getWithDefault(0);
            ({hp = rate("hp"), attack = rate("attack"), defense = rate("defense"),
              magicAttack = rate("magicAttack"), magicDefense = rate("magicDefense"),
              speed = rate("speed"), skill = rate("skill"), luck = rate("luck")}: GrowthRates))

    /// container の meta から JsonArray of JsonString のものを pool として抽出する。
    def decodePoolsFromMeta(meta: Map[String, JsonElement]):
            Option[Map[String, List[String]]] =
        let init: Option[Map[String, List[String]]] = Some(Map.empty());
        Map.foldLeftWithKey((acc, key, value) ->
            Option.flatMap(soFar ->
                match value {
                    case JsonArray(_) =>
                        decodeStringList(value)
                            |> Option.map(ids -> Map.insert(key, ids, soFar))
                    case _ => Some(soFar)
                },
                acc),
            init, meta)

    def decodeStringList(element: JsonElement): Option[List[String]] = match element {
        case JsonArray(items) =>
            List.foldRight(item -> acc ->
                Option.flatMap(soFar ->
                    expectString(item) |> Option.map(s -> s :: soFar),
                    acc),
                Some(Nil), Vector.toList(items))
        case _ => None
    }
}
