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

    /// 消費アイテム 1 種類ぶんのデータ。
    /// `healAmount` は正の整数のみ有効（0 以下は `consume` で即 None になり実質壊れた定義になる）。
    /// `durability` は JSON から読み込んだ初期値が必ず正であることを前提とする。
    ///   `consume` が durability ≤ 0 で None を返すため、JSON に 0 以下が入ると 1 度も使えない。
    /// `sprite` は ItemMenu のアイコンに使う。
    pub type alias ConsumableResource = {
        name       = String,
        healAmount = Int32,
        durability = Int32,
        sprite     = SpriteResource
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
        ConsumableCatalog.ConsumableCatalog(container)

    /// 消費アイテム id を引いて `ConsumableResource` を返す。
    /// 未定義 id は起動時の typo として panic し、定義漏れを即可視化する。
    pub def lookup(id: String, catalog: ConsumableCatalog): ConsumableResource =
        let ConsumableCatalog.ConsumableCatalog(container) = catalog;
        match CatalogContainer.get(id, container) {
            case Some(item) => item
            case None       => bug!("Consumable.lookup: consumable '${id}' not in catalog")
        }

    /// `ConsumableResource` のフィールド名集合。
    /// Set で持つことで load 時に JSON フィールドの追加漏れ・typo を検出できる。
    pub def expectedFields(): Set[String] =
        Set#{"name", "healAmount", "durability", "sprite"}
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
        JObject(Map#{
            "name"       => JString(item#name),
            "healAmount" => JNumber(intToBd(item#healAmount)),
            "durability" => JNumber(intToBd(item#durability)),
            "sprite"     => encodeSprite(item#sprite)
        })

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
            healJ    <- Map.get("healAmount", obj);
            durJ     <- Map.get("durability", obj);
            spriteJ  <- Map.get("sprite", obj);
            name     <- expectString(nameJ);
            heal     <- expectInt(healJ);
            dur      <- expectInt(durJ);
            sprite   <- decodeSprite(spriteJ)
        ) yield ({name = name, healAmount = heal, durability = dur,
                   sprite = sprite}: ConsumableResource)

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
