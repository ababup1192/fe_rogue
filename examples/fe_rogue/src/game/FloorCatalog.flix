/// FloorCatalog — フロアごとの出現テーブル定義
///
/// `resources/floors.json` を読み、各フロアで出現するモンスター・アイテムの種類と
/// 出現率（percent 0-100）、部屋あたりのスポーン上限を保持する。
///
/// 確率は percent 配列 `[{id, percent}, ...]` で、合計は通常 100 を目指すが、
/// 100 でなくても抽選時は合計値で割って正規化する（多少ずれていても破綻しない）。
///
/// JSON 形状:
///   {
///     "floors": {
///       "f01": {
///         "label": "1F",
///         "monsters": [{"id": "goblin", "percent": 70}, {"id": "orc", "percent": 30}],
///         "items":    [{"id": "noviceStaff", "percent": 50}, ...],
///         "monstersPerRoom": 2,
///         "itemsPerRoom":    1
///       }
///     }
///   }
mod FloorCatalog {

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber, JsonArray}

    /// floor カタログ。段階 8 のリファクタで `CatalogContainer[FloorResource]` を wrap する
    /// 形に変更し、`Saveable` instance を追加した (IDE Resources タブで編集可能に)。
    /// containerKey は `"floors"` 固定。
    pub enum FloorCatalog {
        case FloorCatalog(CatalogContainer[FloorResource])
    }

    /// 1 エントリ: ある id (units / weapons の sub-entry id) が percent の重みで出現する
    pub type alias SpawnEntry = {
        id      = String,
        percent = Int32
    }

    /// 部屋あたりスポーン数の min..max inclusive 範囲
    pub type alias SpawnRange = {
        min = Int32,
        max = Int32
    }

    /// ダンジョン生成のパラメータ。LDTK プールは将来 tileset resource に分離するため、
    /// 今は roomCount だけ持たせる
    pub type alias GenerationConfig = {
        roomCount = Int32
    }

    /// 1 フロア分の出現テーブル + 部屋あたりスポーン数レンジ + ダンジョン生成設定
    pub type alias FloorResource = {
        label           = String,
        generation      = GenerationConfig,
        monsters        = List[SpawnEntry],
        items           = List[SpawnEntry],
        monstersPerRoom = SpawnRange,
        itemsPerRoom    = SpawnRange
    }

    /// `resources/floors.json` をロードし、`resources/floors.schema.json` で整合検査する。
    /// 段階 8 のリファクタで `CatalogContainer.loadWithCheck` に委譲する形に変更した。
    /// 失敗は panic（即可視化）。起動時の `Game.start` で 1 度だけ呼ぶ想定。
    pub def load(): FloorCatalog \ Fs.FileRead =
        let container = CatalogContainer.loadWithCheck({
            dataPath       = "resources/floors.json",
            schemaPath     = "resources/floors.schema.json",
            containerKey   = "floors",
            expectedFields = expectedFloorFields(),
            decodeEntry    = FloorCatalogCodec.decodeFloor
        });
        FloorCatalog.FloorCatalog(container)

    /// 指定 id のフロアを取り出す。未定義なら panic（floor id の typo を即発覚させる）
    pub def get(id: String, catalog: FloorCatalog): FloorResource =
        let FloorCatalog.FloorCatalog(container) = catalog;
        match CatalogContainer.get(id, container) {
            case Some(floor) => floor
            case None        => bug!("FloorCatalog.get: unknown floor id: ${id}")
        }

    /// floors.json トップレベルの `"order"` 配列（フロア進行順）を取り出す。
    /// `CatalogContainer` は containerKey (`"floors"`) 以外の top-level フィールドを
    /// meta に保持するため、`order` は meta から読む（schema 検査の対象外）。
    /// 未定義なら空リスト（呼び出し側で panic / フォールバック）。
    pub def order(catalog: FloorCatalog): List[String] =
        let FloorCatalog.FloorCatalog(container) = catalog;
        match Map.get("order", CatalogContainer.metaOf(container)) {
            case Some(element) =>
                JsonCodec.decodeList(JsonCodec.expectString, element)
                    |> Option.getWithDefault(Nil)
            case None => Nil
        }

    /// 進行順の先頭フロア id。`order` が空なら panic（floors.json の設定漏れを即可視化）。
    /// 起動時・全滅リスタート・ゲームクリア後のループで「1F」を指す唯一の入口。
    pub def firstFloorId(catalog: FloorCatalog): String =
        match List.head(order(catalog)) {
            case Some(id) => id
            case None     => bug!("FloorCatalog.firstFloorId: 'order' is empty in floors.json")
        }

    /// 進行順で `currentId` の次のフロア id。`currentId` が最後（= 最終フロア）なら None。
    /// None は「これ以上フロアが無い = ゲームクリア」を意味する。
    pub def nextFloorId(currentId: String, catalog: FloorCatalog): Option[String] =
        idAfter(currentId, order(catalog))

    /// `ids` の中で `target` の直後の要素を返す。`target` が最後 / 未登場なら None。
    def idAfter(target: String, ids: List[String]): Option[String] = match ids {
        case Nil        => None
        case id :: rest => if (id == target) List.head(rest) else idAfter(target, rest)
    }

    /// percent 配列から 1 件をランダムに抽選。
    /// entries 空 / 合計 percent <= 0 なら None（呼び出し側でスキップ）
    pub def pickWeighted(entries: List[SpawnEntry]): Option[String] \ Math.Random = {
        let total = sumPercent(entries);
        if (total <= 0i32) None
        else {
            let r = Math.Random.randomFloat64() * Int32.toFloat64(total);
            pickWeightedRec(r, 0.0, entries)
        }
    }

    def pickWeightedRec(r: Float64, acc: Float64, entries: List[SpawnEntry]):
            Option[String] = match entries {
        case Nil      => None
        case e :: rest =>
            let next = acc + Int32.toFloat64(e#percent);
            if (r < next) Some(e#id)
            else pickWeightedRec(r, next, rest)
    }

    def sumPercent(entries: List[SpawnEntry]): Int32 =
        List.foldLeft((acc, e) -> acc + e#percent, 0i32, entries)

    /// min..max inclusive (max - min + 1 通り) の整数を均等ランダムに返す。
    /// max < min の不正な範囲では min を返す (defensive)
    pub def randomCountInRange(range: SpawnRange): Int32 \ Math.Random =
        let lo = range#min;
        let hi = range#max;
        if (hi < lo) lo
        else {
            let span = hi - lo + 1i32;
            let r = Math.Random.randomFloat64();
            let idx = Float64.truncateToInt32(Float64.floor(r * Int32.toFloat64(span)));
            lo + idx
        }

    /// schema 整合性チェックに使う期待フィールド名集合
    pub def expectedFloorFields(): Set[String] =
        Set#{"label", "generation", "monsters", "items", "monstersPerRoom", "itemsPerRoom"}

}

// ════════════════════════════════════════════════════════════════════════
// Saveable[FloorCatalog] — floors.json の round-trip 実装 (薄い wrap)
// ════════════════════════════════════════════════════════════════════════

instance Saveable[FloorCatalog.FloorCatalog] {
    pub def toJson(value: FloorCatalog.FloorCatalog): Json.JsonElement =
        let FloorCatalog.FloorCatalog.FloorCatalog(container) = value;
        CatalogContainer.encode(FloorCatalogCodec.encodeFloor, container)

    pub def fromJson(element: Json.JsonElement): Option[FloorCatalog.FloorCatalog] =
        CatalogContainer.decode("floors", FloorCatalogCodec.decodeFloor, element)
            |> Option.map(FloorCatalog.FloorCatalog.FloorCatalog)
}

/// FloorResource 1 件分の encode / decode。container 巡回は `CatalogContainer.encode/decode` に委譲する。
mod FloorCatalogCodec {

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber, JsonArray}
    use JsonCodec.{expectObject, expectString, expectInt, intToBd, encodeList, decodeList}
    use FloorCatalog.{FloorResource, SpawnEntry, SpawnRange, GenerationConfig}

    // ── エンコード ──

    pub def encodeFloor(floor: FloorResource): JsonElement =
        JsonObject(Map#{
            "label"           => JsonString(floor#label),
            "generation"      => encodeGeneration(floor#generation),
            "monsters"        => encodeList(encodeSpawnEntry, floor#monsters),
            "items"           => encodeList(encodeSpawnEntry, floor#items),
            "monstersPerRoom" => encodeRange(floor#monstersPerRoom),
            "itemsPerRoom"    => encodeRange(floor#itemsPerRoom)
        })

    def encodeGeneration(config: GenerationConfig): JsonElement =
        JsonObject(Map#{
            "roomCount" => JsonNumber(intToBd(config#roomCount))
        })

    def encodeRange(range: SpawnRange): JsonElement =
        JsonObject(Map#{
            "min" => JsonNumber(intToBd(range#min)),
            "max" => JsonNumber(intToBd(range#max))
        })

    def encodeSpawnEntry(entry: SpawnEntry): JsonElement =
        JsonObject(Map#{
            "id"      => JsonString(entry#id),
            "percent" => JsonNumber(intToBd(entry#percent))
        })

    // ── デコード ──

    pub def decodeFloor(element: JsonElement): Option[FloorResource] =
        forM (
            obj              <- expectObject(element);
            labelJ           <- Map.get("label", obj);
            generationJ      <- Map.get("generation", obj);
            monstersJ        <- Map.get("monsters", obj);
            itemsJ           <- Map.get("items", obj);
            monstersPerRoomJ <- Map.get("monstersPerRoom", obj);
            itemsPerRoomJ    <- Map.get("itemsPerRoom", obj);
            label            <- expectString(labelJ);
            generation       <- decodeGeneration(generationJ);
            monsters         <- decodeList(decodeSpawnEntry, monstersJ);
            items            <- decodeList(decodeSpawnEntry, itemsJ);
            monstersPerRoom  <- decodeSpawnRange(monstersPerRoomJ);
            itemsPerRoom     <- decodeSpawnRange(itemsPerRoomJ)
        ) yield ({
            label = label, generation = generation,
            monsters = monsters, items = items,
            monstersPerRoom = monstersPerRoom, itemsPerRoom = itemsPerRoom
        }: FloorResource)

    /// `{"roomCount": Int32}` を GenerationConfig に decode
    def decodeGeneration(element: JsonElement): Option[GenerationConfig] =
        forM (
            obj        <- expectObject(element);
            roomCountJ <- Map.get("roomCount", obj);
            roomCount  <- expectInt(roomCountJ)
        ) yield ({roomCount = roomCount}: GenerationConfig)

    /// `{"min": Int32, "max": Int32}` を SpawnRange に decode
    def decodeSpawnRange(element: JsonElement): Option[SpawnRange] =
        forM (
            obj  <- expectObject(element);
            minJ <- Map.get("min", obj);
            maxJ <- Map.get("max", obj);
            mn   <- expectInt(minJ);
            mx   <- expectInt(maxJ)
        ) yield ({min = mn, max = mx}: SpawnRange)

    def decodeSpawnEntry(element: JsonElement): Option[SpawnEntry] =
        forM (
            obj      <- expectObject(element);
            idJ      <- Map.get("id", obj);
            percentJ <- Map.get("percent", obj);
            id       <- expectString(idJ);
            percent  <- expectInt(percentJ)
        ) yield ({id = id, percent = percent}: SpawnEntry)

    // expectXxx / 数値変換 / List round-trip は engine の JsonCodec mod に集約されている。
    // 本 mod では `use JsonCodec.{...}` 経由で参照する。
}
