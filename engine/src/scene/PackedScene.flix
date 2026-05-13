/// PackedScene — 「シーンのテンプレート」を表す型（Godot PackedScene 相当）
///
/// JSON ファイルを 1 回読んでパースし、得られた JSON ルートをテンプレートとして保持する。
/// `instantiate` で何度でも独立したインスタンスを scene に追加できる。
///
/// インスタンスごとに root の name / position をオーバーライドできるため、
/// 同じテンプレートを別座標・別名で N 個生成するのに使う。
/// 動的タグ（`Mob({mobId})` のような実行時可変フィールド）は instantiate 後に
/// `Scene.setState` で上書きする運用（既存 BirdScene.addBird パターン）。
///
/// 失敗時は `bug!` でクラッシュ（既存 SceneLoader.loadScene と同じポリシー）。
///
/// 使い方:
///   let template = PackedScene.load("src/scenes/Pipe.scene.json");
///   PackedScene.instantiate({
///       opts = {parentPath = Nil, nameOverride = Some("pipe_0"),
///               positionOverride = Some({x = 100.0, y = 0.0})},
///       tagParser = Game.parseNodeTag,
///       template = template,
///       fontAtlas = None,
///       scene = scene
///   })
///
pub enum PackedScene {
    case PackedScene({
        sourcePath = String,           // デバッグ用ファイルパス（bug! メッセージで使う）
        rootJson = Json.JsonElement    // パース済み JSON（再パース不要）
    })
}

/// PackedScene.instantiate のオプション（ルートノードの上書き）
pub type alias InstantiateOpts = {
    parentPath = NodePath,                  // どこに挿入するか (Nil = ルート)
    nameOverride = Option[NodeName],        // ルートノード name の上書き
    positionOverride = Option[Vec2.Vec2]    // ルートノード pos の上書き
}

/// PackedScene.fromJsonString 用引数
pub type alias FromJsonStringArgs = {
    source = String,        // デバッグ用ラベル
    jsonText = String       // JSON 本体
}

/// PackedScene.instantiate 用引数
/// fontAtlas は Label2D を含むテンプレートのとき Some(...) を指定する
pub type alias InstantiateArgs[t] = {
    opts = InstantiateOpts,
    tagParser = Option[String] -> Result[Json.JsonError, t],
    template = PackedScene,
    fontAtlas = Option[FontAtlas],
    scene = Scene[t]
}

mod PackedScene {

    // ========================================================================
    // 構築
    // ========================================================================

    /// JSON ファイルを 1 回読み込んでパースし、テンプレートとして保持する。
    /// 失敗時 bug! でクラッシュ。
    pub def load(path: String): PackedScene \ Fs.FileRead =
        let content = run { Fs.ReadFile.read(path) } with Fs.ReadFile.runWithFileRead;
        match content {
            case Err(msg) => bug!("PackedScene.load: ${path}: failed to read: ${msg}")
            case Ok(text) =>
                match Json.Parse.parse(String.trim(text)) {
                    case None       => bug!("PackedScene.load: ${path}: JSON parse failed")
                    case Some(json) =>
                        PackedScene.PackedScene({sourcePath = path, rootJson = json})
                }
        }

    /// JSON 文字列から直接構築（テスト・動的生成用）。
    /// 失敗時 bug!。
    pub def fromJsonString(args: FromJsonStringArgs): PackedScene =
        match Json.Parse.parse(String.trim(args#jsonText)) {
            case None       => bug!("PackedScene.fromJsonString: ${args#source}: JSON parse failed")
            case Some(json) =>
                PackedScene.PackedScene({sourcePath = args#source, rootJson = json})
        }

    /// デフォルト opts (parentPath=Nil, override 無し)
    pub def defaultOpts(): InstantiateOpts =
        {parentPath = Nil, nameOverride = None, positionOverride = None}

    // ========================================================================
    // インスタンス化
    // ========================================================================

    /// PackedScene を scene にインスタンス化する。
    /// 同じ PackedScene を異なる nameOverride で N 回呼べば独立した N インスタンスができる。
    /// Label2D を含むテンプレートには args#fontAtlas に Some(...) を渡すこと。
    pub def instantiate(args: InstantiateArgs[t]): Scene[t] \ {GameEngine.Game, Fs.FileRead} =
        let PackedScene.PackedScene(r) = args#template;
        let json = r#rootJson
            |> applyNameOverride(args#opts#nameOverride)
            |> applyPositionOverride(args#opts#positionOverride);
        match SceneLoader.addJsonAt(args#opts#parentPath, args#tagParser,
                                     args#fontAtlas, json, args#scene) {
            case Ok(s)  => s
            case Err(e) =>
                let Json.JsonError.JsonError(p, expected) = e;
                bug!("PackedScene.instantiate: ${r#sourcePath}: at ${p}: expected ${expected}")
        }

    // ========================================================================
    // 内部ヘルパー
    // ========================================================================

    def applyNameOverride(nameOpt: Option[NodeName],
                            json: Json.JsonElement): Json.JsonElement =
        match nameOpt {
            case None       => json
            case Some(name) => SceneLoader.withRootName(name, json)
        }

    def applyPositionOverride(posOpt: Option[Vec2.Vec2],
                                json: Json.JsonElement): Json.JsonElement =
        match posOpt {
            case None      => json
            case Some(pos) => SceneLoader.withRootPosition(pos, json)
        }
}
