// ExportedProperty — Scene のコードで既定値を宣言し、scene.json 側でその値を上書きできるようにする。
// コードが既定値の真実、JSON はそこからの差分だけを持つので、数値の微調整でコードを触らずに済む。
// 利用例: 弾の速度や敵の HP を scene.json で調整する。
//
// 使い方:
//   pub def birdSpeed(): Property[Float64] = Export.float("speed", 144.0)
//
//   pub def declarations(): List[PropertyDecl] =
//       Export.toDecl(birdSpeed()) :: Nil
//
//   pub def applyProperties(props: PropertyBag, scene: Scene[NodeTag]): Scene[NodeTag] =
//       let speed = Export.read(birdSpeed(), props);
//       Scene.setState(birdPath(), NodeTag.Bird({ speed = speed | ... }), scene)


/// プロパティの値の型を表す。将来エディタ UI が型ごとの編集ウィジェットを選ぶのに使う
pub enum PropertyKind with Eq, ToString {
    case KFloat
    case KInt
    case KBool
}

/// 型あり Property 宣言（1 プロパティ = 1 関数の戻り型）
/// key:     scene.json の properties マップでのキー
/// default: JSON にキーが無い or 型不一致のときに使う既定値
/// kind:    ランタイムでの型タグ
pub type alias Property[a] = {
    key = String,
    default = a,
    kind = PropertyKind
}

/// 型消去版の Property 宣言。declarations() の戻り値（List）に詰めるため
/// kind を残しておくと将来エディタ UI で型情報を伝えるのに使える
pub type alias PropertyDecl = {
    key = String,
    kind = PropertyKind
}

/// 1 つのノードに紐づくプロパティ値の集合。SceneLoader が JSON から作る
/// 値は raw Json のまま運び、Export.read で型付きに復元する方式にしているため
/// engine 側はゲーム固有の型を知らずに済む
pub type alias PropertyBag = Map[String, Util.Json.Json]

/// Property[a] の値型 a が JSON から a として復元できることを示す trait
/// MVP では Float64 / Int32 / Bool のみ実装
pub trait Exportable[a] {
    /// Json を a として復元する。失敗時 None を返し、呼び出し側が default にフォールバックする
    pub def decodeFromJson(json: Util.Json.Json): Option[a]
}

instance Exportable[Float64] {
    pub def decodeFromJson(json: Util.Json.Json): Option[Float64] =
        ExportedProperty.decodeFloat(json)
}

instance Exportable[Int32] {
    pub def decodeFromJson(json: Util.Json.Json): Option[Int32] =
        ExportedProperty.decodeInt(json)
}

instance Exportable[Bool] {
    pub def decodeFromJson(json: Util.Json.Json): Option[Bool] =
        ExportedProperty.decodeBool(json)
}


/// JSON → Flix 値のデコーダ群。`Exportable` の各 instance から委譲される
mod ExportedProperty {

    /// 空の PropertyBag。"properties" セクションが無いノードに使う既定値
    pub def emptyBag(): PropertyBag = Map.empty()

    /// JNumber → Float64。Java の BigDecimal.doubleValue を使って変換
    pub def decodeFloat(json: Util.Json.Json): Option[Float64] =
        match json {
            case Util.Json.Json.JNumber(big) => Some(big.doubleValue())
            case _ => None
        }

    /// JNumber → Int32（小数は切り捨て、Int32 範囲外なら None）
    pub def decodeInt(json: Util.Json.Json): Option[Int32] =
        match json {
            case Util.Json.Json.JNumber(big) =>
                Float64.tryToInt32(big.doubleValue())
            case _ => None
        }

    /// JBool → Bool
    pub def decodeBool(json: Util.Json.Json): Option[Bool] =
        match json {
            case Util.Json.Json.JBool(b) => Some(b)
            case _ => None
        }

    /// JSON Object 内の "properties" キーを取り出して PropertyBag にする。
    /// "properties" キーが無い / オブジェクトでない場合は空 bag を返す。
    /// SceneLoader.addJsonAt から呼ばれる
    pub def fromJsonNode(map: Map[String, Util.Json.Json]): PropertyBag =
        match Map.get("properties", map) {
            case Some(Util.Json.Json.JObject(propsMap)) => propsMap
            case _ => emptyBag()
        }
}


/// Export — Property の宣言ビルダーと値読み取り API
///
/// Scene 側コードからは Export.float / Export.read / Export.toDecl の 3 つを使う
mod Export {

    /// Float64 プロパティを宣言する
    pub def float(key: String, default: Float64): Property[Float64] =
        {key = key, default = default, kind = PropertyKind.KFloat}

    /// Int32 プロパティを宣言する
    pub def int(key: String, default: Int32): Property[Int32] =
        {key = key, default = default, kind = PropertyKind.KInt}

    /// Bool プロパティを宣言する
    pub def bool(key: String, default: Bool): Property[Bool] =
        {key = key, default = default, kind = PropertyKind.KBool}

    /// 型あり Property を型消去版の PropertyDecl に変換する。
    /// declarations() の中で `Export.toDecl(birdSpeed()) :: Nil` のように使う
    pub def toDecl(prop: Property[a]): PropertyDecl =
        {key = prop#key, kind = prop#kind}

    /// PropertyBag から Property の値を読み取る。
    /// JSON にキーが無い、または JSON の型が宣言と合わない場合は default にフォールバックする。
    /// scene.json をユーザーが手で壊しても安全に default で動くようにする方針
    pub def read(prop: Property[a], bag: PropertyBag): a with Exportable[a] =
        match Map.get(prop#key, bag) {
            case None       => prop#default
            case Some(json) =>
                match Exportable.decodeFromJson(json) {
                    case Some(value) => value
                    case None        => prop#default
                }
        }
}
