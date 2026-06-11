/// UnitCatalog — 味方ユニットの定義カタログ（`resources/units.json`）。
///
/// 味方・敵で共有する戦闘ステータス・スプライト・持ち物の型と codec は `UnitBase` に集約済み。
/// 本 mod は **味方専用**（成長率 `growthRates`）を足した `PlayerResource` と units.json のロードを担う。
/// 敵は別カタログ `EnemyCatalog`（`resources/enemies.json`）に分離した。
///
/// JSON 形状（units.json）:
///   { "units": { "knight": {...}, ... }, "players": ["knight", "archer", "mage"] }
mod UnitCatalog {

    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JNumber, JArray}
    use UnitBase.{UnitBase, ItemKind, InventoryEntry}

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// カタログ全体。trait instance（`Saveable`）を companion 宣言で持たせるため enum でラップする。
    pub enum UnitCatalog {
        case UnitCatalog({
            units   = CatalogContainer[PlayerResource],
            weapons = WeaponCatalog.WeaponCatalog,
            pools   = Map[String, List[String]]
        })
    }

    /// 味方ユニット 1 種別ぶんのデータ = 共有 14 フィールド + 成長率 `growthRates`。
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
        growthRates      = GrowthRates,
        // 得意武器タイプ（習熟）。ここに含まれるタイプは性能 100%、含まれないタイプ（苦手）は
        // 威力・命中 80%。ロード職種は全タイプ、他職種は初期装備のタイプを既定とする。
        // 旧 JSON に無い場合は decoder が空リストを埋める。IDE で編集可能。
        proficientWeaponTypes = List[WeaponCatalog.WeaponType],
        // このクラスが床の宝箱を開けられるか（ローグのみ true）。開けられない駒が宝箱に乗って
        // 「あける」を選ぶと「開けることができない」と表示される。旧 JSON に無い場合は decoder が false を埋める。
        canOpenChests    = Bool
    }

    /// WeaponCatalog 分離前の呼び出し元を壊さないための後方互換 alias。
    /// 新規コードでは `PlayerResource` を直接使うこと。
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

    /// 以下 WeaponType / WeaponResource / WeaponRange / isPhysical は WeaponCatalog 分離前の
    /// 呼び出し元を壊さないための後方互換 shim。新規コードは WeaponCatalog を直接参照すること。
    pub type alias WeaponType = WeaponCatalog.WeaponType

    pub type alias WeaponResource = WeaponCatalog.WeaponResource

    pub type alias WeaponRange = WeaponCatalog.WeaponRange

    pub def isPhysical(weaponType: WeaponType): Bool =
        WeaponCatalog.isPhysical(weaponType)

    // ────────────────────────────────────────────────────────
    // (B) 参照
    // ────────────────────────────────────────────────────────

    /// キーはユニット id（JSON の `"units"` オブジェクトのキー文字列、例: `"knight"`）。
    /// `CatalogContainer` ごと不要で Map だけ欲しい場合に使う。コンテナ操作が必要なら `unitsContainerOf`。
    pub def unitsOf(catalog: UnitCatalog): Map[String, PlayerResource] =
        let UnitCatalog.UnitCatalog(payload) = catalog;
        CatalogContainer.entriesOf(payload#units)

    /// `CatalogContainer` ごと必要な場合（直接 entries を操作したいとき）に使う。
    pub def unitsContainerOf(catalog: UnitCatalog): CatalogContainer[PlayerResource] =
        let UnitCatalog.UnitCatalog(payload) = catalog;
        payload#units

    /// 武器 id → `WeaponResource` の Map だけ欲しい場合に使う。
    /// `WeaponCatalog` 本体（`lookup` 等）を操作したい場合は `weaponCatalogOf` を使うこと。
    pub def weaponsOf(catalog: UnitCatalog): Map[String, WeaponResource] =
        let UnitCatalog.UnitCatalog(payload) = catalog;
        WeaponCatalog.weaponsOf(payload#weapons)

    /// `WeaponCatalog` 本体を直接操作したいとき（`lookup`・`weaponsOf` 等）に使う。
    /// Map だけ欲しい場合は `weaponsOf` の方が簡潔。
    pub def weaponCatalogOf(catalog: UnitCatalog): WeaponCatalog.WeaponCatalog =
        let UnitCatalog.UnitCatalog(payload) = catalog;
        payload#weapons

    /// プール名 → そのプールに属するユニット id 列（例: `"players" -> ["knight", "archer"]`）。
    /// 出撃可能ユニットの集合管理に使う。個別ユニット取得は `pool(name, catalog)` を通すこと。
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
        let schema = match Resource.loadSchemaDiagnostic(AssetPath.resolve("resources/units.schema.json")) {
            case Ok(value) => value
            case Err(msg)  => bug!("UnitCatalog schema load failed: ${msg}")
        };
        match Resource.checkConsistency(expectedUnitFields(), schema) {
            case Ok(())    => catalog
            case Err(msg)  => bug!("UnitResource schema/type mismatch: ${msg}")
        }

    /// I/O から分離したデコード経路。純粋に保つことでテストや依存性注入が容易になる。
    /// `weaponCatalog` は呼び元が用意して渡す（この関数自体は weapons を読まない）。
    pub def loadFromString(unitsJson: String, weaponCatalog: WeaponCatalog.WeaponCatalog): UnitCatalog =
        let catalog = decodeUnitsJson(unitsJson);
        let UnitCatalog.UnitCatalog(payload) = catalog;
        UnitCatalog.UnitCatalog({weapons = weaponCatalog | payload})

    /// `units.json` を再読し、各味方の `spriteFrames` を texture 実寸で格子→px に解決して埋め直す。
    /// 共有解決ロジックは `UnitBaseCodec.resolveEntriesSpriteFrames` に委譲する。
    pub def resolveSpriteFrames(unitsPath: String, catalog: UnitCatalog):
            UnitCatalog \ {Fs.FileRead, GameEngine.Game} =
        let unitsJson = readFile(unitsPath);
        let parsed = match JsonCompat.parse(unitsJson) {
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
        match JsonCompat.parse(content) {
            case None       => bug!("UnitCatalog units JSON parse failed")
            case Some(json) =>
                let decoded: Option[UnitCatalog] = Saveable.fromJson(json);
                match decoded {
                    case None    => bug!("UnitCatalog units decode failed (schema mismatch?)")
                    case Some(c) => c
                }
        }

    /// 失敗を即 panic にすることで、起動時にファイル欠損や権限エラーを可視化する設計判断。
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

    /// このユニットが指定の武器タイプを得意とするか（= 性能 100%）。
    /// 含まれないタイプは苦手（威力・命中 80%）。`Combat.proficiencyAdjust` と組で使う。
    pub def proficientWith(resource: PlayerResource, weaponType: WeaponCatalog.WeaponType): Bool =
        List.memberOf(weaponType, resource#proficientWeaponTypes)

    /// JSON schema と Flix 型定義（`PlayerResource`）が乖離したときに起動時検知するための防衛機構。
    /// `Resource.checkConsistency` に渡し、schema 側に存在しないフィールドがあれば即 bug! で可視化する。
    /// 共有 14 フィールド + growthRates + proficientWeaponTypes の全フィールド名集合。
    pub def expectedUnitFields(): Set[String] =
        Set#{"moveTiles", "level", "hp", "attack", "defense", "magicAttack", "magicDefense",
              "speed", "skill", "luck", "sprite", "initialInventory",
              "description", "spriteFrames", "growthRates", "proficientWeaponTypes",
              "canOpenChests"}

    /// `WeaponResource` のフィールド名集合（後方互換の委譲）。
    pub def expectedWeaponFields(): Set[String] =
        WeaponCatalog.expectedFields()
}

// ════════════════════════════════════════════════════════════════════════
// Saveable[UnitCatalog] — units.json の round-trip（weapons は別ファイル管理）
// ════════════════════════════════════════════════════════════════════════

instance Saveable[UnitCatalog.UnitCatalog] {
    pub def toJson(value: UnitCatalog.UnitCatalog): Util.Json.Json =
        UnitCatalogCodec.encode(value)

    pub def fromJson(element: Util.Json.Json): Option[UnitCatalog.UnitCatalog] =
        UnitCatalogCodec.decode(element)
}

mod UnitCatalogCodec {
    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JNumber, JArray}
    use JsonCodec.{expectObject, expectString, expectInt}
    use UnitCatalog.{UnitCatalog, PlayerResource, GrowthRates}

    // ── エンコード（weapons は含まない。別ファイル管理のため round-trip しない）──

    /// `CatalogContainer` が汎用の meta フィールドを持つため、pools をそこに相乗りさせる設計。
    /// pools 専用の JSON キーを設けず meta に格納することで、フォーマットの共通化を維持する。
    pub def encode(c: UnitCatalog): Json =
        let unitsContainer = UnitCatalog.unitsContainerOf(c);
        let poolsMeta = UnitCatalog.poolsOf(c)
            |> Map.foldLeftWithKey((acc, name, ids) ->
                Map.insert(name, JArray(List.map(JString, ids) |> List.toVector), acc),
                (Map.empty(): Map[String, Json]));
        let CatalogContainer.CatalogContainer(containerPayload) = unitsContainer;
        let enrichedContainer = CatalogContainer.CatalogContainer({meta = poolsMeta | containerPayload});
        CatalogContainer.encode(encodePlayer, enrichedContainer)

    /// 味方 = 共有ベース（`UnitBaseCodec.encodeBase`）+ `growthRates` + `proficientWeaponTypes`。
    def encodePlayer(u: PlayerResource): Json =
        let base = UnitBaseCodec.encodeBase(u);
        let withGrowth = Map.insert("growthRates", encodeGrowthRates(u#growthRates), base);
        let profArray = JsonCodec.encodeList(
            weaponType -> JString(WeaponCatalogCodec.weaponTypeToString(weaponType)),
            u#proficientWeaponTypes);
        let withProf = Map.insert("proficientWeaponTypes", profArray, withGrowth);
        JObject(Map.insert("canOpenChests", Util.Json.Json.JBool(u#canOpenChests), withProf))

    def encodeGrowthRates(g: GrowthRates): Json =
        JObject(Map#{
            "hp"           => JNumber(JsonCodec.intToBd(g#hp)),
            "attack"       => JNumber(JsonCodec.intToBd(g#attack)),
            "defense"      => JNumber(JsonCodec.intToBd(g#defense)),
            "magicAttack"  => JNumber(JsonCodec.intToBd(g#magicAttack)),
            "magicDefense" => JNumber(JsonCodec.intToBd(g#magicDefense)),
            "speed"        => JNumber(JsonCodec.intToBd(g#speed)),
            "skill"        => JNumber(JsonCodec.intToBd(g#skill)),
            "luck"         => JNumber(JsonCodec.intToBd(g#luck))
        })

    // ── デコード（weapons は常に空で返す。load 側で別途 WeaponCatalog を差し込む）──

    /// pools は container の meta から再構築する。
    pub def decode(element: Json): Option[UnitCatalog] =
        forM (
            container <- CatalogContainer.decode("units", decodePlayer, element);
            pools     <- decodePoolsFromMeta(CatalogContainer.metaOf(container))
        ) yield UnitCatalog.UnitCatalog({
            units   = container,
            weapons = WeaponCatalog.empty(),
            pools   = pools
        })

    /// 味方 = 共有 14 フィールド（`UnitBaseCodec.decodeBase`）+ `growthRates`（省略時は全 0）
    /// + `proficientWeaponTypes`（省略時は `Nil` = 全タイプ苦手、威力・命中 80%）。
    /// `proficientWeaponTypes` の既定値については L46-48 の初期装備タイプ規則も参照。
    def decodePlayer(element: Json): Option[PlayerResource] =
        forM (
            base <- UnitBaseCodec.decodeBase(element);
            obj  <- expectObject(element)
        ) yield {
            let growth = Map.get("growthRates", obj)
                            |> Option.flatMap(decodeGrowthRates)
                            |> Option.getWithDefault(UnitCatalog.zeroGrowthRates());
            let proficient = Map.get("proficientWeaponTypes", obj)
                            |> Option.flatMap(decodeWeaponTypes)
                            |> Option.getWithDefault(Nil);
            // 宝箱開錠可否（省略時は false）。ローグだけ units.json で true にする。
            let canOpen = Map.get("canOpenChests", obj)
                            |> Option.flatMap(JsonCodec.expectBool)
                            |> Option.getWithDefault(false);
            ({moveTiles = base#moveTiles, level = base#level, hp = base#hp, attack = base#attack,
              defense = base#defense, magicAttack = base#magicAttack,
              magicDefense = base#magicDefense, speed = base#speed, skill = base#skill,
              luck = base#luck, sprite = base#sprite, initialInventory = base#initialInventory,
              description = base#description, spriteFrames = base#spriteFrames,
              growthRates = growth, proficientWeaponTypes = proficient,
              canOpenChests = canOpen}: PlayerResource)
        }

    /// 得意武器タイプ配列（`["Sword","Axe"]` 等）をデコード。
    /// 未知文字列は `parseWeaponType` が剣にフォールバックする（フォールバック先の判断は parseWeaponType 側の設計方針）。
    def decodeWeaponTypes(element: Json): Option[List[WeaponCatalog.WeaponType]] =
        JsonCodec.decodeList(
            item -> expectString(item) |> Option.map(WeaponCatalogCodec.parseWeaponType),
            element)

    def decodeGrowthRates(element: Json): Option[GrowthRates] =
        expectObject(element) |> Option.map(obj ->
            let rate = key -> Map.get(key, obj) |> Option.flatMap(expectInt) |> Option.getWithDefault(0);
            ({hp = rate("hp"), attack = rate("attack"), defense = rate("defense"),
              magicAttack = rate("magicAttack"), magicDefense = rate("magicDefense"),
              speed = rate("speed"), skill = rate("skill"), luck = rate("luck")}: GrowthRates))

    /// meta の各キーのうち JArray of JString のみを pool として採用する。
    /// それ以外の型（JObject 等）はスキップするため、pools 以外の meta キーを汚染しない設計。
    def decodePoolsFromMeta(meta: Map[String, Json]):
            Option[Map[String, List[String]]] =
        let init: Option[Map[String, List[String]]] = Some(Map.empty());
        Map.foldLeftWithKey((acc, key, value) ->
            Option.flatMap(soFar ->
                match value {
                    case JArray(_) =>
                        decodeStringList(value)
                            |> Option.map(ids -> Map.insert(key, ids, soFar))
                    case _ => Some(soFar)
                },
                acc),
            init, meta)

    def decodeStringList(element: Json): Option[List[String]] = match element {
        case JArray(items) =>
            List.foldRight(item -> acc ->
                Option.flatMap(soFar ->
                    expectString(item) |> Option.map(s -> s :: soFar),
                    acc),
                Some(Nil), Vector.toList(items))
        case _ => None
    }
}
