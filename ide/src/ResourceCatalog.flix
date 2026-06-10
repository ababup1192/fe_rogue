// ResourceCatalog — data JSON の構造を解析して Resources タブの UI 形態を決める
//
// 設計指針: マジック文字列 ("units", "pools", ...) を一切使わない。
// data の構造だけを見て classification を決め、sub-entry / メタフィールドを抽出する。
//
// 判別ルール (data top が JObject の前提):
//   - 1 つの値が「catalog container」(= JObject で、その全ての値も JObject)
//     ならば、そのキーを catalog container key、それ以外を meta として扱う
//   - 全ての値が catalog container でないなら、top 自体を 1 レコードとして扱う (Single)
//   - 上記以外 (top が array や primitive) は Unsupported
//
// fe_rogue の units.json は `{units: {knight: {...}, ...}, pools: {...}}` で、
// units が catalog container、pools が meta フィールドとなる。

mod ResourceCatalog {
    use Util.Json.Json
    use Util.Json.Json.{JObject, JArray, JString, JNumber, JBool, JNull}

    /// 分類結果。
    ///   Single             : top の JObject 自体が 1 レコード (例: {hp:10, name:""})
    ///   CatalogIn          : top 配下の containerKey に sub-entry が並ぶ
    ///                        (fe_rogue の units がここ)
    ///   Unsupported(msg)   : 配列 top など、v1 で扱わない構造
    pub enum Classification {
        case Single
        case CatalogIn({containerKey = String, subEntries = List[String], metaKeys = List[String]})
        case Unsupported(String)
    }

    /// data JSON を解析して分類を返す。schema や設定値は一切参照しない (data 構造のみ)。
    pub def classify(data: Json): Classification = match data {
        case JObject(topMap) =>
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
                        case JObject(m) => Map.keysOf(m) |> Set.toList
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

    /// JObject であって、中身の全ての値も JObject なら true。
    /// catalog container の定義: `{entry1: {...}, entry2: {...}, ...}` のように
    /// 値がすべてレコードである JObject。
    /// 空 JObject `{}` も catalog container として扱う (空 catalog の維持)。
    def isCatalogContainer(elem: Json): Bool = match elem {
        case JObject(m) =>
            Map.toList(m) |> List.forAll(p -> isJObject(snd(p)))
        case _ => false
    }

    def isJObject(elem: Json): Bool = match elem {
        case JObject(_) => true
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

    /// メタフィールドの編集 UI ヒント。schema の `metaHints` セクションから読む。
    /// engine 側にも同じ enum があるが、依存パッケージ (.fpkg) のキャッシュ更新を待たずに
    /// IDE 単独でビルドできるよう、IDE 内に同等定義を置く (engine リリース後に統合予定)。
    ///   Ref(target)  : `target` キーの catalog コンテナの sub-entries を dropdown 候補にする
    ///   Text         : 自由テキスト入力
    pub enum MetaHint with Eq, ToString {
        case Ref(String)
        case Text
    }

    /// schema JSON の `metaHints` セクションを Map[String, MetaHint] に decode する。
    /// 該当セクションがなければ空 Map を返す。形式不一致はそのキーをスキップ。
    pub def parseMetaHints(schemaJson: Json): Map[String, MetaHint] =
        match schemaJson {
            case JObject(top) =>
                match Map.get("metaHints", top) {
                    case Some(JObject(m)) =>
                        Map.foldLeftWithKey((acc, name, hintJson) ->
                            match parseSingleHint(hintJson) {
                                case Some(h) => Map.insert(name, h, acc)
                                case None    => acc
                            },
                            Map.empty(), m)
                    case _ => Map.empty()
                }
            case _ => Map.empty()
        }

    def parseSingleHint(elem: Json): Option[MetaHint] = match elem {
        case JObject(obj) =>
            match Map.get("type", obj) {
                case Some(JString("ref")) =>
                    match Map.get("to", obj) {
                        case Some(JString(target)) => Some(MetaHint.Ref(target))
                        case _                         => None
                    }
                case Some(JString("text")) => Some(MetaHint.Text)
                case _                         => None
            }
        case _ => None
    }

    /// メタ配列が catalog 参照型 (要素が catalog sub-entry の id) か推定するヒューリスティック。
    /// schema の metaHints に明示がない場合のフォールバック判定に使う。
    ///
    /// ルール:
    ///   - 空配列 → true (catalog 参照型と仮定。UX 上 sub-entries から選ぶのが自然)
    ///   - 全要素が JString で、その値が `subEntries` に含まれる → true
    ///   - それ以外 (一部が非 String、または sub-entries 外の文字列) → false
    pub def isCatalogRefArray(items: List[Json], subEntries: List[String]): Bool =
        if (List.isEmpty(items)) true
        else
            let subSet = List.toSet(subEntries);
            List.forAll(elem -> match elem {
                case JString(s) => Set.memberOf(s, subSet)
                case _             => false
            }, items)
}
