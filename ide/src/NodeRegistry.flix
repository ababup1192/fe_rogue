// NodeRegistry — ノード型カタログの単一ソース（拡張性リファクタ Phase A）
//
// 「Add Child Node メニューに出る型」と「その既定 JSON 断片」は従来 ScenePanel と
// SceneSerializer に二重に散らばっていた。ここへ集約し、ノード型をカタログへ足すのは
// `entries()` に 1 エントリ追加するだけにする。
//
// 依存を持たない低レベルモジュール（純粋な String/Bool のみ）。SceneSerializer / ScenePanel
// から下向きに参照され、循環依存を作らない。Inspector の型別スキーマ（NodeInspector.typeSpecific）
// はノード値からの dispatch なので NodeInspector に同居のまま（別関心・単一箇所）。
mod NodeRegistry {

    /// 1 ノード型のカタログ定義。
    ///   typeName:    シーン JSON の "type" 値
    ///   defaultJson: 新規追加時の最小 JSON 断片を組む（引数 = ノード名）
    ///   addable:     Add Child Node メニューに出すか
    pub type alias NodeTypeDef = {
        typeName = String,
        defaultJson = String -> String,
        addable = Bool
    }

    /// カタログ本体。ノード型を足すときはここへ 1 エントリ追加する。
    /// 順序は Add Child メニューの表示順に対応する。
    pub def entries(): List[NodeTypeDef] =
        ({typeName = "StaticBody2D", addable = true,
          defaultJson = name ->
            "{\"type\": \"StaticBody2D\", \"name\": \"${name}\", \"pos\": [0, 0], \"shape\": {\"kind\": \"RectShape2D\", \"width\": 32, \"height\": 32}}"}
          : NodeTypeDef) ::
        ({typeName = "RigidBody2D", addable = true,
          defaultJson = name ->
            "{\"type\": \"RigidBody2D\", \"name\": \"${name}\", \"pos\": [0, 0], \"shape\": {\"kind\": \"CircleShape2D\", \"radius\": 8}}"}
          : NodeTypeDef) ::
        ({typeName = "CharacterBody2D", addable = true,
          defaultJson = name ->
            "{\"type\": \"CharacterBody2D\", \"name\": \"${name}\", \"pos\": [0, 0], \"shape\": {\"kind\": \"RectShape2D\", \"width\": 48, \"height\": 8}}"}
          : NodeTypeDef) ::
        ({typeName = "Area2D", addable = true,
          defaultJson = name ->
            "{\"type\": \"Area2D\", \"name\": \"${name}\", \"pos\": [0, 0], \"shape\": {\"kind\": \"RectShape2D\", \"width\": 32, \"height\": 16}}"}
          : NodeTypeDef) ::
        ({typeName = "ColorRect", addable = true,
          defaultJson = name ->
            "{\"type\": \"ColorRect\", \"name\": \"${name}\", \"pos\": [0, 0], \"size\": [32, 16], \"color\": {\"r\": 1, \"g\": 1, \"b\": 1}}"}
          : NodeTypeDef) ::
        ({typeName = "Marker2D", addable = true,
          defaultJson = name ->
            "{\"type\": \"Marker2D\", \"name\": \"${name}\", \"pos\": [0, 0]}"}
          : NodeTypeDef) ::
        Nil

    /// Add Child Node メニューに並べる型名（addable のものを定義順で）。
    pub def addableTypeNames(): List[String] =
        entries() |> List.filter(d -> d#addable) |> List.map(d -> d#typeName)

    /// 指定型の既定 JSON 断片。未知型は Marker2D エントリへフォールバック（旧 defaultChildJson と同挙動）。
    /// フォールバックも Marker2D エントリを引くので Marker2D の JSON リテラルは1箇所のみ。
    pub def defaultJsonFor(typeName: String, name: String): String =
        let lookup = t -> List.find(d -> d#typeName == t, entries());
        match lookup(typeName) {
            case Some(d) => (d#defaultJson)(name)
            case None    => match lookup("Marker2D") {
                case Some(m) => (m#defaultJson)(name)
                case None    => "{\"type\": \"Marker2D\", \"name\": \"${name}\", \"pos\": [0, 0]}"
            }
        }
}
