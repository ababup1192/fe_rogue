/// Consumable — 消費アイテム（きずぐすり等）の型・カタログ・純粋ロジック
///
/// 武器（`Weapon.flix`）・杖（`Staff.flix`）とは別系統の「消費アイテム」を定義する。
/// 共通仕様:
///   - 「つかう」と使用者自身に効果が出る（方向・対象選択は無い）
///   - 耐久度 = 使用回数。使うごとに 1 ずつ減り、0 で無くなる
///
/// きずぐすり: 使用者の HP を `healAmount` だけ回復する。
///
/// このモジュールは Scene[NodeTag] / effect に依存せず、テストが純粋値で完結する。
/// 効果適用の Scene 操作は呼び出し側 (`StaffCastScene.applyConsumableUse`) が担う。
///
/// JSON 形状 (`resources/consumables.json`):
///   {
///     "consumables": {
///       "vulnerary": { "name": "きずぐすり", "healAmount": 10,
///                       "durability": 3, "sprite": {...} }
///     }
///   }
mod Consumable {

    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JNumber}
    use Sprite.SpriteResource

    /// 消費アイテムの効果の種類（杖の `Staff.StaffEffect` を手本にした enum）。
    /// `magnitude` / `duration` の意味は種類ごとに異なる（下記コメント参照）。
    /// 新しい薬は基本この enum に値を 1 つ足し、`parseEffect` / `deliveryFor` /
    /// 自己効果なら `StaffCastScene.applyConsumableSelfEffect` に arm を足すだけで増やせる。
    ///   - `Heal`       : 使用者の HP を `magnitude` 回復（自己使用）
    ///   - `FullHeal`   : 使用者の HP を全回復（自己使用、`magnitude` 不使用）
    ///   - `MaxHpUp`    : 使用者の最大 HP を `magnitude` 永続上昇（自己使用、`duration` 不使用）
    ///   - `AutoRevive` : HP0 で自動発動し全回復（所持しているだけで保険になる。復活の草相当）
    ///   - `BlindHit`   : 杖式に投げ、当たったキャラの命中を `magnitude`% を `duration` ターン下げる
    ///   - `SpdDownHit` : 杖式に投げ、当たったキャラの速さ（回避）を `magnitude` を `duration` ターン下げる
    ///   - `AtkUp`      : 使用者の攻撃力を `magnitude` を `duration` ターン上げる（自己使用）
    ///   - `SpdUp`      : 使用者の速さ（回避）を `magnitude` を `duration` ターン上げる（自己使用）
    ///   - `FireBottle` : 火炎瓶。投げて当たった対象に `magnitude` の固定ダメージ（防御無視）
    ///   - `BlastBottle`: 爆発瓶。当たった対象とその周囲 1 マス（味方含む）に `magnitude` 固定ダメージ
    pub enum ConsumableEffect with Eq, ToString {
        case Heal
        case FullHeal
        case MaxHpUp
        case AutoRevive
        case BlindHit
        case SpdDownHit
        case AtkUp
        case SpdUp
        case DefDownHit
        case FireBottle
        case BlastBottle
    }

    /// 効果から導かれる「使い方（デリバリ）」。`effect` から `deliveryFor` で 1:1 に決まるため
    /// JSON / schema / codec には出さない（＝デザイナが投擲/自己/自動を取り違えられない安全設計）。
    ///   - `SelfUse`     : つかうと使用者自身に効果（方向選択なし）
    ///   - `Directional` : 杖と同じく方向を選んで投げ、最初に当たったキャラに効果
    ///   - `AutoOnDeath` : 所持中に HP0 で自動発動（つかうメニューには出さない）
    pub enum Delivery with Eq, ToString {
        case SelfUse
        case Directional
        case AutoOnDeath
    }

    /// 消費アイテム 1 種類ぶんのデータ。
    /// `effect` は効果の種類。`magnitude` は効果量（回復量 / +N / 命中-N% 等、種類で意味が変わる）。
    /// `duration` はバフ・デバフの持続ターン数（回復・最大HP・蘇生では無視される死にフィールド）。
    /// `healAmount` は後方互換のため残置（旧データ用。新コードは `magnitude` を参照する）。
    /// `durability` は JSON から読み込んだ初期値が必ず正であることを前提とする。
    ///   `consume` が durability ≤ 0 で None を返すため、JSON に 0 以下が入ると 1 度も使えない。
    /// `sprite` は ItemMenu のアイコンに使う。
    /// `description` はアイテム詳細ウィンドウに出す一言説明（フレーバーテキスト）。
    pub type alias ConsumableResource = {
        name        = String,
        effect      = ConsumableEffect,
        magnitude   = Int32,
        duration    = Int32,
        healAmount  = Int32,
        durability  = Int32,
        sprite      = SpriteResource,
        description = String,
        // IDE の効果合成エディタが書く効果ルール（簡易形式 JSON）。あれば legacy effect より優先して
        // ゲームが発火に使う。無ければ None（従来の effect で動く）。
        effectRule  = Option[Json]
    }

    /// 効果 → デリバリの 1:1 導出。`Staff` のように方向を要するもの（投擲デバフ）と、
    /// 自己使用、所持中自動発動を振り分ける。`ItemMenuScene.applyUse` がこの結果で経路を分岐する。
    pub def deliveryFor(effect: ConsumableEffect): Delivery = match effect {
        case ConsumableEffect.Heal       => Delivery.SelfUse
        case ConsumableEffect.FullHeal   => Delivery.SelfUse
        case ConsumableEffect.MaxHpUp    => Delivery.SelfUse
        case ConsumableEffect.AtkUp      => Delivery.SelfUse
        case ConsumableEffect.SpdUp      => Delivery.SelfUse
        case ConsumableEffect.BlindHit    => Delivery.Directional
        case ConsumableEffect.SpdDownHit  => Delivery.Directional
        case ConsumableEffect.DefDownHit  => Delivery.Directional
        case ConsumableEffect.FireBottle  => Delivery.Directional
        case ConsumableEffect.BlastBottle => Delivery.Directional
        case ConsumableEffect.AutoRevive  => Delivery.AutoOnDeath
    }

    /// 文字列 → `ConsumableEffect` のパース（`Staff.parseEffect` と同形）。
    /// schema 側で enum を絞っているので通常は到達しないが、JSON 直編集の typo を
    /// 起動時に発覚させるため未知文字列は `Err(その文字列)` で表現する。
    pub def parseEffect(name: String): Result[String, ConsumableEffect] = match name {
        case "Heal"       => Ok(ConsumableEffect.Heal)
        case "FullHeal"   => Ok(ConsumableEffect.FullHeal)
        case "MaxHpUp"    => Ok(ConsumableEffect.MaxHpUp)
        case "AutoRevive" => Ok(ConsumableEffect.AutoRevive)
        case "BlindHit"    => Ok(ConsumableEffect.BlindHit)
        case "SpdDownHit"  => Ok(ConsumableEffect.SpdDownHit)
        case "DefDownHit"  => Ok(ConsumableEffect.DefDownHit)
        case "AtkUp"       => Ok(ConsumableEffect.AtkUp)
        case "SpdUp"       => Ok(ConsumableEffect.SpdUp)
        case "FireBottle"  => Ok(ConsumableEffect.FireBottle)
        case "BlastBottle" => Ok(ConsumableEffect.BlastBottle)
        case other         => Err(other)
    }

    /// `parseEffect` と round-trip する文字列表現を返す。
    pub def effectToString(effect: ConsumableEffect): String = match effect {
        case ConsumableEffect.Heal       => "Heal"
        case ConsumableEffect.FullHeal   => "FullHeal"
        case ConsumableEffect.MaxHpUp    => "MaxHpUp"
        case ConsumableEffect.AutoRevive => "AutoRevive"
        case ConsumableEffect.BlindHit    => "BlindHit"
        case ConsumableEffect.SpdDownHit  => "SpdDownHit"
        case ConsumableEffect.DefDownHit  => "DefDownHit"
        case ConsumableEffect.AtkUp       => "AtkUp"
        case ConsumableEffect.SpdUp       => "SpdUp"
        case ConsumableEffect.FireBottle  => "FireBottle"
        case ConsumableEffect.BlastBottle => "BlastBottle"
    }

    /// 消費アイテムカタログ全体。
    /// `CatalogContainer[ConsumableResource]` を wrap する理由は `Saveable` instance を付与して
    /// consumables.json への round-trip 保存を可能にするため。
    /// containerKey を `"consumables"` に固定することで JSON ルートキーと 1 対 1 に対応し、
    /// `CatalogContainer.loadWithCheck` が正しいネストを解析できる。
    pub enum ConsumableCatalog {
        case ConsumableCatalog(CatalogContainer[ConsumableResource])
    }

    /// consumables 部 (id → ConsumableResource の Map) を取り出す。
    pub def consumablesOf(catalog: ConsumableCatalog): Map[String, ConsumableResource] =
        let ConsumableCatalog.ConsumableCatalog(container) = catalog;
        CatalogContainer.entriesOf(container)

    /// 消費アイテムを 1 回使用したあとの状態を返す（`Staff.consume` と同形）。
    /// 耐久度が 1 → 0 に遷移するなら `None`（使い切った）。
    /// それ以上残っていれば `Some(更新後 consumable)`。
    /// `<= 0` で判定するのは durability=0 の異常 JSON が来た場合も即 None にして防衛するため。
    pub def consume(item: ConsumableResource): Option[ConsumableResource] =
        let newDurability = item#durability - 1;
        if (newDurability <= 0) None
        else Some({durability = newDurability | item})

    /// `resources/consumables.json` をロードし、`resources/consumables.schema.json` で整合検査する。
    /// 起動時の `Game.start` で 1 度だけ呼ぶ想定。失敗は panic で即可視化。
    pub def load(): ConsumableCatalog \ Fs.FileRead =
        let container = CatalogContainer.loadWithCheck({
            dataPath       = AssetPath.resolve("resources/consumables.json"),
            schemaPath     = AssetPath.resolve("resources/consumables.schema.json"),
            containerKey   = "consumables",
            expectedFields = expectedFields(),
            decodeEntry    = ConsumableCatalogCodec.decodeConsumable
        });
        ConsumableCatalog.ConsumableCatalog(CatalogId.requireUniqueNames("Consumable", r -> r#name, container))

    /// `ConsumableResource` から catalog id を逆引きする（name 一致）。スナップショット保存で使う。
    /// name はカタログ内で一意（load 時に検査）。見つからなければ `None`。
    pub def idOf(item: ConsumableResource, catalog: ConsumableCatalog): Option[String] =
        let ConsumableCatalog.ConsumableCatalog(container) = catalog;
        CatalogId.idByName(r -> r#name, item#name, container)

    /// 消費アイテム id を引いて `ConsumableResource` を返す。
    /// 未定義 id は起動時の typo として panic し、定義漏れを即可視化する。
    pub def lookup(id: String, catalog: ConsumableCatalog): ConsumableResource =
        let ConsumableCatalog.ConsumableCatalog(container) = catalog;
        match CatalogContainer.get(id, container) {
            case Some(item) => item
            case None       => bug!("Consumable.lookup: consumable '${id}' not in catalog")
        }

    /// 敵が投げる消費アイテム（火炎瓶 / 爆発瓶 / ほころび薬）の ConsumableResource を即席で作る。
    /// 敵（ローグ_T3 / クレリック_T3 / レンジャー_T2,3）が持つ投擲物をコード側から組むのに使う。
    /// 投擲は `effect` / `magnitude` / `duration` / `name` で決まり sprite は使わないのでダミーで埋める。
    pub def bottle(effect: ConsumableEffect, magnitude: Int32, duration: Int32,
                    name: String): ConsumableResource =
        {name = name, effect = effect, magnitude = magnitude, duration = duration,
         healAmount = 0, durability = 1,
         sprite = ({texture = "item_icons", hframes = 16, vframes = 39, frame = 0,
                     offset = {x = 0.0, y = 0.0}, scale = {x = 1.0, y = 1.0},
                     flipForFacing = false}: SpriteResource),
         description = "", effectRule = None}

    /// `ConsumableResource` のフィールド名集合。
    /// Set で持つことで load 時に JSON フィールドの追加漏れ・typo を検出できる。
    pub def expectedFields(): Set[String] =
        Set#{"name", "effect", "magnitude", "duration",
             "healAmount", "durability", "sprite", "description", "effectRule"}

    // ────────────────────────────────────────────────────────
    // 蘇生（AutoRevive）の純粋判定
    //   HP0 になった味方が AutoRevive 効果の消費アイテムを所持していれば、
    //   その駒を「まだ死んでいない」扱いにして全回復させる。Scene 非依存に保ち、
    //   実際の HP 書き換え・HPBar 更新・ログは呼び出し側 (PlayerScene) が担う。
    // ────────────────────────────────────────────────────────

    /// `consumables` の中で最初に見つかった AutoRevive アイテムを 1 回消費した結果を返す。
    /// AutoRevive を持っていなければ `None`（蘇生不可）。持っていれば `Some(消費後リスト)`
    /// （耐久が尽きたらそのアイテムは取り除かれる）。リストの順序は保たれる。
    pub def reviveConsume(consumables: List[ConsumableResource]):
            Option[List[ConsumableResource]] =
        if (List.exists(item -> item#effect == ConsumableEffect.AutoRevive, consumables))
            Some(consumeFirstRevive(consumables))
        else None

    /// 最初の AutoRevive アイテムを 1 回だけ消費する（耐久 0 で除去）。それ以外は不変。
    /// 呼び出し側 (`reviveConsume`) が AutoRevive の存在を保証してから呼ぶ。
    /// `consume` の `Option`（耐久 0 なら None）は `Option.toList` で「残り 0/1 個」に畳み、
    /// ネストした match を避ける。
    def consumeFirstRevive(consumables: List[ConsumableResource]): List[ConsumableResource] =
        match consumables {
            case Nil          => Nil
            case item :: rest =>
                if (item#effect == ConsumableEffect.AutoRevive)
                    List.append(Option.toList(consume(item)), rest)
                else item :: consumeFirstRevive(rest)
        }

    /// HP0 になった味方 `units` のうち、AutoRevive 所持者を蘇生させる純粋判定。
    /// `revived` は蘇生した味方（消費後の `consumables` 付き。HP は呼び出し側が最大値へ戻す）、
    /// `stillDead` は蘇生できず本当に脱落する id。`removeDeadAndCheckGameOver` の手前で使う。
    pub def tryReviveAll(units: List[{id = Int32, consumables = List[ConsumableResource]}]):
            {revived = List[{id = Int32, consumables = List[ConsumableResource]}],
             stillDead = List[Int32]} =
        List.foldLeft((acc, u) -> match reviveConsume(u#consumables) {
            case Some(newConsumables) =>
                {revived = {id = u#id, consumables = newConsumables} :: acc#revived | acc}
            case None =>
                {stillDead = u#id :: acc#stillDead | acc}
        }, {revived = Nil, stillDead = Nil}, units)
}

// container の巡回・schema 検査は CatalogContainer に委譲し、ここは wrap のみ。
instance Saveable[Consumable.ConsumableCatalog] {
    pub def toJson(value: Consumable.ConsumableCatalog): Util.Json.Json =
        let Consumable.ConsumableCatalog.ConsumableCatalog(container) = value;
        CatalogContainer.encode(ConsumableCatalogCodec.encodeConsumable, container)

    pub def fromJson(element: Util.Json.Json): Option[Consumable.ConsumableCatalog] =
        CatalogContainer.decode("consumables", ConsumableCatalogCodec.decodeConsumable, element)
            |> Option.map(Consumable.ConsumableCatalog.ConsumableCatalog)
}

/// ConsumableResource 1 件分の encode / decode のみ。container 巡回は `CatalogContainer.encode/decode` に委譲する。
mod ConsumableCatalogCodec {

    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JNumber}
    use JsonCodec.{expectObject, expectString, expectInt, intToBd}
    use Consumable.ConsumableResource
    use Sprite.SpriteResource

    pub def encodeConsumable(item: ConsumableResource): Json =
        let base = Map#{
            "name"        => JString(item#name),
            "effect"      => JString(Consumable.effectToString(item#effect)),
            "magnitude"   => JNumber(intToBd(item#magnitude)),
            "duration"    => JNumber(intToBd(item#duration)),
            "healAmount"  => JNumber(intToBd(item#healAmount)),
            "durability"  => JNumber(intToBd(item#durability)),
            "sprite"      => encodeSprite(item#sprite),
            "description" => JString(item#description)
        };
        match item#effectRule {
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

    pub def decodeConsumable(element: Json): Option[ConsumableResource] =
        forM (
            obj      <- expectObject(element);
            nameJ    <- Map.get("name", obj);
            effJ     <- Map.get("effect", obj);
            durJ     <- Map.get("durability", obj);
            spriteJ  <- Map.get("sprite", obj);
            name     <- expectString(nameJ);
            effStr   <- expectString(effJ);
            effect   <- Result.toOption(Consumable.parseEffect(effStr));
            dur      <- expectInt(durJ);
            sprite   <- decodeSprite(spriteJ)
        ) yield {
            // healAmount (旧フィールド) は省略可。欠落時は 0。
            let heal = Map.get("healAmount", obj)
                        |> Option.flatMap(expectInt) |> Option.getWithDefault(0);
            // magnitude は省略可。欠落時は healAmount を流用 (旧きずぐすりデータの後方互換)。
            let mag = Map.get("magnitude", obj)
                        |> Option.flatMap(expectInt) |> Option.getWithDefault(heal);
            // duration (バフ・デバフの持続) は省略可。回復・最大HP・蘇生では未使用。欠落時 0。
            let dura = Map.get("duration", obj)
                        |> Option.flatMap(expectInt) |> Option.getWithDefault(0);
            // description (一言説明) は省略可。欠落時は空文字 (後方互換)。
            let desc = Map.get("description", obj)
                        |> Option.flatMap(expectString)
                        |> Option.getWithDefault("");
            // effectRule（IDE 合成エディタが書く効果ルール）はあれば生 Json のまま保持。
            let effectRule = Map.get("effectRule", obj);
            ({name = name, effect = effect, magnitude = mag, duration = dura,
               healAmount = heal, durability = dur,
               sprite = sprite, description = desc, effectRule = effectRule}: ConsumableResource)
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
