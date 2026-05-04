// SceneLoader — JSON ファイルからシーンツリーを構築する
//
// JSON のルートは単一オブジェクト or 配列を受け付ける。
// 配列の場合は各要素を独立したルートノードとして scene に addNode する。
// オブジェクトの場合は単一ルートノードとして addNode し、その children を再帰的に追加する。
//
// タグ変換は呼び出し側が `tagParser` として渡す。SceneLoader はタグの中身を知らない。
// 各ゲームは自身の NodeTag に応じた tagParser を定義して渡すこと。
//
// Label2D を含むシーンは loadSceneWithFont を使う（FontAtlas が必要）。
// それ以外は loadScene を使う。
//
// 対応ノード型:
//   CanvasLayer / Sprite2D / AnimatedSprite2D / Label2D / TextureButton /
//   StaticBody2D / RigidBody2D / Area2D
// 対応 collision shape: RectShape2D / CircleShape2D

mod SceneLoader {
    use Json.JsonElement.{JsonObject, JsonArray}
    use Json.JsonError.JsonError
    use Json.Path.Path.Root

    // ========================================================================
    // 公開 API
    // ========================================================================

    /// JSON ファイルを読み込み、scene にノードツリーを追加して返す。
    /// tagParser: JSON の "tag" 文字列（None = キーなし）をゲーム固有の t に変換する関数。
    /// Label2D を含む JSON では loadSceneWithFont を使うこと（FontAtlas が必須）。
    /// 失敗時は bug! でクラッシュする
    pub def loadScene(path: String, tagParser: Option[String] -> Result[Json.JsonError, t],
                      scene: Scene[t]): Scene[t] \ Fs.FileRead =
        loadSceneCore(path, tagParser, None, scene)

    /// FontAtlas 付きで JSON ファイルを読み込む（Label2D を含むシーン用）。
    /// その他は loadScene と同じ振る舞い
    pub def loadSceneWithFont(path: String, fontAtlas: FontAtlas,
                              tagParser: Option[String] -> Result[Json.JsonError, t],
                              scene: Scene[t]): Scene[t] \ Fs.FileRead =
        loadSceneCore(path, tagParser, Some(fontAtlas), scene)

    // ========================================================================
    // 内部実装
    // ========================================================================

    def loadSceneCore(path: String, tagParser: Option[String] -> Result[Json.JsonError, t],
                      fontAtlas: Option[FontAtlas],
                      scene: Scene[t]): Scene[t] \ Fs.FileRead =
        let content = run { Fs.ReadFile.read(path) } with Fs.ReadFile.runWithFileRead;
        let result = forM (
            text     <- content |> Result.mapErr(e -> "failed to read: ${e}");
            json     <- Json.Parse.parse(String.trim(text)) |> Option.toOk("JSON parse failed");
            outScene <- addJsonAtTop(tagParser, fontAtlas, json, scene)
                |> Result.mapErr(match JsonError(p, expected) ->
                    "at ${p}: expected ${expected}")
        ) yield outScene;
        match result {
            case Ok(s)    => s
            case Err(msg) => bug!("SceneLoader: ${path}: ${msg}")
        }

    // ========================================================================
    // JSON → Scene 変換
    // ========================================================================

    def addJsonAtTop(tagParser: Option[String] -> Result[Json.JsonError, t],
                     fontAtlas: Option[FontAtlas], json: Json.JsonElement,
                     scene: Scene[t]): Result[Json.JsonError, Scene[t]] =
        match json {
            case JsonObject(_)  => addJsonAt(Nil, tagParser, fontAtlas, json, scene)
            case JsonArray(arr) =>
                List.foldLeft(
                    (acc, child) -> Result.flatMap(s -> addJsonAt(Nil, tagParser, fontAtlas, child, s), acc),
                    Ok(scene),
                    Vector.toList(arr))
            case _ => Err(JsonError(Root, Set#{"JsonObject or JsonArray"}))
        }

    def addJsonAt(parentPath: NodePath, tagParser: Option[String] -> Result[Json.JsonError, t],
                  fontAtlas: Option[FontAtlas], json: Json.JsonElement,
                  scene: Scene[t]): Result[Json.JsonError, Scene[t]] =
        match json {
            case JsonObject(map) =>
                forM (
                    nodeType   <- (Json.getAtKey(Root, "type", map): Result[Json.JsonError, String]);
                    name       <- (Json.getAtKey(Root, "name", map): Result[Json.JsonError, String]);
                    engineNode <- buildByType(tagParser, nodeType, fontAtlas, map);
                    groups     <- parseGroups(map);
                    outScene   <- {
                        let nodePath = parentPath ::: name :: Nil;
                        let added = addAt(parentPath, name, engineNode, scene)
                            |> applyGroups(nodePath, groups);
                        addChildren(nodePath, tagParser, fontAtlas, map, added)
                    }
                ) yield outScene
            case _ => Err(JsonError(Root, Set#{"JsonObject"}))
        }

    def addAt(parentPath: NodePath, name: String, engineNode: EngineNode[t],
              scene: Scene[t]): Scene[t] =
        match parentPath {
            case Nil => Scene.addNode(name, engineNode, scene)
            case _   => Scene.addChildAt(parentPath, name, engineNode, scene)
        }

    def addChildren(parentPath: NodePath, tagParser: Option[String] -> Result[Json.JsonError, t],
                    fontAtlas: Option[FontAtlas], map: Map[String, Json.JsonElement],
                    scene: Scene[t]): Result[Json.JsonError, Scene[t]] =
        match Map.get("children", map) {
            case None                 => Ok(scene)
            case Some(JsonArray(arr)) =>
                List.foldLeft(
                    (acc, child) -> Result.flatMap(s -> addJsonAt(parentPath, tagParser, fontAtlas, child, s), acc),
                    Ok(scene),
                    Vector.toList(arr))
            case Some(_) => Err(JsonError(Root, Set#{"JsonArray"}))
        }

    def applyGroups(path: NodePath, groups: List[String], scene: Scene[t]): Scene[t] =
        List.foldLeft((acc, group) -> Scene.addToGroup(path, group, acc), scene, groups)

    // ========================================================================
    // ノード型ディスパッチ
    // ========================================================================

    def buildByType(tagParser: Option[String] -> Result[Json.JsonError, t],
                    nodeType: String, fontAtlas: Option[FontAtlas],
                    map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[t]] =
        match nodeType {
            case "CanvasLayer"      => buildCanvasLayer(tagParser, map)
            case "Sprite2D"         => buildSprite2D(tagParser, map)
            case "TextureButton"    => buildTextureButton(tagParser, map)
            case "StaticBody2D"     => buildStaticBody2D(tagParser, map)
            case "Label2D"          => buildLabel2D(tagParser, fontAtlas, map)
            case "RigidBody2D"      => buildRigidBody2D(tagParser, map)
            case "Area2D"           => buildArea2D(tagParser, map)
            case "AnimatedSprite2D" => buildAnimatedSprite2D(tagParser, map)
            case unknown            =>
                Err(JsonError(Root, Set#{"known node type (got: ${unknown})"}))
        }

    // ========================================================================
    // 共通フィールドの解析
    // ========================================================================

    def parseVec2(key: String,
                  map: Map[String, Json.JsonElement]): Result[Json.JsonError, Vec2.Vec2] =
        forM (
            pair <- (Json.getAtKey(Root, key, map): Result[Json.JsonError, (Float64, Float64)])
        ) yield {
            let (x, y) = pair;
            {x = x, y = y}
        }

    def parseVec2Opt(key: String,
                     map: Map[String, Json.JsonElement]): Result[Json.JsonError, Option[Vec2.Vec2]] =
        forM (
            opt <- (Json.getAtKeyOpt(Root, key, map): Result[Json.JsonError, Option[(Float64, Float64)]])
        ) yield match opt {
            case Some((x, y)) => Some({x = x, y = y})
            case None         => None
        }

    /// "tag" フィールドを tagParser で変換する。キーがなければ None を渡す
    def parseTagField(tagParser: Option[String] -> Result[Json.JsonError, t],
                      map: Map[String, Json.JsonElement]): Result[Json.JsonError, t] =
        forM (
            tagOpt <- (Json.getAtKeyOpt(Root, "tag", map): Result[Json.JsonError, Option[String]]);
            tag    <- tagParser(tagOpt)
        ) yield tag

    def parseGroups(map: Map[String, Json.JsonElement]): Result[Json.JsonError, List[String]] =
        forM (
            opt <- (Json.getAtKeyOpt(Root, "groups", map): Result[Json.JsonError, Option[List[String]]])
        ) yield Option.getWithDefault(Nil, opt)

    def parseShape(map: Map[String, Json.JsonElement]): Result[Json.JsonError, CollisionShape2D] =
        forM (
            shapeMap <- (Json.getAtKey(Root, "shape", map): Result[Json.JsonError, Map[String, Json.JsonElement]]);
            kind     <- (Json.getAtKey(Root, "kind", shapeMap): Result[Json.JsonError, String]);
            shape    <- buildShape(kind, shapeMap)
        ) yield shape

    def buildShape(kind: String,
                   map: Map[String, Json.JsonElement]): Result[Json.JsonError, CollisionShape2D] =
        match kind {
            case "RectShape2D" =>
                forM (
                    width  <- (Json.getAtKey(Root, "width", map): Result[Json.JsonError, Float64]);
                    height <- (Json.getAtKey(Root, "height", map): Result[Json.JsonError, Float64])
                ) yield CollisionShape2D.RectShape2D({width = width, height = height})
            case "CircleShape2D" =>
                forM (
                    radius <- (Json.getAtKey(Root, "radius", map): Result[Json.JsonError, Float64])
                ) yield CollisionShape2D.CircleShape2D({radius = radius})
            case unknown =>
                Err(JsonError(Root, Set#{"known shape kind (got: ${unknown})"}))
        }

    // ========================================================================
    // ノード型ビルダー
    // ========================================================================

    def buildCanvasLayer(tagParser: Option[String] -> Result[Json.JsonError, t],
                         map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[t]] =
        forM (
            tag       <- parseTagField(tagParser, map);
            drawLayer <- (Json.getAtKey(Root, "layer", map): Result[Json.JsonError, Int32])
        ) yield EngineNode.CanvasLayerWithState(CanvasLayer.make(drawLayer), tag)

    def buildSprite2D(tagParser: Option[String] -> Result[Json.JsonError, t],
                      map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[t]] =
        forM (
            tag        <- parseTagField(tagParser, map);
            pos        <- parseVec2("pos", map);
            scale      <- parseVec2("scale", map);
            texture    <- (Json.getAtKey(Root, "texture", map): Result[Json.JsonError, String]);
            zIndexOpt  <- (Json.getAtKeyOpt(Root, "zIndex", map): Result[Json.JsonError, Option[Int32]]);
            visibleOpt <- (Json.getAtKeyOpt(Root, "visible", map): Result[Json.JsonError, Option[Bool]])
        ) yield {
            let sprite = Sprite2D.make(texture, pos, scale)
                |> applyZIndex(zIndexOpt)
                |> applyVisible(visibleOpt);
            EngineNode.Sprite2DWithState(sprite, tag)
        }

    def buildTextureButton(tagParser: Option[String] -> Result[Json.JsonError, t],
                           map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[t]] =
        forM (
            tag               <- parseTagField(tagParser, map);
            pos               <- parseVec2("pos", map);
            scale             <- parseVec2("scale", map);
            size              <- parseVec2("size", map);
            textureNormal     <- (Json.getAtKey(Root, "textureNormal", map): Result[Json.JsonError, String]);
            texturePressedOpt <- (Json.getAtKeyOpt(Root, "texturePressed", map): Result[Json.JsonError, Option[String]]);
            centeredOpt       <- (Json.getAtKeyOpt(Root, "centered", map): Result[Json.JsonError, Option[Bool]]);
            visibleOpt        <- (Json.getAtKeyOpt(Root, "visible", map): Result[Json.JsonError, Option[Bool]])
        ) yield {
            let button = TextureButton.make(textureNormal, size)
                |> Node2D.setPosition(pos)
                |> Node2D.setScale(scale)
                |> applyTexturePressed(texturePressedOpt)
                |> applyCentered(centeredOpt)
                |> applyButtonVisible(visibleOpt);
            EngineNode.TextureButtonWithState(button, tag)
        }

    def buildStaticBody2D(tagParser: Option[String] -> Result[Json.JsonError, t],
                          map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[t]] =
        forM (
            tag   <- parseTagField(tagParser, map);
            pos   <- parseVec2("pos", map);
            shape <- parseShape(map)
        ) yield EngineNode.StaticBody2DWithState(StaticBody2D.make(pos, shape), tag)

    def buildRigidBody2D(tagParser: Option[String] -> Result[Json.JsonError, t],
                         map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[t]] =
        forM (
            tag               <- parseTagField(tagParser, map);
            pos               <- parseVec2("pos", map);
            shape             <- parseShape(map);
            gravityScaleOpt   <- (Json.getAtKeyOpt(Root, "gravityScale", map): Result[Json.JsonError, Option[Float64]]);
            linearVelocityOpt <- parseVec2Opt("linearVelocity", map)
        ) yield {
            let body = RigidBody2D.make(pos, shape)
                |> applyGravityScale(gravityScaleOpt)
                |> applyLinearVelocity(linearVelocityOpt);
            EngineNode.RigidBody2DWithState(body, tag)
        }

    def buildArea2D(tagParser: Option[String] -> Result[Json.JsonError, t],
                    map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[t]] =
        forM (
            tag           <- parseTagField(tagParser, map);
            pos           <- parseVec2("pos", map);
            shape         <- parseShape(map);
            monitoringOpt <- (Json.getAtKeyOpt(Root, "monitoring", map): Result[Json.JsonError, Option[Bool]])
        ) yield {
            let area = Area2D.make(pos, shape)
                |> applyMonitoring(monitoringOpt);
            EngineNode.Area2DWithState(area, tag)
        }

    /// JSON の 1 アニメーション定義を SpriteFrames.Animation に変換する
    def parseAnimation(animMap: Map[String, Json.JsonElement]):
                        Result[Json.JsonError, SpriteFrames.Animation] =
        forM (
            loops      <- (Json.getAtKey(Root, "loop", animMap): Result[Json.JsonError, Bool]);
            speed      <- (Json.getAtKey(Root, "speed", animMap): Result[Json.JsonError, Float64]);
            frameMaps  <- (Json.getAtKey(Root, "frames", animMap):
                            Result[Json.JsonError, List[Map[String, Json.JsonElement]]]);
            frames     <- Result.traverse(parseFrame, frameMaps)
        ) yield ({loop = loops, speed = speed, frames = frames}: SpriteFrames.Animation)

    /// JSON の 1 フレーム定義を SpriteFrames.Frame に変換する。duration は任意（デフォルト 1.0）
    def parseFrame(frameMap: Map[String, Json.JsonElement]):
                    Result[Json.JsonError, SpriteFrames.Frame] =
        forM (
            texture     <- (Json.getAtKey(Root, "texture", frameMap): Result[Json.JsonError, String]);
            durationOpt <- (Json.getAtKeyOpt(Root, "duration", frameMap):
                             Result[Json.JsonError, Option[Float64]])
        ) yield ({texture = texture,
                  duration = Option.getWithDefault(1.0, durationOpt)}: SpriteFrames.Frame)

    /// JSON の spriteFrames オブジェクトを SpriteFrames リソースに変換する
    def parseSpriteFrames(sfMap: Map[String, Json.JsonElement]):
                           Result[Json.JsonError, SpriteFrames] =
        Map.toList(sfMap)
            |> List.foldLeft((acc, pair) ->
                let (name, json) = pair;
                forM (
                    sf       <- acc;
                    animMap  <- match json {
                        case JsonObject(m) => Ok(m)
                        case _             => Err(JsonError(Root, Set#{"JsonObject for animation '${name}'"}))
                    };
                    anim     <- parseAnimation(animMap)
                ) yield SpriteFrames.addAnimation(name, anim, sf),
                Ok(SpriteFrames.empty()))

    def buildAnimatedSprite2D(tagParser: Option[String] -> Result[Json.JsonError, t],
                               map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[t]] =
        forM (
            tag            <- parseTagField(tagParser, map);
            pos            <- parseVec2("pos", map);
            scale          <- parseVec2("scale", map);
            sfMap          <- (Json.getAtKey(Root, "spriteFrames", map):
                                Result[Json.JsonError, Map[String, Json.JsonElement]]);
            spriteFrames   <- parseSpriteFrames(sfMap);
            animation      <- (Json.getAtKey(Root, "animation", map): Result[Json.JsonError, String]);
            autoplayOpt    <- (Json.getAtKeyOpt(Root, "autoplay", map):
                                Result[Json.JsonError, Option[String]]);
            speedScaleOpt  <- (Json.getAtKeyOpt(Root, "speedScale", map):
                                Result[Json.JsonError, Option[Float64]])
        ) yield {
            let sprite = AnimatedSprite2D.make(spriteFrames, {animation = animation}, pos, scale)
                |> AnimatedSprite2D.setAutoplay(Option.getWithDefault("", autoplayOpt))
                |> AnimatedSprite2D.setSpeedScale(Option.getWithDefault(1.0, speedScaleOpt));
            EngineNode.AnimSprite2DWithState(sprite, tag)
        }

    def buildLabel2D(tagParser: Option[String] -> Result[Json.JsonError, t],
                     fontAtlas: Option[FontAtlas],
                     map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[t]] =
        match fontAtlas {
            case None => Err(JsonError(Root, Set#{"FontAtlas (loadSceneWithFont required for Label2D)"}))
            case Some(font) =>
                forM (
                    tag        <- parseTagField(tagParser, map);
                    text       <- (Json.getAtKey(Root, "text", map): Result[Json.JsonError, String]);
                    pos        <- parseVec2("pos", map);
                    fontSize   <- (Json.getAtKey(Root, "fontSize", map): Result[Json.JsonError, Float64]);
                    hAlignOpt  <- (Json.getAtKeyOpt(Root, "horizontalAlignment", map):
                                     Result[Json.JsonError, Option[String]]);
                    vAlignOpt  <- (Json.getAtKeyOpt(Root, "verticalAlignment", map):
                                     Result[Json.JsonError, Option[String]]);
                    hAlign     <- parseHorizontalAlignment(hAlignOpt);
                    vAlign     <- parseVerticalAlignment(vAlignOpt);
                    visibleOpt <- (Json.getAtKeyOpt(Root, "visible", map): Result[Json.JsonError, Option[Bool]]);
                    zIndexOpt  <- (Json.getAtKeyOpt(Root, "zIndex", map): Result[Json.JsonError, Option[Int32]])
                ) yield {
                    let label = Label2D.make(text, font, fontSize)
                        |> Node2D.setPosition(pos)
                        |> Label2D.setHorizontalAlignment(hAlign)
                        |> Label2D.setVerticalAlignment(vAlign)
                        |> applyLabelVisible(visibleOpt)
                        |> applyLabelZIndex(zIndexOpt);
                    EngineNode.Label2DWithState(label, tag)
                }
        }

    /// JSON の文字列を HorizontalAlignment に変換する。省略時は Left
    def parseHorizontalAlignment(opt: Option[String]): Result[Json.JsonError, HorizontalAlignment] =
        match opt {
            case None           => Ok(HorizontalAlignment.Left)
            case Some("left")   => Ok(HorizontalAlignment.Left)
            case Some("center") => Ok(HorizontalAlignment.Center)
            case Some("right")  => Ok(HorizontalAlignment.Right)
            case Some("fill")   => Ok(HorizontalAlignment.Fill)
            case Some(other)    =>
                Err(JsonError(Root, Set#{"left|center|right|fill (got: ${other})"}))
        }

    /// JSON の文字列を VerticalAlignment に変換する。省略時は Top
    def parseVerticalAlignment(opt: Option[String]): Result[Json.JsonError, VerticalAlignment] =
        match opt {
            case None           => Ok(VerticalAlignment.Top)
            case Some("top")    => Ok(VerticalAlignment.Top)
            case Some("center") => Ok(VerticalAlignment.Center)
            case Some("bottom") => Ok(VerticalAlignment.Bottom)
            case Some("fill")   => Ok(VerticalAlignment.Fill)
            case Some(other)    =>
                Err(JsonError(Root, Set#{"top|center|bottom|fill (got: ${other})"}))
        }

    // ========================================================================
    // ビルダー用ヘルパー（任意フィールド適用）
    // ========================================================================

    def applyZIndex(opt: Option[Int32], sprite: Sprite2D): Sprite2D =
        match opt {
            case Some(zIndex) => CanvasItem.setZIndex(zIndex, sprite)
            case None         => sprite
        }

    def applyVisible(opt: Option[Bool], sprite: Sprite2D): Sprite2D =
        match opt {
            case Some(visible) => CanvasItem.setVisible(visible, sprite)
            case None          => sprite
        }

    def applyTexturePressed(opt: Option[String], button: TextureButton): TextureButton =
        match opt {
            case Some(tex) => TextureButton.setTexturePressed(tex, button)
            case None      => button
        }

    def applyCentered(opt: Option[Bool], button: TextureButton): TextureButton =
        match opt {
            case Some(centered) => TextureButton.setCentered(centered, button)
            case None           => button
        }

    def applyButtonVisible(opt: Option[Bool], button: TextureButton): TextureButton =
        match opt {
            case Some(visible) => CanvasItem.setVisible(visible, button)
            case None          => button
        }

    def applyLabelVisible(opt: Option[Bool], label: Label2D): Label2D =
        match opt {
            case Some(visible) => CanvasItem.setVisible(visible, label)
            case None          => label
        }

    def applyLabelZIndex(opt: Option[Int32], label: Label2D): Label2D =
        match opt {
            case Some(zIndex) => CanvasItem.setZIndex(zIndex, label)
            case None         => label
        }

    def applyGravityScale(opt: Option[Float64], body: RigidBody2D): RigidBody2D =
        match opt {
            case Some(scale) => RigidBody2D.setGravityScale(scale, body)
            case None        => body
        }

    def applyLinearVelocity(opt: Option[Vec2.Vec2], body: RigidBody2D): RigidBody2D =
        match opt {
            case Some(vel) => RigidBody2D.setLinearVelocity(vel, body)
            case None      => body
        }

    def applyMonitoring(opt: Option[Bool], area: Area2D): Area2D =
        match opt {
            case Some(monitoring) => Area2D.setMonitoring(monitoring, area)
            case None             => area
        }
}
