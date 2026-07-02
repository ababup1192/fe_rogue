/// ChestCatalog — 宝箱の種別カタログ（中身の重み付きプールを持つ）
///
/// 宝箱 1 種ごとに「表示スプライト」と「開けたとき何が出るか」の重み付きプール(`contents`)を定義する。
/// `contents` は `FloorCatalog.SpawnEntry` ({id, percent}) のリストで、id は既存の
/// weapons / staves / consumables カタログを指す（解決は `GroundItems.lookupItem` がフォールスルーで行う）。
/// レア武器を高 percent、きずぐすり等のハズレを低 percent にするといった調整を JSON だけで行える。
///
/// 中身の抽選は `FloorCatalog.pickWeighted(contents)` を再利用する。実際にどの中身が出るかは
/// 宝箱を「配置する時点」(`Chests.add`) で確定させ、開錠時には Math.Random を要さない設計にしている。
///
/// JSON 形状 (`resources/chests.json`):
///   {
///     "chests": {
///       "rare": { "label": "レアチェスト",
///                  "contents": [{"id": "silver_sword", "percent": 60}, {"id": "vulnerary", "percent": 40}],
///                  "sprite": {...} }
///     }
///   }
mod ChestCatalog {

    use Util.Json.Json
    use Sprite.SpriteResource

    /// 宝箱カタログ全体。`CatalogContainer[ChestResource]` を wrap し、`Saveable` で
    /// chests.json への round-trip 保存（IDE Resources タブ編集）を可能にする。
    /// containerKey は `"chests"` 固定（chests.json のトップレベルキーと 1 対 1）。
    /// （モジュール同名の companion enum はモジュール内で最初の宣言である必要があるため先頭に置く。）
    pub enum ChestCatalog {
        case ChestCatalog(CatalogContainer[ChestResource])
    }

    /// 宝箱 1 種ぶんの定義。
    /// `label` は IDE 表示用の名前。`sprite` は床に置く宝箱の見た目。
    /// `contents` は開錠で出る候補の重み付きプール（percent は相対重み、合計 100 でなくてよい）。
    /// 空 `contents` は「何も出ない宝箱」になるため、定義時は 1 件以上を入れる前提。
    pub type alias ChestResource = {
        label    = String,
        sprite   = SpriteResource,
        contents = List[FloorCatalog.SpawnEntry]
    }

    /// chests 部 (id → ChestResource の Map) を取り出す。
    pub def chestsOf(catalog: ChestCatalog): Map[String, ChestResource] =
        let ChestCatalog.ChestCatalog(container) = catalog;
        CatalogContainer.entriesOf(container)

    /// `resources/chests.json` をロードし `resources/chests.schema.json` で整合検査する。
    /// 起動時の `Game.start` で 1 度だけ呼ぶ想定。失敗は panic で即可視化。
    pub def load(): ChestCatalog \ Fs.FileRead =
        let container = CatalogContainer.loadWithCheck({
            dataPath       = AssetPath.resolve("resources/chests.json"),
            schemaPath     = AssetPath.resolve("resources/chests.schema.json"),
            containerKey   = "chests",
            expectedFields = expectedFields(),
            decodeEntry    = ChestCatalogCodec.decodeChest
        });
        ChestCatalog.ChestCatalog(container)

    /// 宝箱 id を引いて `ChestResource` を返す。未定義 id は起動時 typo として panic。
    pub def lookup(id: String, catalog: ChestCatalog): ChestResource =
        let ChestCatalog.ChestCatalog(container) = catalog;
        match CatalogContainer.get(id, container) {
            case Some(chest) => chest
            case None        => bug!("ChestCatalog.lookup: chest '${id}' not in catalog")
        }

    /// `ChestResource` の必須フィールド集合。load 時に JSON のフィールド漏れ・typo を検出するために使う。
    pub def expectedFields(): Set[String] =
        Set#{"label", "sprite", "contents"}
}

// container 巡回・schema 検査は CatalogContainer に委譲し、ここは wrap のみ。
instance Saveable[ChestCatalog.ChestCatalog] {
    pub def toJson(value: ChestCatalog.ChestCatalog): Util.Json.Json =
        let ChestCatalog.ChestCatalog.ChestCatalog(container) = value;
        CatalogContainer.encode(ChestCatalogCodec.encodeChest, container)

    pub def fromJson(element: Util.Json.Json): Option[ChestCatalog.ChestCatalog] =
        CatalogContainer.decode("chests", ChestCatalogCodec.decodeChest, element)
            |> Option.map(ChestCatalog.ChestCatalog.ChestCatalog)
}

/// ChestResource 1 件分の encode / decode のみ。container 巡回は `CatalogContainer.encode/decode` に委譲する。
mod ChestCatalogCodec {

    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JNumber}
    use JsonCodec.{expectObject, expectString, expectInt, intToBd, encodeList, decodeList}
    use ChestCatalog.ChestResource
    use FloorCatalog.SpawnEntry
    use Sprite.SpriteResource

    pub def encodeChest(chest: ChestResource): Json =
        JObject(Map#{
            "label"    => JString(chest#label),
            "contents" => encodeList(encodeContent, chest#contents),
            "sprite"   => encodeSprite(chest#sprite)
        })

    /// 中身プールの 1 エントリ ({id, percent})。FloorCatalogCodec.encodeSpawnEntry と同形。
    def encodeContent(entry: SpawnEntry): Json =
        JObject(Map#{
            "id"      => JString(entry#id),
            "percent" => JNumber(intToBd(entry#percent))
        })

    def encodeSprite(sprite: SpriteResource): Json =
        JObject(Map#{
            "texture" => JString(sprite#texture),
            "hframes" => JNumber(intToBd(sprite#hframes)),
            "vframes" => JNumber(intToBd(sprite#vframes)),
            "frame"   => JNumber(intToBd(sprite#frame)),
            "offset"  => JsonCodec.encodeVec2(sprite#offset)
        })

    pub def decodeChest(element: Json): Option[ChestResource] =
        forM (
            obj       <- expectObject(element);
            labelJ    <- Map.get("label", obj);
            contentsJ <- Map.get("contents", obj);
            spriteJ   <- Map.get("sprite", obj);
            label     <- expectString(labelJ);
            contents  <- decodeList(decodeContent, contentsJ);
            sprite    <- decodeSprite(spriteJ)
        ) yield ({label = label, sprite = sprite, contents = contents}: ChestResource)

    def decodeContent(element: Json): Option[SpawnEntry] =
        forM (
            obj      <- expectObject(element);
            idJ      <- Map.get("id", obj);
            percentJ <- Map.get("percent", obj);
            id       <- expectString(idJ);
            percent  <- expectInt(percentJ)
        ) yield ({id = id, percent = percent}: SpawnEntry)

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
