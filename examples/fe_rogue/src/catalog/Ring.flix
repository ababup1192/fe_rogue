/// Ring — 指輪（装備アクセサリ）の型・カタログ・純粋ロジック
///
/// 武器・杖・消費アイテムとは別系統の「装備アクセサリ」を定義する。
/// 共通仕様:
///   - 1 ユニットにつき 1 つだけ効果が発動する（所持リストの先頭が装備中）
///   - 耐久度は持たない（壊れない）
///   - 効果は `effect`（種類）と `power`（効果量）で表す
///
/// このモジュールは Scene[NodeTag] / effect に依存せず、テストが純粋値で完結する。
/// 効果の実適用（ステータス補正の加算・追撃判定・回復・撃破回復）は呼び出し側が担い、
/// ここは「どの効果か」「どれだけか」を純粋に答える。
///
/// JSON 形状 (`resources/rings.json`):
///   {
///     "rings": {
///       "power_ring": { "name": "ちからのリング", "effect": "Power", "power": 3,
///                        "sprite": {...}, "description": "攻撃が3上がる" }
///     }
///   }
mod Ring {

    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JNumber}
    use Sprite.SpriteResource

    /// 指輪の効果の種類。
    ///   - `Pursuit`  : 速さが相手より 3 以上高いと 15% で追撃（2 回攻撃）。`power` 不使用
    ///   - `Power`    : 攻撃を `power` 上げる（負値で下げるネタ指輪も表現できる）
    ///   - `Swift`    : 速さを `power` 上げる
    ///   - `Guard`    : 防御を `power` 上げる
    ///   - `Mend`     : 自分のターン開始時に HP を `power` 回復する
    ///   - `Lifesteal`: 敵を撃破したとき攻撃側の HP を `power` 回復する
    ///   - `Finisher` : 攻撃対象の残 HP が最大の `power`% 以下なら必中の必殺になる
    ///   - `Trivial`  : 何の効果もない（ネタ指輪）
    ///   - `Levitate` : 浮雲。装備も使用もできず「持っているだけ」で効果を持つ特殊アイテム。
    ///                  `weight` フィールドに負値を入れて積載を稼ぐ（例 -1.0 / -2.5 / -4.5）。
    ///                  装備枠を占有しないよう、サブメニューでは「捨てる」だけを出す（`isPassiveHold`）。
    pub enum RingEffect with Eq, ToString {
        case Pursuit
        case Power
        case Swift
        case Guard
        case Mend
        case Lifesteal
        case Finisher
        case Trivial
        case Levitate
    }

    /// 「持っているだけ」系（装備も使用もできず、所持で効果・捨てるのみ）か。
    /// 現状は浮雲（Levitate）のみ。ItemMenu のサブメニュー出し分けに使う。
    pub def isPassiveHold(ring: RingResource): Bool =
        ring#effect == RingEffect.Levitate

    /// 指輪 1 種類ぶんのデータ。
    /// `effect` は効果の種類。`power` は効果量（種類で意味が変わる。Pursuit/Trivial では未使用）。
    /// `sprite` は ItemMenu のアイコンに使う。`description` は詳細ウィンドウの一言説明。
    pub type alias RingResource = {
        name        = String,
        effect      = RingEffect,
        power       = Int32,
        // 重量（積載に効く）。JSON で直接指定する設計値。省略時は decoder が 0.4 を埋める。
        // 浮雲(Levitate)は負値を入れて積載を稼ぐ（例 -1.0 / -2.5 / -4.5）。
        weight      = Float64,
        sprite      = SpriteResource,
        description = String,
        // IDE 合成エディタが書く効果ルール（簡易形式 JSON）。表示の効果文に使う。
        effectRule  = Option[Util.Json.Json]
    }

    /// 装備中指輪が攻守ステータスに与える補正。Power/Swift/Guard のみ非 0。
    /// 命中・必殺（武器側の値）は触らない設計（指輪は weapon の hit/crit をいじらない）。
    pub type alias Bonuses = {
        attack  = Int32,
        speed   = Int32,
        defense = Int32,
        skill   = Int32,
        luck    = Int32
    }

    /// 補正なし（全 0）。
    pub def zeroBonuses(): Bonuses =
        {attack = 0, speed = 0, defense = 0, skill = 0, luck = 0}

    /// effectRule(簡易形式) の "amount" を取り出す。あれば指輪の効果量を IDE 編集に追従させる。
    /// 無し/不正なら None（呼び出し側は従来の `power` にフォールバック）。
    def ruleAmount(ring: RingResource): Option[Int32] =
        ring#effectRule |> Option.flatMap(j -> match j {
            case JObject(m) => Map.get("amount", m) |> Option.flatMap(JsonCodec.expectInt)
            case _          => None
        })

    /// 指輪の効果量。effectRule があればその amount、無ければ `power`。
    /// Power/Swift/Guard/Mend/Lifesteal の量はすべてここを通すので IDE 編集で挙動が変わる。
    def amountOf(ring: RingResource): Int32 =
        ruleAmount(ring) |> Option.getWithDefault(ring#power)

    /// 指輪 1 個の効果からステータス補正を出す（装備の有無判定は `bonuses` が担う。match を入れ子にしない）。
    def effectBonuses(ring: RingResource): Bonuses = match ring#effect {
        case RingEffect.Power => {attack  = amountOf(ring) | zeroBonuses()}
        case RingEffect.Swift => {speed   = amountOf(ring) | zeroBonuses()}
        case RingEffect.Guard => {defense = amountOf(ring) | zeroBonuses()}
        case _                => zeroBonuses()
    }

    /// 装備中（先頭）の指輪が与えるステータス補正。装備していない / 補正を持たない効果は全 0。
    pub def bonuses(equipped: Option[RingResource]): Bonuses =
        equipped |> Option.map(effectBonuses) |> Option.getWithDefault(zeroBonuses())

    /// 指輪 1 個の Mend 回復量（Mend 以外は 0）。effectRule があればその amount に追従。
    def mendPower(ring: RingResource): Int32 = match ring#effect {
        case RingEffect.Mend => amountOf(ring)
        case _               => 0
    }

    /// 装備中指輪が Mend ならターン開始の回復量、それ以外は 0。
    pub def mendAmount(equipped: Option[RingResource]): Int32 =
        equipped |> Option.map(mendPower) |> Option.getWithDefault(0)

    /// 指輪 1 個の Lifesteal 回復量（Lifesteal 以外は 0）。effectRule があればその amount に追従。
    def lifestealPower(ring: RingResource): Int32 = match ring#effect {
        case RingEffect.Lifesteal => amountOf(ring)
        case _                    => 0
    }

    /// 装備中指輪が Lifesteal なら撃破時の回復量、それ以外は 0。
    pub def lifestealAmount(equipped: Option[RingResource]): Int32 =
        equipped |> Option.map(lifestealPower) |> Option.getWithDefault(0)

    /// 指輪 1 個の Finisher しきい値（Finisher 以外は None）。
    def finisherPct(ring: RingResource): Option[Int32] = match ring#effect {
        case RingEffect.Finisher => Some(ring#power)
        case _                   => None
    }

    /// 装備中指輪が Finisher なら「対象の残 HP がこの割合(%)以下で必中必殺」のしきい値、
    /// それ以外は None。
    pub def finisherThreshold(equipped: Option[RingResource]): Option[Int32] =
        equipped |> Option.flatMap(finisherPct)

    /// Finisher の発動判定（純粋）。対象の現 HP が最大 HP の `thresholdPct`% 以下なら true。
    /// 指輪が Finisher でない（None）なら常に false。割り算を避け `cur * 100 <= max * pct` で比較する。
    pub def finisherTriggers(curHp: Int32, maxHp: Int32, threshold: Option[Int32]): Bool =
        match threshold {
            case None      => false
            case Some(pct) => curHp * 100 <= maxHp * pct
        }

    /// 指輪 1 個が Pursuit か。
    def isPursuit(ring: RingResource): Bool = ring#effect == RingEffect.Pursuit

    /// 装備中指輪が Pursuit か。
    pub def hasPursuit(equipped: Option[RingResource]): Bool =
        equipped |> Option.map(isPursuit) |> Option.getWithDefault(false)

    /// 指輪カタログ全体。`CatalogContainer[RingResource]` を wrap して `Saveable` を付与する。
    /// containerKey を `"rings"` に固定し JSON ルートキーと 1 対 1 に対応させる。
    pub enum RingCatalog {
        case RingCatalog(CatalogContainer[RingResource])
    }

    /// rings 部 (id → RingResource の Map) を取り出す。
    pub def ringsOf(catalog: RingCatalog): Map[String, RingResource] =
        let RingCatalog.RingCatalog(container) = catalog;
        CatalogContainer.entriesOf(container)

    /// 文字列 → `RingEffect` のパース（`Staff.parseEffect` と同形）。未知文字列は `Err`。
    pub def parseEffect(name: String): Result[String, RingEffect] = match name {
        case "Pursuit"   => Ok(RingEffect.Pursuit)
        case "Power"     => Ok(RingEffect.Power)
        case "Swift"     => Ok(RingEffect.Swift)
        case "Guard"     => Ok(RingEffect.Guard)
        case "Mend"      => Ok(RingEffect.Mend)
        case "Lifesteal" => Ok(RingEffect.Lifesteal)
        case "Finisher"  => Ok(RingEffect.Finisher)
        case "Trivial"   => Ok(RingEffect.Trivial)
        case "Levitate"  => Ok(RingEffect.Levitate)
        case other       => Err(other)
    }

    /// `parseEffect` と round-trip する文字列表現を返す。
    pub def effectToString(effect: RingEffect): String = match effect {
        case RingEffect.Pursuit   => "Pursuit"
        case RingEffect.Power     => "Power"
        case RingEffect.Swift     => "Swift"
        case RingEffect.Guard     => "Guard"
        case RingEffect.Mend      => "Mend"
        case RingEffect.Lifesteal => "Lifesteal"
        case RingEffect.Finisher  => "Finisher"
        case RingEffect.Trivial   => "Trivial"
        case RingEffect.Levitate  => "Levitate"
    }

    /// `resources/rings.json` をロードし、`resources/rings.schema.json` で整合検査する。
    /// 起動時に 1 度だけ呼ぶ想定。失敗は panic で即可視化。
    pub def load(): RingCatalog \ Fs.FileRead =
        let container = CatalogContainer.loadWithCheck({
            dataPath       = AssetPath.resolve("resources/rings.json"),
            schemaPath     = AssetPath.resolve("resources/rings.schema.json"),
            containerKey   = "rings",
            expectedFields = expectedFields(),
            decodeEntry    = RingCatalogCodec.decodeRing
        });
        RingCatalog.RingCatalog(CatalogId.requireUniqueNames("Ring", r -> r#name, container))

    /// `RingResource` から catalog id を逆引きする（name 一致）。スナップショット保存で使う。
    /// name はカタログ内で一意（load 時に検査）。見つからなければ `None`。
    pub def idOf(ring: RingResource, catalog: RingCatalog): Option[String] =
        let RingCatalog.RingCatalog(container) = catalog;
        CatalogId.idByName(r -> r#name, ring#name, container)

    /// 指輪 id を引いて `RingResource` を返す。未定義 id は起動時 typo として panic。
    pub def lookup(id: String, catalog: RingCatalog): RingResource =
        let RingCatalog.RingCatalog(container) = catalog;
        match CatalogContainer.get(id, container) {
            case Some(ring) => ring
            case None       => bug!("Ring.lookup: ring '${id}' not in catalog")
        }

    /// `RingResource` のフィールド名集合。schema との照合で乖離を起動時に発覚させる。
    pub def expectedFields(): Set[String] =
        Set#{"name", "effect", "power", "weight", "sprite", "description", "effectRule"}
}

// container の巡回・schema 検査は CatalogContainer に委譲し、ここは wrap のみ。
instance Saveable[Ring.RingCatalog] {
    pub def toJson(value: Ring.RingCatalog): Util.Json.Json =
        let Ring.RingCatalog.RingCatalog(container) = value;
        CatalogContainer.encode(RingCatalogCodec.encodeRing, container)

    pub def fromJson(element: Util.Json.Json): Option[Ring.RingCatalog] =
        CatalogContainer.decode("rings", RingCatalogCodec.decodeRing, element)
            |> Option.map(Ring.RingCatalog.RingCatalog)
}

/// RingResource 1 件分の encode / decode のみ。container 巡回は `CatalogContainer.encode/decode` に委譲。
mod RingCatalogCodec {

    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JNumber}
    use JsonCodec.{expectObject, expectString, expectInt, expectFloat, floatToBd, intToBd}
    use Ring.RingResource
    use Sprite.SpriteResource

    pub def encodeRing(ring: RingResource): Json =
        let base = Map#{
            "name"        => JString(ring#name),
            "effect"      => JString(Ring.effectToString(ring#effect)),
            "power"       => JNumber(intToBd(ring#power)),
            "weight"      => JNumber(floatToBd(ring#weight)),
            "sprite"      => encodeSprite(ring#sprite),
            "description" => JString(ring#description)
        };
        match ring#effectRule {
            case Some(j) => JObject(Map.insert("effectRule", j, base))
            case None    => JObject(base)
        }

    def encodeSprite(sprite: SpriteResource): Json =
        JObject(Map#{
            "texture" => JString(sprite#texture),
            "hframes" => JNumber(intToBd(sprite#hframes)),
            "vframes" => JNumber(intToBd(sprite#vframes)),
            "frame"   => JNumber(intToBd(sprite#frame)),
            "offset"  => JsonCodec.encodeVec2(sprite#offset)
        })

    pub def decodeRing(element: Json): Option[RingResource] =
        forM (
            obj      <- expectObject(element);
            nameJ    <- Map.get("name", obj);
            effJ     <- Map.get("effect", obj);
            spriteJ  <- Map.get("sprite", obj);
            name     <- expectString(nameJ);
            effStr   <- expectString(effJ);
            effect   <- Result.toOption(Ring.parseEffect(effStr));
            sprite   <- decodeSprite(spriteJ)
        ) yield {
            // power は省略可。欠落時は 0（Pursuit/Trivial は未使用なので 0 でよい）。
            let power = Map.get("power", obj)
                        |> Option.flatMap(expectInt) |> Option.getWithDefault(0);
            // description は省略可。欠落時は空文字。
            let desc = Map.get("description", obj)
                        |> Option.flatMap(expectString) |> Option.getWithDefault("");
            // weight (重量) は省略可。欠落時は 0.4 (後方互換)。
            let weight = Map.get("weight", obj)
                        |> Option.flatMap(expectFloat) |> Option.getWithDefault(0.4);
            ({name = name, effect = effect, power = power, weight = weight,
               sprite = sprite, description = desc,
               effectRule = Map.get("effectRule", obj)}: RingResource)
        }

    def decodeSprite(element: Json): Option[SpriteResource] =
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
            let off = JsonCodec.decodeVec2OrDefault(Map.get("offset", obj), 0.0);
            let sc = JsonCodec.decodeVec2OrDefault(Map.get("scale", obj), 1.0);
            let flip = Map.get("flipForFacing", obj)
                        |> Option.flatMap(JsonCodec.expectBool) |> Option.getWithDefault(false);
            ({texture = tex, hframes = hf, vframes = vf, frame = fr,
              offset = off, scale = sc, flipForFacing = flip}: SpriteResource)
        }
}
