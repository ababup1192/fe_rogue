/// MonsterCatalog — 敵モンスターのカタログ Resource。
///
/// `resources/monsters.json` の `"monsters": { "<id>": {...} }` 形式から
/// `Map[String, EnemyStats]` を構築する。 `get(id, catalog)` で 1 体取り出して
/// バトル開始時の敵として配置する。
mod MonsterCatalog {

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonNumber, JsonString}

    /// 敵 1 体のスプライト情報。 IDE Resource 画面でプレビューを出すための nested で、
    /// 単一画像なら hframes=vframes=1, frame=0 で OK。 シート分割テクスチャの場合は
    /// frameGrid hint で切り出し位置を指定する。
    pub type alias SpriteSpec = {
        texture = String,
        hframes = Int32,
        vframes = Int32,
        frame   = Int32
    }

    /// 敵 1 体のステータス。 BattleScene.State の enemies フィールドにそのまま入る型。
    /// `sprite` は scene の Sprite2D にロード時に流し込まれる（IDE で編集すれば再起動で反映）。
    pub type alias EnemyStats = {
        name    = String,
        hp      = Int32, maxHp   = Int32,
        attack  = Int32, defense = Int32,
        sprite  = SpriteSpec
    }

    /// `resources/monsters.json` をロードして id → EnemyStats の Map を返す。
    pub def load(path: String): Map[String, EnemyStats] \ Fs.FileRead =
        let readResult = run {
            Fs.ReadFile.read(path)
        } with Fs.ReadFile.runWithFileRead;
        match readResult {
            case Err(e) => bug!("MonsterCatalog.load file read failed: ${path} :: ${e}")
            case Ok(content) =>
                match Json.Parse.parse(content) {
                    case None => bug!("MonsterCatalog.load JSON parse failed: ${path}")
                    case Some(json) =>
                        match decodeCatalog(json) {
                            case Some(c) => c
                            case None    => bug!("MonsterCatalog.load decode failed: ${path}")
                        }
                }
        }

    /// カタログから指定 id の敵を取り出す（id 未定義は panic で即可視化）。
    pub def get(id: String, catalog: Map[String, EnemyStats]): EnemyStats =
        match Map.get(id, catalog) {
            case Some(e) => e
            case None    => bug!("MonsterCatalog.get: unknown monster id: ${id}")
        }

    // ── デコード ──

    def decodeCatalog(element: JsonElement): Option[Map[String, EnemyStats]] =
        forM (
            top       <- expectObject(element);
            monstersJ <- Map.get("monsters", top);
            monstersM <- expectObject(monstersJ);
            catalog   <- traverse(monstersM)
        ) yield catalog

    def traverse(map: Map[String, JsonElement]): Option[Map[String, EnemyStats]] =
        Map.foldLeftWithKey((acc, id, json) ->
            Option.flatMap(soFar ->
                decodeMonster(json) |> Option.map(m -> Map.insert(id, m, soFar)),
                acc),
            Some(Map.empty()), map)

    def decodeMonster(element: JsonElement): Option[EnemyStats] =
        forM (
            obj      <- expectObject(element);
            nameJ    <- Map.get("name", obj);
            hpJ      <- Map.get("hp", obj);
            maxHpJ   <- Map.get("maxHp", obj);
            attackJ  <- Map.get("attack", obj);
            defenseJ <- Map.get("defense", obj);
            spriteJ  <- Map.get("sprite", obj);
            name     <- expectString(nameJ);
            hp       <- expectInt(hpJ);
            maxHp    <- expectInt(maxHpJ);
            attack   <- expectInt(attackJ);
            defense  <- expectInt(defenseJ);
            sprite   <- decodeSprite(spriteJ)
        ) yield ({
            name = name, hp = hp, maxHp = maxHp,
            attack = attack, defense = defense, sprite = sprite
        }: EnemyStats)

    def decodeSprite(element: JsonElement): Option[SpriteSpec] =
        forM (
            obj       <- expectObject(element);
            textureJ  <- Map.get("texture", obj);
            hframesJ  <- Map.get("hframes", obj);
            vframesJ  <- Map.get("vframes", obj);
            frameJ    <- Map.get("frame", obj);
            texture   <- expectString(textureJ);
            hframes   <- expectInt(hframesJ);
            vframes   <- expectInt(vframesJ);
            frame     <- expectInt(frameJ)
        ) yield ({
            texture = texture, hframes = hframes,
            vframes = vframes, frame = frame
        }: SpriteSpec)

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
