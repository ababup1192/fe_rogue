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
/// 効果適用の Scene 操作は呼び出し側 (`StaffCastScene.applyStaffCast`) が担う。
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

    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JNumber}
    use Sprite.SpriteResource

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// 杖の効果の種類。
    ///   - `Heal`     : ライブのつえ。ヒット対象の HP を「魔力 + 10」回復する
    ///   - `Blowback` : ふきとばしのつえ。1 ダメージ + 対象を方向に押し流す
    ///   - `Swap`     : いれかえのつえ。ヒット対象（キャラのみ）と位置を交換する
    ///   - `Bind`     : かなしばりの杖。ヒット対象を完全停止（移動も攻撃も不可）にする。
    ///                  被攻撃 or 被投擲で解除（ターン経過では解けない）
    ///   - `Stopgap`  : 一時しのぎの杖。完全停止 + 対象を階段マス（埋まっていれば隣接の空き）へワープ
    pub enum StaffEffect with Eq, ToString {
        case Heal
        case Blowback
        case Swap
        case Bind
        case Stopgap
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
    /// `description` はアイテム詳細ウィンドウに出す一言説明（フレーバーテキスト）。
    ///
    /// 射程の概念は持たない。杖は指定方向に「壁か別のキャラに当たるまで」直線に飛ぶ。
    /// 盤面外は壁扱いなので、`Board.rayCast` には実質無限の上限を渡して呼ぶ。
    pub type alias StaffResource = {
        name        = String,
        effect      = StaffEffect,
        durability  = Int32,
        sprite      = SpriteResource,
        description = String,
        effectRule  = Option[Util.Json.Json]
    }

    /// 杖カタログ全体。`CatalogContainer[StaffResource]` を wrap して `Saveable` を持たせる。
    /// `containerKey` を `"staves"` 固定にすることで JSON ルートキーと型の対応を 1 か所に集約し、
    /// 将来的な containerKey の取り違えを型境界で防ぐ。
    pub enum StaffCatalog {
        case StaffCatalog(CatalogContainer[StaffResource])
    }

    /// `CatalogContainer` の内部 Map を外部に公開するアクセサ。
    /// カタログを走査するユーティリティ（一覧表示・統計等）はこの Map を使う。
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

    /// グリッドの差分ベクトルを 4 方位に丸める。主軸(絶対値が大きい方)を採用し、
    /// 整列している(片軸が 0)場合はその軸方向になる。
    pub def deltaToDirection(dx: Int32, dy: Int32): Direction =
        if (Int32.abs(dx) >= Int32.abs(dy))
            (if (dx < 0) Direction.Left else Direction.Right)
        else
            (if (dy < 0) Direction.Up else Direction.Down)

    /// 負傷味方の位置リストから杖を構える 4 方位を選ぶ。同じ行/列に整列している位置
    /// （射線が届く）を優先し、次にマンハッタン距離（縦横の移動マス合計）が近い位置を
    /// 選ぶ。候補が空なら None。`origin` は構える本人の位置、`targets` は候補位置の一覧。
    pub def pickHealDirection(origin: {x = Int32, y = Int32},
                               targets: List[{x = Int32, y = Int32}]): Option[Direction] =
        let scored = targets |> List.map(cell -> {
            let dx = cell#x - origin#x;
            let dy = cell#y - origin#y;
            (dx == 0 or dy == 0, Int32.abs(dx) + Int32.abs(dy), deltaToDirection(dx, dy))
        });
        let best = List.foldLeft((acc, cur) -> match acc {
            case None    => Some(cur)
            case Some(b) =>
                let (ba, bd, _) = b;
                let (ca, cd, _) = cur;
                if ((ca and not ba) or (ca == ba and cd < bd)) Some(cur) else acc
        }, None, scored);
        Option.map(t -> { let (_aligned, _dist, d) = t; d }, best)

    /// 文字列 → `StaffEffect` のパース。JSON の `"Heal"` / `"Blowback"` / `"Swap"` を
    /// enum に変換する。未知文字列は `Err(その文字列)` を返す。
    /// schema 側で enum を絞っているので通常は到達しないが、JSON 直編集での typo を
    /// 起動時に発覚させる用途で `Err` で表現する。
    pub def parseEffect(name: String): Result[String, StaffEffect] = match name {
        case "Heal"     => Ok(StaffEffect.Heal)
        case "Blowback" => Ok(StaffEffect.Blowback)
        case "Swap"     => Ok(StaffEffect.Swap)
        case "Bind"     => Ok(StaffEffect.Bind)
        case "Stopgap"  => Ok(StaffEffect.Stopgap)
        case other      => Err(other)
    }

    /// `parseEffect` と round-trip する文字列表現を返す。
    pub def effectToString(effect: StaffEffect): String = match effect {
        case StaffEffect.Heal     => "Heal"
        case StaffEffect.Blowback => "Blowback"
        case StaffEffect.Swap     => "Swap"
        case StaffEffect.Bind     => "Bind"
        case StaffEffect.Stopgap  => "Stopgap"
    }

    // ────────────────────────────────────────────────────────
    // (C) ロード・参照
    // ────────────────────────────────────────────────────────

    /// `resources/staves.json` をロードし、`resources/staves.schema.json` で整合検査する。
    /// 起動時の `Game.start` で 1 度だけ呼ぶ想定。失敗は panic で即可視化し、
    /// 不正な JSON や schema 不一致をゲーム起動直後に発覚させる。
    pub def load(): StaffCatalog \ Fs.FileRead =
        let container = CatalogContainer.loadWithCheck({
            dataPath       = AssetPath.resolve("resources/staves.json"),
            schemaPath     = AssetPath.resolve("resources/staves.schema.json"),
            containerKey   = "staves",
            expectedFields = expectedFields(),
            decodeEntry    = StaffCatalogCodec.decodeStaff
        });
        StaffCatalog.StaffCatalog(CatalogId.requireUniqueNames("Staff", r -> r#name, container))

    /// `StaffResource` から catalog id を逆引きする（name 一致）。スナップショット保存で使う。
    /// name はカタログ内で一意（load 時に検査）。見つからなければ `None`。
    pub def idOf(staff: StaffResource, catalog: StaffCatalog): Option[String] =
        let StaffCatalog.StaffCatalog(container) = catalog;
        CatalogId.idByName(r -> r#name, staff#name, container)

    /// 杖 id を引いて `StaffResource` を返す。未定義 id は起動時 typo として panic。
    /// 各ユニットの `initialInventory` の staff kind エントリから杖インスタンスを解決する用途で使う。
    /// `UnitCatalog.lookupWeapon` と同じ「起動時 typo は即発覚」方針。
    pub def lookup(id: String, catalog: StaffCatalog): StaffResource =
        let StaffCatalog.StaffCatalog(container) = catalog;
        match CatalogContainer.get(id, container) {
            case Some(staff) => staff
            case None        => bug!("Staff.lookup: staff '${id}' not in catalog")
        }

    /// `StaffResource` が持つべきフィールド名の集合。
    /// schema との照合で「型定義と JSON schema の乖離」を起動時に発覚させる不変条件として機能する。
    // 実際の照合は engine の Resource.checkConsistency が担う。
    pub def expectedFields(): Set[String] =
        Set#{"name", "effect", "durability", "sprite", "description", "effectRule"}
}

// ════════════════════════════════════════════════════════════════════════
// Saveable[StaffCatalog] — staves.json の round-trip 実装 (薄い wrap)
// ════════════════════════════════════════════════════════════════════════

instance Saveable[Staff.StaffCatalog] {
    pub def toJson(value: Staff.StaffCatalog): Util.Json.Json =
        let Staff.StaffCatalog.StaffCatalog(container) = value;
        CatalogContainer.encode(StaffCatalogCodec.encodeStaff, container)

    pub def fromJson(element: Util.Json.Json): Option[Staff.StaffCatalog] =
        CatalogContainer.decode("staves", StaffCatalogCodec.decodeStaff, element)
            |> Option.map(Staff.StaffCatalog.StaffCatalog)
}

/// StaffResource 1 件分の encode / decode のみ。container 巡回は `CatalogContainer.encode/decode` に委譲する。
mod StaffCatalogCodec {

    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JNumber}
    use JsonCodec.{expectObject, expectString, expectInt, expectFloat, floatToBd, intToBd}
    use Staff.{StaffResource, StaffEffect}
    use Sprite.SpriteResource

    pub def encodeStaff(staff: StaffResource): Json =
        let base = Map#{
            "name"        => JString(staff#name),
            "effect"      => JString(Staff.effectToString(staff#effect)),
            "durability"  => JNumber(intToBd(staff#durability)),
            "sprite"      => encodeSprite(staff#sprite),
            "description" => JString(staff#description)
        };
        match staff#effectRule {
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

    pub def decodeStaff(element: Json): Option[StaffResource] =
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
        ) yield {
            // description (一言説明) は省略可。欠落時は空文字 (後方互換)。
            let desc = Map.get("description", obj)
                        |> Option.flatMap(expectString)
                        |> Option.getWithDefault("");
            ({name = name, effect = effect, durability = dur,
               sprite = sprite, description = desc,
               effectRule = Map.get("effectRule", obj)}: StaffResource)
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
            // scale は省略可能。staves UI アイコンは board に並べないので既定 {1, 1}。
            let sc = JsonCodec.decodeVec2OrDefault(Map.get("scale", obj), 1.0);
            let flip = Map.get("flipForFacing", obj)
                        |> Option.flatMap(JsonCodec.expectBool) |> Option.getWithDefault(false);
            ({texture = tex, hframes = hf, vframes = vf, frame = fr,
              offset = off, scale = sc, flipForFacing = flip}: SpriteResource)
        }

    // expect helpers / 数値変換は engine の JsonCodec mod に集約されている。
    // 本 mod で再実装せず `use JsonCodec.{...}` 経由で参照するのは、
    // 変換ロジックの一元管理と将来の変更影響範囲を engine 側に限定するため。
}
