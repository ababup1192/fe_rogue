// ResourceCatalog — data JSON の構造を解析して Resources タブの UI 形態を決める
//
// 設計指針: マジック文字列 ("units", "pools", ...) を一切使わない。
// data の構造だけを見て classification を決め、sub-entry / メタフィールドを抽出する。
//
// 判別ルール (data top が JsonObject の前提):
//   - 1 つの値が「catalog container」(= JsonObject で、その全ての値も JsonObject)
//     ならば、そのキーを catalog container key、それ以外を meta として扱う
//   - 全ての値が catalog container でないなら、top 自体を 1 レコードとして扱う (Single)
//   - 上記以外 (top が array や primitive) は Unsupported
//
// fe_rogue の units.json は `{units: {knight: {...}, ...}, pools: {...}}` で、
// units が catalog container、pools が meta フィールドとなる。

mod ResourceCatalog {
    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonArray, JsonString, JsonNumber, JsonBool, JsonNull}

    /// 分類結果。
    ///   Single             : top の JsonObject 自体が 1 レコード (例: {hp:10, name:""})
    ///   CatalogIn          : top 配下の containerKey に sub-entry が並ぶ
    ///                        (fe_rogue の units がここ)
    ///   Unsupported(msg)   : 配列 top など、v1 で扱わない構造
    pub enum Classification {
        case Single
        case CatalogIn({containerKey = String, subEntries = List[String], metaKeys = List[String]})
        case Unsupported(String)
    }

    /// data JSON を解析して分類を返す。schema や設定値は一切参照しない (data 構造のみ)。
    pub def classify(data: JsonElement): Classification = match data {
        case JsonObject(topMap) =>
            let entries = Map.toList(topMap);
            let containers = entries |> List.filter(p -> isCatalogContainer(snd(p)));
            match containers {
                case Nil =>
                    // top 配下に catalog container がなければ、top 自身を 1 レコードとして扱う
                    Classification.Single
                case (containerKey, containerElem) :: _ =>
                    // 複数 catalog container があれば、最初のものを採用 (v1)。
                    // 残りは meta 扱い
                    let subEntries = match containerElem {
                        case JsonObject(m) => Map.keysOf(m) |> Set.toList
                        case _             => Nil
                    };
                    let metaKeys = entries
                        |> List.map(fst)
                        |> List.filter(k -> k != containerKey);
                    Classification.CatalogIn({
                        containerKey = containerKey,
                        subEntries   = subEntries,
                        metaKeys     = metaKeys
                    })
            }
        case _ => Classification.Unsupported("top is not a JSON object")
    }

    /// JsonObject であって、中身の全ての値も JsonObject なら true。
    /// catalog container の定義: `{entry1: {...}, entry2: {...}, ...}` のように
    /// 値がすべてレコードである JsonObject。
    /// 空 JsonObject `{}` も catalog container として扱う (空 catalog の維持)。
    def isCatalogContainer(elem: JsonElement): Bool = match elem {
        case JsonObject(m) =>
            Map.toList(m) |> List.forAll(p -> isJsonObject(snd(p)))
        case _ => false
    }

    def isJsonObject(elem: JsonElement): Bool = match elem {
        case JsonObject(_) => true
        case _             => false
    }

    /// JsonOps.setAtKeyPath 用の key path を組み立てる。
    /// CatalogIn: [containerKey, subEntryKey, ...fieldPath]
    /// Single:    [...fieldPath]
    pub def buildKeyPath(c: Classification, subEntryKey: Option[String], fieldPath: List[String]):
            List[String] =
        match c {
            case Classification.CatalogIn(info) =>
                match subEntryKey {
                    case Some(key) => info#containerKey :: key :: fieldPath
                    case None      => Nil  // sub-entry 未選択時は書き込み無効化
                }
            case Classification.Single        => fieldPath
            case Classification.Unsupported(_) => Nil
        }
}
