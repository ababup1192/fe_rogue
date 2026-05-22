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

    /// floor id → FloorResource の Map。
    /// Flix の規約により、モジュール名と同名の enum (companion) はモジュール先頭に置く必要がある
    pub enum FloorCatalog {
        case FloorCatalog(Map[String, FloorResource])
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

    /// 1 フロア分の出現テーブル + 部屋あたりスポーン数レンジ
    pub type alias FloorResource = {
        label           = String,
        monsters        = List[SpawnEntry],
        items           = List[SpawnEntry],
        monstersPerRoom = SpawnRange,
        itemsPerRoom    = SpawnRange
    }

    /// `resources/floors.json` をロード。decode 失敗は panic（即可視化）。
    pub def load(path: String): FloorCatalog \ Fs.FileRead =
        let readResult = run {
            Fs.ReadFile.read(path)
        } with Fs.ReadFile.runWithFileRead;
        match readResult {
            case Err(e) =>
                bug!("FloorCatalog.load file read failed: ${path} :: ${e}")
            case Ok(content) =>
                match Json.Parse.parse(content) {
                    case None =>
                        bug!("FloorCatalog.load JSON parse failed: ${path}")
                    case Some(json) =>
                        match decodeFile(json) {
                            case None    => bug!("FloorCatalog.load decode failed: ${path}")
                            case Some(c) => c
                        }
                }
        }

    /// 指定 id のフロアを取り出す。未定義なら panic（floor id の typo を即発覚させる）
    pub def get(id: String, catalog: FloorCatalog): FloorResource =
        let FloorCatalog.FloorCatalog(m) = catalog;
        match Map.get(id, m) {
            case Some(f) => f
            case None    => bug!("FloorCatalog.get: unknown floor id: ${id}")
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
        Set#{"label", "monsters", "items", "monstersPerRoom", "itemsPerRoom"}

    // ─────────────────────────────────────────────────────────
    // Decoder
    // ─────────────────────────────────────────────────────────

    def decodeFile(element: JsonElement): Option[FloorCatalog] = match element {
        case JsonObject(top) =>
            match Map.get("floors", top) {
                case Some(JsonObject(fm)) =>
                    let decoded = Map.foldLeftWithKey((acc, key, v) -> match acc {
                        case None      => None
                        case Some(acc2) =>
                            match decodeFloor(v) {
                                case None    => None
                                case Some(f) => Some(Map.insert(key, f, acc2))
                            }
                    }, Some(Map.empty()), fm);
                    decoded |> Option.map(FloorCatalog.FloorCatalog)
                case _ => None
            }
        case _ => None
    }

    def decodeFloor(element: JsonElement): Option[FloorResource] = match element {
        case JsonObject(obj) =>
            forM (
                labelJ           <- Map.get("label", obj);
                monstersJ        <- Map.get("monsters", obj);
                itemsJ           <- Map.get("items", obj);
                monstersPerRoomJ <- Map.get("monstersPerRoom", obj);
                itemsPerRoomJ    <- Map.get("itemsPerRoom", obj);
                label            <- expectString(labelJ);
                monsters         <- decodeSpawnArray(monstersJ);
                items            <- decodeSpawnArray(itemsJ);
                mpr              <- decodeSpawnRange(monstersPerRoomJ);
                ipr              <- decodeSpawnRange(itemsPerRoomJ)
            ) yield ({
                label = label,
                monsters = monsters,
                items = items,
                monstersPerRoom = mpr,
                itemsPerRoom = ipr
            }: FloorResource)
        case _ => None
    }

    /// `{"min": Int32, "max": Int32}` を SpawnRange に decode
    def decodeSpawnRange(element: JsonElement): Option[SpawnRange] = match element {
        case JsonObject(obj) =>
            forM (
                minJ <- Map.get("min", obj);
                maxJ <- Map.get("max", obj);
                mn   <- expectInt(minJ);
                mx   <- expectInt(maxJ)
            ) yield ({min = mn, max = mx}: SpawnRange)
        case _ => None
    }

    def decodeSpawnArray(element: JsonElement): Option[List[SpawnEntry]] = match element {
        case JsonArray(items) =>
            let decoded = Vector.toList(items)
                |> List.foldLeft((acc, v) -> match acc {
                    case None      => None
                    case Some(xs)  => match decodeSpawnEntry(v) {
                        case None    => None
                        case Some(e) => Some(List.append(xs, e :: Nil))
                    }
                }, Some(Nil));
            decoded
        case _ => None
    }

    def decodeSpawnEntry(element: JsonElement): Option[SpawnEntry] = match element {
        case JsonObject(obj) =>
            forM (
                idJ      <- Map.get("id", obj);
                percentJ <- Map.get("percent", obj);
                id       <- expectString(idJ);
                percent  <- expectInt(percentJ)
            ) yield ({id = id, percent = percent}: SpawnEntry)
        case _ => None
    }

    def expectString(element: JsonElement): Option[String] = match element {
        case JsonString(s) => Some(s)
        case _             => None
    }

    def expectInt(element: JsonElement): Option[Int32] = match element {
        case JsonNumber(bd) => BigDecimal.tryToFloat64(bd) |> Option.flatMap(Float64.tryToInt32)
        case _              => None
    }
}
