/// 1 ファイル = 1 catalog container の汎用構造。
/// `containerKey` 配下に entries (id → 値) を持ち、それ以外の top-level フィールドを
/// meta として保持する。
///
/// 例: `weapons.json` は `{"weapons": {"sword": {...}, ...}}`
///       containerKey = "weapons", entries = {sword => ...}, meta = {}
///
/// 例: `units.json` は `{"units": {...}, "players": [...], "enemies": [...]}`
///       containerKey = "units", entries = {knight => ...},
///       meta = {"players" => JsonArray(...), "enemies" => JsonArray(...)}
///
/// **設計メモ**: `Saveable[CatalogContainer[t]]` 用の polymorphic instance は付けない。
/// `fromJson` のシグネチャに containerKey を値として渡せないため (純粋関数の型では
/// 値レベル情報を引数化できない)。代わりに `encode` / `decode` 関数 API を提供し、
/// 各 catalog 側で `enum WeaponCatalog { case WeaponCatalog(CatalogContainer[WeaponResource]) }`
/// の wrap enum + 単相 Saveable instance を書く形にする。
mod CatalogContainer {
    use Json.JsonElement
    use Json.JsonElement.{JsonObject}

    /// 1 container の中身。
    /// `containerKey` は JSON top でこの container を保持しているキー名 (例: "weapons")。
    /// `entries` は id → 値の Map。`meta` は containerKey 以外の top-level フィールド。
    pub enum CatalogContainer[t] {
        case CatalogContainer({
            containerKey = String,
            entries      = Map[String, t],
            meta         = Map[String, JsonElement]
        })
    }

    /// entries だけを取り出すアクセサ。
    pub def entriesOf(catalog: CatalogContainer[t]): Map[String, t] =
        let CatalogContainer.CatalogContainer(payload) = catalog;
        payload#entries

    /// meta フィールド (containerKey 以外の top-level フィールド) を取り出す。
    pub def metaOf(catalog: CatalogContainer[t]): Map[String, JsonElement] =
        let CatalogContainer.CatalogContainer(payload) = catalog;
        payload#meta

    /// 1 件を id で引く。境界: 未定義 id は None。
    pub def get(id: String, catalog: CatalogContainer[t]): Option[t] =
        Map.get(id, entriesOf(catalog))

    /// catalog を JSON object として encode する。
    /// 形式: `{containerKey: encodeStringMap(entries), ...meta}`
    /// entry encoder は pure として渡す (内部で `unsafe IO` を隠した形 = JsonCodec の慣例と整合)。
    pub def encode(encodeEntry: t -> JsonElement, catalog: CatalogContainer[t]): JsonElement =
        let CatalogContainer.CatalogContainer(payload) = catalog;
        let entriesJson = JsonCodec.encodeStringMap(encodeEntry, payload#entries);
        let base = Map.insert(payload#containerKey, entriesJson, payload#meta);
        JsonObject(base)

    /// JSON object から containerKey 配下を entries、残りを meta として decode する。
    /// 失敗ケース (None): containerKey が無い / object でない / 要素 decode 失敗のいずれか。
    pub def decode(containerKey: String,
                    decodeEntry: JsonElement -> Option[t],
                    element: JsonElement): Option[CatalogContainer[t]] =
        forM (
            top         <- JsonCodec.expectObject(element);
            entriesJson <- Map.get(containerKey, top);
            entries     <- JsonCodec.decodeStringMap(decodeEntry, entriesJson)
        ) yield {
            let meta = Map.remove(containerKey, top);
            CatalogContainer.CatalogContainer({
                containerKey = containerKey,
                entries      = entries,
                meta         = meta
            })
        }

    /// `LoadSpec` の各フィールドを使った起動時の典型処理:
    ///   1. データ JSON を file から読み込む
    ///   2. parse / decode で `CatalogContainer[t]` を組み立てる
    ///   3. `Resource.loadSchemaDiagnostic` で `.schema.json` を読む
    ///   4. `Resource.checkConsistency` で Flix 型と schema のフィールド集合一致を検査
    /// 失敗は全段で panic (即可視化、`Resource.checkConsistency` と同方針)。
    /// **唯一の effectful 関数**。pure な `encode` / `decode` は別途呼べる。
    pub def loadWithCheck(spec: LoadSpec[t]): CatalogContainer[t] \ Fs.FileRead =
        let dataResult = run {
            Fs.ReadFile.read(spec#dataPath)
        } with Fs.ReadFile.runWithFileRead;
        let content = match dataResult {
            case Err(error) =>
                bug!("CatalogContainer.loadWithCheck file read failed: ${spec#dataPath} :: ${error}")
            case Ok(text)   => text
        };
        let parsed = match Json.Parse.parse(content) {
            case None       =>
                bug!("CatalogContainer.loadWithCheck JSON parse failed: ${spec#dataPath}")
            case Some(json) => json
        };
        let container = match decode(spec#containerKey, spec#decodeEntry, parsed) {
            case None    =>
                bug!("CatalogContainer.loadWithCheck decode failed: ${spec#dataPath}")
            case Some(c) => c
        };
        let schema = match Resource.loadSchemaDiagnostic(spec#schemaPath) {
            case Err(msg) =>
                bug!("CatalogContainer.loadWithCheck schema load failed: ${msg}")
            case Ok(s)    => s
        };
        match Resource.checkConsistency(spec#expectedFields, schema) {
            case Err(msg) =>
                bug!("CatalogContainer.loadWithCheck schema/type mismatch (${spec#dataPath}): ${msg}")
            case Ok(())   => container
        }

    /// `loadWithCheck` の引数を 1 つの record にまとめたもの。フィールドが多くなりがちなので
    /// 名前付きで渡せるようにしている。
    pub type alias LoadSpec[t] = {
        dataPath       = String,
        schemaPath     = String,
        containerKey   = String,
        expectedFields = Set[String],
        decodeEntry    = JsonElement -> Option[t]
    }
}
