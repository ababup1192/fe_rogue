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
/// 効果適用の Scene 操作は呼び出し側 (`PlayerScene.applyConsumableUse`) が担う。
///
/// JSON 形状 (`resources/consumables.json`):
///   {
///     "consumables": {
///       "vulnerary": { "name": "きずぐすり", "healAmount": 10,
///                       "durability": 3, "sprite": {...} }
///     }
///   }
mod Consumable {

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber}
    use Sprite.SpriteResource

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// 消費アイテム 1 種類ぶんのデータ。
    /// `name` は表示用の和名（例: "きずぐすり"）。
    /// `healAmount` は使用時に使用者の HP を回復する量。
    /// `durability` は使用回数（使うたびに 1 減り、0 で無くなる）。
    /// `sprite` は ItemMenu のアイコンに使う見た目情報。
    pub type alias ConsumableResource = {
        name       = String,
        healAmount = Int32,
        durability = Int32,
        sprite     = SpriteResource
    }

    /// 消費アイテムカタログ全体。`CatalogContainer[ConsumableResource]` を wrap して
    /// `Saveable` を持たせる（Staff / Weapon と同じ形）。containerKey は `"consumables"` 固定。
    pub enum ConsumableCatalog {
        case ConsumableCatalog(CatalogContainer[ConsumableResource])
    }

    /// consumables 部 (id → ConsumableResource の Map) を取り出す。
    pub def consumablesOf(catalog: ConsumableCatalog): Map[String, ConsumableResource] =
        let ConsumableCatalog.ConsumableCatalog(container) = catalog;
        CatalogContainer.entriesOf(container)

    // ────────────────────────────────────────────────────────
    // (B) 純粋ロジック
    // ────────────────────────────────────────────────────────

    /// 消費アイテムを 1 回使用したあとの状態を返す（`Staff.consume` と同形）。
    /// 耐久度が 1 → 0 に遷移するなら `None`（使い切った）。
    /// それ以上残っていれば `Some(更新後 consumable)`。
    pub def consume(item: ConsumableResource): Option[ConsumableResource] =
        let newDurability = item#durability - 1;
        if (newDurability <= 0) None
        else Some({durability = newDurability | item})

    // ────────────────────────────────────────────────────────
    // (C) ロード・参照
    // ────────────────────────────────────────────────────────

    /// `resources/consumables.json` をロードし、`resources/consumables.schema.json` で整合検査する。
    /// 起動時の `Game.start` で 1 度だけ呼ぶ想定。失敗は panic で即可視化。
    pub def load(): ConsumableCatalog \ Fs.FileRead =
        let container = CatalogContainer.loadWithCheck({
            dataPath       = "resources/consumables.json",
            schemaPath     = "resources/consumables.schema.json",
            containerKey   = "consumables",
            expectedFields = expectedFields(),
            decodeEntry    = ConsumableCatalogCodec.decodeConsumable
        });
        ConsumableCatalog.ConsumableCatalog(container)

    /// 消費アイテム id を引いて `ConsumableResource` を返す。未定義 id は起動時 typo として panic。
    /// 各ユニットの `initialInventory` の consumable kind エントリから実体を解決する用途で使う。
    pub def lookup(id: String, catalog: ConsumableCatalog): ConsumableResource =
        let ConsumableCatalog.ConsumableCatalog(container) = catalog;
        match CatalogContainer.get(id, container) {
            case Some(item) => item
            case None       => bug!("Consumable.lookup: consumable '${id}' not in catalog")
        }

    /// `ConsumableResource` のフィールド名集合。`consumables.schema.json` との整合性検査に使う。
    pub def expectedFields(): Set[String] =
        Set#{"name", "healAmount", "durability", "sprite"}
}

// ════════════════════════════════════════════════════════════════════════
// Saveable[ConsumableCatalog] — consumables.json の round-trip 実装 (薄い wrap)
// ════════════════════════════════════════════════════════════════════════

instance Saveable[Consumable.ConsumableCatalog] {
    pub def toJson(value: Consumable.ConsumableCatalog): Json.JsonElement =
        let Consumable.ConsumableCatalog.ConsumableCatalog(container) = value;
        CatalogContainer.encode(ConsumableCatalogCodec.encodeConsumable, container)

    pub def fromJson(element: Json.JsonElement): Option[Consumable.ConsumableCatalog] =
        CatalogContainer.decode("consumables", ConsumableCatalogCodec.decodeConsumable, element)
            |> Option.map(Consumable.ConsumableCatalog.ConsumableCatalog)
}

/// ConsumableResource 1 件分の encode / decode のみ。container 巡回は `CatalogContainer.encode/decode` に委譲する。
mod ConsumableCatalogCodec {

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber}
    use JsonCodec.{expectObject, expectString, expectInt, intToBd}
    use Consumable.ConsumableResource
    use Sprite.SpriteResource

    // ── エンコード ──

    pub def encodeConsumable(item: ConsumableResource): JsonElement =
        JsonObject(Map#{
            "name"       => JsonString(item#name),
            "healAmount" => JsonNumber(intToBd(item#healAmount)),
            "durability" => JsonNumber(intToBd(item#durability)),
            "sprite"     => encodeSprite(item#sprite)
        })

    def encodeSprite(sprite: SpriteResource): JsonElement =
        JsonObject(Map#{
            "texture" => JsonString(sprite#texture),
            "hframes" => JsonNumber(intToBd(sprite#hframes)),
            "vframes" => JsonNumber(intToBd(sprite#vframes)),
            "frame"   => JsonNumber(intToBd(sprite#frame)),
            "offset"  => JsonCodec.encodeVec2(sprite#offset)
        })

    // ── デコード ──

    pub def decodeConsumable(element: JsonElement): Option[ConsumableResource] =
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
            let off = JsonCodec.decodeVec2OrDefault(Map.get("offset", obj), 0.0);
            let sc = JsonCodec.decodeVec2OrDefault(Map.get("scale", obj), 1.0);
            ({texture = tex, hframes = hf, vframes = vf, frame = fr,
              offset = off, scale = sc}: SpriteResource)
        }
}
