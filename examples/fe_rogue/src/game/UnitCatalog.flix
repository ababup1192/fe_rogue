/// UnitCatalog — 味方・敵ユニットの定義カタログ
///
/// FE 風 SRPG の伝統的な「ユニットステータス表」を 1 つの JSON
/// (`assets/units/units.json`) に集約する。各ユニットは id（"knight" 等）で参照され、
/// プール定義（"party" / "enemyTier1"）から `pool(name, catalog)` で取り出す。
///
/// JSON 形状（例）:
///   {
///     "units": {
///       "knight": { "moveTiles": 4, "hp": 14, "sprite": {...} },
///       ...
///     },
///     "pools": {
///       "party":      ["knight", "archer", "mage"],
///       "enemyTier1": ["goblin", "orc"]
///     }
///   }
///
/// IDE 連携用に `assets/units/_schema.json` をサイドカーとして配置する。
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
    pub enum UnitCatalog {
        case UnitCatalog({
            units = Map[String, UnitResource],
            pools = Map[String, List[String]]
        })
    }

    /// ユニット 1 種別ぶんのデータ。
    /// `Saveable` 実装は `instance Saveable[UnitCatalog]` 経由で扱うため
    /// この型自体は anonymous record を含む type alias で OK。
    /// 戦闘 4 値 (HP / 攻 / 防 / 速) はスペック準拠（"Fighter HP:20 攻6 防5 速2"）。
    pub type alias UnitResource = {
        moveTiles = Int32,
        hp        = Int32,
        attack    = Int32,
        defense   = Int32,
        speed     = Int32,
        sprite    = SpriteResource
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

    /// pools 部を取り出す。
    pub def poolsOf(catalog: UnitCatalog): Map[String, List[String]] =
        let UnitCatalog.UnitCatalog(payload) = catalog;
        payload#pools

    // ────────────────────────────────────────────────────────
    // (B) ロード・参照
    // ────────────────────────────────────────────────────────

    /// `assets/units/units.json` をロード。失敗は panic（即可視化）。
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

    /// Z 戦略の整合性検査用に Flix 型のフィールド名集合を公開する。
    /// `UnitResource` のフィールド構造を変更したらここも更新すること。
    /// engine 側 `Resource.checkConsistency` がこの集合と `_schema.json` を照合する。
    pub def expectedUnitFields(): Set[String] =
        Set#{"moveTiles", "hp", "attack", "defense", "speed", "sprite"}
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
    use UnitCatalog.{UnitCatalog, UnitResource, SpriteResource}

    // ── エンコード ──

    pub def encode(c: UnitCatalog): JsonElement =
        let units = UnitCatalog.unitsOf(c)
            |> Map.foldLeftWithKey((acc, id, u) ->
                Map.insert(id, encodeUnit(u), acc),
                Map.empty());
        let pools = UnitCatalog.poolsOf(c)
            |> Map.foldLeftWithKey((acc, name, ids) ->
                Map.insert(name, JsonArray(List.map(JsonString, ids) |> List.toVector), acc),
                Map.empty());
        JsonObject(Map#{
            "units" => JsonObject(units),
            "pools" => JsonObject(pools)
        })

    def encodeUnit(u: UnitResource): JsonElement =
        JsonObject(Map#{
            "moveTiles" => JsonNumber(intToBd(u#moveTiles)),
            "hp"        => JsonNumber(intToBd(u#hp)),
            "attack"    => JsonNumber(intToBd(u#attack)),
            "defense"   => JsonNumber(intToBd(u#defense)),
            "speed"     => JsonNumber(intToBd(u#speed)),
            "sprite"    => encodeSprite(u#sprite)
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

    pub def decode(element: JsonElement): Option[UnitCatalog] =
        forM (
            top      <- expectObject(element);
            unitsJ   <- Map.get("units", top);
            poolsJ   <- Map.get("pools", top);
            unitsM   <- expectObject(unitsJ);
            poolsM   <- expectObject(poolsJ);
            units    <- traverseUnits(unitsM);
            pools    <- traversePools(poolsM)
        ) yield UnitCatalog.UnitCatalog({units = units, pools = pools})

    def traverseUnits(map: Map[String, JsonElement]):
                       Option[Map[String, UnitResource]] =
        Map.foldLeftWithKey((acc, id, json) ->
            Option.flatMap(soFar ->
                decodeUnit(json) |> Option.map(u -> Map.insert(id, u, soFar)),
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
