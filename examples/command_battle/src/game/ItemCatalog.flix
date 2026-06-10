/// ItemCatalog — どうぐ（アイテム）の Resource。
///
/// `resources/items.json` から:
///   - `items`: id → ItemDef のカタログ（不変）
///   - `inventory`: 初期所持リスト ({id, quantity})
/// を構築する。 戦闘中はゲーム側の State#inventory が消費とともに変化する。
mod ItemCatalog {

    use Util.Json.Json
    use Util.Json.Json.{JObject, JArray, JNumber, JString}

    /// アイテムの効果種別。 PR4 では Heal のみ（やくそう）。
    pub enum ItemKind with Eq, ToString {
        case Heal
    }

    /// アイテム 1 種類の定義。
    pub type alias ItemDef = {
        id    = String,
        name  = String,
        kind  = ItemKind,
        power = Int32
    }

    /// 所持アイテム 1 件。 quantity が 0 になったら使用不可。
    pub type alias InventoryEntry = {
        id       = String,
        quantity = Int32
    }

    /// カタログ全体。
    pub type alias Catalog = {
        items     = Map[String, ItemDef],
        inventory = List[InventoryEntry]
    }

    pub def load(path: String): Catalog \ Fs.FileRead =
        let readResult = run {
            Fs.ReadFile.read(path)
        } with Fs.ReadFile.runWithFileRead;
        match readResult {
            case Err(e) => bug!("ItemCatalog.load file read failed: ${path} :: ${e}")
            case Ok(content) =>
                match JsonCompat.parse(content) {
                    case None => bug!("ItemCatalog.load JSON parse failed: ${path}")
                    case Some(json) =>
                        match decodeCatalog(json) {
                            case Some(c) => c
                            case None    => bug!("ItemCatalog.load decode failed: ${path}")
                        }
                }
        }

    pub def get(id: String, catalog: Catalog): ItemDef =
        match Map.get(id, catalog#items) {
            case Some(i) => i
            case None    => bug!("ItemCatalog.get: unknown item id: ${id}")
        }

    /// inventory から指定 id のアイテムを 1 個消費する。
    /// 残数 0 のエントリは消費しない（呼び元で disabled 判定済みの想定）。
    /// 戻り値は更新後の inventory リスト。
    pub def consume(id: String, inventory: List[InventoryEntry]): List[InventoryEntry] =
        List.map(e ->
            if (e#id == id and e#quantity > 0)
                { quantity = e#quantity - 1 | e }
            else e,
            inventory)

    /// 指定 id の残数を取得する。 inventory に無ければ 0。
    pub def quantityOf(id: String, inventory: List[InventoryEntry]): Int32 =
        match List.find(e -> e#id == id, inventory) {
            case Some(e) => e#quantity
            case None    => 0
        }

    // ── デコード ──

    def decodeCatalog(element: Json): Option[Catalog] =
        forM (
            top         <- expectObject(element);
            itemsJ      <- Map.get("items", top);
            itemsM      <- expectObject(itemsJ);
            items       <- traverseItems(itemsM);
            inventoryJ  <- Map.get("inventory", top);
            inventory   <- decodeInventory(inventoryJ)
        ) yield ({items = items, inventory = inventory}: Catalog)

    def traverseItems(map: Map[String, Json]): Option[Map[String, ItemDef]] =
        Map.foldLeftWithKey((acc, id, json) ->
            Option.flatMap(soFar ->
                decodeItem(id, json) |> Option.map(i -> Map.insert(id, i, soFar)),
                acc),
            Some(Map.empty()), map)

    def decodeItem(id: String, element: Json): Option[ItemDef] =
        forM (
            obj    <- expectObject(element);
            nameJ  <- Map.get("name", obj);
            kindJ  <- Map.get("kind", obj);
            powerJ <- Map.get("power", obj);
            name   <- expectString(nameJ);
            kindS  <- expectString(kindJ);
            kind   <- decodeKind(kindS);
            power  <- expectInt(powerJ)
        ) yield ({id = id, name = name, kind = kind, power = power}: ItemDef)

    def decodeKind(s: String): Option[ItemKind] =
        match s {
            case "heal" => Some(ItemKind.Heal)
            case _      => None
        }

    def decodeInventory(element: Json): Option[List[InventoryEntry]] =
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
            obj     <- expectObject(element);
            idJ     <- Map.get("id", obj);
            qtyJ    <- Map.get("quantity", obj);
            id      <- expectString(idJ);
            qty     <- expectInt(qtyJ)
        ) yield ({id = id, quantity = qty}: InventoryEntry)

    def expectObject(element: Json): Option[Map[String, Json]] =
        match element {
            case JObject(map) => Some(map)
            case _               => None
        }

    def expectString(element: Json): Option[String] =
        match element {
            case JString(text) => Some(text)
            case _                => None
        }

    def expectInt(element: Json): Option[Int32] =
        match element {
            case JNumber(bd) =>
                BigDecimal.tryToFloat64(bd) |> Option.flatMap(Float64.tryToInt32)
            case _              => None
        }
}
