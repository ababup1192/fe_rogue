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

    /// カタログ全体。Flix の trait instance は型定義と同モジュールに置く必要があるが、
    /// `Saveable` は外部モジュール定義のため mod 外 instance になる（orphan instance）。
    /// 外部型への orphan instance を付与するには自モジュール所有の enum でラップするのが唯一の手段。
    pub enum EnemyCatalog {
        case EnemyCatalog(CatalogContainer[EnemyResource])
    }

    /// 敵ユニット 1 種別ぶんのデータ = 共有 14 フィールド + 索敵/挙動タイプ `aiType`（成長率なし）。
    /// `aiType` は EnemyAI の起動条件 / 徘徊を決める（IDE では `enemies.json` の 1 フィールド）。
    /// 味方（UnitBase 共有型）には波及しない敵専用の拡張。将来の特殊能力もこの形でここに足す。
    /// （`UnitBase` は閉じた型エイリアスのため `{ f | UnitBase }` のスプレッドはできず、
    ///  PlayerResource と同じく全フィールドを書き下す。codec は共有部を `UnitBaseCodec` に委譲。）
    pub type alias EnemyResource = {
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
        sprite           = Sprite.SpriteResource,
        initialInventory = List[UnitBase.InventoryEntry],
        description      = String,
        spriteFrames     = Option[SpriteFrames],
        aiType           = EnemyAI.AiType,
        // 装備する指輪の id（rings.json）。多くの敵は持たないので Option。欠落 → None。
        ring             = Option[String]
    }

    /// 全 id を列挙・イテレートしたいとき（EnemyScene のロスター構築など）に使う。
    /// 個別取得は `get` を使い、この関数でフィルタするのは避ける。
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
            dataPath       = AssetPath.resolve("resources/enemies.json"),
            schemaPath     = AssetPath.resolve("resources/enemies.schema.json"),
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
        let parsed = match JsonCompat.parse(json) {
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

    /// schema 整合性検査用のフィールド名集合（共有 14 + 敵専用 `aiType`・**growthRates なし**）。
    /// `loadWithCheck` がこの集合と `enemies.schema.json` の `fields` キー集合の完全一致を要求するため、
    /// `aiType` を足すときは schema 側と enemies.json の各エントリも同時に揃える（揃えないと起動 panic）。
    pub def expectedEnemyFields(): Set[String] =
        Set#{"moveTiles", "level", "hp", "attack", "defense", "magicAttack", "magicDefense",
              "speed", "skill", "luck", "sprite", "initialInventory", "description", "spriteFrames",
              "aiType", "ring"}
}

// Saveable[EnemyCatalog.EnemyCatalog] は mod 外 instance として置く。
// Flix の orphan ルールにより、自モジュール外の型（EnemyCatalog.EnemyCatalog）への
// instance は呼び出し側モジュールに定義しなければならないため。

instance Saveable[EnemyCatalog.EnemyCatalog] {
    pub def toJson(value: EnemyCatalog.EnemyCatalog): Util.Json.Json =
        let EnemyCatalog.EnemyCatalog(container) = value;
        CatalogContainer.encode(EnemyCatalogCodec.encodeEnemy, container)

    pub def fromJson(element: Util.Json.Json): Option[EnemyCatalog.EnemyCatalog] =
        CatalogContainer.decode("enemies", EnemyCatalogCodec.decodeEnemy, element)
            |> Option.map(EnemyCatalog.EnemyCatalog.EnemyCatalog)
}

mod EnemyCatalogCodec {
    use Util.Json.Json
    use Util.Json.Json.JString
    use JsonCodec.{expectObject, expectString}
    use EnemyCatalog.EnemyResource

    /// 敵 = 共有 14 フィールド（`UnitBaseCodec.decodeBase`）+ `aiType`。
    /// `aiType` 欠落 / 未知文字列は `parseAiType` が Aggressive にフォールバック（後方互換）。
    /// `UnitBase` は閉じた型のためスプレッドできず、`decodePlayer` と同じく全フィールドを書き下す。
    pub def decodeEnemy(element: Json): Option[EnemyResource] =
        forM (
            base <- UnitBaseCodec.decodeBase(element);
            obj  <- expectObject(element)
        ) yield {
            let aiType = Map.get("aiType", obj)
                            |> Option.flatMap(expectString)
                            |> Option.map(EnemyAI.parseAiType)
                            |> Option.getWithDefault(EnemyAI.AiType.Aggressive);
            // ring (装備指輪 id) は省略可。欠落 → None。
            let ring = Map.get("ring", obj) |> Option.flatMap(expectString);
            ({moveTiles = base#moveTiles, level = base#level, hp = base#hp, attack = base#attack,
              defense = base#defense, magicAttack = base#magicAttack,
              magicDefense = base#magicDefense, speed = base#speed, skill = base#skill,
              luck = base#luck, sprite = base#sprite, initialInventory = base#initialInventory,
              description = base#description, spriteFrames = base#spriteFrames,
              aiType = aiType, ring = ring}: EnemyResource)
        }

    /// 敵 = 共有ベース + `aiType`。共有部の Map に `aiType` 文字列を差して
    /// `CatalogContainer.encode` が期待するエントリ形式に整える。
    /// `encodeBase` は row-polymorphic なので `aiType` 付きの EnemyResource をそのまま渡せる（共有部だけ書く）。
    pub def encodeEnemy(e: EnemyResource): Json =
        let withAi = Map.insert("aiType", JString(EnemyAI.aiTypeToString(e#aiType)),
                                UnitBaseCodec.encodeBase(e));
        // ring は Some のときだけ書き出す（None は省略 → decode 既定 None で round-trip）。
        let withRing = match e#ring {
            case Some(id) => Map.insert("ring", JString(id), withAi)
            case None     => withAi
        };
        Util.Json.Json.JObject(withRing)
}
