/// EnemyCatalog — 敵ユニットの定義カタログ（`resources/enemies.json`）。
///
/// 味方（UnitCatalog）から分離した敵専用カタログ。共有の戦闘ステータス・スプライト・持ち物は
/// `UnitBase` を使い、敵には成長率（`growthRates`）を持たせない。将来の「特殊能力」フィールドは
/// `EnemyResource` をここで拡張して足す（味方に波及しない）。
/// `weapons.json` / `floors.json` と同じく `CatalogContainer.loadWithCheck` ベースの独立カタログ。
///
/// JSON 形状（enemies.json）: `{ "enemies": { "goblin": {...}, "orc": {...} } }`
/// （プール配列は持たない。floors.json の `monsters` が id 文字列で参照する。）
mod EnemyCatalog {

    use UnitBase.UnitBase

    /// カタログ全体。`Saveable` を持たせるため enum でラップする（companion 宣言）。
    pub enum EnemyCatalog {
        case EnemyCatalog(CatalogContainer[EnemyResource])
    }

    /// 敵ユニット 1 種別ぶんのデータ = 共有ベース（成長率なし）。
    /// 将来の特殊能力は `{abilities = ... | UnitBase}` の形でここを拡張する。
    pub type alias EnemyResource = UnitBase

    /// enemies 部 (id → EnemyResource の Map) を取り出す。
    pub def enemiesOf(catalog: EnemyCatalog): Map[String, EnemyResource] =
        let EnemyCatalog.EnemyCatalog(container) = catalog;
        CatalogContainer.entriesOf(container)

    /// id で敵リソースを引く。未定義なら None（呼び出し側で panic 判断）。
    pub def get(id: String, catalog: EnemyCatalog): Option[EnemyResource] =
        let EnemyCatalog.EnemyCatalog(container) = catalog;
        CatalogContainer.get(id, container)

    /// `resources/enemies.json` をロード（schema 整合性検査込み）。起動時 Game.start で 1 度呼ぶ。
    /// `spriteFrames` は pure 経路では None。続けて `resolveSpriteFrames` で埋める。
    pub def load(): EnemyCatalog \ Fs.FileRead =
        let container = CatalogContainer.loadWithCheck({
            dataPath       = "resources/enemies.json",
            schemaPath     = "resources/enemies.schema.json",
            containerKey   = "enemies",
            expectedFields = expectedEnemyFields(),
            decodeEntry    = EnemyCatalogCodec.decodeEnemy
        });
        EnemyCatalog.EnemyCatalog(container)

    /// `enemies.json` を再読し、各敵の `spriteFrames` を texture 実寸で格子→px に解決して埋め直す。
    /// 共有解決ロジックは `UnitBaseCodec.resolveEntriesSpriteFrames` に委譲（味方と同じ）。
    pub def resolveSpriteFrames(enemiesPath: String, catalog: EnemyCatalog):
            EnemyCatalog \ {Fs.FileRead, GameEngine.Game} =
        let json = readFile(enemiesPath);
        let parsed = match Json.Parse.parse(json) {
            case None       => bug!("EnemyCatalog enemies JSON re-parse failed during resolveSpriteFrames")
            case Some(elem) => elem
        };
        let EnemyCatalog.EnemyCatalog(container) = catalog;
        let CatalogContainer.CatalogContainer(cp) = container;
        let resolved = UnitBaseCodec.resolveEntriesSpriteFrames(parsed, "enemies", cp#entries);
        let newContainer = CatalogContainer.CatalogContainer({entries = resolved | cp});
        EnemyCatalog.EnemyCatalog(newContainer)

    /// 指定 path をテキストとして読み、エラーなら即 panic する。
    def readFile(path: String): String \ Fs.FileRead =
        let readResult = run {
            Fs.ReadFile.read(path)
        } with Fs.ReadFile.runWithFileRead;
        match readResult {
            case Err(e)      => bug!("EnemyCatalog file read failed: ${path} :: ${e}")
            case Ok(content) => content
        }

    /// schema 整合性検査用のフィールド名集合（共有 14・**growthRates なし**）。
    pub def expectedEnemyFields(): Set[String] =
        Set#{"moveTiles", "level", "hp", "attack", "defense", "magicAttack", "magicDefense",
              "speed", "skill", "luck", "sprite", "initialInventory", "description", "spriteFrames"}
}

// ════════════════════════════════════════════════════════════════════════
// Saveable[EnemyCatalog] — enemies.json の round-trip
// ════════════════════════════════════════════════════════════════════════

instance Saveable[EnemyCatalog.EnemyCatalog] {
    pub def toJson(value: EnemyCatalog.EnemyCatalog): Json.JsonElement =
        let EnemyCatalog.EnemyCatalog(container) = value;
        CatalogContainer.encode(EnemyCatalogCodec.encodeEnemy, container)

    pub def fromJson(element: Json.JsonElement): Option[EnemyCatalog.EnemyCatalog] =
        CatalogContainer.decode("enemies", EnemyCatalogCodec.decodeEnemy, element)
            |> Option.map(EnemyCatalog.EnemyCatalog.EnemyCatalog)
}

mod EnemyCatalogCodec {
    use Json.JsonElement
    use EnemyCatalog.EnemyResource

    /// 敵 = 共有ベースのみ（成長率なし）。decode/encode は `UnitBaseCodec` に委譲。
    pub def decodeEnemy(element: JsonElement): Option[EnemyResource] =
        UnitBaseCodec.decodeBase(element)

    pub def encodeEnemy(e: EnemyResource): JsonElement =
        Json.JsonElement.JsonObject(UnitBaseCodec.encodeBase(e))
}
