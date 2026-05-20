/// UnitCatalog — 味方・敵ユニットの定義カタログ
///
/// FE 風 SRPG の伝統的な「ユニットステータス表」を 1 つの JSON
/// (`resources/units.json`) に集約する。各ユニットは id（"knight" 等）で参照され、
/// プール定義（"players" / "enemies"）から `pool(name, catalog)` で取り出す。
///
/// JSON 形状（例）:
///   {
///     "units": {
///       "knight": { "moveTiles": 4, "hp": 14, "sprite": {...} },
///       ...
///     },
///     "players": ["knight", "archer", "mage"],
///     "enemies": ["goblin", "orc"]
///   }
///
/// プールは「`units` 以外の top-level array」として表現する。pool 名は任意で、ゲーム側が
/// `pool(name, catalog)` で参照する。IDE のメタフィールド UI でも直感的に表示される。
///
/// IDE 連携用に `resources/units.schema.json` をサイドカーとして配置する。
/// schema は engine の `Resource.ResourceSchema` 規格で書き、`Game.start` 時に
/// `Resource.checkConsistency(expectedUnitFields(), schema)` で Flix 型との整合を検査する。
mod UnitCatalog {

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber, JsonArray}

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// カタログ全体。`Saveable` を持たせるため enum でラップする。
    /// 名前がモジュール名と同じなので「companion 宣言」となり、モジュール先頭に置く必要がある。
    /// `weapons` は武器カタログ（id → WeaponResource）。`pools` は id 配列の参照で
    /// "players"/"enemies" は `units` を、"playerWeapons"/"enemyWeapons" は `weapons` を指す。
    pub enum UnitCatalog {
        case UnitCatalog({
            units   = Map[String, UnitResource],
            weapons = Map[String, WeaponResource],
            pools   = Map[String, List[String]]
        })
    }

    /// ユニット 1 種別ぶんのデータ。
    /// `Saveable` 実装は `instance Saveable[UnitCatalog]` 経由で扱うため
    /// この型自体は anonymous record を含む type alias で OK。
    /// `attack` は素の「力」(might)。実際の与ダメは `attack + 武器の attack - 防御`。
    pub type alias UnitResource = {
        moveTiles = Int32,
        hp        = Int32,
        attack    = Int32,
        defense   = Int32,
        speed     = Int32,
        sprite    = SpriteResource
    }

    /// 武器 1 種別ぶんのデータ。
    /// `name` は表示用の和名（例: "くんれんやり"）。`attack` は武器の攻撃力ボーナス、
    /// `durability` は耐久度。攻撃するたびに 1 減り、0 になると武器が壊れて
    /// 装備者の `weapon` は `None` になる（= 攻撃できなくなる）。
    pub type alias WeaponResource = {
        name       = String,
        attack     = Int32,
        durability = Int32
    }

    /// 見た目情報。後でテクスチャ単独 Resource に切り出す余地を残し nested に。
    pub type alias SpriteResource = {
        texture = String,
        hframes = Int32,
        vframes = Int32,
        frame   = Int32
    }

    /// units 部を取り出す。
    pub def unitsOf(catalog: UnitCatalog): Map[String, UnitResource] =
        let UnitCatalog.UnitCatalog(payload) = catalog;
        payload#units

    /// weapons 部を取り出す。
    pub def weaponsOf(catalog: UnitCatalog): Map[String, WeaponResource] =
        let UnitCatalog.UnitCatalog(payload) = catalog;
        payload#weapons

    /// pools 部を取り出す。
    pub def poolsOf(catalog: UnitCatalog): Map[String, List[String]] =
        let UnitCatalog.UnitCatalog(payload) = catalog;
        payload#pools

    // ────────────────────────────────────────────────────────
    // (B) ロード・参照
    // ────────────────────────────────────────────────────────

    /// `resources/units.json` をロード。失敗は panic（即可視化）。
    /// 起動時の Game.start で 1 度だけ呼ぶ想定。
    /// 各段階（read / parse / decode）で個別にエラー文言を出して診断しやすくする。
    pub def load(path: String): UnitCatalog \ Fs.FileRead =
        let readResult = run {
            Fs.ReadFile.read(path)
        } with Fs.ReadFile.runWithFileRead;
        match readResult {
            case Err(e) =>
                bug!("UnitCatalog.load file read failed: ${path} :: ${e}")
            case Ok(content) =>
                match Json.Parse.parse(content) {
                    case None =>
                        bug!("UnitCatalog.load JSON parse failed: ${path}")
                    case Some(json) =>
                        let decoded: Option[UnitCatalog] = Saveable.fromJson(json);
                        match decoded {
                            case None    => bug!("UnitCatalog.load decode failed (schema mismatch?): ${path}")
                            case Some(c) => c
                        }
                }
        }

    /// プール名 → そのプールに属する `UnitResource` のリスト。
    /// プール未定義 / 内部 id がカタログに存在しない場合は panic。
    /// （PlayerScene.add / EnemyScene.add から呼ばれる前提で、起動時の typo は即発覚させる）
    /// Flix は strict 評価なので `Option.getWithDefault(bug!(...))` は **常に panic** する。
    /// `match` で None ケースのみ bug! を呼ぶように書く必要がある。
    pub def pool(name: String, catalog: UnitCatalog): List[UnitResource] =
        match Map.get(name, poolsOf(catalog)) {
            case None     => bug!("UnitCatalog.pool: unknown pool name: ${name}")
            case Some(ids) =>
                let units = unitsOf(catalog);
                List.map(id -> match Map.get(id, units) {
                    case Some(u) => u
                    case None    => bug!("UnitCatalog.pool: unit '${id}' not in catalog")
                }, ids)
        }

    /// 武器プール名 → そのプールに属する `WeaponResource` のリスト。
    /// `pool` の武器版で、"playerWeapons" / "enemyWeapons" 等を解決する。
    /// 解決失敗時の panic 方針も同じ。
    pub def weaponPool(name: String, catalog: UnitCatalog): List[WeaponResource] =
        match Map.get(name, poolsOf(catalog)) {
            case None     => bug!("UnitCatalog.weaponPool: unknown pool name: ${name}")
            case Some(ids) =>
                let weapons = weaponsOf(catalog);
                List.map(id -> match Map.get(id, weapons) {
                    case Some(w) => w
                    case None    => bug!("UnitCatalog.weaponPool: weapon '${id}' not in catalog")
                }, ids)
        }

    /// Z 戦略の整合性検査用に Flix 型のフィールド名集合を公開する。
    /// `UnitResource` のフィールド構造を変更したらここも更新すること。
    /// engine 側 `Resource.checkConsistency` がこの集合と `_schema.json` を照合する。
    pub def expectedUnitFields(): Set[String] =
        Set#{"moveTiles", "hp", "attack", "defense", "speed", "sprite"}

    /// `WeaponResource` のフィールド名集合。`weapons.schema.json` との整合性検査に使う。
    pub def expectedWeaponFields(): Set[String] =
        Set#{"name", "attack", "durability"}
}

// ════════════════════════════════════════════════════════════════════════
// Saveable[UnitCatalog] — units.json の round-trip 実装
// ════════════════════════════════════════════════════════════════════════

instance Saveable[UnitCatalog.UnitCatalog] {
    pub def toJson(value: UnitCatalog.UnitCatalog): Json.JsonElement =
        UnitCatalogCodec.encode(value)

    pub def fromJson(element: Json.JsonElement): Option[UnitCatalog.UnitCatalog] =
        UnitCatalogCodec.decode(element)
}

mod UnitCatalogCodec {
    import java.math.{BigDecimal => JBigDecimal}

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber, JsonArray}
    use UnitCatalog.{UnitCatalog, UnitResource, WeaponResource, SpriteResource}

    // ── エンコード ──

    /// data top の JsonObject に "units" / "weapons" と、pools の各 entry をフラットに並べる。
    /// 例: { "units": {...}, "weapons": {...}, "players": [...], "playerWeapons": [...] }
    /// 旧形式の `"pools": {"party":[...], ...}` という入れ子はやめた (IDE 上で
    /// メタフィールドが pool 名のままトップに並び、ユーザに直感的)。
    pub def encode(c: UnitCatalog): JsonElement =
        let units = UnitCatalog.unitsOf(c)
            |> Map.foldLeftWithKey((acc, id, u) ->
                Map.insert(id, encodeUnit(u), acc),
                Map.empty());
        let weapons = UnitCatalog.weaponsOf(c)
            |> Map.foldLeftWithKey((acc, id, w) ->
                Map.insert(id, encodeWeapon(w), acc),
                Map.empty());
        let topWithUnits   = Map#{"units" => JsonObject(units)};
        let topWithWeapons = Map.insert("weapons", JsonObject(weapons), topWithUnits);
        let top = UnitCatalog.poolsOf(c)
            |> Map.foldLeftWithKey((acc, name, ids) ->
                Map.insert(name, JsonArray(List.map(JsonString, ids) |> List.toVector), acc),
                topWithWeapons);
        JsonObject(top)

    def encodeUnit(u: UnitResource): JsonElement =
        JsonObject(Map#{
            "moveTiles" => JsonNumber(intToBd(u#moveTiles)),
            "hp"        => JsonNumber(intToBd(u#hp)),
            "attack"    => JsonNumber(intToBd(u#attack)),
            "defense"   => JsonNumber(intToBd(u#defense)),
            "speed"     => JsonNumber(intToBd(u#speed)),
            "sprite"    => encodeSprite(u#sprite)
        })

    def encodeWeapon(w: WeaponResource): JsonElement =
        JsonObject(Map#{
            "name"       => JsonString(w#name),
            "attack"     => JsonNumber(intToBd(w#attack)),
            "durability" => JsonNumber(intToBd(w#durability))
        })

    def encodeSprite(s: SpriteResource): JsonElement =
        JsonObject(Map#{
            "texture" => JsonString(s#texture),
            "hframes" => JsonNumber(intToBd(s#hframes)),
            "vframes" => JsonNumber(intToBd(s#vframes)),
            "frame"   => JsonNumber(intToBd(s#frame))
        })

    def intToBd(value: Int32): BigDecimal =
        unsafe IO {
            let stripped = JBigDecimal.valueOf(Int32.toFloat64(value)).stripTrailingZeros();
            if (stripped.scale() < 0) stripped.setScale(0) else stripped
        }

    // ── デコード ──

    /// data top から "units" / "weapons" を取り出し、残りの全てのキーを pool として扱う。
    /// 旧形式 `"pools": {...}` の入れ子も互換のため受け入れる (中身を pools として読む)。
    /// `weapons` が存在しない旧 JSON は空 Map で初期化する（後方互換）。
    pub def decode(element: JsonElement): Option[UnitCatalog] =
        forM (
            top      <- expectObject(element);
            unitsJ   <- Map.get("units", top);
            unitsM   <- expectObject(unitsJ);
            units    <- traverseUnits(unitsM);
            weapons  <- decodeWeapons(top);
            pools    <- collectPools(top)
        ) yield UnitCatalog.UnitCatalog({units = units, weapons = weapons, pools = pools})

    /// "weapons" キーがあれば map を読む。無ければ空 Map を返す（旧 JSON 互換）。
    /// 値の型が不正なら None で全体を失敗させる。
    def decodeWeapons(top: Map[String, JsonElement]): Option[Map[String, WeaponResource]] =
        match Map.get("weapons", top) {
            case None         => Some(Map.empty())
            case Some(weaponsJ) =>
                forM (
                    weaponsM <- expectObject(weaponsJ);
                    weapons  <- traverseWeapons(weaponsM)
                ) yield weapons
        }

    /// top の "units" / "weapons" を除いた残りのキーで、値が JsonArray of JsonString のものを
    /// pool として収集。旧形式の "pools" 入れ子があれば、その中身も pool として展開する (互換性)。
    def collectPools(top: Map[String, JsonElement]): Option[Map[String, List[String]]] =
        let init: Option[Map[String, List[String]]] = Some(Map.empty());
        Map.foldLeftWithKey((acc, key, value) ->
            Option.flatMap(soFar -> {
                if (key == "units" or key == "weapons") Some(soFar)
                else match value {
                    case JsonObject(inner) =>
                        if (key == "pools")
                            // 旧形式: pools の中身を展開
                            traversePools(inner)
                                |> Option.map(m -> Map.foldLeftWithKey(
                                    (acc2, k, v) -> Map.insert(k, v, acc2), soFar, m))
                        else Some(soFar)
                    case JsonArray(_) =>
                        decodeStringList(value)
                            |> Option.map(ids -> Map.insert(key, ids, soFar))
                    case _ => Some(soFar)
                }
            }, acc),
            init, top)

    def traverseUnits(map: Map[String, JsonElement]):
                       Option[Map[String, UnitResource]] =
        Map.foldLeftWithKey((acc, id, json) ->
            Option.flatMap(soFar ->
                decodeUnit(json) |> Option.map(u -> Map.insert(id, u, soFar)),
                acc),
            Some(Map.empty()),
            map)

    def traverseWeapons(map: Map[String, JsonElement]):
                       Option[Map[String, WeaponResource]] =
        Map.foldLeftWithKey((acc, id, json) ->
            Option.flatMap(soFar ->
                decodeWeapon(json) |> Option.map(w -> Map.insert(id, w, soFar)),
                acc),
            Some(Map.empty()),
            map)

    def traversePools(map: Map[String, JsonElement]):
                       Option[Map[String, List[String]]] =
        Map.foldLeftWithKey((acc, name, json) ->
            Option.flatMap(soFar ->
                decodeStringList(json) |> Option.map(ids -> Map.insert(name, ids, soFar)),
                acc),
            Some(Map.empty()),
            map)

    def decodeUnit(element: JsonElement): Option[UnitResource] =
        forM (
            obj    <- expectObject(element);
            mtJ    <- Map.get("moveTiles", obj);
            hpJ    <- Map.get("hp", obj);
            atkJ   <- Map.get("attack", obj);
            defJ   <- Map.get("defense", obj);
            spdJ   <- Map.get("speed", obj);
            spJ    <- Map.get("sprite", obj);
            mt     <- expectInt(mtJ);
            hp     <- expectInt(hpJ);
            atk    <- expectInt(atkJ);
            df     <- expectInt(defJ);
            spd    <- expectInt(spdJ);
            sp     <- decodeSprite(spJ)
        ) yield ({moveTiles = mt, hp = hp, attack = atk, defense = df, speed = spd, sprite = sp}: UnitResource)

    def decodeWeapon(element: JsonElement): Option[WeaponResource] =
        forM (
            obj    <- expectObject(element);
            nameJ  <- Map.get("name", obj);
            atkJ   <- Map.get("attack", obj);
            durJ   <- Map.get("durability", obj);
            name   <- expectString(nameJ);
            atk    <- expectInt(atkJ);
            dur    <- expectInt(durJ)
        ) yield ({name = name, attack = atk, durability = dur}: WeaponResource)

    def decodeSprite(element: JsonElement): Option[SpriteResource] =
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
        ) yield ({texture = tex, hframes = hf, vframes = vf, frame = fr}: SpriteResource)

    def decodeStringList(element: JsonElement): Option[List[String]] = match element {
        case JsonArray(items) =>
            List.foldRight(item -> acc ->
                Option.flatMap(soFar ->
                    expectString(item) |> Option.map(s -> s :: soFar),
                    acc),
                Some(Nil), Vector.toList(items))
        case _ => None
    }

    // ── ヘルパー ──

    def expectObject(element: JsonElement): Option[Map[String, JsonElement]] =
        match element {
            case JsonObject(map) => Some(map)
            case _               => None
        }

    def expectString(element: JsonElement): Option[String] =
        match element {
            case JsonString(text) => Some(text)
            case _                => None
        }

    def expectInt(element: JsonElement): Option[Int32] = match element {
        case JsonNumber(bd) => BigDecimal.tryToFloat64(bd) |> Option.flatMap(Float64.tryToInt32)
        case _              => None
    }
}
