/// UnitCatalog — 味方・敵ユニットの定義カタログ
///
/// FE 風 SRPG の伝統的な「ユニットステータス表」を 2 つのリソース JSON に分けて持つ:
///   - `resources/units.json`   — ユニット定義 + `players` / `enemies` プール
///   - `resources/weapons.json` — 武器カタログ (id → WeaponResource)
///
/// 分割理由は IDE Resources タブが 1 ファイル = 1 catalog container しか扱えないため
/// (`ide/src/ResourceCatalog.flix` の classify は最初の container のみ採用)。
/// weapons を units.json に同居させていた時代は IDE から武器を編集できなかった。
///
/// 各ユニットは `initialWeapon` フィールドで自分の初期装備武器 id を直接持つ。
/// `players` / `enemies` プールはユニット id の配列で、ゲーム側がスポーン順を決める。
///
/// JSON 形状（units.json）:
///   {
///     "units": {
///       "knight": { "moveTiles": 4, "hp": 14, ..., "initialWeapon": "trainingSpear" },
///       ...
///     },
///     "players": ["knight", "archer", "mage"],
///     "enemies": ["goblin", "orc"]
///   }
///
/// JSON 形状（weapons.json）:
///   {
///     "weapons": {
///       "trainingSpear": { "name": "くんれんやり", "attack": 2, "durability": 41 },
///       ...
///     }
///   }
///
/// IDE 連携用に `units.schema.json` / `weapons.schema.json` をサイドカーとして配置する。
/// schema は engine の `Resource.ResourceSchema` 規格で書き、`Game.start` 時に
/// `Resource.checkConsistency(expected*Fields(), schema)` で Flix 型との整合を検査する。
mod UnitCatalog {

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber, JsonArray}

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// カタログ全体。`Saveable` を持たせるため enum でラップする。
    /// 名前がモジュール名と同じなので「companion 宣言」となり、モジュール先頭に置く必要がある。
    /// `weapons` は weapons.json から読んだ武器カタログ。`pools` は id 配列の参照で
    /// `"players"` / `"enemies"` は `units` を指す。
    pub enum UnitCatalog {
        case UnitCatalog({
            units   = Map[String, UnitResource],
            weapons = Map[String, WeaponResource],
            pools   = Map[String, List[String]]
        })
    }

    /// ユニット 1 種別ぶんのデータ。
    /// `attack` は素の「力」(might)。実際の与ダメは `attack + 武器の attack - 防御`。
    /// `initialWeapon` は武器カタログ (weapons.json) 内の武器 id への参照。
    pub type alias UnitResource = {
        moveTiles     = Int32,
        hp            = Int32,
        attack        = Int32,
        defense       = Int32,
        speed         = Int32,
        sprite        = SpriteResource,
        initialWeapon = String
    }

    /// 武器 1 種別ぶんのデータ。
    /// `name` は表示用の和名（例: "くんれんやり"）。`attack` は武器の攻撃力ボーナス、
    /// `durability` は耐久度。攻撃するたびに 1 減り、0 になると武器が壊れて
    /// 装備者の `weapon` は `None` になる（= 攻撃できなくなる）。
    /// `range` は攻撃可能な距離の範囲 (`min..max` inclusive)。`min == max == 1` で
    /// 直接攻撃 (剣・槍・杖)、`min == 2 && max == 2` で 2 マス先のみ (弓)、
    /// `min == 1 && max == 2` で隣接 + 2 マス先 (手槍・手斧) などを表現する。
    pub type alias WeaponResource = {
        name       = String,
        attack     = Int32,
        durability = Int32,
        range      = WeaponRange,
        sprite     = SpriteResource
    }

    /// 攻撃可能な距離の範囲。`min..max` inclusive のマンハッタン距離で判定する。
    pub type alias WeaponRange = {
        min = Int32,
        max = Int32
    }

    /// 見た目情報。後でテクスチャ単独 Resource に切り出す余地を残し nested に。
    /// `offset` は描画時の x/y シフト（px）。スプライトシートに padding がある場合
    /// （例: Kenney 系で 16 px 絵 + 1 px gutter で cellW=17 となるケース）の
    /// 視覚的中央寄せ補正に使う。デフォルトは {0, 0}。
    pub type alias SpriteResource = {
        texture = String,
        hframes = Int32,
        vframes = Int32,
        frame   = Int32,
        offset  = Vec2.Vec2
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

    /// `resources/units.json` + `resources/weapons.json` をロードしてマージする。
    /// 失敗は panic（即可視化）。起動時の Game.start で 1 度だけ呼ぶ想定。
    pub def load(unitsPath: String, weaponsPath: String): UnitCatalog \ Fs.FileRead =
        let catalog = loadUnitsFile(unitsPath);
        let weapons = loadWeaponsFile(weaponsPath);
        let UnitCatalog.UnitCatalog(payload) = catalog;
        UnitCatalog.UnitCatalog({weapons = weapons | payload})

    /// units.json を読み Saveable[UnitCatalog] でデコード。weapons は空 Map で返る
    /// (units.json 側は weapons セクションを持たないため)。
    def loadUnitsFile(path: String): UnitCatalog \ Fs.FileRead =
        let readResult = run {
            Fs.ReadFile.read(path)
        } with Fs.ReadFile.runWithFileRead;
        match readResult {
            case Err(e) =>
                bug!("UnitCatalog.load units file read failed: ${path} :: ${e}")
            case Ok(content) =>
                match Json.Parse.parse(content) {
                    case None =>
                        bug!("UnitCatalog.load units JSON parse failed: ${path}")
                    case Some(json) =>
                        let decoded: Option[UnitCatalog] = Saveable.fromJson(json);
                        match decoded {
                            case None    => bug!("UnitCatalog.load units decode failed (schema mismatch?): ${path}")
                            case Some(c) => c
                        }
                }
        }

    /// weapons.json を読み `{"weapons": {...}}` の中身を Map にデコード。
    def loadWeaponsFile(path: String): Map[String, WeaponResource] \ Fs.FileRead =
        let readResult = run {
            Fs.ReadFile.read(path)
        } with Fs.ReadFile.runWithFileRead;
        match readResult {
            case Err(e) =>
                bug!("UnitCatalog.load weapons file read failed: ${path} :: ${e}")
            case Ok(content) =>
                match Json.Parse.parse(content) {
                    case None =>
                        bug!("UnitCatalog.load weapons JSON parse failed: ${path}")
                    case Some(json) =>
                        match UnitCatalogCodec.decodeWeaponsFile(json) {
                            case None    => bug!("UnitCatalog.load weapons decode failed: ${path}")
                            case Some(w) => w
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

    /// 武器 id を引いて `WeaponResource` を返す。未定義 id は起動時 typo として panic。
    /// 各ユニットの `initialWeapon` から武器インスタンスを解決する用途で使う。
    pub def lookupWeapon(id: String, catalog: UnitCatalog): WeaponResource =
        match Map.get(id, weaponsOf(catalog)) {
            case Some(w) => w
            case None    => bug!("UnitCatalog.lookupWeapon: weapon '${id}' not in catalog")
        }

    /// sprite#frame → ユニット表示名。units.json のスプライトシート上の並び順に
    /// 1:1 で対応する（0=Knight / 1=Archer / 2=Mage / 3=Orc / 4=Goblin）。
    /// HUD パネル（UnitInfoPopupScene）の名前表示に使う。シートの並びを変えたらここも更新する。
    pub def displayName(frame: Int32): String = match frame {
        case 0 => "Knight"
        case 1 => "Archer"
        case 2 => "Mage"
        case 3 => "Orc"
        case 4 => "Goblin"
        case _ => "Unknown"
    }

    /// Z 戦略の整合性検査用に Flix 型のフィールド名集合を公開する。
    /// `UnitResource` のフィールド構造を変更したらここも更新すること。
    /// engine 側 `Resource.checkConsistency` がこの集合と `_schema.json` を照合する。
    pub def expectedUnitFields(): Set[String] =
        Set#{"moveTiles", "hp", "attack", "defense", "speed", "sprite", "initialWeapon"}

    /// `WeaponResource` のフィールド名集合。`weapons.schema.json` との整合性検査に使う。
    pub def expectedWeaponFields(): Set[String] =
        Set#{"name", "attack", "durability", "range", "sprite"}
}

// ════════════════════════════════════════════════════════════════════════
// Saveable[UnitCatalog] — units.json の round-trip 実装
// ════════════════════════════════════════════════════════════════════════
//
// weapons.json は別ファイルなのでこの Saveable では扱わない。
// fromJson で得られた UnitCatalog の `weapons` は常に空 Map。
// 呼び出し側 (UnitCatalog.load) が weapons.json をマージする責務を持つ。

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

    /// units.json の round-trip 用エンコーダ。weapons は含めない (別ファイルで管理)。
    /// 例: { "units": {...}, "players": [...], "enemies": [...] }
    pub def encode(c: UnitCatalog): JsonElement =
        let units = UnitCatalog.unitsOf(c)
            |> Map.foldLeftWithKey((acc, id, u) ->
                Map.insert(id, encodeUnit(u), acc),
                Map.empty());
        let topWithUnits = Map#{"units" => JsonObject(units)};
        let top = UnitCatalog.poolsOf(c)
            |> Map.foldLeftWithKey((acc, name, ids) ->
                Map.insert(name, JsonArray(List.map(JsonString, ids) |> List.toVector), acc),
                topWithUnits);
        JsonObject(top)

    def encodeUnit(u: UnitResource): JsonElement =
        JsonObject(Map#{
            "moveTiles"     => JsonNumber(intToBd(u#moveTiles)),
            "hp"            => JsonNumber(intToBd(u#hp)),
            "attack"        => JsonNumber(intToBd(u#attack)),
            "defense"       => JsonNumber(intToBd(u#defense)),
            "speed"         => JsonNumber(intToBd(u#speed)),
            "sprite"        => encodeSprite(u#sprite),
            "initialWeapon" => JsonString(u#initialWeapon)
        })

    def encodeSprite(s: SpriteResource): JsonElement =
        JsonObject(Map#{
            "texture" => JsonString(s#texture),
            "hframes" => JsonNumber(intToBd(s#hframes)),
            "vframes" => JsonNumber(intToBd(s#vframes)),
            "frame"   => JsonNumber(intToBd(s#frame)),
            "offset"  => encodeOffset(s#offset)
        })

    def encodeOffset(v: Vec2.Vec2): JsonElement =
        JsonObject(Map#{
            "x" => JsonNumber(floatToBd(v#x)),
            "y" => JsonNumber(floatToBd(v#y))
        })

    def floatToBd(value: Float64): BigDecimal =
        unsafe IO {
            JBigDecimal.valueOf(value).stripTrailingZeros()
        }

    def intToBd(value: Int32): BigDecimal =
        unsafe IO {
            let stripped = JBigDecimal.valueOf(Int32.toFloat64(value)).stripTrailingZeros();
            if (stripped.scale() < 0) stripped.setScale(0) else stripped
        }

    // ── デコード ──

    /// units.json をデコード。weapons は常に空 Map で返す (別ファイル管理)。
    /// pools は `units` 以外のトップレベル array (= `players` / `enemies` 等) を全部取り込む。
    pub def decode(element: JsonElement): Option[UnitCatalog] =
        forM (
            top      <- expectObject(element);
            unitsJ   <- Map.get("units", top);
            unitsM   <- expectObject(unitsJ);
            units    <- traverseUnits(unitsM);
            pools    <- collectPools(top)
        ) yield UnitCatalog.UnitCatalog({units = units, weapons = Map.empty(), pools = pools})

    /// weapons.json の top JsonElement (`{"weapons": {...}}`) から武器マップを取り出す。
    pub def decodeWeaponsFile(element: JsonElement): Option[Map[String, WeaponResource]] =
        forM (
            top      <- expectObject(element);
            weaponsJ <- Map.get("weapons", top);
            weaponsM <- expectObject(weaponsJ);
            weapons  <- traverseWeapons(weaponsM)
        ) yield weapons

    /// top の `units` を除いた残りのキーで、値が JsonArray of JsonString のものを pool として収集。
    def collectPools(top: Map[String, JsonElement]): Option[Map[String, List[String]]] =
        let init: Option[Map[String, List[String]]] = Some(Map.empty());
        Map.foldLeftWithKey((acc, key, value) ->
            Option.flatMap(soFar -> {
                if (key == "units") Some(soFar)
                else match value {
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

    def decodeUnit(element: JsonElement): Option[UnitResource] =
        forM (
            obj    <- expectObject(element);
            mtJ    <- Map.get("moveTiles", obj);
            hpJ    <- Map.get("hp", obj);
            atkJ   <- Map.get("attack", obj);
            defJ   <- Map.get("defense", obj);
            spdJ   <- Map.get("speed", obj);
            spJ    <- Map.get("sprite", obj);
            iwJ    <- Map.get("initialWeapon", obj);
            mt     <- expectInt(mtJ);
            hp     <- expectInt(hpJ);
            atk    <- expectInt(atkJ);
            df     <- expectInt(defJ);
            spd    <- expectInt(spdJ);
            sp     <- decodeSprite(spJ);
            iw     <- expectString(iwJ)
        ) yield ({moveTiles = mt, hp = hp, attack = atk, defense = df,
                  speed = spd, sprite = sp, initialWeapon = iw}: UnitResource)

    def decodeWeapon(element: JsonElement): Option[WeaponResource] =
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
        ) yield ({name = name, attack = atk, durability = dur, range = rng,
                  sprite = sp}: WeaponResource)

    def decodeRange(element: JsonElement): Option[UnitCatalog.WeaponRange] =
        forM (
            obj    <- expectObject(element);
            minJ   <- Map.get("min", obj);
            maxJ   <- Map.get("max", obj);
            mn     <- expectInt(minJ);
            mx     <- expectInt(maxJ)
        ) yield ({min = mn, max = mx}: UnitCatalog.WeaponRange)

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
        ) yield {
            // offset は省略可能。無ければ {x = 0, y = 0}。
            let off = match Map.get("offset", obj) {
                case None     => ({x = 0.0, y = 0.0}: Vec2.Vec2)
                case Some(oj) => match decodeOffset(oj) {
                    case Some(v) => v
                    case None    => ({x = 0.0, y = 0.0}: Vec2.Vec2)
                }
            };
            ({texture = tex, hframes = hf, vframes = vf, frame = fr,
              offset = off}: SpriteResource)
        }

    /// `{"x": ..., "y": ...}` の片方だけでも読めるように、x/y を独立に optional に扱う。
    /// IDE のスライダーは値 0 のときフィールドを書き出さないことがあるので、片方欠落への
    /// 寛容な decoder にする。両方欠落でも `{x = 0, y = 0}` を返す。
    def decodeOffset(element: JsonElement): Option[Vec2.Vec2] =
        match element {
            case JsonObject(obj) =>
                let x = Map.get("x", obj) |> Option.flatMap(expectFloat)
                          |> Option.getWithDefault(0.0);
                let y = Map.get("y", obj) |> Option.flatMap(expectFloat)
                          |> Option.getWithDefault(0.0);
                Some({x = x, y = y})
            case _ => None
        }

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

    def expectFloat(element: JsonElement): Option[Float64] = match element {
        case JsonNumber(bd) => BigDecimal.tryToFloat64(bd)
        case _              => None
    }
}
