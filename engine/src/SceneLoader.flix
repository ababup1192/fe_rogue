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
//   StaticBody2D / RigidBody2D / Area2D / CharacterBody2D / Marker2D /
//   Camera2D / TileMapLayer / ColorRect / RichTextLabel
// 対応 collision shape: RectShape2D / CircleShape2D
//
// 注:
//   TileMapLayer は LDTKLoader 経由で `.ldtkl` を読むため GameEngine.Game eff を要求する。
//   このため loadScene 全体の eff に GameEngine.Game が含まれる（TileMapLayer を使わない
//   JSON では実質 no-op）。

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
    /// TileMapLayer を含む JSON では LDTKLoader が GameEngine.Game eff を要求するため
    /// 呼び出し側もそのスコープから呼ぶ必要がある。
    /// 失敗時は bug! でクラッシュする
    pub def loadScene(path: String, tagParser: Option[String] -> Result[Json.JsonError, t],
                      scene: Scene[t]): Scene[t] \ {GameEngine.Game, Fs.FileRead} =
        loadSceneCore(path, tagParser, None, scene)

    /// FontAtlas 付きで JSON ファイルを読み込む（Label2D を含むシーン用）。
    /// その他は loadScene と同じ振る舞い
    pub def loadSceneWithFont(path: String, fontAtlas: FontAtlas,
                              tagParser: Option[String] -> Result[Json.JsonError, t],
                              scene: Scene[t]): Scene[t] \ {GameEngine.Game, Fs.FileRead} =
        loadSceneCore(path, tagParser, Some(fontAtlas), scene)

    /// JSON 側のタグ文字列を無視し、常に与えた値を返す tagParser を作る。
    /// scene.json 側にタグ情報を載せない（= ロード後に Scene.setState で個別注入する）
    /// 方針のシーンで使う標準ヘルパー。
    pub def constTagParser(tag: t): Option[String] -> Result[Json.JsonError, t] =
        _ -> Ok(tag)

    // ========================================================================
    // 内部実装
    // ========================================================================

    def loadSceneCore(path: String, tagParser: Option[String] -> Result[Json.JsonError, t],
                      fontAtlas: Option[FontAtlas],
                      scene: Scene[t]): Scene[t] \ {GameEngine.Game, Fs.FileRead} =
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
                     scene: Scene[t]): Result[Json.JsonError, Scene[t]] \ {GameEngine.Game, Fs.FileRead} =
        match json {
            case JsonObject(_)  => addJsonAt(Nil, tagParser, fontAtlas, json, scene)
            case JsonArray(arr) =>
                List.foldLeft(
                    (acc, child) -> match acc {
                        case Err(e) => Err(e)
                        case Ok(s)  => addJsonAt(Nil, tagParser, fontAtlas, child, s)
                    },
                    Ok(scene),
                    Vector.toList(arr))
            case _ => Err(JsonError(Root, Set#{"JsonObject or JsonArray"}))
        }

    def addJsonAt(parentPath: NodePath, tagParser: Option[String] -> Result[Json.JsonError, t],
                  fontAtlas: Option[FontAtlas], json: Json.JsonElement,
                  scene: Scene[t]): Result[Json.JsonError, Scene[t]] \ {GameEngine.Game, Fs.FileRead} =
        match json {
            case JsonObject(map) =>
                let header = forM (
                    nodeType   <- (Json.FromJson.getAtKey(Root, "type", map): Result[Json.JsonError, String]);
                    name       <- (Json.FromJson.getAtKey(Root, "name", map): Result[Json.JsonError, String]);
                    groups     <- parseGroups(map)
                ) yield (nodeType, name, groups);
                match header {
                    case Err(e) => Err(e)
                    case Ok((nodeType, name, groups)) =>
                        match buildByType(tagParser, nodeType, fontAtlas, map) {
                            case Err(e) => Err(e)
                            case Ok(engineNode) =>
                                let nodePath = parentPath ::: name :: Nil;
                                let added = addAt(parentPath, name, engineNode, scene)
                                    |> applyGroups(nodePath, groups);
                                addChildren(nodePath, tagParser, fontAtlas, map, added)
                        }
                }
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
                    scene: Scene[t]): Result[Json.JsonError, Scene[t]] \ {GameEngine.Game, Fs.FileRead} =
        match Map.get("children", map) {
            case None                 => Ok(scene)
            case Some(JsonArray(arr)) =>
                List.foldLeft(
                    (acc, child) -> match acc {
                        case Err(e) => Err(e)
                        case Ok(s)  => addJsonAt(parentPath, tagParser, fontAtlas, child, s)
                    },
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
                    map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[t]] \ {GameEngine.Game, Fs.FileRead} =
        match nodeType {
            case "TileMapLayer" => buildTileMapLayer(tagParser, map)
            case other          => checked_ecast(buildPureNodeType(tagParser, other, fontAtlas, map))
        }

    /// `TileMapLayer` を除く、副作用を持たないビルダーへのディスパッチ。
    /// 関数 1 つあたりの case が増えると Flix の型推論が破綻するため、
    /// `buildByType` から effectful な `TileMapLayer` を分離して残りをまとめる。
    def buildPureNodeType(tagParser: Option[String] -> Result[Json.JsonError, t],
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
            case "CharacterBody2D"  => buildCharacterBody2D(tagParser, map)
            case "Marker2D"         => buildMarker2D(tagParser, map)
            case "Camera2D"         => buildCamera2D(tagParser, map)
            case "ColorRect"        => buildColorRect(tagParser, map)
            case "RichTextLabel"    => buildRichTextLabel(tagParser, fontAtlas, map)
            case unknown            =>
                Err(JsonError(Root, Set#{"known node type (got: ${unknown})"}))
        }

    // ========================================================================
    // 共通フィールドの解析
    // ========================================================================

    def parseVec2(key: String,
                  map: Map[String, Json.JsonElement]): Result[Json.JsonError, Vec2.Vec2] =
        forM (
            pair <- (Json.FromJson.getAtKey(Root, key, map): Result[Json.JsonError, (Float64, Float64)])
        ) yield {
            let (x, y) = pair;
            {x = x, y = y}
        }

    def parseVec2Opt(key: String,
                     map: Map[String, Json.JsonElement]): Result[Json.JsonError, Option[Vec2.Vec2]] =
        forM (
            opt <- (Json.FromJson.getAtKeyOpt(Root, key, map): Result[Json.JsonError, Option[(Float64, Float64)]])
        ) yield match opt {
            case Some((x, y)) => Some({x = x, y = y})
            case None         => None
        }

    /// "tag" フィールドを tagParser で変換する。キーがなければ None を渡す
    def parseTagField(tagParser: Option[String] -> Result[Json.JsonError, t],
                      map: Map[String, Json.JsonElement]): Result[Json.JsonError, t] =
        forM (
            tagOpt <- (Json.FromJson.getAtKeyOpt(Root, "tag", map): Result[Json.JsonError, Option[String]]);
            tag    <- tagParser(tagOpt)
        ) yield tag

    def parseGroups(map: Map[String, Json.JsonElement]): Result[Json.JsonError, List[String]] =
        forM (
            opt <- (Json.FromJson.getAtKeyOpt(Root, "groups", map): Result[Json.JsonError, Option[List[String]]])
        ) yield Option.getWithDefault(Nil, opt)

    def parseShape(map: Map[String, Json.JsonElement]): Result[Json.JsonError, CollisionShape2D] =
        forM (
            shapeMap <- (Json.FromJson.getAtKey(Root, "shape", map): Result[Json.JsonError, Map[String, Json.JsonElement]]);
            kind     <- (Json.FromJson.getAtKey(Root, "kind", shapeMap): Result[Json.JsonError, String]);
            shape    <- buildShape(kind, shapeMap)
        ) yield shape

    def buildShape(kind: String,
                   map: Map[String, Json.JsonElement]): Result[Json.JsonError, CollisionShape2D] =
        match kind {
            case "RectShape2D" =>
                forM (
                    width  <- (Json.FromJson.getAtKey(Root, "width", map): Result[Json.JsonError, Float64]);
                    height <- (Json.FromJson.getAtKey(Root, "height", map): Result[Json.JsonError, Float64])
                ) yield CollisionShape2D.RectShape2D({width = width, height = height})
            case "CircleShape2D" =>
                forM (
                    radius <- (Json.FromJson.getAtKey(Root, "radius", map): Result[Json.JsonError, Float64])
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
            tag         <- parseTagField(tagParser, map);
            drawLayer   <- (Json.FromJson.getAtKey(Root, "layer", map): Result[Json.JsonError, Int32]);
            posOpt      <- parseVec2Opt("pos", map);
            rotationOpt <- (Json.FromJson.getAtKeyOpt(Root, "rotation", map): Result[Json.JsonError, Option[Float64]])
        ) yield {
            let layer = CanvasLayer.make(drawLayer)
                |> applyOpt(posOpt, setCanvasLayerPosition)
                |> applyOpt(rotationOpt, setCanvasLayerRotation);
            EngineNode.CanvasLayerWithState(layer, tag)
        }

    def setCanvasLayerPosition(pos: Vec2.Vec2, layer: CanvasLayer): CanvasLayer =
        Node2D.setPosition(pos, layer)

    def setCanvasLayerRotation(rot: Float64, layer: CanvasLayer): CanvasLayer =
        Node2D.setRotation(rot, layer)

    def buildSprite2D(tagParser: Option[String] -> Result[Json.JsonError, t],
                      map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[t]] =
        forM (
            tag         <- parseTagField(tagParser, map);
            pos         <- parseVec2("pos", map);
            scale       <- parseVec2("scale", map);
            texture     <- (Json.FromJson.getAtKey(Root, "texture", map): Result[Json.JsonError, String]);
            rotationOpt <- (Json.FromJson.getAtKeyOpt(Root, "rotation", map): Result[Json.JsonError, Option[Float64]]);
            skewOpt     <- (Json.FromJson.getAtKeyOpt(Root, "skew", map): Result[Json.JsonError, Option[Float64]]);
            zIndexOpt   <- (Json.FromJson.getAtKeyOpt(Root, "zIndex", map): Result[Json.JsonError, Option[Int32]]);
            visibleOpt  <- (Json.FromJson.getAtKeyOpt(Root, "visible", map): Result[Json.JsonError, Option[Bool]]);
            flipHOpt    <- (Json.FromJson.getAtKeyOpt(Root, "flipH", map): Result[Json.JsonError, Option[Bool]]);
            flipVOpt    <- (Json.FromJson.getAtKeyOpt(Root, "flipV", map): Result[Json.JsonError, Option[Bool]]);
            hframesOpt  <- (Json.FromJson.getAtKeyOpt(Root, "hframes", map): Result[Json.JsonError, Option[Int32]]);
            vframesOpt  <- (Json.FromJson.getAtKeyOpt(Root, "vframes", map): Result[Json.JsonError, Option[Int32]]);
            frameOpt    <- (Json.FromJson.getAtKeyOpt(Root, "frame", map): Result[Json.JsonError, Option[Int32]])
        ) yield {
            let sprite = Sprite2D.make(texture, pos, scale)
                |> applyOpt(rotationOpt, setSpriteRotation)
                |> applyOpt(skewOpt, setSpriteSkew)
                |> applyZIndex(zIndexOpt)
                |> applyVisible(visibleOpt)
                |> applyOpt(flipHOpt, Sprite2D.setFlipH)
                |> applyOpt(flipVOpt, Sprite2D.setFlipV)
                |> applyOpt(hframesOpt, Sprite2D.setHframes)
                |> applyOpt(vframesOpt, Sprite2D.setVframes)
                |> applyOpt(frameOpt, Sprite2D.setFrame);
            EngineNode.Sprite2DWithState(sprite, tag)
        }

    // ── Node2D / CanvasItem 経由のフィールド適用に使う型固定ラッパー ──

    def setSpriteRotation(rot: Float64, sprite: Sprite2D): Sprite2D =
        Node2D.setRotation(rot, sprite)

    def setSpriteSkew(skew: Float64, sprite: Sprite2D): Sprite2D =
        Node2D.setSkew(skew, sprite)

    def buildTextureButton(tagParser: Option[String] -> Result[Json.JsonError, t],
                           map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[t]] =
        forM (
            tag               <- parseTagField(tagParser, map);
            pos               <- parseVec2("pos", map);
            scale             <- parseVec2("scale", map);
            size              <- parseVec2("size", map);
            textureNormal     <- (Json.FromJson.getAtKey(Root, "textureNormal", map): Result[Json.JsonError, String]);
            texturePressedOpt <- (Json.FromJson.getAtKeyOpt(Root, "texturePressed", map): Result[Json.JsonError, Option[String]]);
            centeredOpt       <- (Json.FromJson.getAtKeyOpt(Root, "centered", map): Result[Json.JsonError, Option[Bool]]);
            visibleOpt        <- (Json.FromJson.getAtKeyOpt(Root, "visible", map): Result[Json.JsonError, Option[Bool]])
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
            gravityScaleOpt   <- (Json.FromJson.getAtKeyOpt(Root, "gravityScale", map): Result[Json.JsonError, Option[Float64]]);
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
            monitoringOpt <- (Json.FromJson.getAtKeyOpt(Root, "monitoring", map): Result[Json.JsonError, Option[Bool]])
        ) yield {
            let area = Area2D.make(pos, shape)
                |> applyMonitoring(monitoringOpt);
            EngineNode.Area2DWithState(area, tag)
        }

    /// JSON の 1 アニメーション定義を SpriteFrames.Animation に変換する
    def parseAnimation(animMap: Map[String, Json.JsonElement]):
                        Result[Json.JsonError, SpriteFrames.Animation] =
        forM (
            loops      <- (Json.FromJson.getAtKey(Root, "loop", animMap): Result[Json.JsonError, Bool]);
            speed      <- (Json.FromJson.getAtKey(Root, "speed", animMap): Result[Json.JsonError, Float64]);
            frameMaps  <- (Json.FromJson.getAtKey(Root, "frames", animMap):
                            Result[Json.JsonError, List[Map[String, Json.JsonElement]]]);
            frames     <- Result.traverse(parseFrame, frameMaps)
        ) yield ({loop = loops, speed = speed, frames = frames}: SpriteFrames.Animation)

    /// JSON の 1 フレーム定義を SpriteFrames.Frame に変換する。duration は任意（デフォルト 1.0）
    def parseFrame(frameMap: Map[String, Json.JsonElement]):
                    Result[Json.JsonError, SpriteFrames.Frame] =
        forM (
            texture     <- (Json.FromJson.getAtKey(Root, "texture", frameMap): Result[Json.JsonError, String]);
            durationOpt <- (Json.FromJson.getAtKeyOpt(Root, "duration", frameMap):
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
            sfMap          <- (Json.FromJson.getAtKey(Root, "spriteFrames", map):
                                Result[Json.JsonError, Map[String, Json.JsonElement]]);
            spriteFrames   <- parseSpriteFrames(sfMap);
            animation      <- (Json.FromJson.getAtKey(Root, "animation", map): Result[Json.JsonError, String]);
            autoplayOpt    <- (Json.FromJson.getAtKeyOpt(Root, "autoplay", map):
                                Result[Json.JsonError, Option[String]]);
            speedScaleOpt  <- (Json.FromJson.getAtKeyOpt(Root, "speedScale", map):
                                Result[Json.JsonError, Option[Float64]])
        ) yield {
            let sprite = AnimatedSprite2D.make(spriteFrames, {animation = animation}, pos, scale)
                |> AnimatedSprite2D.setAutoplay(Option.getWithDefault("", autoplayOpt))
                |> AnimatedSprite2D.setSpeedScale(Option.getWithDefault(1.0, speedScaleOpt));
            EngineNode.AnimSprite2DWithState(sprite, tag)
        }

    def buildCharacterBody2D(tagParser: Option[String] -> Result[Json.JsonError, t],
                              map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[t]] =
        forM (
            tag             <- parseTagField(tagParser, map);
            pos             <- parseVec2("pos", map);
            shape           <- parseShape(map);
            moveSpeedOpt    <- (Json.FromJson.getAtKeyOpt(Root, "moveSpeed", map): Result[Json.JsonError, Option[Float64]]);
            velocityOpt     <- parseVec2Opt("velocity", map);
            scaleOpt        <- parseVec2Opt("scale", map);
            rotationOpt     <- (Json.FromJson.getAtKeyOpt(Root, "rotation", map): Result[Json.JsonError, Option[Float64]]);
            skewOpt         <- (Json.FromJson.getAtKeyOpt(Root, "skew", map): Result[Json.JsonError, Option[Float64]]);
            visibleOpt      <- (Json.FromJson.getAtKeyOpt(Root, "visible", map): Result[Json.JsonError, Option[Bool]]);
            zIndexOpt       <- (Json.FromJson.getAtKeyOpt(Root, "zIndex", map): Result[Json.JsonError, Option[Int32]]);
            monitoringOpt   <- (Json.FromJson.getAtKeyOpt(Root, "monitoring", map): Result[Json.JsonError, Option[Bool]]);
            monitorableOpt  <- (Json.FromJson.getAtKeyOpt(Root, "monitorable", map): Result[Json.JsonError, Option[Bool]]);
            priorityOpt     <- (Json.FromJson.getAtKeyOpt(Root, "priority", map): Result[Json.JsonError, Option[Int32]]);
            upDirectionOpt  <- parseVec2Opt("upDirection", map);
            floorMaxAngleOpt <- (Json.FromJson.getAtKeyOpt(Root, "floorMaxAngle", map): Result[Json.JsonError, Option[Float64]]);
            maxSlidesOpt    <- (Json.FromJson.getAtKeyOpt(Root, "maxSlides", map): Result[Json.JsonError, Option[Int32]])
        ) yield {
            let body = CharacterBody2D.make(pos, {moveSpeed = Option.getWithDefault(0.0, moveSpeedOpt)})
                |> CharacterBody2D.setCollisionShape(Some(shape))
                |> applyOpt(velocityOpt, CharacterBody2D.setVelocity)
                |> applyOpt(scaleOpt, setBody2DScale)
                |> applyOpt(rotationOpt, setBody2DRotation)
                |> applyOpt(skewOpt, setBody2DSkew)
                |> applyOpt(visibleOpt, setBody2DVisible)
                |> applyOpt(zIndexOpt, setBody2DZIndex)
                |> applyOpt(monitoringOpt, CharacterBody2D.setMonitoring)
                |> applyOpt(monitorableOpt, CharacterBody2D.setMonitorable)
                |> applyOpt(priorityOpt, CharacterBody2D.setPriority)
                |> applyOpt(upDirectionOpt, CharacterBody2D.setUpDirection)
                |> applyOpt(floorMaxAngleOpt, CharacterBody2D.setFloorMaxAngle)
                |> applyOpt(maxSlidesOpt, CharacterBody2D.setMaxSlides);
            EngineNode.Body2DWithState(body, tag)
        }

    def setBody2DScale(scale: Vec2.Vec2, body: CharacterBody2D): CharacterBody2D =
        Node2D.setScale(scale, body)

    def setBody2DRotation(rot: Float64, body: CharacterBody2D): CharacterBody2D =
        Node2D.setRotation(rot, body)

    def setBody2DSkew(skew: Float64, body: CharacterBody2D): CharacterBody2D =
        Node2D.setSkew(skew, body)

    def setBody2DVisible(v: Bool, body: CharacterBody2D): CharacterBody2D =
        CanvasItem.setVisible(v, body)

    def setBody2DZIndex(z: Int32, body: CharacterBody2D): CharacterBody2D =
        CanvasItem.setZIndex(z, body)

    def buildMarker2D(tagParser: Option[String] -> Result[Json.JsonError, t],
                      map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[t]] =
        forM (
            tag         <- parseTagField(tagParser, map);
            pos         <- parseVec2("pos", map);
            scaleOpt    <- parseVec2Opt("scale", map);
            rotationOpt <- (Json.FromJson.getAtKeyOpt(Root, "rotation", map): Result[Json.JsonError, Option[Float64]]);
            skewOpt     <- (Json.FromJson.getAtKeyOpt(Root, "skew", map): Result[Json.JsonError, Option[Float64]]);
            visibleOpt  <- (Json.FromJson.getAtKeyOpt(Root, "visible", map): Result[Json.JsonError, Option[Bool]]);
            zIndexOpt   <- (Json.FromJson.getAtKeyOpt(Root, "zIndex", map): Result[Json.JsonError, Option[Int32]])
        ) yield {
            let marker = Marker2D.make(pos)
                |> applyOpt(scaleOpt, setMarker2DScale)
                |> applyOpt(rotationOpt, setMarker2DRotation)
                |> applyOpt(skewOpt, setMarker2DSkew)
                |> applyOpt(visibleOpt, setMarker2DVisible)
                |> applyOpt(zIndexOpt, setMarker2DZIndex);
            EngineNode.Marker2DWithState(marker, tag)
        }

    def setMarker2DScale(scale: Vec2.Vec2, marker: Marker2D): Marker2D =
        Node2D.setScale(scale, marker)

    def setMarker2DRotation(rot: Float64, marker: Marker2D): Marker2D =
        Node2D.setRotation(rot, marker)

    def setMarker2DSkew(skew: Float64, marker: Marker2D): Marker2D =
        Node2D.setSkew(skew, marker)

    def setMarker2DVisible(v: Bool, marker: Marker2D): Marker2D =
        CanvasItem.setVisible(v, marker)

    def setMarker2DZIndex(z: Int32, marker: Marker2D): Marker2D =
        CanvasItem.setZIndex(z, marker)

    def buildCamera2D(tagParser: Option[String] -> Result[Json.JsonError, t],
                      map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[t]] =
        forM (
            tag                     <- parseTagField(tagParser, map);
            pos                     <- parseVec2("pos", map);
            offsetOpt               <- parseVec2Opt("offset", map);
            zoomOpt                 <- parseVec2Opt("zoom", map);
            scaleOpt                <- parseVec2Opt("scale", map);
            rotationOpt             <- (Json.FromJson.getAtKeyOpt(Root, "rotation", map): Result[Json.JsonError, Option[Float64]]);
            skewOpt                 <- (Json.FromJson.getAtKeyOpt(Root, "skew", map): Result[Json.JsonError, Option[Float64]]);
            visibleOpt              <- (Json.FromJson.getAtKeyOpt(Root, "visible", map): Result[Json.JsonError, Option[Bool]]);
            zIndexOpt               <- (Json.FromJson.getAtKeyOpt(Root, "zIndex", map): Result[Json.JsonError, Option[Int32]]);
            enabledOpt              <- (Json.FromJson.getAtKeyOpt(Root, "enabled", map): Result[Json.JsonError, Option[Bool]]);
            anchorModeOpt           <- (Json.FromJson.getAtKeyOpt(Root, "anchorMode", map): Result[Json.JsonError, Option[String]]);
            anchorMode              <- parseAnchorMode(anchorModeOpt);
            processCallbackOpt      <- (Json.FromJson.getAtKeyOpt(Root, "processCallback", map): Result[Json.JsonError, Option[String]]);
            processCallback         <- parseProcessCallback(processCallbackOpt);
            ignoreRotationOpt       <- (Json.FromJson.getAtKeyOpt(Root, "ignoreRotation", map): Result[Json.JsonError, Option[Bool]]);
            limitLeftOpt            <- (Json.FromJson.getAtKeyOpt(Root, "limitLeft", map): Result[Json.JsonError, Option[Int32]]);
            limitTopOpt             <- (Json.FromJson.getAtKeyOpt(Root, "limitTop", map): Result[Json.JsonError, Option[Int32]]);
            limitRightOpt           <- (Json.FromJson.getAtKeyOpt(Root, "limitRight", map): Result[Json.JsonError, Option[Int32]]);
            limitBottomOpt          <- (Json.FromJson.getAtKeyOpt(Root, "limitBottom", map): Result[Json.JsonError, Option[Int32]]);
            limitSmoothedOpt        <- (Json.FromJson.getAtKeyOpt(Root, "limitSmoothed", map): Result[Json.JsonError, Option[Bool]]);
            posSmoothEnabledOpt     <- (Json.FromJson.getAtKeyOpt(Root, "positionSmoothingEnabled", map): Result[Json.JsonError, Option[Bool]]);
            posSmoothSpeedOpt       <- (Json.FromJson.getAtKeyOpt(Root, "positionSmoothingSpeed", map): Result[Json.JsonError, Option[Float64]]);
            rotSmoothEnabledOpt     <- (Json.FromJson.getAtKeyOpt(Root, "rotationSmoothingEnabled", map): Result[Json.JsonError, Option[Bool]]);
            rotSmoothSpeedOpt       <- (Json.FromJson.getAtKeyOpt(Root, "rotationSmoothingSpeed", map): Result[Json.JsonError, Option[Float64]]);
            dragHEnabledOpt         <- (Json.FromJson.getAtKeyOpt(Root, "dragHorizontalEnabled", map): Result[Json.JsonError, Option[Bool]]);
            dragVEnabledOpt         <- (Json.FromJson.getAtKeyOpt(Root, "dragVerticalEnabled", map): Result[Json.JsonError, Option[Bool]]);
            dragLeftOpt             <- (Json.FromJson.getAtKeyOpt(Root, "dragLeftMargin", map): Result[Json.JsonError, Option[Float64]]);
            dragRightOpt            <- (Json.FromJson.getAtKeyOpt(Root, "dragRightMargin", map): Result[Json.JsonError, Option[Float64]]);
            dragTopOpt              <- (Json.FromJson.getAtKeyOpt(Root, "dragTopMargin", map): Result[Json.JsonError, Option[Float64]]);
            dragBottomOpt           <- (Json.FromJson.getAtKeyOpt(Root, "dragBottomMargin", map): Result[Json.JsonError, Option[Float64]])
        ) yield {
            let camera = Camera2D.make(pos)
                |> applyOpt(offsetOpt, Camera2D.setOffset)
                |> applyOpt(zoomOpt, Camera2D.setZoom)
                |> applyOpt(scaleOpt, setCameraScale)
                |> applyOpt(rotationOpt, setCameraRotation)
                |> applyOpt(skewOpt, setCameraSkew)
                |> applyOpt(visibleOpt, setCameraVisible)
                |> applyOpt(zIndexOpt, setCameraZIndex)
                |> applyOpt(enabledOpt, Camera2D.setEnabled)
                |> Camera2D.setAnchorMode(anchorMode)
                |> Camera2D.setProcessCallback(processCallback)
                |> applyOpt(ignoreRotationOpt, Camera2D.setIgnoreRotation)
                |> applyOpt(limitLeftOpt, Camera2D.setLimitLeft)
                |> applyOpt(limitTopOpt, Camera2D.setLimitTop)
                |> applyOpt(limitRightOpt, Camera2D.setLimitRight)
                |> applyOpt(limitBottomOpt, Camera2D.setLimitBottom)
                |> applyOpt(limitSmoothedOpt, Camera2D.setLimitSmoothed)
                |> applyOpt(posSmoothEnabledOpt, Camera2D.setPositionSmoothingEnabled)
                |> applyOpt(posSmoothSpeedOpt, Camera2D.setPositionSmoothingSpeed)
                |> applyOpt(rotSmoothEnabledOpt, Camera2D.setRotationSmoothingEnabled)
                |> applyOpt(rotSmoothSpeedOpt, Camera2D.setRotationSmoothingSpeed)
                |> applyOpt(dragHEnabledOpt, Camera2D.setDragHorizontalEnabled)
                |> applyOpt(dragVEnabledOpt, Camera2D.setDragVerticalEnabled)
                |> applyOpt(dragLeftOpt, Camera2D.setDragLeftMargin)
                |> applyOpt(dragRightOpt, Camera2D.setDragRightMargin)
                |> applyOpt(dragTopOpt, Camera2D.setDragTopMargin)
                |> applyOpt(dragBottomOpt, Camera2D.setDragBottomMargin);
            EngineNode.Camera2DWithState(camera, tag)
        }

    def setCameraScale(scale: Vec2.Vec2, cam: Camera2D): Camera2D =
        Node2D.setScale(scale, cam)

    def setCameraRotation(rot: Float64, cam: Camera2D): Camera2D =
        Node2D.setRotation(rot, cam)

    def setCameraSkew(skew: Float64, cam: Camera2D): Camera2D =
        Node2D.setSkew(skew, cam)

    def setCameraVisible(v: Bool, cam: Camera2D): Camera2D =
        CanvasItem.setVisible(v, cam)

    def setCameraZIndex(z: Int32, cam: Camera2D): Camera2D =
        CanvasItem.setZIndex(z, cam)

    /// "DragCenter" / "FixedTopLeft" を Camera2DAnchorMode に変換する。省略時は DragCenter
    def parseAnchorMode(opt: Option[String]): Result[Json.JsonError, Camera2DAnchorMode] =
        match opt {
            case None                  => Ok(Camera2DAnchorMode.DragCenter)
            case Some("DragCenter")    => Ok(Camera2DAnchorMode.DragCenter)
            case Some("FixedTopLeft")  => Ok(Camera2DAnchorMode.FixedTopLeft)
            case Some(other)           =>
                Err(JsonError(Root, Set#{"DragCenter|FixedTopLeft (got: ${other})"}))
        }

    /// "PhysicsProcess" / "IdleProcess" を Camera2DProcessCallback に変換する。省略時は IdleProcess
    def parseProcessCallback(opt: Option[String]): Result[Json.JsonError, Camera2DProcessCallback] =
        match opt {
            case None                    => Ok(Camera2DProcessCallback.IdleProcess)
            case Some("PhysicsProcess")  => Ok(Camera2DProcessCallback.PhysicsProcess)
            case Some("IdleProcess")     => Ok(Camera2DProcessCallback.IdleProcess)
            case Some(other)             =>
                Err(JsonError(Root, Set#{"PhysicsProcess|IdleProcess (got: ${other})"}))
        }

    /// LDTK レベル（.ldtkl）を読み込んで TileMapLayer ノードを構築する。
    /// JSON フィールド: ldtkPath / textureName / marginX / marginY / spacingX / spacingY
    def buildTileMapLayer(tagParser: Option[String] -> Result[Json.JsonError, t],
                          map: Map[String, Json.JsonElement]):
                          Result[Json.JsonError, EngineNode[t]] \ {GameEngine.Game, Fs.FileRead} =
        let header = forM (
            tag         <- parseTagField(tagParser, map);
            ldtkPath    <- (Json.FromJson.getAtKey(Root, "ldtkPath", map): Result[Json.JsonError, String]);
            textureName <- (Json.FromJson.getAtKey(Root, "textureName", map): Result[Json.JsonError, String]);
            marginXOpt  <- (Json.FromJson.getAtKeyOpt(Root, "marginX", map): Result[Json.JsonError, Option[Float64]]);
            marginYOpt  <- (Json.FromJson.getAtKeyOpt(Root, "marginY", map): Result[Json.JsonError, Option[Float64]]);
            spacingXOpt <- (Json.FromJson.getAtKeyOpt(Root, "spacingX", map): Result[Json.JsonError, Option[Float64]]);
            spacingYOpt <- (Json.FromJson.getAtKeyOpt(Root, "spacingY", map): Result[Json.JsonError, Option[Float64]])
        ) yield {
            tag = tag,
            config = ({
                path        = ldtkPath,
                textureName = textureName,
                marginX     = Option.getWithDefault(0.0, marginXOpt),
                marginY     = Option.getWithDefault(0.0, marginYOpt),
                spacingX    = Option.getWithDefault(0.0, spacingXOpt),
                spacingY    = Option.getWithDefault(0.0, spacingYOpt)
            }: LDTKLoader.LDTKLoaderConfig)
        };
        match header {
            case Err(e) => Err(e)
            case Ok(h)  =>
                let levelData = LDTKLoader.loadLevel(h#config);
                Ok(EngineNode.TileMapLayerWithState(levelData#tileLayer, h#tag))
        }

    def buildLabel2D(tagParser: Option[String] -> Result[Json.JsonError, t],
                     fontAtlas: Option[FontAtlas],
                     map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[t]] =
        match fontAtlas {
            case None => Err(JsonError(Root, Set#{"FontAtlas (loadSceneWithFont required for Label2D)"}))
            case Some(font) =>
                forM (
                    tag         <- parseTagField(tagParser, map);
                    text        <- (Json.FromJson.getAtKey(Root, "text", map): Result[Json.JsonError, String]);
                    pos         <- parseVec2("pos", map);
                    fontSize    <- (Json.FromJson.getAtKey(Root, "fontSize", map): Result[Json.JsonError, Float64]);
                    hAlignOpt   <- (Json.FromJson.getAtKeyOpt(Root, "horizontalAlignment", map):
                                     Result[Json.JsonError, Option[String]]);
                    vAlignOpt   <- (Json.FromJson.getAtKeyOpt(Root, "verticalAlignment", map):
                                     Result[Json.JsonError, Option[String]]);
                    hAlign      <- parseHorizontalAlignment(hAlignOpt);
                    vAlign      <- parseVerticalAlignment(vAlignOpt);
                    visibleOpt  <- (Json.FromJson.getAtKeyOpt(Root, "visible", map): Result[Json.JsonError, Option[Bool]]);
                    zIndexOpt   <- (Json.FromJson.getAtKeyOpt(Root, "zIndex", map): Result[Json.JsonError, Option[Int32]]);
                    rotationOpt <- (Json.FromJson.getAtKeyOpt(Root, "rotation", map): Result[Json.JsonError, Option[Float64]])
                ) yield {
                    let label = Label2D.make(text, font, fontSize)
                        |> Node2D.setPosition(pos)
                        |> Label2D.setHorizontalAlignment(hAlign)
                        |> Label2D.setVerticalAlignment(vAlign)
                        |> applyLabelVisible(visibleOpt)
                        |> applyLabelZIndex(zIndexOpt)
                        |> applyOpt(rotationOpt, (r, l) -> Node2D.setRotation(r, l));
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

    /// `{"r": 1.0, "g": 1.0, "b": 1.0}` 形式の JSON オブジェクトを Color (Float32) に変換する。
    /// 数値は JSON 上 Float64 として読み、Float32 に縮小する
    def parseColor(key: String,
                   map: Map[String, Json.JsonElement]): Result[Json.JsonError, Color] =
        forM (
            colorMap <- (Json.FromJson.getAtKey(Root, key, map): Result[Json.JsonError, Map[String, Json.JsonElement]]);
            r        <- (Json.FromJson.getAtKey(Root, "r", colorMap): Result[Json.JsonError, Float64]);
            g        <- (Json.FromJson.getAtKey(Root, "g", colorMap): Result[Json.JsonError, Float64]);
            b        <- (Json.FromJson.getAtKey(Root, "b", colorMap): Result[Json.JsonError, Float64])
        ) yield ({
            r = Float64.truncateToFloat32(r),
            g = Float64.truncateToFloat32(g),
            b = Float64.truncateToFloat32(b)
        }: Color)

    def buildColorRect(tagParser: Option[String] -> Result[Json.JsonError, t],
                       map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[t]] =
        forM (
            tag         <- parseTagField(tagParser, map);
            pos         <- parseVec2("pos", map);
            size        <- parseVec2("size", map);
            color       <- parseColor("color", map);
            alphaOpt    <- (Json.FromJson.getAtKeyOpt(Root, "alpha", map): Result[Json.JsonError, Option[Float64]]);
            visibleOpt  <- (Json.FromJson.getAtKeyOpt(Root, "visible", map): Result[Json.JsonError, Option[Bool]]);
            zIndexOpt   <- (Json.FromJson.getAtKeyOpt(Root, "zIndex", map): Result[Json.JsonError, Option[Int32]]);
            rotationOpt <- (Json.FromJson.getAtKeyOpt(Root, "rotation", map): Result[Json.JsonError, Option[Float64]])
        ) yield {
            let rect = ColorRect.make(size, color)
                |> Node2D.setPosition(pos)
                |> applyOpt(alphaOpt, setColorRectAlpha)
                |> applyOpt(visibleOpt, setColorRectVisible)
                |> applyOpt(zIndexOpt, setColorRectZIndex)
                |> applyOpt(rotationOpt, (r, c) -> Node2D.setRotation(r, c));
            EngineNode.ColorRectWithState(rect, tag)
        }

    def setColorRectAlpha(alpha: Float64, rect: ColorRect): ColorRect =
        ColorRect.setAlpha(Float64.truncateToFloat32(alpha), rect)

    def setColorRectVisible(v: Bool, rect: ColorRect): ColorRect =
        CanvasItem.setVisible(v, rect)

    def setColorRectZIndex(z: Int32, rect: ColorRect): ColorRect =
        CanvasItem.setZIndex(z, rect)

    def buildRichTextLabel(tagParser: Option[String] -> Result[Json.JsonError, t],
                           fontAtlas: Option[FontAtlas],
                           map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[t]] =
        match fontAtlas {
            case None => Err(JsonError(Root, Set#{"FontAtlas (loadSceneWithFont required for RichTextLabel)"}))
            case Some(font) =>
                forM (
                    tag        <- parseTagField(tagParser, map);
                    pos        <- parseVec2("pos", map);
                    size       <- parseVec2("size", map);
                    text       <- (Json.FromJson.getAtKey(Root, "text", map): Result[Json.JsonError, String]);
                    fontSize   <- (Json.FromJson.getAtKey(Root, "fontSize", map): Result[Json.JsonError, Float64]);
                    visibleOpt <- (Json.FromJson.getAtKeyOpt(Root, "visible", map): Result[Json.JsonError, Option[Bool]]);
                    zIndexOpt  <- (Json.FromJson.getAtKeyOpt(Root, "zIndex", map): Result[Json.JsonError, Option[Int32]])
                ) yield {
                    let label = RichTextLabel.make(text, font, fontSize, size)
                        |> Node2D.setPosition(pos)
                        |> applyOpt(visibleOpt, setRichTextLabelVisible)
                        |> applyOpt(zIndexOpt, setRichTextLabelZIndex);
                    EngineNode.RichTextLabelWithState(label, tag)
                }
        }

    def setRichTextLabelVisible(v: Bool, label: RichTextLabel): RichTextLabel =
        CanvasItem.setVisible(v, label)

    def setRichTextLabelZIndex(z: Int32, label: RichTextLabel): RichTextLabel =
        CanvasItem.setZIndex(z, label)

    // ========================================================================
    // ビルダー用ヘルパー（任意フィールド適用）
    // ========================================================================

    /// Option[a] が Some なら setter(x, target) を適用し、None なら target をそのまま返す。
    /// 単相な setter（例: `Sprite2D.setHframes`）と組み合わせてビルダー内のオプション
    /// フィールド適用を 1 行で書くために使う
    def applyOpt(opt: Option[a], setter: (a, b) -> b, target: b): b =
        match opt {
            case Some(x) => setter(x, target)
            case None    => target
        }

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
