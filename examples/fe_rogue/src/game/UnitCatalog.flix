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
/// 各ユニットは `initialInventory` で初期持ち物（武器・杖の混在リスト）を持つ。
/// `players` / `enemies` プールはユニット id の配列で、ゲーム側がスポーン順を決める。
///
/// JSON 形状（units.json）:
///   {
///     "units": {
///       "knight": {
///         "moveTiles": 4, "hp": 14, ...,
///         "initialInventory": [{ "kind": "weapon", "id": "trainingSpear" }]
///       },
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
    /// 段階 9 のリファクタで `units` を `CatalogContainer[UnitResource]` に変更した。
    /// `weapons` は段階 6 で `WeaponCatalog.WeaponCatalog` (独立 catalog) に分離済み。
    /// `pools` は id 配列の参照で `"players"` / `"enemies"` は `units` を指す。encode/decode 時に
    /// units container の meta としても投影される。
    pub enum UnitCatalog {
        case UnitCatalog({
            units   = CatalogContainer[UnitResource],
            weapons = WeaponCatalog.WeaponCatalog,
            pools   = Map[String, List[String]]
        })
    }

    /// 持ち物アイテムの種別。`weapons.json` か `staves.json` のどちらの id を指すか判別する。
    /// JSON では小文字文字列 `"weapon"` / `"staff"` でシリアライズする。
    pub enum ItemKind with Eq, ToString {
        case Weapon
        case Staff
    }

    /// `initialInventory` の 1 エントリ。JSON は `{"kind": "weapon", "id": "trainingSpear"}` の形。
    /// 並び順は意味あり: weapon は最初のものが装備中、staff は配列順で持ち物に積まれる。
    pub type alias InventoryEntry = {
        kind = ItemKind,
        id   = String
    }

    /// ユニット 1 種別ぶんのデータ。
    /// `attack` は素の「力」(might)。物理武器装備時の与ダメは `attack + 武器の attack - 防御`。
    /// `magicAttack` は魔力。魔法武器装備時の与ダメは `magicAttack + 武器の attack - 魔防`。
    /// `magicDefense` は魔防。魔法攻撃を受けた際の防御に使う。
    /// `initialInventory` は spawn 時に持たせる武器・杖を kind 別に並べたリスト。
    /// 旧フィールド `initialWeapon` / `initialStaves` を統合した形。
    pub type alias UnitResource = {
        moveTiles        = Int32,
        hp               = Int32,
        attack           = Int32,
        defense          = Int32,
        magicAttack      = Int32,
        magicDefense     = Int32,
        speed            = Int32,
        sprite           = SpriteResource,
        initialInventory = List[InventoryEntry],
        // 兵種名 (例: "アーチャー" / "ナイト" / "メイジ")。UI 上で表示する用途。
        // 旧 JSON に値が無い場合は decoder が "" を埋める (後方互換)。
        description      = String,
        // 方向別アニメ用 SpriteFrames リソース (Godot AnimatedSprite2D 準拠)。
        // 設定されていれば PlayerScene / EnemyScene が AnimatedSprite2D で表示し、
        // `idle` / `walk_up` / `walk_down` / `walk_left` / `walk_right` アニメ名を
        // 移動方向に応じて再生する。設定されていなければ従来通り Sprite2D で
        // `sprite` フィールドの単一フレームを表示する。
        spriteFrames     = Option[SpriteFrames]
    }

    // 武器系の型 (WeaponType / WeaponRange / WeaponResource) は段階 6 で
    // `WeaponCatalog` mod に移動した。本 mod では後方互換のため type alias 経由で参照する。
    // 既存コード (`UnitCatalog.WeaponResource` 等の参照) はそのまま動く。

    /// 武器の属性。`WeaponCatalog.WeaponType` の alias (後方互換)。
    pub type alias WeaponType = WeaponCatalog.WeaponType

    /// 武器 1 種別ぶんのデータ。`WeaponCatalog.WeaponResource` の alias (後方互換)。
    pub type alias WeaponResource = WeaponCatalog.WeaponResource

    /// 攻撃可能な距離の範囲。`WeaponCatalog.WeaponRange` の alias (後方互換)。
    pub type alias WeaponRange = WeaponCatalog.WeaponRange

    /// `WeaponType` が物理武器か。`WeaponCatalog.isPhysical` への薄い委譲 (後方互換)。
    pub def isPhysical(weaponType: WeaponType): Bool =
        WeaponCatalog.isPhysical(weaponType)

    /// 静止スプライト情報 (Sprite2D 用)。`Sprite.SpriteResource` の alias (後方互換)。
    /// 実体は中立な `Sprite` mod に移動した (依存方向を Unit/Weapon/Staff → Sprite に揃える)。
    /// HUD / popup / 単一フレーム表示で使う。`UnitResource.sprite` の型として参照する。
    /// 方向別アニメは `UnitResource.spriteFrames` (engine の SpriteFrames) で別途持つ。
    pub type alias SpriteResource = Sprite.SpriteResource

    /// units 部 (id → UnitResource の Map) を取り出す。
    /// 段階 9 で内部は `CatalogContainer[UnitResource]` 保持に変わったため、
    /// `CatalogContainer.entriesOf` を経由する。
    pub def unitsOf(catalog: UnitCatalog): Map[String, UnitResource] =
        let UnitCatalog.UnitCatalog(payload) = catalog;
        CatalogContainer.entriesOf(payload#units)

    /// `CatalogContainer[UnitResource]` そのものを取り出す (新 API、IDE Resources タブ等で利用想定)。
    pub def unitsContainerOf(catalog: UnitCatalog): CatalogContainer[UnitResource] =
        let UnitCatalog.UnitCatalog(payload) = catalog;
        payload#units

    /// weapons 部 (id → WeaponResource の Map) を取り出す。
    /// 内部は `WeaponCatalog.WeaponCatalog` 保持に変わったため、`WeaponCatalog.weaponsOf` を経由する。
    pub def weaponsOf(catalog: UnitCatalog): Map[String, WeaponResource] =
        let UnitCatalog.UnitCatalog(payload) = catalog;
        WeaponCatalog.weaponsOf(payload#weapons)

    /// `WeaponCatalog.WeaponCatalog` そのものを取り出す (新 API)。
    pub def weaponCatalogOf(catalog: UnitCatalog): WeaponCatalog.WeaponCatalog =
        let UnitCatalog.UnitCatalog(payload) = catalog;
        payload#weapons

    /// pools 部を取り出す。
    pub def poolsOf(catalog: UnitCatalog): Map[String, List[String]] =
        let UnitCatalog.UnitCatalog(payload) = catalog;
        payload#pools

    // ────────────────────────────────────────────────────────
    // (B) ロード・参照
    // ────────────────────────────────────────────────────────

    /// `resources/units.json` をロードして UnitCatalog を組む。
    /// 段階 6 のリファクタで weapons は別 catalog (`WeaponCatalog`) に分離されたため、
    /// **事前に** `WeaponCatalog.load()` で得た `weaponCatalog` を渡す必要がある。
    /// 失敗は panic（即可視化）。起動時の Game.start で 1 度だけ呼ぶ想定。
    ///
    /// **注意**: `spriteFrames` は authoring 形式（`{frame: Int, duration: Float}`）で
    /// 書かれており、engine の `SpriteFrames`（px 矩形）に解決するにはテクスチャの実寸が要る。
    /// この関数は pure（`\ Fs.FileRead`）に保つため、UnitResource.spriteFrames は
    /// すべて None で返す。Game.start のように `GameEngine.Game` が使える文脈では
    /// 続けて `UnitCatalog.resolveSpriteFrames(unitsPath, catalog)` を呼んで埋め直す。
    pub def load(unitsPath: String, weaponCatalog: WeaponCatalog.WeaponCatalog):
            UnitCatalog \ Fs.FileRead =
        let unitsJson = readFile(unitsPath);
        let catalog = loadFromString(unitsJson, weaponCatalog);
        // 段階 9 のリファクタで schema 整合性検査を load 内部に内包させた
        // (他 catalog の `CatalogContainer.loadWithCheck` と同じ責務境界に揃える)。
        let schema = match Resource.loadSchemaDiagnostic("resources/units.schema.json") {
            case Ok(value) => value
            case Err(msg)  => bug!("UnitCatalog schema load failed: ${msg}")
        };
        match Resource.checkConsistency(expectedUnitFields(), schema) {
            case Ok(())    => catalog
            case Err(msg)  => bug!("UnitResource schema/type mismatch: ${msg}")
        }

    /// I/O から分離したデコード経路: JSON 文字列から `UnitCatalog` を組む。
    /// テスト・runtime 生成カタログ等で使う。weapons は `weaponCatalog` を直接組み込む。
    pub def loadFromString(unitsJson: String, weaponCatalog: WeaponCatalog.WeaponCatalog): UnitCatalog =
        let catalog = decodeUnitsJson(unitsJson);
        let UnitCatalog.UnitCatalog(payload) = catalog;
        UnitCatalog.UnitCatalog({weapons = weaponCatalog | payload})

    /// `units.json` を再読してその中の `spriteFrames` セクションを texture の実寸を用いて
    /// **格子インデックス → px 矩形** に解決し、`catalog` の各 UnitResource に埋め直す。
    /// `load` の後段で呼ぶ。`Game.start` のような `GameEngine.Game` effect が使える文脈用。
    /// テスト等で texture registry が空（または対象 texture 未登録）の場合、その unit の
    /// spriteFrames は None のまま残る（静止 Sprite2D にフォールバック）。
    pub def resolveSpriteFrames(unitsPath: String, catalog: UnitCatalog):
            UnitCatalog \ {Fs.FileRead, GameEngine.Game} =
        let unitsJson = readFile(unitsPath);
        let parsed = match Json.Parse.parse(unitsJson) {
            case None       => bug!("UnitCatalog units JSON re-parse failed during resolveSpriteFrames")
            case Some(json) => json
        };
        UnitCatalogCodec.resolveSpriteFrames(parsed, catalog)

    /// JSON 文字列から `UnitCatalog` を decode する内部ヘルパ。
    /// pure な経路で、spriteFrames は常に None になる。
    def decodeUnitsJson(content: String): UnitCatalog =
        match Json.Parse.parse(content) {
            case None       => bug!("UnitCatalog units JSON parse failed")
            case Some(json) =>
                let decoded: Option[UnitCatalog] = Saveable.fromJson(json);
                match decoded {
                    case None    => bug!("UnitCatalog units decode failed (schema mismatch?)")
                    case Some(c) => c
                }
        }

    /// 指定 path をテキストとして読み、エラーなら即 panic する。
    def readFile(path: String): String \ Fs.FileRead =
        let readResult = run {
            Fs.ReadFile.read(path)
        } with Fs.ReadFile.runWithFileRead;
        match readResult {
            case Err(e)      => bug!("UnitCatalog file read failed: ${path} :: ${e}")
            case Ok(content) => content
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
    /// 内部は `WeaponCatalog.lookup` への薄い委譲 (段階 6 のリファクタ後の後方互換 API)。
    pub def lookupWeapon(id: String, catalog: UnitCatalog): WeaponResource =
        WeaponCatalog.lookup(id, weaponCatalogOf(catalog))

    /// Z 戦略の整合性検査用に Flix 型のフィールド名集合を公開する。
    /// `UnitResource` のフィールド構造を変更したらここも更新すること。
    /// engine 側 `Resource.checkConsistency` がこの集合と `_schema.json` を照合する。
    pub def expectedUnitFields(): Set[String] =
        Set#{"moveTiles", "hp", "attack", "defense", "magicAttack", "magicDefense",
              "speed", "sprite", "initialInventory",
              "description", "spriteFrames"}

    /// `WeaponResource` のフィールド名集合。`WeaponCatalog.expectedFields` への委譲 (後方互換)。
    /// 段階 6 のリファクタで weapons schema 検査は `WeaponCatalog.load` 内部で行うので
    /// Game.start からの直接呼び出しは不要になる予定。
    pub def expectedWeaponFields(): Set[String] =
        WeaponCatalog.expectedFields()
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
    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber, JsonArray}
    use JsonCodec.{expectObject, expectString, expectInt, expectFloat, expectBool, floatToBd, intToBd}
    use UnitCatalog.{UnitCatalog, UnitResource, WeaponResource, SpriteResource}

    // ── エンコード ──

    /// units.json の round-trip 用エンコーダ。weapons は含めない (別ファイルで管理)。
    /// 例: { "units": {...}, "players": [...], "enemies": [...] }
    /// 段階 9 のリファクタで `units` 部の巡回は `CatalogContainer.encode` に委譲する形に変更。
    /// pools (players / enemies) は CatalogContainer の meta に投影してから encode する。
    pub def encode(c: UnitCatalog): JsonElement =
        let unitsContainer = UnitCatalog.unitsContainerOf(c);
        let poolsMeta = UnitCatalog.poolsOf(c)
            |> Map.foldLeftWithKey((acc, name, ids) ->
                Map.insert(name, JsonArray(List.map(JsonString, ids) |> List.toVector), acc),
                (Map.empty(): Map[String, JsonElement]));
        // CatalogContainer の meta を pools で差し替える (元の meta は今は空想定)
        let CatalogContainer.CatalogContainer(containerPayload) = unitsContainer;
        let enrichedContainer = CatalogContainer.CatalogContainer({meta = poolsMeta | containerPayload});
        CatalogContainer.encode(encodeUnit, enrichedContainer)

    def encodeUnit(u: UnitResource): JsonElement =
        let base = Map#{
            "moveTiles"        => JsonNumber(intToBd(u#moveTiles)),
            "hp"               => JsonNumber(intToBd(u#hp)),
            "attack"           => JsonNumber(intToBd(u#attack)),
            "defense"          => JsonNumber(intToBd(u#defense)),
            "magicAttack"      => JsonNumber(intToBd(u#magicAttack)),
            "magicDefense"     => JsonNumber(intToBd(u#magicDefense)),
            "speed"            => JsonNumber(intToBd(u#speed)),
            "sprite"           => encodeSprite(u#sprite),
            "initialInventory" => encodeInventory(u#initialInventory),
            "description"      => JsonString(u#description)
        };
        // spriteFrames は設定がある unit (= AnimatedSprite2D で描く unit) だけ書き出す。
        // grid 形式 ({frame: Int, duration: Float}) で書き出す。frame index は
        // sprite.hframes と regionRect サイズから逆算する。None 時はフィールドを省略。
        let withSf = match u#spriteFrames {
            case None     => base
            case Some(sf) => Map.insert("spriteFrames", encodeSpriteFrames(sf, u#sprite#hframes), base)
        };
        JsonObject(withSf)

    /// `initialInventory` を `[{"kind": "weapon"|"staff", "id": "..."}, ...]` JSON にする。
    def encodeInventory(inv: List[UnitCatalog.InventoryEntry]): JsonElement =
        JsonArray(List.map(encodeInventoryEntry, inv) |> List.toVector)

    def encodeInventoryEntry(e: UnitCatalog.InventoryEntry): JsonElement =
        JsonObject(Map#{
            "kind" => JsonString(itemKindToString(e#kind)),
            "id"   => JsonString(e#id)
        })

    def itemKindToString(k: UnitCatalog.ItemKind): String = match k {
        case UnitCatalog.ItemKind.Weapon => "weapon"
        case UnitCatalog.ItemKind.Staff  => "staff"
    }

    def encodeSprite(s: SpriteResource): JsonElement =
        JsonObject(Map#{
            "texture" => JsonString(s#texture),
            "hframes" => JsonNumber(intToBd(s#hframes)),
            "vframes" => JsonNumber(intToBd(s#vframes)),
            "frame"   => JsonNumber(intToBd(s#frame)),
            "offset"  => JsonCodec.encodeVec2(s#offset),
            "scale"   => JsonCodec.encodeVec2(s#scale)
        })

    /// SpriteFrames リソースを `{anim_name: {loop, speed, frames}}` 形式で書き出す。
    /// 各 frame は authoring 形式の `{frame: Int, duration: Float}`。frame index は
    /// `hframes` と regionRect の cellW/cellH から逆算する（in-memory は px 矩形だが
    /// JSON 側は格子 index で保存する設計のため）。
    def encodeSpriteFrames(sf: SpriteFrames, hframes: Int32): JsonElement =
        let names = SpriteFrames.animationNames(sf);
        let obj = List.foldLeft((acc, name) ->
            match SpriteFrames.getAnimation(name, sf) {
                case None    => acc
                case Some(a) => Map.insert(name, encodeSpriteAnimation(a, hframes), acc)
            }, (Map.empty(): Map[String, JsonElement]), names);
        JsonObject(obj)

    def encodeSpriteAnimation(a: SpriteFrames.Animation, hframes: Int32): JsonElement =
        JsonObject(Map#{
            "loop"   => Json.JsonElement.JsonBool(a#loop),
            "speed"  => JsonNumber(floatToBd(a#speed)),
            "frames" => JsonArray(
                List.map(f -> encodeSpriteFrame(f, hframes), a#frames) |> List.toVector)
        })

    /// `regionRect` の `pos / size` と `hframes` から frame index を逆算して書き出す。
    /// 全フレームは同じ cellW × cellH である前提（grid 形式の通常運用）。
    /// regionRect 未指定（= テクスチャ全体）の場合は frame=0 で書き出す（フォールバック）。
    def encodeSpriteFrame(f: SpriteFrames.Frame, hframes: Int32): JsonElement =
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
        JsonObject(Map#{
            "frame"    => JsonNumber(intToBd(frameIdx)),
            "duration" => JsonNumber(floatToBd(f#duration))
        })


    // floatToBd / intToBd は engine の JsonCodec mod に集約済み (上の use 経由で参照)。

    // ── デコード ──

    /// units.json をデコード。weapons は常に空 (`WeaponCatalog.empty()`) で返す (別ファイル管理)。
    /// 段階 9 のリファクタで units 部分の巡回は `CatalogContainer.decode` に委譲。
    /// pools (players / enemies 等の id 配列) は container の meta から再構築する。
    pub def decode(element: JsonElement): Option[UnitCatalog] =
        forM (
            container <- CatalogContainer.decode("units", decodeUnit, element);
            pools     <- decodePoolsFromMeta(CatalogContainer.metaOf(container))
        ) yield UnitCatalog.UnitCatalog({
            units   = container,
            weapons = WeaponCatalog.empty(),  // 実 weapons は UnitCatalog.loadFromString で後段で組み込む
            pools   = pools
        })

    /// container の meta (= units 以外の top-level フィールド) から
    /// JsonArray of JsonString のものを pool として抽出する。それ以外の meta フィールドは無視。
    def decodePoolsFromMeta(meta: Map[String, JsonElement]):
            Option[Map[String, List[String]]] =
        let init: Option[Map[String, List[String]]] = Some(Map.empty());
        Map.foldLeftWithKey((acc, key, value) ->
            Option.flatMap(soFar ->
                match value {
                    case JsonArray(_) =>
                        decodeStringList(value)
                            |> Option.map(ids -> Map.insert(key, ids, soFar))
                    case _ => Some(soFar)
                },
                acc),
            init, meta)

    def decodeUnit(element: JsonElement): Option[UnitResource] =
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
            // magicAttack / magicDefense は省略可能。欠落時は 0。
            // IDE のスライダーが 0 のときフィールドを省略するケース、および
            // 旧 units.json への後方互換のため。
            let mAtk = Map.get("magicAttack", obj)
                         |> Option.flatMap(expectInt)
                         |> Option.getWithDefault(0);
            let mDef = Map.get("magicDefense", obj)
                         |> Option.flatMap(expectInt)
                         |> Option.getWithDefault(0);
            // description (兵種名表示用) は省略可。後方互換のため欠落時は "" を埋める。
            let desc = Map.get("description", obj)
                            |> Option.flatMap(expectString)
                            |> Option.getWithDefault("");
            // spriteFrames は pure 経路では None。
            // 実体は `UnitCatalog.loadFromString` の effectful な後段パスで、
            // sprite.hframes/vframes と texture 実寸から格子→px に解決される。
            ({moveTiles = mt, hp = hp, attack = atk, defense = df,
              magicAttack = mAtk, magicDefense = mDef,
              speed = spd, sprite = sp, initialInventory = inv,
              description = desc,
              spriteFrames = None}: UnitResource)
        }

    /// `[{"kind": "weapon"|"staff", "id": "..."}, ...]` を decode する。
    /// 配列以外なら None（必須フィールドとして扱い、欠落は schema 不整合として panic させる）。
    def decodeInventory(element: JsonElement): Option[List[UnitCatalog.InventoryEntry]] =
        match element {
            case JsonArray(items) =>
                List.foldRight(item -> acc ->
                    Option.flatMap(soFar ->
                        decodeInventoryEntry(item) |> Option.map(e -> e :: soFar),
                        acc),
                    Some(Nil), Vector.toList(items))
            case _ => None
        }

    def decodeInventoryEntry(element: JsonElement): Option[UnitCatalog.InventoryEntry] =
        forM (
            obj    <- expectObject(element);
            kindJ  <- Map.get("kind", obj);
            idJ    <- Map.get("id", obj);
            kStr   <- expectString(kindJ);
            id     <- expectString(idJ);
            kind   <- parseItemKind(kStr)
        ) yield ({kind = kind, id = id}: UnitCatalog.InventoryEntry)

    def parseItemKind(s: String): Option[UnitCatalog.ItemKind] = match s {
        case "weapon" => Some(UnitCatalog.ItemKind.Weapon)
        case "staff"  => Some(UnitCatalog.ItemKind.Staff)
        case _        => None
    }

    // 武器系の decode (decodeWeapon / parseWeaponType / decodeRange) は段階 6 で
    // `WeaponCatalogCodec` mod へ移動した。UnitCatalogCodec は units.json の round-trip にのみ責任を持つ。

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
            let off = JsonCodec.decodeVec2OrDefault(Map.get("offset", obj), 0.0);
            // scale は省略可能。既定は等倍 {1, 1} (画像ピクセル原寸)。
            // 大きく見せたいユニットだけ units.json で scale を上書きする。
            let sc = JsonCodec.decodeVec2OrDefault(Map.get("scale", obj), 1.0);
            ({texture = tex, hframes = hf, vframes = vf, frame = fr,
              offset = off, scale = sc}: SpriteResource)
        }

    // ── spriteFrames の grid → px 解決（effectful 後段パス）──
    //
    // authoring 形式（units.json）：
    //   "spriteFrames": {
    //     "idle":      { "loop": true, "speed": 4.0, "frames": [{ "frame": 0, "duration": 1.0 }] },
    //     "walk_down": { ... }
    //   }
    // 各 frame の `frame` は sprite.hframes × sprite.vframes 分割の 0-origin row-major index。
    // texture は sprite.texture を共有する。`duration` は省略可（デフォルト 1.0）。
    //
    // runtime 表現（engine の `SpriteFrames.Frame`）には px 矩形が必要なので、
    // texture の実寸（`GameEngine.Game.getTextureInfo`）から cellW/cellH を計算して
    // 各 frame index を `regionRect = {pos, size}` に変換する。

    /// 解決時のコンテキスト。1 ユニットの sprite 設定 + 解決済み cell サイズ。
    type alias SpriteCtx = {
        texture = String,
        hframes = Int32,
        vframes = Int32,
        cellW   = Float64,
        cellH   = Float64
    }

    /// `units.json` の top JSON から、各ユニットの `spriteFrames` を引いて
    /// engine の `SpriteFrames` に解決し、`baseCatalog` の対応 `UnitResource` に
    /// 差し込む。`spriteFrames` フィールドが無いユニットは触らず（spriteFrames = None のまま）。
    /// texture 未登録 / hframes×vframes が無効 / JSON が崩れている場合はその unit の
    /// spriteFrames は None のままにする（panic させずに静止表示にフォールバック）。
    pub def resolveSpriteFrames(unitsJson: JsonElement, baseCatalog: UnitCatalog):
            UnitCatalog \ GameEngine.Game =
        match expectObject(unitsJson) {
            case None     => baseCatalog
            case Some(top) =>
                match Map.get("units", top) |> Option.flatMap(expectObject) {
                    case None         => baseCatalog
                    case Some(unitsM) =>
                        let UnitCatalog.UnitCatalog(payload) = baseCatalog;
                        let container = payload#units;
                        let CatalogContainer.CatalogContainer(containerPayload) = container;
                        let originalEntries = containerPayload#entries;
                        // 段階 9 のリファクタで units 部は CatalogContainer 経由になったため、
                        // entries (Map) を fold で resolve → 新しい container を再構築して差し戻す。
                        let resolvedEntries = Map.foldLeftWithKey((acc, id, unitJson) ->
                            resolveOneUnit(id, unitJson, acc),
                            originalEntries, unitsM);
                        let resolvedContainer = CatalogContainer.CatalogContainer({
                            entries = resolvedEntries | containerPayload
                        });
                        UnitCatalog.UnitCatalog({units = resolvedContainer | payload})
                }
        }

    /// 1 ユニットぶんの spriteFrames を解決して `units` Map に差し戻す。
    /// 該当 unit が catalog に居ない、spriteFrames フィールドが無い、texture 未登録、
    /// hframes/vframes が 0 以下のいずれかなら no-op（元の値を維持）。
    def resolveOneUnit(id: String, unitJson: JsonElement,
                        units: Map[String, UnitResource]):
            Map[String, UnitResource] \ GameEngine.Game =
        match (Map.get(id, units), expectObject(unitJson)) {
            case (Some(unitRes), Some(unitObj)) =>
                match Map.get("spriteFrames", unitObj) {
                    case None     => units
                    case Some(sf) =>
                        match buildSpriteCtx(unitRes#sprite) {
                            case None      => units
                            case Some(ctx) =>
                                match decodeSpriteFramesGrid(sf, ctx) {
                                    case None      => units
                                    case Some(sff) =>
                                        Map.insert(id, {spriteFrames = Some(sff) | unitRes}, units)
                                }
                        }
                }
            case _ => units
        }

    /// `SpriteCtx` を組み立てる。texture が登録されていない、または hframes/vframes が
    /// 0 以下なら None（呼び出し側で no-op フォールバック）。
    def buildSpriteCtx(sprite: SpriteResource): Option[SpriteCtx] \ GameEngine.Game =
        if (sprite#hframes <= 0 or sprite#vframes <= 0) None
        else match GameEngine.Game.getTextureInfo(sprite#texture) {
            case None       => None
            case Some(info) =>
                let cellW = info#width  / Int32.toFloat64(sprite#hframes);
                let cellH = info#height / Int32.toFloat64(sprite#vframes);
                Some(({texture = sprite#texture,
                        hframes = sprite#hframes,
                        vframes = sprite#vframes,
                        cellW = cellW,
                        cellH = cellH}: SpriteCtx))
        }

    /// `{anim_name: {loop, speed, frames: [{frame: Int, duration?: Float}]}}` の grid
    /// 形式 JSON を engine の `SpriteFrames` に解決する。
    /// frame index は ctx の hframes × vframes 分割に対する 0-origin row-major。
    def decodeSpriteFramesGrid(element: JsonElement, ctx: SpriteCtx): Option[SpriteFrames] =
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

    def decodeSpriteAnimationGrid(element: JsonElement, ctx: SpriteCtx):
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

    def decodeGridFrameList(element: JsonElement, ctx: SpriteCtx):
            Option[List[SpriteFrames.Frame]] =
        match element {
            case JsonArray(items) =>
                List.foldRight(item -> acc ->
                    Option.flatMap(soFar ->
                        decodeGridFrame(item, ctx) |> Option.map(f -> f :: soFar),
                        acc),
                    Some(Nil), Vector.toList(items))
            case _ => None
        }

    /// `{frame: Int, duration?: Float}` を engine の `SpriteFrames.Frame` に解決。
    /// frame index → (col, row) → px 矩形 を ctx の cellW/cellH から計算する。
    def decodeGridFrame(element: JsonElement, ctx: SpriteCtx): Option[SpriteFrames.Frame] =
        forM (
            obj      <- expectObject(element);
            frameJ   <- Map.get("frame", obj);
            frameIdx <- expectInt(frameJ)
        ) yield {
            let dur = Map.get("duration", obj)
                            |> Option.flatMap(expectFloat)
                            |> Option.getWithDefault(1.0);
            let col = Int32.remainder(frameIdx, ctx#hframes);
            let row = frameIdx / ctx#hframes;
            let rect = ({
                position = {x = Int32.toFloat64(col) * ctx#cellW,
                             y = Int32.toFloat64(row) * ctx#cellH},
                size = {x = ctx#cellW, y = ctx#cellH}
            }: Rect2.Rect2);
            ({texture = ctx#texture, regionRect = Some(rect), duration = dur}: SpriteFrames.Frame)
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

    // expectObject / expectString / expectInt / expectFloat / expectBool は
    // engine の JsonCodec mod に集約済み。本 mod では `use JsonCodec.{...}` 経由で参照する。
}
