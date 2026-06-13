/// 武器カタログ (`resources/weapons.json` + `resources/weapons.schema.json`)。
/// UnitCatalog から分離した独立カタログ。engine の `CatalogContainer[WeaponResource]` +
/// `Saveable` 単相 instance のパターンに従う。
///
/// JSON 形状 (`resources/weapons.json`):
///   {
///     "weapons": {
///       "iron_lance": { "name": "てつのやり", "attack": 7, "durability": 10,
///                         "range": {"min":1, "max":1}, "weaponType": "Lance",
///                         "sprite": {...} },
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

    use Util.Json.Json
    use Util.Json.Json.{JObject}

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// 武器カタログ全体。`CatalogContainer[WeaponResource]` を wrap して `Saveable` を持たせる。
    /// containerKey は `"weapons"` 固定。
    /// **配置順の注意**: companion enum (= モジュール名と同名 enum) は Flix の規約上、
    /// モジュール先頭に置く。
    pub enum WeaponCatalog {
        case WeaponCatalog(CatalogContainer[WeaponResource])
    }

    /// 武器の種類。三竦み（剣 → 斧 → 槍 → 剣）の判定と、物理 / 魔法の区別を兼ねる。
    /// 剣・斧・槍は三竦みに参加する物理武器、弓は三竦み外の物理武器、魔法は魔力 vs 魔防。
    /// 力 vs 防御で計算するのは Magic 以外（= 物理武器）すべて。
    /// JSON では case 名の文字列（`"Sword"` 等）でシリアライズされる。
    /// 旧データの `"Physical"` は読み込み時に `Sword` へ読み替える（後方互換）。
    pub enum WeaponType with Eq, ToString {
        case Sword   // 剣（斧に有利）
        case Axe     // 斧（槍に有利）
        case Lance   // 槍（剣に有利）
        case Bow     // 弓（三竦みの外・常に中立）
        case Magic   // 魔法（中立・魔防を参照）
    }

    /// 全武器タイプの列挙。得意武器トグル UI の選択肢生成や、
    /// 初期ロード時にすべての武器タイプを得意とするユニットを生成する際に使う。
    pub def allWeaponTypes(): List[WeaponType] =
        WeaponType.Sword :: WeaponType.Axe :: WeaponType.Lance ::
        WeaponType.Bow :: WeaponType.Magic :: Nil

    /// `WeaponType` が物理武器か。Combat 系の分岐で使う薄いヘルパ。
    /// 魔法だけが魔力 vs 魔防で、剣・斧・槍・弓はすべて力 vs 防御の物理武器。
    pub def isPhysical(weaponType: WeaponType): Bool = match weaponType {
        case WeaponType.Magic => false
        case _                => true
    }

    /// 武器の特殊効果。`effectValue` がその効果の数値パラメータ（種類で意味が変わる）。
    /// `Staff.StaffEffect` / `Ring.RingEffect` と同様、JSON では case 名文字列でシリアライズ。
    ///   - `NoEffect`     : 効果なし（通常武器・あくまの斧）。`effectValue` 未使用
    ///   - `BraveOnSpeed` : 速さが相手より `effectValue` 以上速ければ 2 回攻撃（はやぶさの剣）
    ///   - `Knockback`    : 当てた相手を `effectValue` マス押し流す（0=無制限）。突風の書 / 如意棒
    ///   - `Desperation`  : 自分の HP が `effectValue`% 以下のとき威力 1.5 倍（背水の槍）
    ///   - `Lifesteal`    : 与ダメージの `effectValue`% を毎ヒット回復（血吸いの剣）
    ///   - `ThiefDrop`    : ローグ装備時のみ、命中時 `effectValue`% で敵がアイテムを落とす（盗人の剣）
    pub enum WeaponEffect with Eq, ToString {
        case NoEffect
        case BraveOnSpeed
        case Knockback
        case Desperation
        case Lifesteal
        case ThiefDrop
    }

    /// 文字列 → `WeaponEffect`。未知文字列は `Err`（JSON 直編集 typo を起動時に発覚させる）。
    pub def parseEffect(text: String): Result[String, WeaponEffect] = match text {
        case "NoEffect"     => Ok(WeaponEffect.NoEffect)
        case "BraveOnSpeed" => Ok(WeaponEffect.BraveOnSpeed)
        case "Knockback"    => Ok(WeaponEffect.Knockback)
        case "Desperation"  => Ok(WeaponEffect.Desperation)
        case "Lifesteal"    => Ok(WeaponEffect.Lifesteal)
        case "ThiefDrop"    => Ok(WeaponEffect.ThiefDrop)
        case other          => Err(other)
    }

    /// `parseEffect` と round-trip する文字列表現。
    pub def effectToString(effect: WeaponEffect): String = match effect {
        case WeaponEffect.NoEffect     => "NoEffect"
        case WeaponEffect.BraveOnSpeed => "BraveOnSpeed"
        case WeaponEffect.Knockback    => "Knockback"
        case WeaponEffect.Desperation  => "Desperation"
        case WeaponEffect.Lifesteal    => "Lifesteal"
        case WeaponEffect.ThiefDrop    => "ThiefDrop"
    }

    // ── 効果アクセサ（純粋・match 入れ子なし。Ring の lifestealAmount 等に倣う）─────

    /// はやぶさ: 2 回攻撃に必要な「自分−相手」の速さ差しきい値（None=ブレイブ武器でない）。
    pub def braveThreshold(effect: WeaponEffect, value: Int32): Option[Int32] = match effect {
        case WeaponEffect.BraveOnSpeed => Some(value)
        case _                         => None
    }

    /// ノックバック: 押し流すマス数（0 は無制限）。None=ノックバック武器でない。
    pub def knockbackTiles(effect: WeaponEffect, value: Int32): Option[Int32] = match effect {
        case WeaponEffect.Knockback => Some(value)
        case _                      => None
    }

    /// 背水: 威力 1.5 倍が発動する自 HP%しきい値。None=背水武器でない。
    pub def desperationThreshold(effect: WeaponEffect, value: Int32): Option[Int32] = match effect {
        case WeaponEffect.Desperation => Some(value)
        case _                        => None
    }

    /// 血吸い: 与ダメージの何 % を回復するか。0=吸収武器でない。
    pub def lifestealPercent(effect: WeaponEffect, value: Int32): Int32 = match effect {
        case WeaponEffect.Lifesteal => value
        case _                      => 0
    }

    /// 盗人: アイテムを落とす確率 %。0=盗人武器でない。
    pub def thiefDropChance(effect: WeaponEffect, value: Int32): Int32 = match effect {
        case WeaponEffect.ThiefDrop => value
        case _                      => 0
    }

    /// 攻撃可能な距離の範囲。`min..max` inclusive のマンハッタン距離で判定する。
    pub type alias WeaponRange = {
        min = Int32,
        max = Int32
    }

    /// 武器カタログの sprite メタ情報。中立な `Sprite.SpriteResource` の alias として共有する。
    /// UnitCatalog への逆依存を避けるため `Sprite` mod に集約している。
    pub type alias WeaponSpriteResource = Sprite.SpriteResource

    /// 武器 1 種類ぶんのデータ。
    /// `name` は表示用の和名。`attack` は武器の攻撃力ボーナス、`durability` は耐久度。
    /// `hit` は武器命中率 (命中 = 武器命中 + 技×2 + 幸運÷2 の基礎値)。
    /// `range` は攻撃可能距離。`weaponType` は物理 / 魔法。`sprite` は ItemMenu アイコン用。
    /// `description` はアイテム詳細ウィンドウに出す一言説明（フレーバーテキスト）。
    pub type alias WeaponResource = {
        name        = String,
        attack      = Int32,
        hit         = Int32,
        crit        = Int32,
        durability  = Int32,
        range       = WeaponRange,
        weaponType  = WeaponType,
        effect      = WeaponEffect,
        effectValue = Int32,
        sprite      = WeaponSpriteResource,
        description = String,
        effectRule  = Option[Util.Json.Json]
    }

    // ────────────────────────────────────────────────────────
    // (B) アクセサ / ロード
    // ────────────────────────────────────────────────────────

    /// `WeaponCatalog` ラップを剥がして生 Map を返す。
    pub def weaponsOf(catalog: WeaponCatalog): Map[String, WeaponResource] =
        let WeaponCatalog.WeaponCatalog(container) = catalog;
        CatalogContainer.entriesOf(container)

    /// `resources/weapons.json` をロードし、`resources/weapons.schema.json` で整合検査する。
    /// 起動時の `Game.start` で 1 度だけ呼ぶ想定。失敗は panic で即可視化。
    pub def load(): WeaponCatalog \ Fs.FileRead =
        let container = CatalogContainer.loadWithCheck({
            dataPath       = AssetPath.resolve("resources/weapons.json"),
            schemaPath     = AssetPath.resolve("resources/weapons.schema.json"),
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

    /// 空の `WeaponCatalog` (entries 0 件) を返す。`Saveable.fromJson` でセーブデータを
    /// 復元する前の初期値として使用する（`load` ではなく JSON 復元パスで使う）。
    pub def empty(): WeaponCatalog =
        WeaponCatalog.WeaponCatalog(CatalogContainer.CatalogContainer({
            containerKey = "weapons",
            entries      = (Map.empty(): Map[String, WeaponResource]),
            meta         = (Map.empty(): Map[String, Util.Json.Json])
        }))

    /// schema 検査用の expected key 集合（`CatalogContainer.loadWithCheck` に渡す）。
    pub def expectedFields(): Set[String] =
        Set#{"name", "attack", "hit", "crit", "durability", "range", "weaponType",
             "effect", "effectValue", "sprite", "description", "effectRule"}
}

// ════════════════════════════════════════════════════════════════════════
// Saveable[WeaponCatalog] — weapons.json の round-trip 実装 (薄い wrap)
// ════════════════════════════════════════════════════════════════════════

instance Saveable[WeaponCatalog.WeaponCatalog] {
    pub def toJson(value: WeaponCatalog.WeaponCatalog): Util.Json.Json =
        let WeaponCatalog.WeaponCatalog.WeaponCatalog(container) = value;
        CatalogContainer.encode(WeaponCatalogCodec.encodeWeapon, container)

    pub def fromJson(element: Util.Json.Json): Option[WeaponCatalog.WeaponCatalog] =
        CatalogContainer.decode("weapons", WeaponCatalogCodec.decodeWeapon, element)
            |> Option.map(WeaponCatalog.WeaponCatalog.WeaponCatalog)
}

/// `WeaponResource` ↔ Json の変換ロジックを集約するモジュール。
/// container 全体の巡回は `CatalogContainer.encode/decode` に委譲し、
/// このモジュールはエントリ単位の変換のみを担う（責務の分離）。
mod WeaponCatalogCodec {

    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JNumber}
    use JsonCodec.{expectObject, expectString, expectInt, expectFloat, floatToBd, intToBd}
    use WeaponCatalog.{WeaponResource, WeaponRange, WeaponType, WeaponSpriteResource}

    /// `WeaponResource` を `weapons.json` エントリ形式の `JObject` に変換する。
    /// `Saveable[WeaponCatalog].toJson` 経由で `CatalogContainer.encode` に渡される。
    pub def encodeWeapon(weapon: WeaponResource): Json =
        let base = Map#{
            "name"        => JString(weapon#name),
            "attack"      => JNumber(intToBd(weapon#attack)),
            "hit"         => JNumber(intToBd(weapon#hit)),
            "crit"        => JNumber(intToBd(weapon#crit)),
            "durability"  => JNumber(intToBd(weapon#durability)),
            "range"       => encodeRange(weapon#range),
            "weaponType"  => JString(weaponTypeToString(weapon#weaponType)),
            "effect"      => JString(WeaponCatalog.effectToString(weapon#effect)),
            "effectValue" => JNumber(intToBd(weapon#effectValue)),
            "sprite"      => encodeSprite(weapon#sprite),
            "description" => JString(weapon#description)
        };
        match weapon#effectRule {
            case Some(j) => JObject(Map.insert("effectRule", j, base))
            case None    => JObject(base)
        }

    def encodeRange(range: WeaponRange): Json =
        JObject(Map#{
            "min" => JNumber(intToBd(range#min)),
            "max" => JNumber(intToBd(range#max))
        })

    /// `WeaponType` を JSON / 設定で使う case 名文字列に。`parseWeaponType` と対。
    /// 武器タイプ習熟（得意/苦手）の units.json 配列でも使うため pub。
    pub def weaponTypeToString(weaponType: WeaponType): String = match weaponType {
        case WeaponType.Sword => "Sword"
        case WeaponType.Axe   => "Axe"
        case WeaponType.Lance => "Lance"
        case WeaponType.Bow   => "Bow"
        case WeaponType.Magic => "Magic"
    }

    def encodeSprite(sprite: WeaponSpriteResource): Json =
        JObject(Map#{
            "texture" => JString(sprite#texture),
            "hframes" => JNumber(intToBd(sprite#hframes)),
            "vframes" => JNumber(intToBd(sprite#vframes)),
            "frame"   => JNumber(intToBd(sprite#frame)),
            "offset"  => JsonCodec.encodeVec2(sprite#offset),
            "scale"   => JsonCodec.encodeVec2(sprite#scale)
        })

    /// `weapons.json` の 1 エントリを `WeaponResource` に変換する。
    /// `load` と `Saveable[WeaponCatalog].fromJson` の両パスから呼ばれる。
    /// 必須フィールドの欠落・型不一致は `None` を返す（panic しない）。
    /// `weaponType` / `hit` は後方互換のため省略可（欠落時は `Sword` / `0`）。
    pub def decodeWeapon(element: Json): Option[WeaponResource] =
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
            // weaponType は省略可能。欠落 / 未知文字列は Sword (旧 weapons.json への後方互換)
            let wt = Map.get("weaponType", obj)
                        |> Option.flatMap(expectString)
                        |> Option.map(parseWeaponType)
                        |> Option.getWithDefault(WeaponType.Sword);
            // hit (武器命中率) も省略可。欠落時は 0 (後方互換)。
            let hit = Map.get("hit", obj)
                        |> Option.flatMap(expectInt)
                        |> Option.getWithDefault(0);
            // description (一言説明) も省略可。欠落時は空文字 (旧 weapons.json / 旧セーブ後方互換)。
            let desc = Map.get("description", obj)
                        |> Option.flatMap(expectString)
                        |> Option.getWithDefault("");
            // crit (武器必殺率) も省略可。欠落時は 0 (後方互換)。
            let crit = Map.get("crit", obj)
                        |> Option.flatMap(expectInt)
                        |> Option.getWithDefault(0);
            // effect (特殊効果) / effectValue も省略可。欠落 / 未知文字列は NoEffect / 0 (後方互換)。
            let effect = Map.get("effect", obj)
                        |> Option.flatMap(expectString)
                        |> Option.map(WeaponCatalog.parseEffect)
                        |> Option.flatMap(Result.toOption)
                        |> Option.getWithDefault(WeaponCatalog.WeaponEffect.NoEffect);
            let effectValue = Map.get("effectValue", obj)
                        |> Option.flatMap(expectInt)
                        |> Option.getWithDefault(0);
            ({name = name, attack = atk, hit = hit, crit = crit, durability = dur, range = rng,
              weaponType = wt, effect = effect, effectValue = effectValue,
              sprite = sp, description = desc,
              effectRule = Map.get("effectRule", obj)}: WeaponResource)
        }

    /// case 名文字列から `WeaponType` に。旧データの `"Physical"` は剣として読み替え、
    /// 未知文字列も剣にフォールバックする（JSON 直編集の typo / 後方互換対策）。
    pub def parseWeaponType(text: String): WeaponType = match text {
        case "Sword"    => WeaponType.Sword
        case "Axe"      => WeaponType.Axe
        case "Lance"    => WeaponType.Lance
        case "Bow"      => WeaponType.Bow
        case "Magic"    => WeaponType.Magic
        case "Physical" => WeaponType.Sword
        case _          => WeaponType.Sword
    }

    def decodeRange(element: Json): Option[WeaponRange] =
        forM (
            obj    <- expectObject(element);
            minJ   <- Map.get("min", obj);
            maxJ   <- Map.get("max", obj);
            mn     <- expectInt(minJ);
            mx     <- expectInt(maxJ)
        ) yield ({min = mn, max = mx}: WeaponRange)

    def decodeSprite(element: Json): Option[WeaponSpriteResource] =
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
            // offset / scale / flipForFacing は省略可能フィールド。
            // texture / hframes / vframes / frame と異なり、後から追加されたため
            // 旧 weapons.json には存在しない場合があり、欠落時はデフォルト値を使う。
            // offset: (0,0), scale: (1,1), flipForFacing: false。
            let off = JsonCodec.decodeVec2OrDefault(Map.get("offset", obj), 0.0);
            let sc  = JsonCodec.decodeVec2OrDefault(Map.get("scale", obj),  1.0);
            let flip = Map.get("flipForFacing", obj)
                        |> Option.flatMap(JsonCodec.expectBool) |> Option.getWithDefault(false);
            ({texture = tex, hframes = hf, vframes = vf, frame = fr,
              offset = off, scale = sc, flipForFacing = flip}: WeaponSpriteResource)
        }
}
