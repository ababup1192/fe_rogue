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
//   段階 4 後段で LDtk 経路 (TileMapLayer 用 buildTileMapLayer) を削除済み。
//   loadScene の eff は他の effectful builder (Fs.FileRead 等) のためのみ残る (TileMapLayer 用 GameEngine.Game 要件は不要になった)。
//   過去経緯メモ:
//   JSON では実質 no-op）。

mod SceneLoader {
    import java.math.BigDecimal
    use Util.Json.Json.{JObject, JArray}
    use JsonCompat.PathTag.Root

    // ========================================================================
    // JSON ユーティリティ（PackedScene からも利用）
    // ========================================================================

    /// Float64 を BigDecimal に変換する（PackedScene の pos 上書き用）
    def floatToBd(value: Float64): BigDecimal =
        unsafe IO { BigDecimal.valueOf(value).stripTrailingZeros() }

    /// JSON Object のトップレベル "name" を別の値に置き換える。
    /// JSON Object 以外なら入力をそのまま返す（PackedScene.instantiate がここを通る）
    pub def withRootName(name: NodeName, json: Util.Json.Json): Util.Json.Json =
        match json {
            case JObject(map) =>
                JObject(Map.insert("name", Util.Json.Json.JString(name), map))
            case _ => json
        }

    /// JSON Object のトップレベル "pos" を [x, y] に置き換える。
    /// JSON Object 以外なら入力をそのまま返す
    pub def withRootPosition(pos: Vec2.Vec2, json: Util.Json.Json): Util.Json.Json =
        match json {
            case JObject(map) =>
                let posArr = Util.Json.Json.JArray(Vector#{
                    Util.Json.Json.JNumber(floatToBd(pos#x)),
                    Util.Json.Json.JNumber(floatToBd(pos#y))
                });
                JObject(Map.insert("pos", posArr, map))
            case _ => json
        }

    /// JSON Object のトップレベル "name" 文字列を取り出す。
    /// PackedScene が template root name を解決するのに使う
    pub def rootNameOf(json: Util.Json.Json): Option[NodeName] =
        match json {
            case JObject(map) =>
                match Map.get("name", map) {
                    case Some(Util.Json.Json.JString(s)) => Some(s)
                    case _ => None
                }
            case _ => None
        }

    // ========================================================================
    // 公開 API
    // ========================================================================

    /// JSON ファイルを読み込み、scene にノードツリーを追加して返す。
    /// tagParser: JSON の "tag" 文字列（None = キーなし）をゲーム固有の t に変換する関数。
    /// Label2D を含む JSON では loadSceneWithFont を使うこと（FontAtlas が必須）。
    /// `GameEngine.Game` eff は将来 effectful な builder を追加する余地のため保持している。
    /// 失敗時は bug! でクラッシュする
    pub def loadScene(path: String, tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                      scene: Scene[t]): Scene[t] \ {GameEngine.Game, Fs.FileRead} =
        loadSceneCoreAt(Nil, path, tagParser, None, None, scene)

    /// FontAtlas 付きで JSON ファイルを読み込む（Label2D を含むシーン用）。
    /// その他は loadScene と同じ振る舞い
    pub def loadSceneWithFont(path: String, fontAtlas: FontAtlas,
                              tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                              scene: Scene[t]): Scene[t] \ {GameEngine.Game, Fs.FileRead} =
        loadSceneCoreAt(Nil, path, tagParser, Some(fontAtlas), None, scene)

    /// `loadSceneWithFont` の親パス指定版。 scene.json のルートノードを `parentPath` 配下に
    /// 追加する（root 直下ではなく既存ノードの子として配置）。
    /// 親子 hierarchy で UI レイヤーをまとめたいとき（CanvasLayer の子に複数 Panel を入れて
    /// 親の visible で一括 hide）に使う。
    pub def loadSceneWithFontAt(parentPath: NodePath, path: String, fontAtlas: FontAtlas,
                                tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                                scene: Scene[t]): Scene[t] \ {GameEngine.Game, Fs.FileRead} =
        loadSceneCoreAt(parentPath, path, tagParser, Some(fontAtlas), None, scene)

    /// JSON ファイルを読み込み、scene を構築した後で `propsApplier` を呼ぶ。
    /// scene.json の root が JSON Object のとき、その "properties" キーを PropertyBag として
    /// applier に渡す（Godot @export 相当）。"properties" が無い、または root が array の
    /// 場合は空 bag を渡す。applier は通常 `XxxScene.applyProperties` で、`Export.read` を
    /// 使って Data 型に値を流し込む役割を持つ。ホットリロード時もこの関数経由で applier が
    /// 再実行されることで、scene.json の編集が即反映される
    pub def loadSceneWith(path: String,
                          tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                          propsApplier: PropertyBag -> Scene[t] -> Scene[t],
                          scene: Scene[t]): Scene[t] \ {GameEngine.Game, Fs.FileRead} =
        loadSceneCoreAt(Nil, path, tagParser, None, Some(propsApplier), scene)

    /// JSON 側のタグ文字列を無視し、常に与えた値を返す tagParser を作る。
    /// scene.json 側にタグ情報を載せない（= ロード後に Scene.setState で個別注入する）
    /// 方針のシーンで使う標準ヘルパー。
    pub def constTagParser(tag: t): Option[String] -> Result[Util.Json.JsonError, t] =
        _ -> Ok(tag)

    /// scene tree を walk し、各 `EngineNode.AudioStreamPlayerWithState` ノードに対して
    /// `AudioStreamPlayer.applyAttach` を呼び出す。`volume` / `loop` を OpenAL に反映し、
    /// `autoplay = true` のものは play する。
    ///
    /// `loadScene` 系は副作用を持たない純粋な parse 層に留めたいため、ホットリロード /
    /// 初回ロード後にこの関数を別途呼ぶ運用とする。
    pub def applyAudioAttach(scene: Scene[s]): Unit \ GameEngine.Audio =
        List.forEach(p -> match Scene.getEngineNode(p, scene) {
            case Some(EngineNode.AudioStreamPlayerWithState(player, _)) =>
                AudioStreamPlayer.applyAttach(player)
            case _ => ()
        }, Scene.preorderPaths(scene))

    // ========================================================================
    // 内部実装
    // ========================================================================

    def loadSceneCoreAt(parentPath: NodePath, path: String,
                        tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                        fontAtlas: Option[FontAtlas],
                        propsApplier: Option[PropertyBag -> Scene[t] -> Scene[t]],
                        scene: Scene[t]): Scene[t] \ {GameEngine.Game, Fs.FileRead} =
        let content = run { Fs.ReadFile.read(path) } with Fs.ReadFile.runWithFileRead;
        let result = forM (
            text     <- content |> Result.mapErr(e -> "failed to read: ${e}");
            json     <- JsonCompat.parse(String.trim(text)) |> Option.toOk("JSON parse failed");
            outScene <- addJsonAtTopAt(parentPath, tagParser, fontAtlas, json, scene)
                |> Result.mapErr(e -> "${e}")
        ) yield applyPropsIfPresent(propsApplier, json, outScene);
        match result {
            case Ok(s)    => s
            case Err(msg) => bug!("SceneLoader: ${path}: ${msg}")
        }

    /// applier が Some なら root JSON Object の "properties" を取り出して呼ぶ
    def applyPropsIfPresent(propsApplier: Option[PropertyBag -> Scene[t] -> Scene[t]],
                            json: Util.Json.Json,
                            scene: Scene[t]): Scene[t] =
        match propsApplier {
            case None          => scene
            case Some(applier) => applier(rootProperties(json), scene)
        }

    /// JSON root から "properties" を取り出す。Object でない or キーが無い場合は空 bag
    def rootProperties(json: Util.Json.Json): PropertyBag =
        match json {
            case JObject(map) => ExportedProperty.fromJsonNode(map)
            case _               => ExportedProperty.emptyBag()
        }

    // ========================================================================
    // JSON → Scene 変換
    // ========================================================================

    /// 親パス指定版。 root 直下に追加するなら parentPath = Nil。
    def addJsonAtTopAt(parentPath: NodePath,
                       tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                       fontAtlas: Option[FontAtlas], json: Util.Json.Json,
                       scene: Scene[t]): Result[Util.Json.JsonError, Scene[t]] \ {GameEngine.Game, Fs.FileRead} =
        match json {
            case JObject(_)  => addJsonAt(parentPath, tagParser, fontAtlas, json, scene)
            case JArray(arr) =>
                List.foldLeft(
                    (acc, child) -> match acc {
                        case Err(e) => Err(e)
                        case Ok(s)  => addJsonAt(parentPath, tagParser, fontAtlas, child, s)
                    },
                    Ok(scene),
                    Vector.toList(arr))
            case _ => Err(JsonCompat.jsonError(Root, Set#{"JObject or JArray"}))
        }

    /// JSON ルートノードを `parentPath` 配下に追加する。
    /// PackedScene.instantiate がこの関数経由でテンプレートを scene に挿入するため public。
    pub def addJsonAt(parentPath: NodePath, tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                  fontAtlas: Option[FontAtlas], json: Util.Json.Json,
                  scene: Scene[t]): Result[Util.Json.JsonError, Scene[t]] \ {GameEngine.Game, Fs.FileRead} =
        match json {
            case JObject(map) =>
                let nodeTypeResult: Result[Util.Json.JsonError, String] =
                    JsonCompat.getAtKey(Root, "type", map);
                match nodeTypeResult {
                    case Err(e) => Err(e)
                    // Container は scene tree のノードではなく、load 時の layout directive。
                    // children を parentPath 直下に追加し、最後に Layout.apply を 1 回呼ぶ。
                    case Ok("Container") =>
                        handleContainer(parentPath, tagParser, fontAtlas, map, scene)
                    case Ok(nodeType) =>
                        let header = forM (
                            name   <- (JsonCompat.getAtKey(Root, "name", map): Result[Util.Json.JsonError, String]);
                            groups <- parseGroups(map)
                        ) yield (name, groups);
                        match header {
                            case Err(e) => Err(e)
                            case Ok((name, groups)) =>
                                match buildByType(tagParser, nodeType, fontAtlas, map) {
                                    case Err(e) => Err(e)
                                    case Ok(engineNode) =>
                                        let nodePath = parentPath ::: name :: Nil;
                                        let added = addAt(parentPath, name, engineNode, scene)
                                            |> applyGroups(nodePath, groups);
                                        addChildren(nodePath, tagParser, fontAtlas, map, added)
                                }
                        }
                }
            case _ => Err(JsonCompat.jsonError(Root, Set#{"JObject"}))
        }

    /// Container ノードの処理 (load-time directive):
    /// 1. `rect` と `layout` をパース
    /// 2. Layout を walk して各 `Node` case の definition から実 engine node を作り
    ///    scene tree (parentPath 直下) に追加
    /// 3. `Layout.apply(parentPath, rect, layout, scene)` で位置決め
    ///
    /// Container 自身は scene tree にノードを残さない (load-time directive)。
    /// scene.json 側で Container に `children` 配列を持たせる必要はない (Layout の Node case で代替)。
    def handleContainer(parentPath: NodePath,
                         tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                         fontAtlas: Option[FontAtlas],
                         map: Map[String, Util.Json.Json],
                         scene: Scene[t]):
                         Result[Util.Json.JsonError, Scene[t]] \ {GameEngine.Game, Fs.FileRead} =
        // rect 省略時は画面 viewport (design rect) を基準にする＝CanvasLayer 直下などで
        // 「画面の右下からの相対位置」を anchor で表現できるようにする。
        let viewport = GameEngine.Game.getViewportRect();
        let parsed = forM (
            rect       <- (match Map.get("rect", map) {
                              case Some(_) => parseRect(map)
                              case None    => Ok(viewport)
                          });
            layoutJson <- (JsonCompat.getAtKey(Root, "layout", map): Result[Util.Json.JsonError, Util.Json.Json]);
            layout     <- Layout.fromJson(layoutJson)
        ) yield (rect, layout);
        match parsed {
            case Err(e) => Err(e)
            case Ok((rect, layout)) =>
                match buildLayoutNodes(parentPath, tagParser, fontAtlas, layout, scene) {
                    case Err(e)         => Err(e)
                    case Ok(withNodes)  => Ok(Layout.apply(parentPath, rect, layout, withNodes))
                }
        }

    /// Layout を再帰的に walk し、各 `Node` case の definition から実 engine node を作って
    /// scene tree (parentPath 直下) に追加する。Layout primitive (HBoxContainer 等) は
    /// 子に対して再帰する。
    def buildLayoutNodes(parentPath: NodePath,
                          tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                          fontAtlas: Option[FontAtlas],
                          layout: Layout,
                          scene: Scene[t]):
                          Result[Util.Json.JsonError, Scene[t]] \ {GameEngine.Game, Fs.FileRead} =
        match layout {
            case Layout.Node({name = _, definition}) =>
                addJsonAt(parentPath, tagParser, fontAtlas, definition, scene)
            case Layout.MarginContainer({margin = _, child}) =>
                buildLayoutNodes(parentPath, tagParser, fontAtlas, child, scene)
            case Layout.CenterContainer(child) =>
                buildLayoutNodes(parentPath, tagParser, fontAtlas, child, scene)
            case Layout.VBoxContainer({separation = _, alignment = _, crossAxis = _, children}) =>
                buildLayoutChildren(parentPath, tagParser, fontAtlas, children, scene)
            case Layout.HBoxContainer({separation = _, alignment = _, crossAxis = _, children}) =>
                buildLayoutChildren(parentPath, tagParser, fontAtlas, children, scene)
            case Layout.GridContainer({columns = _, separation = _, children}) =>
                buildLayoutChildren(parentPath, tagParser, fontAtlas, children, scene)
            case Layout.Panel(children) =>
                buildLayoutChildren(parentPath, tagParser, fontAtlas, children, scene)
        }

    def buildLayoutChildren(parentPath: NodePath,
                             tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                             fontAtlas: Option[FontAtlas],
                             children: List[Layout],
                             scene: Scene[t]):
                             Result[Util.Json.JsonError, Scene[t]] \ {GameEngine.Game, Fs.FileRead} =
        List.foldLeft((acc, child) -> match acc {
            case Err(e) => Err(e)
            case Ok(s)  => buildLayoutNodes(parentPath, tagParser, fontAtlas, child, s)
        }, Ok(scene), children)

    /// `"rect": {"x": .., "y": .., "width": .., "height": ..}` を Rect2 に変換する。
    /// 配列形式 `[x, y, w, h]` より可読性が高い (各フィールドの意味が名前で明示される)。
    def parseRect(map: Map[String, Util.Json.Json]):
                   Result[Util.Json.JsonError, Rect2.Rect2] =
        forM (
            rectMap <- (JsonCompat.getAtKey(Root, "rect", map): Result[Util.Json.JsonError, Map[String, Util.Json.Json]]);
            x       <- (JsonCompat.getAtKey(Root, "x", rectMap): Result[Util.Json.JsonError, Float64]);
            y       <- (JsonCompat.getAtKey(Root, "y", rectMap): Result[Util.Json.JsonError, Float64]);
            w       <- (JsonCompat.getAtKey(Root, "width", rectMap): Result[Util.Json.JsonError, Float64]);
            h       <- (JsonCompat.getAtKey(Root, "height", rectMap): Result[Util.Json.JsonError, Float64])
        ) yield ({position = {x = x, y = y}, size = {x = w, y = h}}: Rect2.Rect2)

    def addAt(parentPath: NodePath, name: String, engineNode: EngineNode[t],
              scene: Scene[t]): Scene[t] =
        match parentPath {
            case Nil => Scene.addNode(name, engineNode, scene)
            case _   => Scene.addChildAt(parentPath, name, engineNode, scene)
        }

    def addChildren(parentPath: NodePath, tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                    fontAtlas: Option[FontAtlas], map: Map[String, Util.Json.Json],
                    scene: Scene[t]): Result[Util.Json.JsonError, Scene[t]] \ {GameEngine.Game, Fs.FileRead} =
        match Map.get("children", map) {
            case None                 => Ok(scene)
            case Some(JArray(arr)) =>
                List.foldLeft(
                    (acc, child) -> match acc {
                        case Err(e) => Err(e)
                        case Ok(s)  => addJsonAt(parentPath, tagParser, fontAtlas, child, s)
                    },
                    Ok(scene),
                    Vector.toList(arr))
            case Some(_) => Err(JsonCompat.jsonError(Root, Set#{"JArray"}))
        }

    def applyGroups(path: NodePath, groups: List[String], scene: Scene[t]): Scene[t] =
        List.foldLeft((acc, group) -> Scene.addToGroup(path, group, acc), scene, groups)

    // ========================================================================
    // ノード型ディスパッチ
    // ========================================================================

    def buildByType(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                    nodeType: String, fontAtlas: Option[FontAtlas],
                    map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] \ {GameEngine.Game, Fs.FileRead} =
        checked_ecast(buildPureNodeType(tagParser, nodeType, fontAtlas, map))

    /// 副作用を持たないビルダーへのディスパッチ。
    /// 段階 4 後段で LDtk (`TileMapLayer`) 削除に伴い、effectful 分岐は無くなった。
    def buildPureNodeType(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                          nodeType: String, fontAtlas: Option[FontAtlas],
                          map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        match nodeType {
            case "CanvasLayer"      => buildCanvasLayer(tagParser, map)
            case "Sprite2D"         => buildSprite2D(tagParser, map)
            case "Button"           => buildButton(tagParser, fontAtlas, map)
            case "TextureButton"    => buildTextureButton(tagParser, map)
            case "TextureRect"      => buildTextureRect(tagParser, map)
            case "StaticBody2D"     => buildStaticBody2D(tagParser, map)
            case "Label2D"          => buildLabel2D(tagParser, fontAtlas, map)
            case "RigidBody2D"      => buildRigidBody2D(tagParser, map)
            case "Area2D"           => buildArea2D(tagParser, map)
            case "AnimatedSprite2D" => buildAnimatedSprite2D(tagParser, map)
            case "CharacterBody2D"  => buildCharacterBody2D(tagParser, map)
            case "Marker2D"         => buildMarker2D(tagParser, map)
            case "Camera2D"         => buildCamera2D(tagParser, map)
            case "ColorRect"        => buildColorRect(tagParser, map)
            case "Polygon2D"        => buildPolygon2D(tagParser, map)
            case "Arc2D"            => buildArc2D(tagParser, map)
            case "RichTextLabel"    => buildRichTextLabel(tagParser, fontAtlas, map)
            case "Panel"            => buildPanel(tagParser, map)
            case "ProgressBar"      => buildProgressBar(tagParser, map)
            case "ItemList"         => buildItemList(tagParser, fontAtlas, map)
            case "AudioStreamPlayer" => buildAudioStreamPlayer(tagParser, map)
            case unknown            =>
                Err(JsonCompat.jsonError(Root, Set#{"known node type (got: ${unknown})"}))
        }

    // ========================================================================
    // 共通フィールドの解析
    // ========================================================================

    def parseVec2(key: String,
                  map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, Vec2.Vec2] =
        forM (
            pair <- (JsonCompat.getAtKey(Root, key, map): Result[Util.Json.JsonError, (Float64, Float64)])
        ) yield {
            let (x, y) = pair;
            {x = x, y = y}
        }

    def parseVec2Opt(key: String,
                     map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, Option[Vec2.Vec2]] =
        forM (
            opt <- (JsonCompat.getAtKeyOpt(Root, key, map): Result[Util.Json.JsonError, Option[(Float64, Float64)]])
        ) yield match opt {
            case Some((x, y)) => Some({x = x, y = y})
            case None         => None
        }

    /// "tag" フィールドを tagParser で変換する。キーがなければ None を渡す
    def parseTagField(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                      map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, t] =
        forM (
            tagOpt <- (JsonCompat.getAtKeyOpt(Root, "tag", map): Result[Util.Json.JsonError, Option[String]]);
            tag    <- tagParser(tagOpt)
        ) yield tag

    def parseGroups(map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, List[String]] =
        forM (
            opt <- (JsonCompat.getAtKeyOpt(Root, "groups", map): Result[Util.Json.JsonError, Option[List[String]]])
        ) yield Option.getWithDefault(Nil, opt)

    def parseShape(map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, CollisionShape2D] =
        forM (
            shapeMap <- (JsonCompat.getAtKey(Root, "shape", map): Result[Util.Json.JsonError, Map[String, Util.Json.Json]]);
            kind     <- (JsonCompat.getAtKey(Root, "kind", shapeMap): Result[Util.Json.JsonError, String]);
            shape    <- buildShape(kind, shapeMap)
        ) yield shape

    def buildShape(kind: String,
                   map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, CollisionShape2D] =
        match kind {
            case "RectShape2D" =>
                forM (
                    width  <- (JsonCompat.getAtKey(Root, "width", map): Result[Util.Json.JsonError, Float64]);
                    height <- (JsonCompat.getAtKey(Root, "height", map): Result[Util.Json.JsonError, Float64])
                ) yield CollisionShape2D.RectShape2D({width = width, height = height})
            case "CircleShape2D" =>
                forM (
                    radius <- (JsonCompat.getAtKey(Root, "radius", map): Result[Util.Json.JsonError, Float64])
                ) yield CollisionShape2D.CircleShape2D({radius = radius})
            case "CapsuleShape2D" =>
                forM (
                    radius   <- (JsonCompat.getAtKey(Root, "radius", map): Result[Util.Json.JsonError, Float64]);
                    height   <- (JsonCompat.getAtKey(Root, "height", map): Result[Util.Json.JsonError, Float64]);
                    vertical <- (JsonCompat.getAtKey(Root, "vertical", map): Result[Util.Json.JsonError, Bool])
                ) yield CollisionShape2D.CapsuleShape2D({radius = radius, height = height, vertical = vertical})
            case unknown =>
                Err(JsonCompat.jsonError(Root, Set#{"known shape kind (got: ${unknown})"}))
        }

    // ========================================================================
    // ノード型ビルダー
    // ========================================================================

    def buildCanvasLayer(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                         map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        forM (
            tag         <- parseTagField(tagParser, map);
            drawLayer   <- (JsonCompat.getAtKey(Root, "layer", map): Result[Util.Json.JsonError, Int32]);
            posOpt      <- parseVec2Opt("pos", map);
            rotationOpt <- (JsonCompat.getAtKeyOpt(Root, "rotation", map): Result[Util.Json.JsonError, Option[Float64]]);
            visibleOpt  <- (JsonCompat.getAtKeyOpt(Root, "visible", map): Result[Util.Json.JsonError, Option[Bool]]);
            zIndexOpt   <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[Util.Json.JsonError, Option[Int32]]);
            modulateOpt <- parseColorOpt("modulate", map)
        ) yield {
            let layer = CanvasLayer.make(drawLayer)
                |> applyOpt(posOpt, setCanvasLayerPosition)
                |> applyOpt(rotationOpt, setCanvasLayerRotation)
                |> applyOpt(visibleOpt, (v, l) -> CanvasItem.setVisible(v, l))
                |> applyOpt(zIndexOpt, (z, l) -> CanvasItem.setZIndex(z, l))
                |> applyOpt(modulateOpt, (c, l) -> CanvasItem.setModulate(c, l));
            EngineNode.CanvasLayerWithState(layer, tag)
        }

    def setCanvasLayerPosition(pos: Vec2.Vec2, layer: CanvasLayer): CanvasLayer =
        Node2D.setPosition(pos, layer)

    def setCanvasLayerRotation(rot: Float64, layer: CanvasLayer): CanvasLayer =
        Node2D.setRotation(rot, layer)

    def buildSprite2D(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                      map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        forM (
            tag         <- parseTagField(tagParser, map);
            pos         <- parseVec2("pos", map);
            scale       <- parseVec2("scale", map);
            texture     <- (JsonCompat.getAtKey(Root, "texture", map): Result[Util.Json.JsonError, String]);
            rotationOpt <- (JsonCompat.getAtKeyOpt(Root, "rotation", map): Result[Util.Json.JsonError, Option[Float64]]);
            skewOpt     <- (JsonCompat.getAtKeyOpt(Root, "skew", map): Result[Util.Json.JsonError, Option[Float64]]);
            zIndexOpt   <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[Util.Json.JsonError, Option[Int32]]);
            visibleOpt  <- (JsonCompat.getAtKeyOpt(Root, "visible", map): Result[Util.Json.JsonError, Option[Bool]]);
            flipHOpt    <- (JsonCompat.getAtKeyOpt(Root, "flipH", map): Result[Util.Json.JsonError, Option[Bool]]);
            flipVOpt    <- (JsonCompat.getAtKeyOpt(Root, "flipV", map): Result[Util.Json.JsonError, Option[Bool]]);
            hframesOpt  <- (JsonCompat.getAtKeyOpt(Root, "hframes", map): Result[Util.Json.JsonError, Option[Int32]]);
            vframesOpt  <- (JsonCompat.getAtKeyOpt(Root, "vframes", map): Result[Util.Json.JsonError, Option[Int32]]);
            frameOpt    <- (JsonCompat.getAtKeyOpt(Root, "frame", map): Result[Util.Json.JsonError, Option[Int32]]);
            alphaOpt    <- (JsonCompat.getAtKeyOpt(Root, "alpha", map): Result[Util.Json.JsonError, Option[Float64]]);
            centeredOpt <- (JsonCompat.getAtKeyOpt(Root, "centered", map): Result[Util.Json.JsonError, Option[Bool]]);
            offsetOpt   <- parseVec2Opt("offset", map);
            modulateOpt <- parseColorOpt("modulate", map);
            ySortEnabledOpt <- (JsonCompat.getAtKeyOpt(Root, "ySortEnabled", map): Result[Util.Json.JsonError, Option[Bool]])
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
                |> applyOpt(frameOpt, Sprite2D.setFrame)
                |> applyOpt(alphaOpt, setSpriteAlpha)
                |> applyOpt(centeredOpt, Sprite2D.setCentered)
                |> applyOpt(offsetOpt, Sprite2D.setOffset)
                |> applyOpt(modulateOpt, setSpriteModulate)
                |> applyOpt(ySortEnabledOpt, setSpriteYSortEnabled);
            EngineNode.Sprite2DWithState(sprite, tag)
        }

    def setSpriteModulate(c: Color, sprite: Sprite2D): Sprite2D =
        CanvasItem.setModulate(c, sprite)

    def setSpriteAlpha(a: Float64, sprite: Sprite2D): Sprite2D =
        Sprite2D.setAlpha(Float64.tryToFloat32(a) |> Option.getWithDefault(1.0f32), sprite)

    // ── Node2D / CanvasItem 経由のフィールド適用に使う型固定ラッパー ──

    def setSpriteRotation(rot: Float64, sprite: Sprite2D): Sprite2D =
        Node2D.setRotation(rot, sprite)

    def setSpriteSkew(skew: Float64, sprite: Sprite2D): Sprite2D =
        Node2D.setSkew(skew, sprite)

    def setSpriteYSortEnabled(v: Bool, sprite: Sprite2D): Sprite2D =
        CanvasItem.setYSortEnabled(v, sprite)

    def buildTextureRect(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                          map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        forM (
            tag         <- parseTagField(tagParser, map);
            posOpt      <- parseVec2Opt("pos", map);
            sizeOpt     <- parseVec2Opt("size", map);
            texture     <- (JsonCompat.getAtKey(Root, "texture", map): Result[Util.Json.JsonError, String]);
            rotationOpt <- (JsonCompat.getAtKeyOpt(Root, "rotation", map): Result[Util.Json.JsonError, Option[Float64]]);
            skewOpt     <- (JsonCompat.getAtKeyOpt(Root, "skew", map): Result[Util.Json.JsonError, Option[Float64]]);
            zIndexOpt   <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[Util.Json.JsonError, Option[Int32]]);
            visibleOpt  <- (JsonCompat.getAtKeyOpt(Root, "visible", map): Result[Util.Json.JsonError, Option[Bool]]);
            modulateOpt <- parseColorOpt("modulate", map);
            alphaOpt    <- (JsonCompat.getAtKeyOpt(Root, "alpha", map): Result[Util.Json.JsonError, Option[Float64]]);
            flipHOpt    <- (JsonCompat.getAtKeyOpt(Root, "flipH", map): Result[Util.Json.JsonError, Option[Bool]]);
            flipVOpt    <- (JsonCompat.getAtKeyOpt(Root, "flipV", map): Result[Util.Json.JsonError, Option[Bool]])
        ) yield {
            let pos = Option.getWithDefault(Vec2.zero(), posOpt);
            let size = Option.getWithDefault(Vec2.zero(), sizeOpt);
            let rect = TextureRect.make(texture, pos, size)
                |> applyOpt(rotationOpt, setTextureRectRotation)
                |> applyOpt(skewOpt, setTextureRectSkew)
                |> applyOpt(zIndexOpt, setTextureRectZIndex)
                |> applyOpt(visibleOpt, setTextureRectVisible)
                |> applyOpt(modulateOpt, setTextureRectModulate)
                |> applyOpt(alphaOpt, setTextureRectAlpha)
                |> applyOpt(flipHOpt, TextureRect.setFlipH)
                |> applyOpt(flipVOpt, TextureRect.setFlipV);
            EngineNode.TextureRectWithState(rect, tag)
        }

    def setTextureRectModulate(c: Color, rect: TextureRect): TextureRect =
        CanvasItem.setModulate(c, rect)

    def setTextureRectRotation(rot: Float64, rect: TextureRect): TextureRect =
        Node2D.setRotation(rot, rect)

    def setTextureRectSkew(skew: Float64, rect: TextureRect): TextureRect =
        Node2D.setSkew(skew, rect)

    def setTextureRectAlpha(alpha: Float64, rect: TextureRect): TextureRect =
        TextureRect.setAlpha(Float64.truncateToFloat32(alpha), rect)

    def setTextureRectZIndex(z: Int32, rect: TextureRect): TextureRect =
        CanvasItem.setZIndex(z, rect)

    def setTextureRectVisible(v: Bool, rect: TextureRect): TextureRect =
        CanvasItem.setVisible(v, rect)

    /// テキストベース Button (`Button.make(text, fontAtlas, fontSize, size)`) を JSON から構築する。
    /// FontAtlas が必須なので loadSceneWithFont 経由で呼ばれる前提。
    /// 必須フィールド: text, fontSize, size。任意: pos / visible.
    def buildButton(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                    fontAtlas: Option[FontAtlas],
                    map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        match fontAtlas {
            case None => Err(JsonCompat.jsonError(Root, Set#{"FontAtlas (loadSceneWithFont required for Button)"}))
            case Some(font) =>
                forM (
                    tag         <- parseTagField(tagParser, map);
                    text        <- (JsonCompat.getAtKey(Root, "text", map): Result[Util.Json.JsonError, String]);
                    fontSize    <- (JsonCompat.getAtKey(Root, "fontSize", map): Result[Util.Json.JsonError, Float64]);
                    size        <- parseVec2("size", map);
                    posOpt      <- parseVec2Opt("pos", map);
                    visibleOpt  <- (JsonCompat.getAtKeyOpt(Root, "visible", map): Result[Util.Json.JsonError, Option[Bool]]);
                    zIndexOpt   <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[Util.Json.JsonError, Option[Int32]]);
                    modulateOpt <- parseColorOpt("modulate", map)
                ) yield {
                    let pos = Option.getWithDefault(Vec2.zero(), posOpt);
                    let button = Button.make(text, font, fontSize, size)
                        |> Node2D.setPosition(pos)
                        |> applyOpt(visibleOpt, (v, b) -> CanvasItem.setVisible(v, b))
                        |> applyOpt(zIndexOpt, (z, b) -> CanvasItem.setZIndex(z, b))
                        |> applyOpt(modulateOpt, (c, b) -> CanvasItem.setModulate(c, b));
                    EngineNode.ButtonWithState(button, tag)
                }
        }

    def buildTextureButton(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                           map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        forM (
            tag               <- parseTagField(tagParser, map);
            posOpt            <- parseVec2Opt("pos", map);
            scale             <- parseVec2("scale", map);
            sizeOpt           <- parseVec2Opt("size", map);
            textureNormal     <- (JsonCompat.getAtKey(Root, "textureNormal", map): Result[Util.Json.JsonError, String]);
            texturePressedOpt <- (JsonCompat.getAtKeyOpt(Root, "texturePressed", map): Result[Util.Json.JsonError, Option[String]]);
            centeredOpt       <- (JsonCompat.getAtKeyOpt(Root, "centered", map): Result[Util.Json.JsonError, Option[Bool]]);
            visibleOpt        <- (JsonCompat.getAtKeyOpt(Root, "visible", map): Result[Util.Json.JsonError, Option[Bool]]);
            zIndexOpt         <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[Util.Json.JsonError, Option[Int32]]);
            modulateOpt       <- parseColorOpt("modulate", map)
        ) yield {
            let pos = Option.getWithDefault(Vec2.zero(), posOpt);
            let size = Option.getWithDefault(Vec2.zero(), sizeOpt);
            let button = TextureButton.make(textureNormal, size)
                |> Node2D.setPosition(pos)
                |> Node2D.setScale(scale)
                |> applyTexturePressed(texturePressedOpt)
                |> applyCentered(centeredOpt)
                |> applyButtonVisible(visibleOpt)
                |> applyOpt(zIndexOpt, (z, b) -> CanvasItem.setZIndex(z, b))
                |> applyOpt(modulateOpt, (c, b) -> CanvasItem.setModulate(c, b));
            EngineNode.TextureButtonWithState(button, tag)
        }

    def buildStaticBody2D(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                          map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        forM (
            tag                <- parseTagField(tagParser, map);
            pos                <- parseVec2("pos", map);
            shape              <- parseShape(map);
            collisionLayerOpt  <- (JsonCompat.getAtKeyOpt(Root, "collisionLayer", map): Result[Util.Json.JsonError, Option[Int32]]);
            collisionMaskOpt   <- (JsonCompat.getAtKeyOpt(Root, "collisionMask", map): Result[Util.Json.JsonError, Option[Int32]]);
            visibleOpt         <- (JsonCompat.getAtKeyOpt(Root, "visible", map): Result[Util.Json.JsonError, Option[Bool]]);
            zIndexOpt          <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[Util.Json.JsonError, Option[Int32]]);
            modulateOpt        <- parseColorOpt("modulate", map)
        ) yield {
            let body = StaticBody2D.make(pos, shape)
                |> applyOpt(collisionLayerOpt, StaticBody2D.setCollisionLayer)
                |> applyOpt(collisionMaskOpt, StaticBody2D.setCollisionMask)
                |> applyOpt(visibleOpt, (v, b) -> CanvasItem.setVisible(v, b))
                |> applyOpt(zIndexOpt, (z, b) -> CanvasItem.setZIndex(z, b))
                |> applyOpt(modulateOpt, (c, b) -> CanvasItem.setModulate(c, b));
            EngineNode.StaticBody2DWithState(body, tag)
        }

    def buildRigidBody2D(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                         map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        forM (
            tag               <- parseTagField(tagParser, map);
            pos               <- parseVec2("pos", map);
            shape             <- parseShape(map);
            gravityScaleOpt   <- (JsonCompat.getAtKeyOpt(Root, "gravityScale", map): Result[Util.Json.JsonError, Option[Float64]]);
            linearVelocityOpt <- parseVec2Opt("linearVelocity", map);
            collisionLayerOpt <- (JsonCompat.getAtKeyOpt(Root, "collisionLayer", map): Result[Util.Json.JsonError, Option[Int32]]);
            collisionMaskOpt  <- (JsonCompat.getAtKeyOpt(Root, "collisionMask", map): Result[Util.Json.JsonError, Option[Int32]]);
            visibleOpt        <- (JsonCompat.getAtKeyOpt(Root, "visible", map): Result[Util.Json.JsonError, Option[Bool]]);
            zIndexOpt         <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[Util.Json.JsonError, Option[Int32]]);
            modulateOpt       <- parseColorOpt("modulate", map)
        ) yield {
            let body = RigidBody2D.make(pos, shape)
                |> applyGravityScale(gravityScaleOpt)
                |> applyLinearVelocity(linearVelocityOpt)
                |> applyOpt(collisionLayerOpt, RigidBody2D.setCollisionLayer)
                |> applyOpt(collisionMaskOpt, RigidBody2D.setCollisionMask)
                |> applyOpt(visibleOpt, (v, b) -> CanvasItem.setVisible(v, b))
                |> applyOpt(zIndexOpt, (z, b) -> CanvasItem.setZIndex(z, b))
                |> applyOpt(modulateOpt, (c, b) -> CanvasItem.setModulate(c, b));
            EngineNode.RigidBody2DWithState(body, tag)
        }

    def buildArea2D(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                    map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        forM (
            tag               <- parseTagField(tagParser, map);
            pos               <- parseVec2("pos", map);
            shape             <- parseShape(map);
            monitoringOpt     <- (JsonCompat.getAtKeyOpt(Root, "monitoring", map): Result[Util.Json.JsonError, Option[Bool]]);
            collisionLayerOpt <- (JsonCompat.getAtKeyOpt(Root, "collisionLayer", map): Result[Util.Json.JsonError, Option[Int32]]);
            collisionMaskOpt  <- (JsonCompat.getAtKeyOpt(Root, "collisionMask", map): Result[Util.Json.JsonError, Option[Int32]]);
            visibleOpt        <- (JsonCompat.getAtKeyOpt(Root, "visible", map): Result[Util.Json.JsonError, Option[Bool]]);
            zIndexOpt         <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[Util.Json.JsonError, Option[Int32]]);
            modulateOpt       <- parseColorOpt("modulate", map)
        ) yield {
            let area = Area2D.make(pos, shape)
                |> applyMonitoring(monitoringOpt)
                |> applyOpt(collisionLayerOpt, Area2D.setCollisionLayer)
                |> applyOpt(collisionMaskOpt, Area2D.setCollisionMask)
                |> applyOpt(visibleOpt, (v, a) -> CanvasItem.setVisible(v, a))
                |> applyOpt(zIndexOpt, (z, a) -> CanvasItem.setZIndex(z, a))
                |> applyOpt(modulateOpt, (c, a) -> CanvasItem.setModulate(c, a));
            EngineNode.Area2DWithState(area, tag)
        }

    /// JSON の 1 アニメーション定義を SpriteFrames.Animation に変換する
    def parseAnimation(animMap: Map[String, Util.Json.Json]):
                        Result[Util.Json.JsonError, SpriteFrames.Animation] =
        forM (
            loops      <- (JsonCompat.getAtKey(Root, "loop", animMap): Result[Util.Json.JsonError, Bool]);
            speed      <- (JsonCompat.getAtKey(Root, "speed", animMap): Result[Util.Json.JsonError, Float64]);
            frameMaps  <- (JsonCompat.getAtKey(Root, "frames", animMap):
                            Result[Util.Json.JsonError, List[Map[String, Util.Json.Json]]]);
            frames     <- Result.traverse(parseFrame, frameMaps)
        ) yield ({loop = loops, speed = speed, frames = frames}: SpriteFrames.Animation)

    /// JSON の 1 フレーム定義を SpriteFrames.Frame に変換する。
    /// duration は任意（デフォルト 1.0）、region も任意（None ならテクスチャ全体）。
    /// region JSON 形式: `{"pos": [x, y], "size": [w, h]}` (Godot Rect2 と同じ位置/サイズ)。
    def parseFrame(frameMap: Map[String, Util.Json.Json]):
                    Result[Util.Json.JsonError, SpriteFrames.Frame] =
        forM (
            texture      <- (JsonCompat.getAtKey(Root, "texture", frameMap): Result[Util.Json.JsonError, String]);
            durationOpt  <- (JsonCompat.getAtKeyOpt(Root, "duration", frameMap):
                              Result[Util.Json.JsonError, Option[Float64]]);
            regionMapOpt <- (JsonCompat.getAtKeyOpt(Root, "region", frameMap):
                              Result[Util.Json.JsonError, Option[Map[String, Util.Json.Json]]]);
            regionOpt    <- parseRegionOpt(regionMapOpt)
        ) yield ({texture = texture,
                  regionRect = regionOpt,
                  duration = Option.getWithDefault(1.0, durationOpt)}: SpriteFrames.Frame)

    /// region が JSON 上に存在すれば `{"pos": [...], "size": [...]}` を Rect2 に
    /// デコード、無ければ None を返す。
    def parseRegionOpt(regionMapOpt: Option[Map[String, Util.Json.Json]]):
                        Result[Util.Json.JsonError, Option[Rect2.Rect2]] =
        match regionMapOpt {
            case None    => Ok(None)
            case Some(m) => forM (
                              pos  <- parseVec2("pos", m);
                              size <- parseVec2("size", m)
                            ) yield Some({position = pos, size = size})
        }

    /// JSON の spriteFrames オブジェクトを SpriteFrames リソースに変換する
    def parseSpriteFrames(sfMap: Map[String, Util.Json.Json]):
                           Result[Util.Json.JsonError, SpriteFrames] =
        Map.toList(sfMap)
            |> List.foldLeft((acc, pair) ->
                let (name, json) = pair;
                forM (
                    sf       <- acc;
                    animMap  <- match json {
                        case JObject(m) => Ok(m)
                        case _             => Err(JsonCompat.jsonError(Root, Set#{"JObject for animation '${name}'"}))
                    };
                    anim     <- parseAnimation(animMap)
                ) yield SpriteFrames.addAnimation(name, anim, sf),
                Ok(SpriteFrames.empty()))

    def buildAnimatedSprite2D(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                               map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        forM (
            tag            <- parseTagField(tagParser, map);
            pos            <- parseVec2("pos", map);
            scale          <- parseVec2("scale", map);
            sfMap          <- (JsonCompat.getAtKey(Root, "spriteFrames", map):
                                Result[Util.Json.JsonError, Map[String, Util.Json.Json]]);
            spriteFrames   <- parseSpriteFrames(sfMap);
            animation      <- (JsonCompat.getAtKey(Root, "animation", map): Result[Util.Json.JsonError, String]);
            autoplayOpt    <- (JsonCompat.getAtKeyOpt(Root, "autoplay", map):
                                Result[Util.Json.JsonError, Option[String]]);
            speedScaleOpt  <- (JsonCompat.getAtKeyOpt(Root, "speedScale", map):
                                Result[Util.Json.JsonError, Option[Float64]]);
            rotationOpt    <- (JsonCompat.getAtKeyOpt(Root, "rotation", map):
                                Result[Util.Json.JsonError, Option[Float64]]);
            skewOpt        <- (JsonCompat.getAtKeyOpt(Root, "skew", map):
                                Result[Util.Json.JsonError, Option[Float64]]);
            zIndexOpt      <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map):
                                Result[Util.Json.JsonError, Option[Int32]]);
            visibleOpt     <- (JsonCompat.getAtKeyOpt(Root, "visible", map):
                                Result[Util.Json.JsonError, Option[Bool]]);
            playingOpt     <- (JsonCompat.getAtKeyOpt(Root, "playing", map):
                                Result[Util.Json.JsonError, Option[Bool]]);
            frameOpt       <- (JsonCompat.getAtKeyOpt(Root, "frame", map):
                                Result[Util.Json.JsonError, Option[Int32]]);
            centeredOpt    <- (JsonCompat.getAtKeyOpt(Root, "centered", map):
                                Result[Util.Json.JsonError, Option[Bool]]);
            offsetOpt      <- parseVec2Opt("offset", map);
            flipHOpt       <- (JsonCompat.getAtKeyOpt(Root, "flipH", map):
                                Result[Util.Json.JsonError, Option[Bool]]);
            flipVOpt       <- (JsonCompat.getAtKeyOpt(Root, "flipV", map):
                                Result[Util.Json.JsonError, Option[Bool]]);
            modulateOpt    <- parseColorOpt("modulate", map);
            ySortEnabledOpt <- (JsonCompat.getAtKeyOpt(Root, "ySortEnabled", map): Result[Util.Json.JsonError, Option[Bool]])
        ) yield {
            let sprite = AnimatedSprite2D.make(spriteFrames, {animation = animation}, pos, scale)
                |> AnimatedSprite2D.setAutoplay(Option.getWithDefault("", autoplayOpt))
                |> AnimatedSprite2D.setSpeedScale(Option.getWithDefault(1.0, speedScaleOpt))
                |> applyOpt(rotationOpt, Node2D.setRotation)
                |> applyOpt(skewOpt, Node2D.setSkew)
                |> applyOpt(zIndexOpt, setAnimSpriteZIndex)
                |> applyOpt(visibleOpt, setAnimSpriteVisible)
                |> applyOpt(playingOpt, AnimatedSprite2D.setPlaying)
                |> applyOpt(frameOpt, AnimatedSprite2D.setFrame)
                |> applyOpt(centeredOpt, AnimatedSprite2D.setCentered)
                |> applyOpt(offsetOpt, AnimatedSprite2D.setOffset)
                |> applyOpt(flipHOpt, AnimatedSprite2D.setFlipH)
                |> applyOpt(flipVOpt, AnimatedSprite2D.setFlipV)
                |> applyOpt(modulateOpt, setAnimSpriteModulate)
                |> applyOpt(ySortEnabledOpt, setAnimSpriteYSortEnabled);
            EngineNode.AnimSprite2DWithState(sprite, tag)
        }

    def setAnimSpriteZIndex(z: Int32, s: AnimatedSprite2D): AnimatedSprite2D =
        CanvasItem.setZIndex(z, s)
    def setAnimSpriteVisible(v: Bool, s: AnimatedSprite2D): AnimatedSprite2D =
        CanvasItem.setVisible(v, s)
    def setAnimSpriteModulate(c: Color, s: AnimatedSprite2D): AnimatedSprite2D =
        CanvasItem.setModulate(c, s)

    def setAnimSpriteYSortEnabled(v: Bool, sprite: AnimatedSprite2D): AnimatedSprite2D =
        CanvasItem.setYSortEnabled(v, sprite)

    def buildCharacterBody2D(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                              map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        forM (
            tag             <- parseTagField(tagParser, map);
            pos             <- parseVec2("pos", map);
            shape           <- parseShape(map);
            moveSpeedOpt    <- (JsonCompat.getAtKeyOpt(Root, "moveSpeed", map): Result[Util.Json.JsonError, Option[Float64]]);
            velocityOpt     <- parseVec2Opt("velocity", map);
            scaleOpt        <- parseVec2Opt("scale", map);
            rotationOpt     <- (JsonCompat.getAtKeyOpt(Root, "rotation", map): Result[Util.Json.JsonError, Option[Float64]]);
            skewOpt         <- (JsonCompat.getAtKeyOpt(Root, "skew", map): Result[Util.Json.JsonError, Option[Float64]]);
            visibleOpt      <- (JsonCompat.getAtKeyOpt(Root, "visible", map): Result[Util.Json.JsonError, Option[Bool]]);
            zIndexOpt       <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[Util.Json.JsonError, Option[Int32]]);
            monitoringOpt     <- (JsonCompat.getAtKeyOpt(Root, "monitoring", map): Result[Util.Json.JsonError, Option[Bool]]);
            monitorableOpt    <- (JsonCompat.getAtKeyOpt(Root, "monitorable", map): Result[Util.Json.JsonError, Option[Bool]]);
            priorityOpt       <- (JsonCompat.getAtKeyOpt(Root, "priority", map): Result[Util.Json.JsonError, Option[Int32]]);
            collisionLayerOpt <- (JsonCompat.getAtKeyOpt(Root, "collisionLayer", map): Result[Util.Json.JsonError, Option[Int32]]);
            collisionMaskOpt  <- (JsonCompat.getAtKeyOpt(Root, "collisionMask", map): Result[Util.Json.JsonError, Option[Int32]]);
            upDirectionOpt    <- parseVec2Opt("upDirection", map);
            floorMaxAngleOpt  <- (JsonCompat.getAtKeyOpt(Root, "floorMaxAngle", map): Result[Util.Json.JsonError, Option[Float64]]);
            maxSlidesOpt      <- (JsonCompat.getAtKeyOpt(Root, "maxSlides", map): Result[Util.Json.JsonError, Option[Int32]]);
            modulateOpt       <- parseColorOpt("modulate", map)
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
                |> applyOpt(collisionLayerOpt, CharacterBody2D.setCollisionLayer)
                |> applyOpt(collisionMaskOpt, CharacterBody2D.setCollisionMask)
                |> applyOpt(upDirectionOpt, CharacterBody2D.setUpDirection)
                |> applyOpt(floorMaxAngleOpt, CharacterBody2D.setFloorMaxAngle)
                |> applyOpt(maxSlidesOpt, CharacterBody2D.setMaxSlides)
                |> applyOpt(modulateOpt, (c, b) -> CanvasItem.setModulate(c, b));
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

    def buildMarker2D(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                      map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        forM (
            tag         <- parseTagField(tagParser, map);
            pos         <- parseVec2("pos", map);
            scaleOpt    <- parseVec2Opt("scale", map);
            rotationOpt <- (JsonCompat.getAtKeyOpt(Root, "rotation", map): Result[Util.Json.JsonError, Option[Float64]]);
            skewOpt     <- (JsonCompat.getAtKeyOpt(Root, "skew", map): Result[Util.Json.JsonError, Option[Float64]]);
            visibleOpt  <- (JsonCompat.getAtKeyOpt(Root, "visible", map): Result[Util.Json.JsonError, Option[Bool]]);
            zIndexOpt   <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[Util.Json.JsonError, Option[Int32]]);
            modulateOpt <- parseColorOpt("modulate", map);
            ySortEnabledOpt <- (JsonCompat.getAtKeyOpt(Root, "ySortEnabled", map): Result[Util.Json.JsonError, Option[Bool]])
        ) yield {
            let marker = Marker2D.make(pos)
                |> applyOpt(scaleOpt, setMarker2DScale)
                |> applyOpt(rotationOpt, setMarker2DRotation)
                |> applyOpt(skewOpt, setMarker2DSkew)
                |> applyOpt(visibleOpt, setMarker2DVisible)
                |> applyOpt(zIndexOpt, setMarker2DZIndex)
                |> applyOpt(modulateOpt, (c, m) -> CanvasItem.setModulate(c, m))
                |> applyOpt(ySortEnabledOpt, setMarker2DYSortEnabled);
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

    def setMarker2DYSortEnabled(v: Bool, marker: Marker2D): Marker2D =
        CanvasItem.setYSortEnabled(v, marker)

    /// AudioStreamPlayer ノードを scene.json から組み立てる。
    /// 必須: `stream` (サウンドマニフェスト上の論理名)
    /// オプション: `autoplay` (default false), `loop` (default false), `volume` (default 1.0)
    /// 注: scene attach 時の play 自体は `applyAudioAttach` が後段で行うため、ここでは
    /// 純粋にノード生成だけ行う。
    def buildAudioStreamPlayer(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                                 map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        forM (
            tag         <- parseTagField(tagParser, map);
            stream      <- (JsonCompat.getAtKey(Root, "stream", map): Result[Util.Json.JsonError, String]);
            autoplayOpt <- (JsonCompat.getAtKeyOpt(Root, "autoplay", map): Result[Util.Json.JsonError, Option[Bool]]);
            loopOpt     <- (JsonCompat.getAtKeyOpt(Root, "loop", map): Result[Util.Json.JsonError, Option[Bool]]);
            volumeOpt   <- (JsonCompat.getAtKeyOpt(Root, "volume", map): Result[Util.Json.JsonError, Option[Float64]])
        ) yield {
            let player = AudioStreamPlayer.make(stream)
                |> applyOpt(autoplayOpt, AudioStreamPlayer.setAutoplay)
                |> applyOpt(loopOpt, AudioStreamPlayer.setLoop)
                |> applyOpt(volumeOpt, (v, p) ->
                    AudioStreamPlayer.setVolumeField(
                        Float64.tryToFloat32(v) |> Option.getWithDefault(1.0f32), p));
            EngineNode.AudioStreamPlayerWithState(player, tag)
        }

    def buildCamera2D(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                      map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        forM (
            tag                     <- parseTagField(tagParser, map);
            pos                     <- parseVec2("pos", map);
            offsetOpt               <- parseVec2Opt("offset", map);
            zoomOpt                 <- parseVec2Opt("zoom", map);
            scaleOpt                <- parseVec2Opt("scale", map);
            rotationOpt             <- (JsonCompat.getAtKeyOpt(Root, "rotation", map): Result[Util.Json.JsonError, Option[Float64]]);
            skewOpt                 <- (JsonCompat.getAtKeyOpt(Root, "skew", map): Result[Util.Json.JsonError, Option[Float64]]);
            visibleOpt              <- (JsonCompat.getAtKeyOpt(Root, "visible", map): Result[Util.Json.JsonError, Option[Bool]]);
            zIndexOpt               <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[Util.Json.JsonError, Option[Int32]]);
            enabledOpt              <- (JsonCompat.getAtKeyOpt(Root, "enabled", map): Result[Util.Json.JsonError, Option[Bool]]);
            anchorModeOpt           <- (JsonCompat.getAtKeyOpt(Root, "anchorMode", map): Result[Util.Json.JsonError, Option[String]]);
            anchorMode              <- parseAnchorMode(anchorModeOpt);
            processCallbackOpt      <- (JsonCompat.getAtKeyOpt(Root, "processCallback", map): Result[Util.Json.JsonError, Option[String]]);
            processCallback         <- parseProcessCallback(processCallbackOpt);
            ignoreRotationOpt       <- (JsonCompat.getAtKeyOpt(Root, "ignoreRotation", map): Result[Util.Json.JsonError, Option[Bool]]);
            limitLeftOpt            <- (JsonCompat.getAtKeyOpt(Root, "limitLeft", map): Result[Util.Json.JsonError, Option[Int32]]);
            limitTopOpt             <- (JsonCompat.getAtKeyOpt(Root, "limitTop", map): Result[Util.Json.JsonError, Option[Int32]]);
            limitRightOpt           <- (JsonCompat.getAtKeyOpt(Root, "limitRight", map): Result[Util.Json.JsonError, Option[Int32]]);
            limitBottomOpt          <- (JsonCompat.getAtKeyOpt(Root, "limitBottom", map): Result[Util.Json.JsonError, Option[Int32]]);
            limitSmoothedOpt        <- (JsonCompat.getAtKeyOpt(Root, "limitSmoothed", map): Result[Util.Json.JsonError, Option[Bool]]);
            posSmoothEnabledOpt     <- (JsonCompat.getAtKeyOpt(Root, "positionSmoothingEnabled", map): Result[Util.Json.JsonError, Option[Bool]]);
            posSmoothSpeedOpt       <- (JsonCompat.getAtKeyOpt(Root, "positionSmoothingSpeed", map): Result[Util.Json.JsonError, Option[Float64]]);
            rotSmoothEnabledOpt     <- (JsonCompat.getAtKeyOpt(Root, "rotationSmoothingEnabled", map): Result[Util.Json.JsonError, Option[Bool]]);
            rotSmoothSpeedOpt       <- (JsonCompat.getAtKeyOpt(Root, "rotationSmoothingSpeed", map): Result[Util.Json.JsonError, Option[Float64]]);
            dragHEnabledOpt         <- (JsonCompat.getAtKeyOpt(Root, "dragHorizontalEnabled", map): Result[Util.Json.JsonError, Option[Bool]]);
            dragVEnabledOpt         <- (JsonCompat.getAtKeyOpt(Root, "dragVerticalEnabled", map): Result[Util.Json.JsonError, Option[Bool]]);
            dragLeftOpt             <- (JsonCompat.getAtKeyOpt(Root, "dragLeftMargin", map): Result[Util.Json.JsonError, Option[Float64]]);
            dragRightOpt            <- (JsonCompat.getAtKeyOpt(Root, "dragRightMargin", map): Result[Util.Json.JsonError, Option[Float64]]);
            dragTopOpt              <- (JsonCompat.getAtKeyOpt(Root, "dragTopMargin", map): Result[Util.Json.JsonError, Option[Float64]]);
            dragBottomOpt           <- (JsonCompat.getAtKeyOpt(Root, "dragBottomMargin", map): Result[Util.Json.JsonError, Option[Float64]]);
            modulateOpt             <- parseColorOpt("modulate", map)
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
                |> applyOpt(dragBottomOpt, Camera2D.setDragBottomMargin)
                |> applyOpt(modulateOpt, (c, cam) -> CanvasItem.setModulate(c, cam));
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
    def parseAnchorMode(opt: Option[String]): Result[Util.Json.JsonError, Camera2DAnchorMode] =
        match opt {
            case None                  => Ok(Camera2DAnchorMode.DragCenter)
            case Some("DragCenter")    => Ok(Camera2DAnchorMode.DragCenter)
            case Some("FixedTopLeft")  => Ok(Camera2DAnchorMode.FixedTopLeft)
            case Some(other)           =>
                Err(JsonCompat.jsonError(Root, Set#{"DragCenter|FixedTopLeft (got: ${other})"}))
        }

    /// "PhysicsProcess" / "IdleProcess" を Camera2DProcessCallback に変換する。省略時は IdleProcess
    def parseProcessCallback(opt: Option[String]): Result[Util.Json.JsonError, Camera2DProcessCallback] =
        match opt {
            case None                    => Ok(Camera2DProcessCallback.IdleProcess)
            case Some("PhysicsProcess")  => Ok(Camera2DProcessCallback.PhysicsProcess)
            case Some("IdleProcess")     => Ok(Camera2DProcessCallback.IdleProcess)
            case Some(other)             =>
                Err(JsonCompat.jsonError(Root, Set#{"PhysicsProcess|IdleProcess (got: ${other})"}))
        }

    def buildLabel2D(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                     fontAtlas: Option[FontAtlas],
                     map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        match fontAtlas {
            case None => Err(JsonCompat.jsonError(Root, Set#{"FontAtlas (loadSceneWithFont required for Label2D)"}))
            case Some(font) =>
                forM (
                    tag         <- parseTagField(tagParser, map);
                    text        <- (JsonCompat.getAtKey(Root, "text", map): Result[Util.Json.JsonError, String]);
                    pos         <- parseVec2("pos", map);
                    fontSize    <- (JsonCompat.getAtKey(Root, "fontSize", map): Result[Util.Json.JsonError, Float64]);
                    hAlignOpt   <- (JsonCompat.getAtKeyOpt(Root, "horizontalAlignment", map):
                                     Result[Util.Json.JsonError, Option[String]]);
                    vAlignOpt   <- (JsonCompat.getAtKeyOpt(Root, "verticalAlignment", map):
                                     Result[Util.Json.JsonError, Option[String]]);
                    hAlign      <- parseHorizontalAlignment(hAlignOpt);
                    vAlign      <- parseVerticalAlignment(vAlignOpt);
                    visibleOpt  <- (JsonCompat.getAtKeyOpt(Root, "visible", map): Result[Util.Json.JsonError, Option[Bool]]);
                    zIndexOpt   <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[Util.Json.JsonError, Option[Int32]]);
                    rotationOpt <- (JsonCompat.getAtKeyOpt(Root, "rotation", map): Result[Util.Json.JsonError, Option[Float64]]);
                    skewOpt     <- (JsonCompat.getAtKeyOpt(Root, "skew", map): Result[Util.Json.JsonError, Option[Float64]]);
                    modulateOpt <- parseColorOpt("modulate", map)
                ) yield {
                    let label = Label2D.make(text, font, fontSize)
                        |> Node2D.setPosition(pos)
                        |> Label2D.setHorizontalAlignment(hAlign)
                        |> Label2D.setVerticalAlignment(vAlign)
                        |> applyLabelVisible(visibleOpt)
                        |> applyLabelZIndex(zIndexOpt)
                        |> applyOpt(rotationOpt, (r, l) -> Node2D.setRotation(r, l))
                        |> applyOpt(skewOpt, (s, l) -> Node2D.setSkew(s, l))
                        |> applyOpt(modulateOpt, setLabelModulate);
                    EngineNode.Label2DWithState(label, tag)
                }
        }

    /// JSON の文字列を HorizontalAlignment に変換する。省略時は Left
    def parseHorizontalAlignment(opt: Option[String]): Result[Util.Json.JsonError, HorizontalAlignment] =
        match opt {
            case None           => Ok(HorizontalAlignment.Left)
            case Some("left")   => Ok(HorizontalAlignment.Left)
            case Some("center") => Ok(HorizontalAlignment.Center)
            case Some("right")  => Ok(HorizontalAlignment.Right)
            case Some("fill")   => Ok(HorizontalAlignment.Fill)
            case Some(other)    =>
                Err(JsonCompat.jsonError(Root, Set#{"left|center|right|fill (got: ${other})"}))
        }

    /// JSON の文字列を VerticalAlignment に変換する。省略時は Top
    def parseVerticalAlignment(opt: Option[String]): Result[Util.Json.JsonError, VerticalAlignment] =
        match opt {
            case None           => Ok(VerticalAlignment.Top)
            case Some("top")    => Ok(VerticalAlignment.Top)
            case Some("center") => Ok(VerticalAlignment.Center)
            case Some("bottom") => Ok(VerticalAlignment.Bottom)
            case Some("fill")   => Ok(VerticalAlignment.Fill)
            case Some(other)    =>
                Err(JsonCompat.jsonError(Root, Set#{"top|center|bottom|fill (got: ${other})"}))
        }

    /// `{"r": 1.0, "g": 1.0, "b": 1.0}` 形式の JSON オブジェクトを Color (Float32) に変換する。
    /// 数値は JSON 上 Float64 として読み、Float32 に縮小する
    def parseColor(key: String,
                   map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, Color] =
        forM (
            colorMap <- (JsonCompat.getAtKey(Root, key, map): Result[Util.Json.JsonError, Map[String, Util.Json.Json]]);
            r        <- (JsonCompat.getAtKey(Root, "r", colorMap): Result[Util.Json.JsonError, Float64]);
            g        <- (JsonCompat.getAtKey(Root, "g", colorMap): Result[Util.Json.JsonError, Float64]);
            b        <- (JsonCompat.getAtKey(Root, "b", colorMap): Result[Util.Json.JsonError, Float64])
        ) yield ({
            r = Float64.truncateToFloat32(r),
            g = Float64.truncateToFloat32(g),
            b = Float64.truncateToFloat32(b)
        }: Color)

    def buildColorRect(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                       map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        forM (
            tag         <- parseTagField(tagParser, map);
            posOpt      <- parseVec2Opt("pos", map);
            sizeOpt     <- parseVec2Opt("size", map);
            color       <- parseColor("color", map);
            alphaOpt    <- (JsonCompat.getAtKeyOpt(Root, "alpha", map): Result[Util.Json.JsonError, Option[Float64]]);
            visibleOpt  <- (JsonCompat.getAtKeyOpt(Root, "visible", map): Result[Util.Json.JsonError, Option[Bool]]);
            zIndexOpt   <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[Util.Json.JsonError, Option[Int32]]);
            rotationOpt <- (JsonCompat.getAtKeyOpt(Root, "rotation", map): Result[Util.Json.JsonError, Option[Float64]]);
            skewOpt     <- (JsonCompat.getAtKeyOpt(Root, "skew", map): Result[Util.Json.JsonError, Option[Float64]]);
            modulateOpt <- parseColorOpt("modulate", map)
        ) yield {
            let pos = Option.getWithDefault(Vec2.zero(), posOpt);
            let size = Option.getWithDefault(Vec2.zero(), sizeOpt);
            let rect = ColorRect.make(size, color)
                |> Node2D.setPosition(pos)
                |> applyOpt(alphaOpt, setColorRectAlpha)
                |> applyOpt(visibleOpt, setColorRectVisible)
                |> applyOpt(zIndexOpt, setColorRectZIndex)
                |> applyOpt(rotationOpt, (r, c) -> Node2D.setRotation(r, c))
                |> applyOpt(skewOpt, (s, c) -> Node2D.setSkew(s, c))
                |> applyOpt(modulateOpt, (c, rect) -> CanvasItem.setModulate(c, rect));
            EngineNode.ColorRectWithState(rect, tag)
        }

    /// Polygon2D を JSON から構築する。`radius` があれば円（12 角形）、無ければ `points`
    /// （[[x,y],...] の配列）を頂点列とする。色は `color`、その他は ColorRect と同様。
    def buildPolygon2D(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                       map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        forM (
            tag         <- parseTagField(tagParser, map);
            posOpt      <- parseVec2Opt("pos", map);
            scaleOpt    <- parseVec2Opt("scale", map);
            color       <- parseColor("color", map);
            radiusOpt   <- (JsonCompat.getAtKeyOpt(Root, "radius", map): Result[Util.Json.JsonError, Option[Float64]]);
            pointsOpt   <- (JsonCompat.getAtKeyOpt(Root, "points", map): Result[Util.Json.JsonError, Option[List[(Float64, Float64)]]]);
            alphaOpt    <- (JsonCompat.getAtKeyOpt(Root, "alpha", map): Result[Util.Json.JsonError, Option[Float64]]);
            visibleOpt  <- (JsonCompat.getAtKeyOpt(Root, "visible", map): Result[Util.Json.JsonError, Option[Bool]]);
            zIndexOpt   <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[Util.Json.JsonError, Option[Int32]]);
            rotationOpt <- (JsonCompat.getAtKeyOpt(Root, "rotation", map): Result[Util.Json.JsonError, Option[Float64]]);
            modulateOpt <- parseColorOpt("modulate", map)
        ) yield {
            let pos = Option.getWithDefault(Vec2.zero(), posOpt);
            let base = match radiusOpt {
                case Some(r) => Polygon2D.circle(r, color)
                case None    =>
                    let pts = Option.getWithDefault(Nil, pointsOpt)
                        |> List.map(xy -> let (x, y) = xy; ({x = x, y = y}: Vec2.Vec2));
                    Polygon2D.make(pts, color)
            };
            let poly = base
                |> Node2D.setPosition(pos)
                |> applyOpt(scaleOpt, (sc, p) -> Node2D.setScale(sc, p))
                |> applyOpt(alphaOpt, (a, p) -> Polygon2D.setAlpha(Float64.truncateToFloat32(a), p))
                |> applyOpt(visibleOpt, (v, p) -> CanvasItem.setVisible(v, p))
                |> applyOpt(zIndexOpt, (z, p) -> CanvasItem.setZIndex(z, p))
                |> applyOpt(rotationOpt, (rot, p) -> Node2D.setRotation(rot, p))
                |> applyOpt(modulateOpt, (c, p) -> CanvasItem.setModulate(c, p));
            EngineNode.Polygon2DWithState(poly, tag)
        }

    /// `{ "type": "Arc2D", "pos": [x,y], "radius": r, "width": w,
    ///    "startAngle": a0, "endAngle": a1, "segments": n, "color": {...}, "alpha": a, "zIndex": z }`
    /// から円弧/リングノードを構築する。startAngle/endAngle はラジアン（既定 0..2π = 全周リング）。
    /// クールダウン表示は前景 Arc2D の endAngle をシーン側で毎フレーム更新する。
    def buildArc2D(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                   map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        forM (
            tag           <- parseTagField(tagParser, map);
            posOpt        <- parseVec2Opt("pos", map);
            scaleOpt      <- parseVec2Opt("scale", map);
            color         <- parseColor("color", map);
            radiusOpt     <- (JsonCompat.getAtKeyOpt(Root, "radius", map): Result[Util.Json.JsonError, Option[Float64]]);
            widthOpt      <- (JsonCompat.getAtKeyOpt(Root, "width", map): Result[Util.Json.JsonError, Option[Float64]]);
            startAngleOpt <- (JsonCompat.getAtKeyOpt(Root, "startAngle", map): Result[Util.Json.JsonError, Option[Float64]]);
            endAngleOpt   <- (JsonCompat.getAtKeyOpt(Root, "endAngle", map): Result[Util.Json.JsonError, Option[Float64]]);
            segmentsOpt   <- (JsonCompat.getAtKeyOpt(Root, "segments", map): Result[Util.Json.JsonError, Option[Int32]]);
            alphaOpt      <- (JsonCompat.getAtKeyOpt(Root, "alpha", map): Result[Util.Json.JsonError, Option[Float64]]);
            visibleOpt    <- (JsonCompat.getAtKeyOpt(Root, "visible", map): Result[Util.Json.JsonError, Option[Bool]]);
            zIndexOpt     <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[Util.Json.JsonError, Option[Int32]]);
            rotationOpt   <- (JsonCompat.getAtKeyOpt(Root, "rotation", map): Result[Util.Json.JsonError, Option[Float64]]);
            modulateOpt   <- parseColorOpt("modulate", map)
        ) yield {
            let pos = Option.getWithDefault(Vec2.zero(), posOpt);
            let radius = Option.getWithDefault(8.0, radiusOpt);
            let width = Option.getWithDefault(2.0, widthOpt);
            let startAngle = Option.getWithDefault(0.0, startAngleOpt);
            let endAngle = Option.getWithDefault(Arc2D.tau(), endAngleOpt);
            let arc = Arc2D.make(radius, width, startAngle, endAngle, color)
                |> Node2D.setPosition(pos)
                |> applyOpt(segmentsOpt, (s, a) -> Arc2D.setSegments(s, a))
                |> applyOpt(scaleOpt, (sc, a) -> Node2D.setScale(sc, a))
                |> applyOpt(alphaOpt, (al, a) -> Arc2D.setAlpha(Float64.truncateToFloat32(al), a))
                |> applyOpt(visibleOpt, (v, a) -> CanvasItem.setVisible(v, a))
                |> applyOpt(zIndexOpt, (z, a) -> CanvasItem.setZIndex(z, a))
                |> applyOpt(rotationOpt, (rot, a) -> Node2D.setRotation(rot, a))
                |> applyOpt(modulateOpt, (c, a) -> CanvasItem.setModulate(c, a));
            EngineNode.Arc2DWithState(arc, tag)
        }

    def setColorRectAlpha(alpha: Float64, rect: ColorRect): ColorRect =
        ColorRect.setAlpha(Float64.truncateToFloat32(alpha), rect)

    def setColorRectVisible(v: Bool, rect: ColorRect): ColorRect =
        CanvasItem.setVisible(v, rect)

    def setColorRectZIndex(z: Int32, rect: ColorRect): ColorRect =
        CanvasItem.setZIndex(z, rect)

    /// `parseColor` のオプション版。指定キーが無ければ `None`。
    /// Panel の borderColor のように、未指定なら描画なしを意図するケースで使う。
    def parseColorOpt(key: String,
                      map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, Option[Color]] =
        forM (
            colorMapOpt <- (JsonCompat.getAtKeyOpt(Root, key, map): Result[Util.Json.JsonError, Option[Map[String, Util.Json.Json]]]);
            colorOpt    <- match colorMapOpt {
                case None    => (Ok(None): Result[Util.Json.JsonError, Option[Color]])
                case Some(m) => forM (
                    r <- (JsonCompat.getAtKey(Root, "r", m): Result[Util.Json.JsonError, Float64]);
                    g <- (JsonCompat.getAtKey(Root, "g", m): Result[Util.Json.JsonError, Float64]);
                    b <- (JsonCompat.getAtKey(Root, "b", m): Result[Util.Json.JsonError, Float64])
                ) yield Some(({
                    r = Float64.truncateToFloat32(r),
                    g = Float64.truncateToFloat32(g),
                    b = Float64.truncateToFloat32(b)
                }: Color))
            }
        ) yield colorOpt

    /// `key: {fillColor,fillAlpha,borderColor,borderAlpha,borderWidth,cornerRadius,inset}`
    /// を `SelectedHighlight` に。キー欠落時は `None`（＝ハイライト無効）。各サブ項目は既定値で補完。
    /// `key` を引数化して "selectedHighlight"（選択行）と "rowHighlight"（全行チップ）の両方で使う。
    def parseHighlightAt(key: String, map: Map[String, Util.Json.Json]):
            Result[Util.Json.JsonError, Option[SelectedHighlight]] =
        forM (
            subOpt <- (JsonCompat.getAtKeyOpt(Root, key, map): Result[Util.Json.JsonError, Option[Map[String, Util.Json.Json]]]);
            result <- match subOpt {
                case None    => (Ok(None): Result[Util.Json.JsonError, Option[SelectedHighlight]])
                case Some(m) => forM (
                    fillColorOpt    <- parseColorOpt("fillColor", m);
                    fillAlphaOpt    <- (JsonCompat.getAtKeyOpt(Root, "fillAlpha", m): Result[Util.Json.JsonError, Option[Float64]]);
                    borderColorOpt  <- parseColorOpt("borderColor", m);
                    borderAlphaOpt  <- (JsonCompat.getAtKeyOpt(Root, "borderAlpha", m): Result[Util.Json.JsonError, Option[Float64]]);
                    borderWidthOpt  <- (JsonCompat.getAtKeyOpt(Root, "borderWidth", m): Result[Util.Json.JsonError, Option[Float64]]);
                    cornerRadiusOpt <- (JsonCompat.getAtKeyOpt(Root, "cornerRadius", m): Result[Util.Json.JsonError, Option[Float64]]);
                    insetOpt        <- (JsonCompat.getAtKeyOpt(Root, "inset", m): Result[Util.Json.JsonError, Option[Float64]])
                ) yield Some(({
                    fillColor    = fillColorOpt,
                    fillAlpha    = Option.getWithDefault(1.0f32, Option.map(Float64.truncateToFloat32, fillAlphaOpt)),
                    borderColor  = Option.getWithDefault(({r = 1.0f32, g = 1.0f32, b = 1.0f32}: Color), borderColorOpt),
                    borderAlpha  = Option.getWithDefault(1.0f32, Option.map(Float64.truncateToFloat32, borderAlphaOpt)),
                    borderWidth  = Option.getWithDefault(0.0, borderWidthOpt),
                    cornerRadius = Option.getWithDefault(0.0, cornerRadiusOpt),
                    inset        = Option.getWithDefault(0.0, insetOpt)
                }: SelectedHighlight))
            }
        ) yield result

    def buildPanel(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                   map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        forM (
            tag                <- parseTagField(tagParser, map);
            posOpt             <- parseVec2Opt("pos", map);
            sizeOpt            <- parseVec2Opt("size", map);
            background         <- parseColor("background", map);
            backgroundAlphaOpt <- (JsonCompat.getAtKeyOpt(Root, "backgroundAlpha", map): Result[Util.Json.JsonError, Option[Float64]]);
            borderColorOpt     <- parseColorOpt("border", map);
            borderAlphaOpt     <- (JsonCompat.getAtKeyOpt(Root, "borderAlpha", map): Result[Util.Json.JsonError, Option[Float64]]);
            borderWidthOpt     <- (JsonCompat.getAtKeyOpt(Root, "borderWidth", map): Result[Util.Json.JsonError, Option[Float64]]);
            cornerRadiusOpt    <- (JsonCompat.getAtKeyOpt(Root, "cornerRadius", map): Result[Util.Json.JsonError, Option[Float64]]);
            stripeColorOpt     <- parseColorOpt("stripeColor", map);
            stripeAlphaOpt     <- (JsonCompat.getAtKeyOpt(Root, "stripeAlpha", map): Result[Util.Json.JsonError, Option[Float64]]);
            stripeWidthOpt     <- (JsonCompat.getAtKeyOpt(Root, "stripeWidth", map): Result[Util.Json.JsonError, Option[Float64]]);
            stripePeriodOpt    <- (JsonCompat.getAtKeyOpt(Root, "stripePeriod", map): Result[Util.Json.JsonError, Option[Float64]]);
            visibleOpt         <- (JsonCompat.getAtKeyOpt(Root, "visible", map): Result[Util.Json.JsonError, Option[Bool]]);
            zIndexOpt          <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[Util.Json.JsonError, Option[Int32]]);
            modulateOpt        <- parseColorOpt("modulate", map)
        ) yield {
            let pos = Option.getWithDefault(Vec2.zero(), posOpt);
            let size = Option.getWithDefault(Vec2.zero(), sizeOpt);
            // 斜線ハッチ: stripeWidth が指定されたときのみ適用（色/alpha/period は省略時デフォルト）。
            let stripeColor = Option.getWithDefault({r = 1.0f32, g = 1.0f32, b = 1.0f32}, stripeColorOpt);
            let stripeAlpha = Float64.truncateToFloat32(Option.getWithDefault(1.0, stripeAlphaOpt));
            let stripePeriod = Option.getWithDefault(0.0, stripePeriodOpt);
            let panel = Panel.make(size, background)
                |> Node2D.setPosition(pos)
                |> applyOpt(backgroundAlphaOpt, setPanelBackgroundAlpha)
                |> applyOpt(borderColorOpt, Panel.setBorderColor)
                |> applyOpt(borderAlphaOpt, setPanelBorderAlpha)
                |> applyOpt(borderWidthOpt, Panel.setBorderWidth)
                |> applyOpt(cornerRadiusOpt, Panel.setCornerRadius)
                |> applyOpt(stripeWidthOpt, (w, p) -> Panel.setStripe(stripeColor, stripeAlpha, w, stripePeriod, p))
                |> applyOpt(visibleOpt, setPanelVisible)
                |> applyOpt(zIndexOpt, setPanelZIndex)
                |> applyOpt(modulateOpt, (c, p) -> CanvasItem.setModulate(c, p));
            EngineNode.PanelWithState(panel, tag)
        }

    def setPanelBackgroundAlpha(alpha: Float64, panel: Panel): Panel =
        Panel.setBackgroundAlpha(Float64.truncateToFloat32(alpha), panel)

    def setPanelBorderAlpha(alpha: Float64, panel: Panel): Panel =
        Panel.setBorderAlpha(Float64.truncateToFloat32(alpha), panel)

    def setPanelVisible(v: Bool, panel: Panel): Panel =
        CanvasItem.setVisible(v, panel)

    def setPanelZIndex(z: Int32, panel: Panel): Panel =
        CanvasItem.setZIndex(z, panel)

    /// scene.json から ProgressBar を構築する。Panel の構造に Range 由来の値
    /// (minValue/maxValue/value)、塗り (fillColor/fillAlpha/fillMode) を足した形。
    /// `fillMode` の文字列 → enum 変換は `parseFillMode` で行う。
    def buildProgressBar(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                         map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        forM (
            tag                <- parseTagField(tagParser, map);
            posOpt             <- parseVec2Opt("pos", map);
            sizeOpt            <- parseVec2Opt("size", map);
            maxValueOpt        <- (JsonCompat.getAtKeyOpt(Root, "maxValue", map): Result[Util.Json.JsonError, Option[Float64]]);
            minValueOpt        <- (JsonCompat.getAtKeyOpt(Root, "minValue", map): Result[Util.Json.JsonError, Option[Float64]]);
            valueOpt           <- (JsonCompat.getAtKeyOpt(Root, "value", map): Result[Util.Json.JsonError, Option[Float64]]);
            fillColor          <- parseColor("fillColor", map);
            fillAlphaOpt       <- (JsonCompat.getAtKeyOpt(Root, "fillAlpha", map): Result[Util.Json.JsonError, Option[Float64]]);
            fillModeOpt        <- parseFillModeOpt("fillMode", map);
            backgroundOpt      <- parseColorOpt("backgroundColor", map);
            backgroundAlphaOpt <- (JsonCompat.getAtKeyOpt(Root, "backgroundAlpha", map): Result[Util.Json.JsonError, Option[Float64]]);
            tickIntervalOpt    <- (JsonCompat.getAtKeyOpt(Root, "tickInterval", map): Result[Util.Json.JsonError, Option[Float64]]);
            tickColorOpt       <- parseColorOpt("tickColor", map);
            tickAlphaOpt       <- (JsonCompat.getAtKeyOpt(Root, "tickAlpha", map): Result[Util.Json.JsonError, Option[Float64]]);
            tickWidthOpt       <- (JsonCompat.getAtKeyOpt(Root, "tickWidth", map): Result[Util.Json.JsonError, Option[Int32]]);
            borderColorOpt     <- parseColorOpt("borderColor", map);
            borderAlphaOpt     <- (JsonCompat.getAtKeyOpt(Root, "borderAlpha", map): Result[Util.Json.JsonError, Option[Float64]]);
            borderWidthOpt     <- (JsonCompat.getAtKeyOpt(Root, "borderWidth", map): Result[Util.Json.JsonError, Option[Int32]]);
            visibleOpt         <- (JsonCompat.getAtKeyOpt(Root, "visible", map): Result[Util.Json.JsonError, Option[Bool]]);
            zIndexOpt          <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[Util.Json.JsonError, Option[Int32]]);
            modulateOpt        <- parseColorOpt("modulate", map)
        ) yield {
            let pos = Option.getWithDefault(Vec2.zero(), posOpt);
            let size = Option.getWithDefault(Vec2.zero(), sizeOpt);
            let maxValue = Option.getWithDefault(100.0, maxValueOpt);
            let bar = ProgressBar.make(size, maxValue, fillColor)
                |> Node2D.setPosition(pos)
                |> applyOpt(minValueOpt, ProgressBar.setMinValue)
                |> applyOpt(valueOpt, ProgressBar.setValue)
                |> applyOpt(fillAlphaOpt, setProgressBarFillAlpha)
                |> applyOpt(fillModeOpt, ProgressBar.setFillMode)
                |> applyOpt(backgroundOpt, ProgressBar.setBackgroundColor)
                |> applyOpt(backgroundAlphaOpt, setProgressBarBackgroundAlpha)
                |> applyOpt(tickIntervalOpt, ProgressBar.setTickInterval)
                |> applyOpt(tickColorOpt, ProgressBar.setTickColor)
                |> applyOpt(tickAlphaOpt, setProgressBarTickAlpha)
                |> applyOpt(tickWidthOpt, ProgressBar.setTickWidth)
                |> applyOpt(borderColorOpt, ProgressBar.setBorderColor)
                |> applyOpt(borderAlphaOpt, setProgressBarBorderAlpha)
                |> applyOpt(borderWidthOpt, ProgressBar.setBorderWidth)
                |> applyOpt(visibleOpt, setProgressBarVisible)
                |> applyOpt(zIndexOpt, setProgressBarZIndex)
                |> applyOpt(modulateOpt, (c, b) -> CanvasItem.setModulate(c, b));
            EngineNode.ProgressBarWithState(bar, tag)
        }

    def setProgressBarFillAlpha(alpha: Float64, bar: ProgressBar): ProgressBar =
        ProgressBar.setFillAlpha(Float64.truncateToFloat32(alpha), bar)

    def setProgressBarBackgroundAlpha(alpha: Float64, bar: ProgressBar): ProgressBar =
        ProgressBar.setBackgroundAlpha(Float64.truncateToFloat32(alpha), bar)

    def setProgressBarTickAlpha(alpha: Float64, bar: ProgressBar): ProgressBar =
        ProgressBar.setTickAlpha(Float64.truncateToFloat32(alpha), bar)

    def setProgressBarBorderAlpha(alpha: Float64, bar: ProgressBar): ProgressBar =
        ProgressBar.setBorderAlpha(Float64.truncateToFloat32(alpha), bar)

    def setProgressBarVisible(v: Bool, bar: ProgressBar): ProgressBar =
        CanvasItem.setVisible(v, bar)

    def setProgressBarZIndex(z: Int32, bar: ProgressBar): ProgressBar =
        CanvasItem.setZIndex(z, bar)

    /// `"LeftToRight"` / `"RightToLeft"` / `"TopToBottom"` / `"BottomToTop"` の
    /// 文字列を `FillMode` enum に変換する。未指定なら None、未知値は JsonError。
    def parseFillModeOpt(key: String,
                         map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, Option[FillMode]] =
        forM (
            strOpt <- (JsonCompat.getAtKeyOpt(Root, key, map): Result[Util.Json.JsonError, Option[String]]);
            modeOpt <- match strOpt {
                case None      => (Ok(None): Result[Util.Json.JsonError, Option[FillMode]])
                case Some(str) => match str {
                    case "LeftToRight" => (Ok(Some(FillMode.LeftToRight)): Result[Util.Json.JsonError, Option[FillMode]])
                    case "RightToLeft" => (Ok(Some(FillMode.RightToLeft)): Result[Util.Json.JsonError, Option[FillMode]])
                    case "TopToBottom" => (Ok(Some(FillMode.TopToBottom)): Result[Util.Json.JsonError, Option[FillMode]])
                    case "BottomToTop" => (Ok(Some(FillMode.BottomToTop)): Result[Util.Json.JsonError, Option[FillMode]])
                    case unknown       =>
                        (Err(JsonCompat.jsonError(Root, Set#{"fillMode (got: ${unknown})"})): Result[Util.Json.JsonError, Option[FillMode]])
                }
            }
        ) yield modeOpt

    /// `"itemAlignment": "Left" | "Center"` を `ItemAlignment` に。キー欠落時は `None`（既定 Left のまま）。
    def parseItemAlignmentOpt(key: String,
                              map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, Option[ItemAlignment]] =
        forM (
            strOpt <- (JsonCompat.getAtKeyOpt(Root, key, map): Result[Util.Json.JsonError, Option[String]]);
            alignOpt <- match strOpt {
                case None      => (Ok(None): Result[Util.Json.JsonError, Option[ItemAlignment]])
                case Some(str) => match str {
                    case "Left"   => (Ok(Some(ItemAlignment.Left)): Result[Util.Json.JsonError, Option[ItemAlignment]])
                    case "Center" => (Ok(Some(ItemAlignment.Center)): Result[Util.Json.JsonError, Option[ItemAlignment]])
                    case unknown  =>
                        (Err(JsonCompat.jsonError(Root, Set#{"itemAlignment (got: ${unknown})"})): Result[Util.Json.JsonError, Option[ItemAlignment]])
                }
            }
        ) yield alignOpt

    /// scene.json の "items" 配列から ItemEntry のリストを組み立てる。
    /// 各要素は `{"text": "...", "disabled": false}` の形式。disabled は省略可能。
    def parseItemEntries(map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, List[ItemEntry]] =
        forM (
            itemsJson <- (JsonCompat.getAtKeyOpt(Root, "items", map): Result[Util.Json.JsonError, Option[List[Map[String, Util.Json.Json]]]]);
            entries   <- match itemsJson {
                case None     => (Ok(Nil): Result[Util.Json.JsonError, List[ItemEntry]])
                case Some(ms) => Result.traverse(parseItemEntry, ms)
            }
        ) yield entries

    def parseItemEntry(m: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, ItemEntry] =
        forM (
            text        <- (JsonCompat.getAtKey(Root, "text", m): Result[Util.Json.JsonError, String]);
            disabledOpt <- (JsonCompat.getAtKeyOpt(Root, "disabled", m): Result[Util.Json.JsonError, Option[Bool]]);
            metadataOpt <- (JsonCompat.getAtKeyOpt(Root, "metadata", m): Result[Util.Json.JsonError, Option[String]])
        ) yield ({
            text = text,
            disabled = Option.getWithDefault(false, disabledOpt),
            metadata = metadataOpt
        }: ItemEntry)

    def buildItemList(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                      fontAtlas: Option[FontAtlas],
                      map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        match fontAtlas {
            case None => Err(JsonCompat.jsonError(Root, Set#{"FontAtlas (loadSceneWithFont required for ItemList)"}))
            case Some(font) =>
                forM (
                    tag             <- parseTagField(tagParser, map);
                    posOpt          <- parseVec2Opt("pos", map);
                    sizeOpt         <- parseVec2Opt("size", map);
                    fontSize        <- (JsonCompat.getAtKey(Root, "fontSize", map): Result[Util.Json.JsonError, Float64]);
                    items           <- parseItemEntries(map);
                    focusedOpt      <- (JsonCompat.getAtKeyOpt(Root, "focused", map): Result[Util.Json.JsonError, Option[Bool]]);
                    cursorGlyphOpt  <- (JsonCompat.getAtKeyOpt(Root, "cursorGlyph", map): Result[Util.Json.JsonError, Option[String]]);
                    wrapOpt         <- (JsonCompat.getAtKeyOpt(Root, "wrap", map): Result[Util.Json.JsonError, Option[Bool]]);
                    maxVisibleRowsOpt <- (JsonCompat.getAtKeyOpt(Root, "maxVisibleRows", map): Result[Util.Json.JsonError, Option[Int32]]);
                    itemHeightOpt   <- (JsonCompat.getAtKeyOpt(Root, "itemHeight", map): Result[Util.Json.JsonError, Option[Float64]]);
                    cursorOffsetOpt <- (JsonCompat.getAtKeyOpt(Root, "cursorOffsetX", map): Result[Util.Json.JsonError, Option[Float64]]);
                    cursorColorOpt  <- parseColorOpt("cursorColor", map);
                    textColorOpt    <- parseColorOpt("textColor", map);
                    disabledColorOpt <- parseColorOpt("disabledColor", map);
                    subtextColorOpt  <- parseColorOpt("subtextColor", map);
                    subtextFontSizeOpt <- (JsonCompat.getAtKeyOpt(Root, "subtextFontSize", map): Result[Util.Json.JsonError, Option[Float64]]);
                    sublineColorOpt  <- parseColorOpt("sublineColor", map);
                    sublineFontSizeOpt <- (JsonCompat.getAtKeyOpt(Root, "sublineFontSize", map): Result[Util.Json.JsonError, Option[Float64]]);
                    badgeColorOpt    <- parseColorOpt("badgeColor", map);
                    badgeTextColorOpt <- parseColorOpt("badgeTextColor", map);
                    selHighlightOpt  <- parseHighlightAt("selectedHighlight", map);
                    rowHighlightOpt  <- parseHighlightAt("rowHighlight", map);
                    iconBgOpt        <- parseHighlightAt("iconBackground", map);
                    iconBgPadOpt     <- (JsonCompat.getAtKeyOpt(Root, "iconBgPad", map): Result[Util.Json.JsonError, Option[Float64]]);
                    itemAlignmentOpt <- parseItemAlignmentOpt("itemAlignment", map);
                    visibleOpt      <- (JsonCompat.getAtKeyOpt(Root, "visible", map): Result[Util.Json.JsonError, Option[Bool]]);
                    zIndexOpt       <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[Util.Json.JsonError, Option[Int32]]);
                    modulateOpt     <- parseColorOpt("modulate", map)
                ) yield {
                    let pos = Option.getWithDefault(Vec2.zero(), posOpt);
                    let size = Option.getWithDefault(Vec2.zero(), sizeOpt);
                    let list = ItemList.make(items, font, fontSize, size)
                        |> Node2D.setPosition(pos)
                        |> applyOpt(focusedOpt, ItemList.setFocused)
                        |> applyOpt(cursorGlyphOpt, ItemList.setCursorGlyph)
                        |> applyOpt(wrapOpt, ItemList.setWrap)
                        |> applyOpt(maxVisibleRowsOpt, ItemList.setMaxVisibleRows)
                        |> applyOpt(itemHeightOpt, ItemList.setItemHeight)
                        |> applyOpt(cursorOffsetOpt, ItemList.setCursorOffsetX)
                        |> applyOpt(cursorColorOpt, ItemList.setCursorColor)
                        |> applyOpt(textColorOpt, ItemList.setTextColor)
                        |> applyOpt(disabledColorOpt, ItemList.setDisabledColor)
                        |> applyOpt(subtextColorOpt, ItemList.setSubtextColor)
                        |> applyOpt(subtextFontSizeOpt, ItemList.setSubtextFontSize)
                        |> applyOpt(sublineColorOpt, ItemList.setSublineColor)
                        |> applyOpt(sublineFontSizeOpt, ItemList.setSublineFontSize)
                        |> applyOpt(badgeColorOpt, ItemList.setBadgeColor)
                        |> applyOpt(badgeTextColorOpt, ItemList.setBadgeTextColor)
                        |> applyOpt(selHighlightOpt, ItemList.setSelectedHighlight)
                        |> applyOpt(rowHighlightOpt, ItemList.setRowHighlight)
                        |> applyOpt(iconBgOpt, ItemList.setIconBg)
                        |> applyOpt(iconBgPadOpt, ItemList.setIconBgPad)
                        |> applyOpt(itemAlignmentOpt, ItemList.setItemAlignment)
                        |> applyOpt(visibleOpt, setItemListVisible)
                        |> applyOpt(zIndexOpt, setItemListZIndex)
                        |> applyOpt(modulateOpt, (c, l) -> CanvasItem.setModulate(c, l));
                    EngineNode.ItemListWithState(list, tag)
                }
        }

    def setItemListVisible(v: Bool, list: ItemList): ItemList =
        CanvasItem.setVisible(v, list)

    def setItemListZIndex(z: Int32, list: ItemList): ItemList =
        CanvasItem.setZIndex(z, list)

    def buildRichTextLabel(tagParser: Option[String] -> Result[Util.Json.JsonError, t],
                           fontAtlas: Option[FontAtlas],
                           map: Map[String, Util.Json.Json]): Result[Util.Json.JsonError, EngineNode[t]] =
        match fontAtlas {
            case None => Err(JsonCompat.jsonError(Root, Set#{"FontAtlas (loadSceneWithFont required for RichTextLabel)"}))
            case Some(font) =>
                forM (
                    tag                  <- parseTagField(tagParser, map);
                    posOpt               <- parseVec2Opt("pos", map);
                    sizeOpt              <- parseVec2Opt("size", map);
                    text                 <- (JsonCompat.getAtKey(Root, "text", map): Result[Util.Json.JsonError, String]);
                    fontSize             <- (JsonCompat.getAtKey(Root, "fontSize", map): Result[Util.Json.JsonError, Float64]);
                    visibleOpt           <- (JsonCompat.getAtKeyOpt(Root, "visible", map): Result[Util.Json.JsonError, Option[Bool]]);
                    zIndexOpt            <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[Util.Json.JsonError, Option[Int32]]);
                    visibleCharactersOpt <- (JsonCompat.getAtKeyOpt(Root, "visibleCharacters", map): Result[Util.Json.JsonError, Option[Int32]]);
                    visibleRatioOpt      <- (JsonCompat.getAtKeyOpt(Root, "visibleRatio", map): Result[Util.Json.JsonError, Option[Float64]]);
                    modulateOpt          <- parseColorOpt("modulate", map)
                ) yield {
                    let pos = Option.getWithDefault(Vec2.zero(), posOpt);
                    let size = Option.getWithDefault(Vec2.zero(), sizeOpt);
                    let label = RichTextLabel.make(text, font, fontSize, size)
                        |> Node2D.setPosition(pos)
                        |> applyOpt(visibleOpt, setRichTextLabelVisible)
                        |> applyOpt(zIndexOpt, setRichTextLabelZIndex)
                        |> applyOpt(visibleCharactersOpt, RichTextLabel.setVisibleCharacters)
                        |> applyOpt(visibleRatioOpt, RichTextLabel.setVisibleRatio)
                        |> applyOpt(modulateOpt, (c, l) -> CanvasItem.setModulate(c, l));
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

    def setLabelModulate(c: Color, label: Label2D): Label2D =
        CanvasItem.setModulate(c, label)

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
