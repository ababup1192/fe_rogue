/// SpellCatalog — じゅもん（呪文）の Resource。
///
/// `resources/spells.json` の `"spells": { "<id>": {...} }` 形式から
/// `Map[String, SpellDef]` を構築する。 `kind` で "heal" / "damage" を分岐し、
/// 効果値は `[minPower, maxPower]` の範囲で乱数によって振れる（Battle.computeSpell 経由）。
///
/// `"known"` 配列に勇者が習得済みの呪文 id を並べる（PR4 では固定リスト、 PR5+ で
/// レベルアップ習得などに発展可能）。
mod SpellCatalog {

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonArray, JsonNumber, JsonString}

    /// 呪文の効果種別。 表示メッセージ・ターゲット選択 (敵 / 味方) の分岐に使う。
    pub enum SpellKind with Eq, ToString {
        case Heal     // 自分の HP を回復
        case Damage   // 敵に攻撃
    }

    /// 呪文 1 つぶんの定義。
    pub type alias SpellDef = {
        id       = String,
        name     = String,
        cost     = Int32,
        kind     = SpellKind,
        minPower = Int32,
        maxPower = Int32
    }

    /// カタログ全体。 `spells` は id → def、 `known` は習得済み id のリスト。
    pub type alias Catalog = {
        spells = Map[String, SpellDef],
        known  = List[String]
    }

    /// `resources/spells.json` をロードする。
    pub def load(path: String): Catalog \ Fs.FileRead =
        let readResult = run {
            Fs.ReadFile.read(path)
        } with Fs.ReadFile.runWithFileRead;
        match readResult {
            case Err(e) => bug!("SpellCatalog.load file read failed: ${path} :: ${e}")
            case Ok(content) =>
                match Json.Parse.parse(content) {
                    case None => bug!("SpellCatalog.load JSON parse failed: ${path}")
                    case Some(json) =>
                        match decodeCatalog(json) {
                            case Some(c) => c
                            case None    => bug!("SpellCatalog.load decode failed: ${path}")
                        }
                }
        }

    /// 指定 id の呪文を取り出す（id 未定義は panic）。
    pub def get(id: String, catalog: Catalog): SpellDef =
        match Map.get(id, catalog#spells) {
            case Some(s) => s
            case None    => bug!("SpellCatalog.get: unknown spell id: ${id}")
        }

    /// 勇者が習得済みの呪文を順に取り出す（known 順を保持）。
    pub def knownSpells(catalog: Catalog): List[SpellDef] =
        List.map(id -> get(id, catalog), catalog#known)

    // ── デコード ──

    def decodeCatalog(element: JsonElement): Option[Catalog] =
        forM (
            top      <- expectObject(element);
            spellsJ  <- Map.get("spells", top);
            spellsM  <- expectObject(spellsJ);
            spells   <- traverse(spellsM);
            knownJ   <- Map.get("known", top);
            known    <- decodeStringList(knownJ)
        ) yield ({spells = spells, known = known}: Catalog)

    def traverse(map: Map[String, JsonElement]): Option[Map[String, SpellDef]] =
        Map.foldLeftWithKey((acc, id, json) ->
            Option.flatMap(soFar ->
                decodeSpell(id, json) |> Option.map(s -> Map.insert(id, s, soFar)),
                acc),
            Some(Map.empty()), map)

    def decodeSpell(id: String, element: JsonElement): Option[SpellDef] =
        forM (
            obj      <- expectObject(element);
            nameJ    <- Map.get("name", obj);
            costJ    <- Map.get("cost", obj);
            kindJ    <- Map.get("kind", obj);
            minPwJ   <- Map.get("minPower", obj);
            maxPwJ   <- Map.get("maxPower", obj);
            name     <- expectString(nameJ);
            cost     <- expectInt(costJ);
            kindStr  <- expectString(kindJ);
            kind     <- decodeKind(kindStr);
            minPower <- expectInt(minPwJ);
            maxPower <- expectInt(maxPwJ)
        ) yield ({
            id = id, name = name, cost = cost, kind = kind,
            minPower = minPower, maxPower = maxPower
        }: SpellDef)

    def decodeKind(s: String): Option[SpellKind] =
        match s {
            case "heal"   => Some(SpellKind.Heal)
            case "damage" => Some(SpellKind.Damage)
            case _        => None
        }

    def decodeStringList(element: JsonElement): Option[List[String]] =
        match element {
            case JsonArray(items) =>
                List.foldRight(item -> acc ->
                    Option.flatMap(soFar ->
                        expectString(item) |> Option.map(s -> s :: soFar),
                        acc),
                    Some(Nil), Vector.toList(items))
            case _ => None
        }

    def expectObject(element: JsonElement): Option[Map[String, JsonElement]] =
        match element {
            case JsonObject(map) => Some(map)
            case _               => None
        }

    def expectString(element: JsonElement): Option[String] =
        match element {
            case JsonString(text) => Some(text)
            case _                => None
        }

    def expectInt(element: JsonElement): Option[Int32] =
        match element {
            case JsonNumber(bd) =>
                BigDecimal.tryToFloat64(bd) |> Option.flatMap(Float64.tryToInt32)
            case _              => None
        }
}
