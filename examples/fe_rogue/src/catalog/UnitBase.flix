/// UnitBase — 味方ユニット（UnitCatalog）と敵ユニット（EnemyCatalog）で共有する土台。
///
/// 共有する戦闘ステータス・スプライト・持ち物の型と、その JSON codec をここに集約する。
/// 味方専用（`growthRates`）は `UnitCatalog`、敵専用（将来の特殊能力）は `EnemyCatalog` に置く。
/// 依存方向は一方向: `UnitCatalog → UnitBase ← EnemyCatalog`（UnitBase は両者を知らない）。
///
/// effect には依存しない純粋データ型（spriteFrames の格子→px 解決のみ `GameEngine.Game` を使う）。
mod UnitBase {

    use SpriteRes.SpriteResource


    /// 持ち物アイテムの種別。`weapons.json` / `staves.json` / `consumables.json` の
    /// どの id を指すか判別する。
    /// JSON では小文字文字列 `"weapon"` / `"staff"` / `"consumable"` でシリアライズする。
    pub enum ItemKind with Eq, ToString {
        case Weapon
        case Staff
        case Consumable
    }

    /// `initialInventory` の 1 エントリ。JSON は `{"kind": "weapon", "id": "iron_lance"}` の形。
    /// 並び順は意味あり: weapon は最初のものが装備中、staff は配列順で持ち物に積まれる。
    pub type alias InventoryEntry = {
        kind = ItemKind,
        id   = String
    }

    /// 味方・敵で共通の戦闘ステータス一式。味方は別途 `growthRates` を、
    /// 敵は将来別途「特殊能力」を足す。`attack` は素の「力」、`magicAttack` は魔力。
    /// `level` は JSON に記録された基準レベル（味方の現在レベルは PlayerScene が動的に管理し、
    /// 敵はこの値がそのまま戦闘相手の Lv として使われる）。
    pub type alias UnitBase = {
        moveTiles        = Int32,
        level            = Int32,
        hp               = Int32,
        attack           = Int32,
        defense          = Int32,
        magicAttack      = Int32,
        magicDefense     = Int32,
        speed            = Int32,
        skill            = Int32,
        luck             = Int32,
        sprite           = SpriteResource,
        initialInventory = List[InventoryEntry],
        description      = String,
        spriteFrames     = Option[SpriteFrames]
    }
}

mod UnitBaseCodec {
    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JNumber, JArray, JBool}
    use JsonCodec.{expectObject, expectString, expectInt, expectFloat, expectBool, floatToBd, intToBd}
    use UnitBase.{UnitBase, ItemKind, InventoryEntry}
    use SpriteRes.SpriteResource

    /// 共有戦闘ステータスを JSON オブジェクトの Map に書き出す。呼び出し側が
    /// `growthRates`（味方）や将来の特殊能力（敵）を追加できるよう Map を返す。
    /// `spriteFrames` は設定がある unit だけ格子形式で書き出す。
    /// row-polymorphic にして PlayerResource / EnemyResource どちらも受ける。
    pub def encodeBase(u: {moveTiles = Int32, level = Int32, hp = Int32, attack = Int32,
                            defense = Int32, magicAttack = Int32, magicDefense = Int32,
                            speed = Int32, skill = Int32, luck = Int32, sprite = SpriteResource,
                            initialInventory = List[InventoryEntry], description = String,
                            spriteFrames = Option[SpriteFrames] | r}):
            Map[String, Json] =
        let base = Map#{
            "moveTiles"        => JNumber(intToBd(u#moveTiles)),
            "level"            => JNumber(intToBd(u#level)),
            "hp"               => JNumber(intToBd(u#hp)),
            "attack"           => JNumber(intToBd(u#attack)),
            "defense"          => JNumber(intToBd(u#defense)),
            "magicAttack"      => JNumber(intToBd(u#magicAttack)),
            "magicDefense"     => JNumber(intToBd(u#magicDefense)),
            "speed"            => JNumber(intToBd(u#speed)),
            "skill"            => JNumber(intToBd(u#skill)),
            "luck"             => JNumber(intToBd(u#luck)),
            "sprite"           => encodeSprite(u#sprite),
            "initialInventory" => encodeInventory(u#initialInventory),
            "description"      => JString(u#description)
        };
        match u#spriteFrames {
            case None     => base
            case Some(sf) => Map.insert("spriteFrames", encodeSpriteFrames(sf, u#sprite#hframes), base)
        }

    /// `initialInventory` を JSON 配列にシリアライズする。
    /// pub なのは `UnitCatalog` / `EnemyCatalog` の encode 側が直接呼ぶため。
    /// 戻り値は常に `JArray`（空リストでも `JArray([])`）— decode 側が `JArray` 以外を None とする契約に対応。
    pub def encodeInventory(inv: List[InventoryEntry]): Json =
        JArray(List.map(encodeInventoryEntry, inv) |> List.toVector)

    def encodeInventoryEntry(e: InventoryEntry): Json =
        JObject(Map#{
            "kind" => JString(itemKindToString(e#kind)),
            "id"   => JString(e#id)
        })

    def itemKindToString(k: ItemKind): String = match k {
        case ItemKind.Weapon     => "weapon"
        case ItemKind.Staff      => "staff"
        case ItemKind.Consumable => "consumable"
    }

    /// `SpriteResource` を JSON オブジェクトに encode する。`decodeSprite` と 1-to-1 対応。
    /// `flipForFacing` は「向きに応じてスプライトを左右反転するフラグ」を JSON キーとして保持する。
    pub def encodeSprite(s: SpriteResource): Json =
        JObject(Map#{
            "texture" => JString(s#texture),
            "hframes" => JNumber(intToBd(s#hframes)),
            "vframes" => JNumber(intToBd(s#vframes)),
            "frame"   => JNumber(intToBd(s#frame)),
            "offset"  => JsonCodec.encodeVec2(s#offset),
            "scale"   => JsonCodec.encodeVec2(s#scale),
            "flipForFacing" => JBool(s#flipForFacing)
        })

    /// SpriteFrames を `{anim_name: {loop, speed, frames}}` 形式で書き出す。
    /// 各 frame は格子 index（hframes と regionRect から逆算）+ duration。
    def encodeSpriteFrames(sf: SpriteFrames, hframes: Int32): Json =
        let names = SpriteFrames.animationNames(sf);
        let obj = List.foldLeft((acc, name) ->
            match SpriteFrames.getAnimation(name, sf) {
                case None    => acc
                case Some(a) => Map.insert(name, encodeSpriteAnimation(a, hframes), acc)
            }, (Map.empty(): Map[String, Json]), names);
        JObject(obj)

    def encodeSpriteAnimation(a: SpriteFrames.Animation, hframes: Int32): Json =
        JObject(Map#{
            "loop"   => Util.Json.Json.JBool(a#loop),
            "speed"  => JNumber(floatToBd(a#speed)),
            "frames" => JArray(
                List.map(f -> encodeSpriteFrame(f, hframes), a#frames) |> List.toVector)
        })

    def encodeSpriteFrame(f: SpriteFrames.Frame, hframes: Int32): Json =
        let frameIdx = match f#regionRect {
            case None       => 0
            case Some(rect) =>
                let cellW = rect#size#x;
                let cellH = rect#size#y;
                let col = if (cellW > 0.0) Float64.floor(rect#position#x / cellW) |> Float64.tryToInt32
                                              |> Option.getWithDefault(0)
                            else 0;
                let row = if (cellH > 0.0) Float64.floor(rect#position#y / cellH) |> Float64.tryToInt32
                                              |> Option.getWithDefault(0)
                            else 0;
                col + row * hframes
        };
        JObject(Map#{
            "frame"    => JNumber(intToBd(frameIdx)),
            "duration" => JNumber(floatToBd(f#duration))
        })

    /// 共有戦闘ステータスを decode して `UnitBase` を返す。`spriteFrames` は pure 経路では
    /// 常に None（実体は `resolveEntriesSpriteFrames` の effectful 後段で埋める）。
    /// 味方は別途 `growthRates` を、敵は別途特殊能力を足す。
    pub def decodeBase(element: Json): Option[UnitBase] =
        forM (
            obj    <- expectObject(element);
            mtJ    <- Map.get("moveTiles", obj);
            hpJ    <- Map.get("hp", obj);
            atkJ   <- Map.get("attack", obj);
            defJ   <- Map.get("defense", obj);
            spdJ   <- Map.get("speed", obj);
            spJ    <- Map.get("sprite", obj);
            invJ   <- Map.get("initialInventory", obj);
            mt     <- expectInt(mtJ);
            hp     <- expectInt(hpJ);
            atk    <- expectInt(atkJ);
            df     <- expectInt(defJ);
            spd    <- expectInt(spdJ);
            sp     <- decodeSprite(spJ);
            inv    <- decodeInventory(invJ)
        ) yield {
            // magicAttack / magicDefense / skill / luck / description / level は省略可（後方互換）。
            let optInt = (key, default) -> Map.get(key, obj) |> Option.flatMap(expectInt)
                                                |> Option.getWithDefault(default);
            let mAtk = optInt("magicAttack", 0);
            let mDef = optInt("magicDefense", 0);
            let skl  = optInt("skill", 0);
            let lck  = optInt("luck", 0);
            let lvl  = optInt("level", 1);
            let desc = Map.get("description", obj) |> Option.flatMap(expectString)
                            |> Option.getWithDefault("");
            ({moveTiles = mt, level = lvl, hp = hp, attack = atk, defense = df,
              magicAttack = mAtk, magicDefense = mDef,
              speed = spd, skill = skl, luck = lck,
              sprite = sp, initialInventory = inv,
              description = desc,
              spriteFrames = None}: UnitBase)
        }

    /// インベントリ配列を decode する。配列以外（オブジェクト・プリミティブ等の schema 不整合）は None を返す。
    /// 配列内にデコード不能なエントリが 1 件でもあれば全体を None とする（部分成功なし）。
    pub def decodeInventory(element: Json): Option[List[InventoryEntry]] =
        match element {
            case JArray(items) =>
                List.foldRight(item -> acc ->
                    Option.flatMap(soFar ->
                        decodeInventoryEntry(item) |> Option.map(e -> e :: soFar),
                        acc),
                    Some(Nil), Vector.toList(items))
            case _ => None
        }

    def decodeInventoryEntry(element: Json): Option[InventoryEntry] =
        forM (
            obj    <- expectObject(element);
            kindJ  <- Map.get("kind", obj);
            idJ    <- Map.get("id", obj);
            kStr   <- expectString(kindJ);
            id     <- expectString(idJ);
            kind   <- parseItemKind(kStr)
        ) yield ({kind = kind, id = id}: InventoryEntry)

    def parseItemKind(s: String): Option[ItemKind] = match s {
        case "weapon"     => Some(ItemKind.Weapon)
        case "staff"      => Some(ItemKind.Staff)
        case "consumable" => Some(ItemKind.Consumable)
        case _            => None
    }

    pub def decodeSprite(element: Json): Option[SpriteResource] =
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
            let sc  = JsonCodec.decodeVec2OrDefault(Map.get("scale", obj), 1.0);
            // flipForFacing は省略可能。欠落 / 不正は false。
            let flip = Map.get("flipForFacing", obj)
                        |> Option.flatMap(expectBool) |> Option.getWithDefault(false);
            ({texture = tex, hframes = hf, vframes = vf, frame = fr,
              offset = off, scale = sc, flipForFacing = flip}: SpriteResource)
        }

    // ── spriteFrames の格子 → px 解決（effectful 後段パス。味方・敵で共有）──

    /// 格子→px 解決の中間パス用コンテキスト。
    /// `getTextureInfo`（effectful）を 1 回だけ呼んで実寸を取得し、cellW/cellH を確定させる。
    /// 以後の各フレーム decode はこの値を使い回すことで effect 呼び出しを 1 ユニット 1 回に抑える。
    type alias SpriteCtx = {
        texture = String,
        hframes = Int32,
        vframes = Int32,
        cellW   = Float64,
        cellH   = Float64
    }

    /// データ JSON（units.json / enemies.json の top）から `containerKey`（"units"/"enemies"）配下の
    /// 各エントリの `spriteFrames` を texture 実寸で格子→px 解決し、`entries` の対応リソースに差し込む。
    /// row-polymorphic で sprite/spriteFrames を持つ任意のリソース Map に使える。
    /// texture 未登録 / hframes×vframes 無効 / JSON 不整合のエントリは None のまま（静止フォールバック）。
    pub def resolveEntriesSpriteFrames(dataJson: Json, containerKey: String,
                                        entries: Map[String, {sprite = SpriteResource,
                                                               spriteFrames = Option[SpriteFrames] | r}]):
            Map[String, {sprite = SpriteResource, spriteFrames = Option[SpriteFrames] | r}] \ GameEngine.Game =
        match expectObject(dataJson) {
            case None     => entries
            case Some(top) =>
                match Map.get(containerKey, top) |> Option.flatMap(expectObject) {
                    case None        => entries
                    case Some(unitsM) =>
                        Map.foldLeftWithKey((acc, id, unitJson) ->
                            resolveOne(id, unitJson, acc), entries, unitsM)
                }
        }

    /// 1 エントリの `spriteFrames` を解決して `entries` を更新する。
    /// id 未登録 / JSON 不整合 / texture 取得失敗 / grid decode 失敗のいずれかで詰まった場合は
    /// 部分更新せず `entries` をそのまま返す（all-or-nothing 方針 — decodeInventory と同様）。
    def resolveOne(id: String, unitJson: Json,
                    entries: Map[String, {sprite = SpriteResource,
                                          spriteFrames = Option[SpriteFrames] | r}]):
            Map[String, {sprite = SpriteResource, spriteFrames = Option[SpriteFrames] | r}] \ GameEngine.Game =
        // 「res 取得 → unit JSON → spriteFrames キー → ctx 構築 → grid デコード」の
        // どれか 1 つでも欠けたら entries をそのまま返す。4 段の match ネストを forM 1 本に畳む。
        let updated = forM (
            res     <- Map.get(id, entries);
            unitObj <- expectObject(unitJson);
            sf      <- Map.get("spriteFrames", unitObj);
            ctx     <- buildSpriteCtx(res#sprite);
            sff     <- decodeSpriteFramesGrid(sf, ctx)
        ) yield Map.insert(id, {spriteFrames = Some(sff) | res}, entries);
        Option.getWithDefault(entries, updated)

    def buildSpriteCtx(sprite: SpriteResource): Option[SpriteCtx] \ GameEngine.Game =
        if (sprite#hframes <= 0 or sprite#vframes <= 0) None
        else match GameEngine.Game.getTextureInfo(sprite#texture) {
            case None       => None
            case Some(info) =>
                let cellW = info#width  / Int32.toFloat64(sprite#hframes);
                let cellH = info#height / Int32.toFloat64(sprite#vframes);
                Some(({texture = sprite#texture, hframes = sprite#hframes,
                        vframes = sprite#vframes, cellW = cellW, cellH = cellH}: SpriteCtx))
        }

    def decodeSpriteFramesGrid(element: Json, ctx: SpriteCtx): Option[SpriteFrames] =
        match expectObject(element) {
            case None      => None
            case Some(obj) =>
                Map.foldLeftWithKey((acc, name, animJson) ->
                    Option.flatMap(soFar ->
                        decodeSpriteAnimationGrid(animJson, ctx) |> Option.map(anim ->
                            SpriteFrames.addAnimation(name, anim, soFar)),
                        acc),
                    Some(SpriteFrames.empty()), obj)
        }

    def decodeSpriteAnimationGrid(element: Json, ctx: SpriteCtx):
            Option[SpriteFrames.Animation] =
        forM (
            obj      <- expectObject(element);
            loopJ    <- Map.get("loop", obj);
            speedJ   <- Map.get("speed", obj);
            framesJ  <- Map.get("frames", obj);
            lp       <- expectBool(loopJ);
            spd      <- expectFloat(speedJ);
            frames   <- decodeGridFrameList(framesJ, ctx)
        ) yield ({loop = lp, speed = spd, frames = frames}: SpriteFrames.Animation)

    def decodeGridFrameList(element: Json, ctx: SpriteCtx):
            Option[List[SpriteFrames.Frame]] =
        match element {
            case JArray(items) =>
                List.foldRight(item -> acc ->
                    Option.flatMap(soFar ->
                        decodeGridFrame(item, ctx) |> Option.map(f -> f :: soFar),
                        acc),
                    Some(Nil), Vector.toList(items))
            case _ => None
        }

    def decodeGridFrame(element: Json, ctx: SpriteCtx): Option[SpriteFrames.Frame] =
        forM (
            obj      <- expectObject(element);
            frameJ   <- Map.get("frame", obj);
            frameIdx <- expectInt(frameJ)
        ) yield {
            let dur = Map.get("duration", obj) |> Option.flatMap(expectFloat)
                            |> Option.getWithDefault(1.0);
            // encode 側の `col + row * hframes` の逆算: col = frameIdx % hframes, row = frameIdx / hframes。
            let col = Int32.remainder(frameIdx, ctx#hframes);
            let row = frameIdx / ctx#hframes;
            let rect = ({
                position = {x = Int32.toFloat64(col) * ctx#cellW,
                             y = Int32.toFloat64(row) * ctx#cellH},
                size = {x = ctx#cellW, y = ctx#cellH}
            }: Rect2.Rect2);
            ({texture = ctx#texture, regionRect = Some(rect), duration = dur}: SpriteFrames.Frame)
        }
}
