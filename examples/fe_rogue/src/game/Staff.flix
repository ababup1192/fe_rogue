/// Staff — 杖の型・カタログ・純粋ロジック
///
/// 武器（`Weapon.flix` + `UnitCatalog` の `WeaponResource`）とは別系統の装備として
/// 「杖」を定義する。共通仕様:
///   - 縦横 4 方向のいずれかを指定して直線に飛ぶ
///   - 最初に当たった敵か味方に対して効果が発動する
///   - 耐久度を持ち、使用ごとに 1 ずつ減る。0 で壊れる
///   - 空振り（壁・射程外）でも耐久 -1
///
/// このモジュールは Scene[NodeTag] / effect に依存せず、テストが純粋値で完結する。
/// 効果適用の Scene 操作は呼び出し側 (`PlayerScene.applyStaffCast`) が担う。
///
/// JSON 形状 (`resources/staves.json`):
///   {
///     "staves": {
///       "live_staff":     { "name": "ライブのつえ",     "effect": "Heal",
///                            "durability": 8, "range": 6, "sprite": {...} },
///       "blowback_staff": { "name": "ふきとばしのつえ", "effect": "Blowback", ... },
///       "swap_staff":     { "name": "いれかえのつえ",   "effect": "Swap",     ... }
///     }
///   }
mod Staff {

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber}
    use Sprite.SpriteResource

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// 杖の効果の種類。
    ///   - `Heal`     : ライブのつえ。ヒット対象の HP を「魔力 + 10」回復する
    ///   - `Blowback` : ふきとばしのつえ。1 ダメージ + 対象を方向に押し流す
    ///   - `Swap`     : いれかえのつえ。ヒット対象（キャラのみ）と位置を交換する
    pub enum StaffEffect with Eq, ToString {
        case Heal
        case Blowback
        case Swap
    }

    /// 杖の発射方向。縦横 4 方向のみ。
    /// `toVec2i` でグリッド上の単位ベクトル `{x, y}` に変換できる。
    pub enum Direction with Eq, ToString {
        case Up
        case Down
        case Left
        case Right
    }

    /// 杖 1 種類ぶんのデータ。
    /// `name` は表示用の和名（例: "ライブのつえ"）。
    /// `effect` は効果の種類。
    /// `durability` は耐久度（攻撃するたびに 1 減り、0 で壊れる）。
    /// `sprite` は ItemMenu のアイコンに使う見た目情報。
    ///
    /// 射程の概念は持たない。杖は指定方向に「壁か別のキャラに当たるまで」直線に飛ぶ。
    /// 盤面外は壁扱いなので、`Board.rayCast` には実質無限の上限を渡して呼ぶ。
    pub type alias StaffResource = {
        name       = String,
        effect     = StaffEffect,
        durability = Int32,
        sprite     = SpriteResource
    }

    /// 杖カタログ全体。段階 7 のリファクタで `CatalogContainer[StaffResource]` を wrap して
    /// `Saveable` を持たせる形に変更した。containerKey は `"staves"` 固定。
    pub enum StaffCatalog {
        case StaffCatalog(CatalogContainer[StaffResource])
    }

    /// staves 部 (id → StaffResource の Map) を取り出す。
    pub def stavesOf(catalog: StaffCatalog): Map[String, StaffResource] =
        let StaffCatalog.StaffCatalog(container) = catalog;
        CatalogContainer.entriesOf(container)

    // ────────────────────────────────────────────────────────
    // (B) 純粋ロジック
    // ────────────────────────────────────────────────────────

    /// 杖を 1 回使用したあとの状態を返す（`Weapon.consume` と同形）。
    /// 耐久度が 1 → 0 に遷移するなら `None`（杖が壊れた）。
    /// それ以上残っていれば `Some(更新後 staff)`。
    pub def consume(staff: StaffResource): Option[StaffResource] =
        let newDurability = staff#durability - 1;
        if (newDurability <= 0) None
        else Some({durability = newDurability | staff})

    /// 方向をグリッド上の単位ベクトルに変換する。
    /// 画面座標系（y 軸下向き）に合わせて Up は y = -1、Down は y = +1。
    pub def toVec2i(direction: Direction): {x = Int32, y = Int32} = match direction {
        case Direction.Up    => {x =  0, y = -1}
        case Direction.Down  => {x =  0, y =  1}
        case Direction.Left  => {x = -1, y =  0}
        case Direction.Right => {x =  1, y =  0}
    }

    /// 文字列 → `StaffEffect` のパース。JSON の `"Heal"` / `"Blowback"` / `"Swap"` を
    /// enum に変換する。未知文字列は `Err(その文字列)` を返す。
    /// schema 側で enum を絞っているので通常は到達しないが、JSON 直編集での typo を
    /// 起動時に発覚させる用途で `Err` で表現する。
    pub def parseEffect(name: String): Result[String, StaffEffect] = match name {
        case "Heal"     => Ok(StaffEffect.Heal)
        case "Blowback" => Ok(StaffEffect.Blowback)
        case "Swap"     => Ok(StaffEffect.Swap)
        case other      => Err(other)
    }

    /// `StaffEffect` → 文字列。JSON シリアライズ用。`parseEffect` と round-trip する。
    pub def effectToString(effect: StaffEffect): String = match effect {
        case StaffEffect.Heal     => "Heal"
        case StaffEffect.Blowback => "Blowback"
        case StaffEffect.Swap     => "Swap"
    }

    // ────────────────────────────────────────────────────────
    // (C) ロード・参照
    // ────────────────────────────────────────────────────────

    /// `resources/staves.json` をロードし、`resources/staves.schema.json` で整合検査する。
    /// 起動時の `Game.start` で 1 度だけ呼ぶ想定。失敗は panic で即可視化。
    /// 段階 7 のリファクタで `CatalogContainer.loadWithCheck` に処理を委譲する形に変更した。
    pub def load(): StaffCatalog \ Fs.FileRead =
        let container = CatalogContainer.loadWithCheck({
            dataPath       = "resources/staves.json",
            schemaPath     = "resources/staves.schema.json",
            containerKey   = "staves",
            expectedFields = expectedFields(),
            decodeEntry    = StaffCatalogCodec.decodeStaff
        });
        StaffCatalog.StaffCatalog(container)

    /// 杖 id を引いて `StaffResource` を返す。未定義 id は起動時 typo として panic。
    /// 各ユニットの `initialInventory` の staff kind エントリから杖インスタンスを解決する用途で使う。
    /// `UnitCatalog.lookupWeapon` と同じ「起動時 typo は即発覚」方針。
    pub def lookup(id: String, catalog: StaffCatalog): StaffResource =
        let StaffCatalog.StaffCatalog(container) = catalog;
        match CatalogContainer.get(id, container) {
            case Some(staff) => staff
            case None        => bug!("Staff.lookup: staff '${id}' not in catalog")
        }

    /// `StaffResource` のフィールド名集合。`staves.schema.json` との整合性検査に使う。
    /// engine 側 `Resource.checkConsistency` がこの集合と schema を照合する。
    pub def expectedFields(): Set[String] =
        Set#{"name", "effect", "durability", "sprite"}
}

// ════════════════════════════════════════════════════════════════════════
// Saveable[StaffCatalog] — staves.json の round-trip 実装 (薄い wrap)
// ════════════════════════════════════════════════════════════════════════

instance Saveable[Staff.StaffCatalog] {
    pub def toJson(value: Staff.StaffCatalog): Json.JsonElement =
        let Staff.StaffCatalog.StaffCatalog(container) = value;
        CatalogContainer.encode(StaffCatalogCodec.encodeStaff, container)

    pub def fromJson(element: Json.JsonElement): Option[Staff.StaffCatalog] =
        CatalogContainer.decode("staves", StaffCatalogCodec.decodeStaff, element)
            |> Option.map(Staff.StaffCatalog.StaffCatalog)
}

/// StaffResource 1 件分の encode / decode のみ。container 巡回は `CatalogContainer.encode/decode` に委譲する。
mod StaffCatalogCodec {

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber}
    use JsonCodec.{expectObject, expectString, expectInt, expectFloat, floatToBd, intToBd}
    use Staff.{StaffResource, StaffEffect}
    use Sprite.SpriteResource

    // ── エンコード ──

    pub def encodeStaff(staff: StaffResource): JsonElement =
        JsonObject(Map#{
            "name"       => JsonString(staff#name),
            "effect"     => JsonString(Staff.effectToString(staff#effect)),
            "durability" => JsonNumber(intToBd(staff#durability)),
            "sprite"     => encodeSprite(staff#sprite)
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

    pub def decodeStaff(element: JsonElement): Option[StaffResource] =
        forM (
            obj      <- expectObject(element);
            nameJ    <- Map.get("name", obj);
            effJ     <- Map.get("effect", obj);
            durJ     <- Map.get("durability", obj);
            spriteJ  <- Map.get("sprite", obj);
            name     <- expectString(nameJ);
            effStr   <- expectString(effJ);
            effect   <- Result.toOption(Staff.parseEffect(effStr));
            dur      <- expectInt(durJ);
            sprite   <- decodeSprite(spriteJ)
        ) yield ({name = name, effect = effect, durability = dur,
                   sprite = sprite}: StaffResource)

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
            // scale は省略可能。staves UI アイコンは board に並べないので既定 {1, 1}。
            let sc = JsonCodec.decodeVec2OrDefault(Map.get("scale", obj), 1.0);
            let flip = Map.get("flipForFacing", obj)
                        |> Option.flatMap(JsonCodec.expectBool) |> Option.getWithDefault(false);
            ({texture = tex, hframes = hf, vframes = vf, frame = fr,
              offset = off, scale = sc, flipForFacing = flip}: SpriteResource)
        }

    // expect helpers / 数値変換は engine の JsonCodec mod に集約されている。
    // 本 mod では `use JsonCodec.{...}` 経由で参照する。
}
