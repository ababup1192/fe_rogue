// Overlay — エディタ ON 時にだけ追加で描画するオーバーレイ要素
//
// エディタが効いていることを示す右上の "EDITOR" ラベル と、選択中ノードを取り囲む
// 黄色の矩形を、最前面の CanvasLayer に追加する。
// ここで返したシーンは「次フレームに引き継がない」想定。Game.flix の render 直前に
// 1 回だけ合成して使い、次フレームの handleInput は元のシーンから始める

mod Overlay {

    /// エディタが ON であることを示す右上の "EDITOR" ラベルを最前面に追加する
    pub def addEditorIndicator(fontAtlas: FontAtlas, scene: Scene[NodeTag]): Scene[NodeTag] =
        let layerName = "_editor_indicator_layer";
        let labelName = "_editor_indicator_label";
        let layer = CanvasLayer.make(overlayLayerIndex());
        let label = Label2D.make("EDITOR", fontAtlas, 14.0)
            |> Node2D.setPosition({x = 230.0, y = 16.0})
            |> CanvasItem.setModulate({r = 1.0f32, g = 0.85f32, b = 0.2f32});
        scene
            |> Scene.addNode(layerName,
                EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag))
            |> Scene.addChildAt(layerName :: Nil, labelName,
                EngineNode.Label2DWithState(label, NodeTag.NoTag))

    /// 4 辺の枠の見た目を表すスタイル。
    type alias OutlineStyle = {
        layerName = String,
        color = {r = Float32, g = Float32, b = Float32},
        thickness = Float64
    }

    /// 選択中ノードを取り囲む黄色の矩形（4 辺の細い ColorRect）を最前面に追加する。
    /// さらに 8 個のリサイズハンドル（4 隅 + 4 辺）を選択枠の上に重ねる。
    pub def addSelectionBox(rootJsonIndex: Map[NodeName, String],
                            selected: Option[(String, NodePath)],
                            transform: Camera2D.ViewTransform,
                            scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        match selected {
            case None => scene
            case Some((_, nodePath)) =>
                let ctx = {rootJsonIndex = rootJsonIndex, scene = scene};
                match EditableNode.findByNodePath(ctx, nodePath) {
                    case None => scene
                    case Some(entry) =>
                        let refPos = Scene.screenPositionAt(nodePath, transform, scene);
                        let topLeft = Vec2.add(refPos, entry#topLeftOffset);
                        let box = {topLeft = topLeft,
                                   size = {x = entry#width, y = entry#height}};
                        scene
                            |> addOutline(box, selectionStyle())
                            |> addResizeHandles(box)
                }
        }

    /// 選択枠の 8 ハンドル + 上部の回転ノブを最前面に置く
    pub def addResizeHandles(box: {topLeft = Vec2.Vec2, size = Vec2.Vec2},
                              scene: Scene[NodeTag]): Scene[NodeTag] =
        let layerName = handleLayerName();
        let layer = CanvasLayer.make(overlayLayerIndex());
        let color = selectionStyle()#color;
        let withLayer = Scene.addNode(layerName,
            EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag), scene);
        let withResize = ResizeHandle.overlayRects(box)
            |> List.foldLeft((acc, indexed) -> {
                let (handle, rect) = indexed;
                let handleTag = "${handle}";
                let fill = ColorRect.make(rect#size, color)
                    |> Node2D.setPosition(rect#position);
                Scene.addChildAt(layerName :: Nil, handleTag,
                    EngineNode.ColorRectWithState(fill, NodeTag.NoTag), acc)
            }, withLayer);
        addRotateKnob(layerName, box, color, withResize)

    /// 上辺中央から rotateKnobOffset 上にノブを配置し、選択枠との間にリンク線を引く
    def addRotateKnob(layerName: String,
                      box: {topLeft = Vec2.Vec2, size = Vec2.Vec2},
                      color: {r = Float32, g = Float32, b = Float32},
                      scene: Scene[NodeTag]): Scene[NodeTag] =
        let knobCenter = ResizeHandle.rotateKnobCenter(box);
        let knobSize = ResizeHandle.handleSize();
        let knob = ColorRect.make({x = knobSize, y = knobSize}, color)
            |> Node2D.setPosition({x = knobCenter#x - knobSize / 2.0,
                                    y = knobCenter#y - knobSize / 2.0});
        // ノブから選択枠上辺中央までの細い縦線（基準線）
        let lineThickness = 1.0;
        let topMidX = box#topLeft#x + box#size#x / 2.0;
        let lineTop = knobCenter#y + knobSize / 2.0;
        let lineBottom = box#topLeft#y;
        let line = ColorRect.make(
            {x = lineThickness, y = lineBottom - lineTop}, color)
            |> Node2D.setPosition({x = topMidX - lineThickness / 2.0, y = lineTop});
        scene
            |> Scene.addChildAt(layerName :: Nil, "_rotate_link",
                EngineNode.ColorRectWithState(line, NodeTag.NoTag))
            |> Scene.addChildAt(layerName :: Nil, "_rotate_knob",
                EngineNode.ColorRectWithState(knob, NodeTag.NoTag))

    /// ハンドル群を載せる CanvasLayer のノード名
    def handleLayerName(): String = "_editor_handle_layer"

    /// マウス位置の編集対象ノードに薄い枠を描く
    pub def addHoverBox(rootJsonIndex: Map[NodeName, String],
                        mousePos: Vec2.Vec2,
                        selected: Option[(String, NodePath)],
                        transform: Camera2D.ViewTransform,
                        scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        let ctx = {rootJsonIndex = rootJsonIndex, scene = scene};
        let entries = EditableNode.collectAll(ctx);
        let preferDescendant = GameEngine.Game.isKeyPressed(GameEngine.Key.LeftShift);
        match Picking.pickTopAt(mousePos, entries, transform, preferDescendant, scene) {
            case None => scene
            case Some((entry, _)) =>
                if (isSelectedPath(entry#nodePath, selected)) scene
                else {
                    let refPos = Scene.screenPositionAt(entry#nodePath, transform, scene);
                    let topLeft = Vec2.add(refPos, entry#topLeftOffset);
                    let box = {topLeft = topLeft,
                               size = {x = entry#width, y = entry#height}};
                    addOutline(box, hoverStyle(), scene)
                }
        }

    /// hover 対象が選択中ノードと一致するかを判定
    def isSelectedPath(path: NodePath, selected: Option[(String, NodePath)]): Bool =
        match selected {
            case Some((_, selPath)) => path == selPath
            case None               => false
        }

    /// シーンに含まれるすべての CollisionObject2D の衝突形状を可視化する
    pub def addCollisionShapes(transform: Camera2D.ViewTransform,
                               scene: Scene[NodeTag]): Scene[NodeTag] =
        let layerName = collisionLayerName();
        let layer = CanvasLayer.make(collisionLayerIndex());
        let withLayer = Scene.addNode(layerName,
            EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag), scene);
        Scene.preorderPaths(scene)
            |> List.foldLeft((accScene, path) ->
                addShapeAtPath(layerName, path, transform, scene, accScene), withLayer)

    /// 指定パスのノードに衝突形状があれば描画する
    def addShapeAtPath(layerName: String, path: NodePath,
                       transform: Camera2D.ViewTransform,
                       sourceScene: Scene[NodeTag],
                       acc: Scene[NodeTag]): Scene[NodeTag] =
        match Scene.getEngineNode(path, sourceScene) {
            case None => acc
            case Some(node) => match CollisionObject2D.getCollisionShape(node) {
                case None => acc
                case Some(shape) =>
                    let center = Scene.screenPositionAt(path, transform, sourceScene);
                    let style = collisionStyle();
                    let rects = collisionShapeToFillRects(center, shape, style);
                    let pathTag = pathToTag(path);
                    appendFillRects(layerName, pathTag, rects, style, acc)
            }
        }

    /// 衝突形状を塗りつぶし用の矩形リストへ変換する
    def collisionShapeToFillRects(center: Vec2.Vec2,
                                   shape: CollisionShape2D,
                                   style: CollisionStyle): List[FillRect] =
        match shape {
            case CollisionShape2D.RectShape2D(r) =>
                rectFillAndOutlineRects(center, r#width, r#height,
                                         style#outlineThickness)
            case CollisionShape2D.CircleShape2D(c) =>
                circleRingScanLines(center, c#radius, style#outlineThickness)
            case CollisionShape2D.CapsuleShape2D(c) =>
                capsuleRingScanLines(center, c#radius, c#height, c#vertical,
                                      style#outlineThickness)
        }

    def rectFillAndOutlineRects(center: Vec2.Vec2, width: Float64, height: Float64,
                                 outlineThickness: Float64): List[FillRect] =
        let halfW = width / 2.0;
        let halfH = height / 2.0;
        let topLeft = {x = center#x - halfW, y = center#y - halfH};
        let fill = {topLeft = topLeft, size = {x = width, y = height},
                    isOutline = false};
        let topEdge = {topLeft = {x = topLeft#x - outlineThickness,
                                  y = topLeft#y - outlineThickness},
                       size = {x = width + 2.0 * outlineThickness, y = outlineThickness},
                       isOutline = true};
        let bottomEdge = {topLeft = {x = topLeft#x - outlineThickness,
                                     y = topLeft#y + height},
                          size = {x = width + 2.0 * outlineThickness, y = outlineThickness},
                          isOutline = true};
        let leftEdge = {topLeft = {x = topLeft#x - outlineThickness, y = topLeft#y},
                        size = {x = outlineThickness, y = height},
                        isOutline = true};
        let rightEdge = {topLeft = {x = topLeft#x + width, y = topLeft#y},
                         size = {x = outlineThickness, y = height},
                         isOutline = true};
        fill :: topEdge :: bottomEdge :: leftEdge :: rightEdge :: Nil

    def circleRingScanLines(center: Vec2.Vec2, radius: Float64,
                             outlineThickness: Float64): List[FillRect] =
        let outerRadius = radius + outlineThickness;
        let outerHalfWidthAt = y -> circleHalfWidthAt(outerRadius, y);
        let innerHalfWidthAt = y -> circleHalfWidthAt(radius, y);
        ringScanLines(center, outerRadius, outerHalfWidthAt, innerHalfWidthAt)

    def capsuleRingScanLines(center: Vec2.Vec2, radius: Float64,
                              height: Float64, vertical: Bool,
                              outlineThickness: Float64): List[FillRect] =
        let outerRadius = radius + outlineThickness;
        let halfSeg = Float64.max(0.0, height / 2.0 - radius);
        let yExtent = if (vertical)
                          height / 2.0 + outlineThickness
                      else
                          outerRadius;
        let halfWidthFn = if (vertical)
                              capsuleVerticalHalfWidthAt(halfSeg)
                          else
                              capsuleHorizontalHalfWidthAt(halfSeg);
        let outerHalfWidthAt = halfWidthFn(outerRadius);
        let innerHalfWidthAt = halfWidthFn(radius);
        ringScanLines(center, yExtent, outerHalfWidthAt, innerHalfWidthAt)

    def circleHalfWidthAt(radius: Float64, y: Float64): Float64 =
        let inside = radius * radius - y * y;
        if (inside <= 0.0) 0.0
        else Vec2.sqrt(inside)

    def capsuleVerticalHalfWidthAt(halfSeg: Float64):
            Float64 -> Float64 -> Float64 =
        radius -> y -> {
            let absY = Float64.abs(y);
            if (absY <= halfSeg) radius
            else circleHalfWidthAt(radius, absY - halfSeg)
        }

    def capsuleHorizontalHalfWidthAt(halfSeg: Float64):
            Float64 -> Float64 -> Float64 =
        radius -> y -> {
            let circleHalf = circleHalfWidthAt(radius, y);
            if (circleHalf <= 0.0) 0.0
            else halfSeg + circleHalf
        }

    def ringScanLines(center: Vec2.Vec2, yExtent: Float64,
                      outerHalfWidthAt: Float64 -> Float64,
                      innerHalfWidthAt: Float64 -> Float64): List[FillRect] =
        let yExtentInt = Float64.round(yExtent)
            |> Float64.tryToInt32 |> Option.getWithDefault(0i32);
        List.range(-yExtentInt, yExtentInt + 1i32)
            |> List.flatMap(yi -> {
                let y = Int32.toFloat64(yi);
                let outerHalf = outerHalfWidthAt(y);
                if (outerHalf <= 0.0) (Nil: List[FillRect])
                else {
                    let innerHalf = innerHalfWidthAt(y);
                    if (innerHalf <= 0.0)
                        {topLeft = {x = center#x - outerHalf, y = center#y + y},
                         size = {x = 2.0 * outerHalf, y = 1.0},
                         isOutline = true} :: Nil
                    else {
                        let leftEdge = {topLeft = {x = center#x - outerHalf,
                                                   y = center#y + y},
                                        size = {x = outerHalf - innerHalf, y = 1.0},
                                        isOutline = true};
                        let fill = {topLeft = {x = center#x - innerHalf,
                                               y = center#y + y},
                                    size = {x = 2.0 * innerHalf, y = 1.0},
                                    isOutline = false};
                        let rightEdge = {topLeft = {x = center#x + innerHalf,
                                                    y = center#y + y},
                                         size = {x = outerHalf - innerHalf, y = 1.0},
                                         isOutline = true};
                        leftEdge :: fill :: rightEdge :: Nil
                    }
                }
            })

    def appendFillRects(layerName: String, pathTag: String,
                        rects: List[FillRect],
                        style: CollisionStyle,
                        scene: Scene[NodeTag]): Scene[NodeTag] =
        List.foldLeft((acc, indexed) -> {
            let (idx, rect) = indexed;
            let childName = "${pathTag}_${idx}";
            let color = if (rect#isOutline) style#outlineColor else style#fillColor;
            let alpha = if (rect#isOutline) style#outlineAlpha else style#fillAlpha;
            let colorRect = ColorRect.make(rect#size, color)
                |> Node2D.setPosition(rect#topLeft)
                |> ColorRect.setAlpha(alpha);
            Scene.addChildAt(layerName :: Nil, childName,
                EngineNode.ColorRectWithState(colorRect, NodeTag.NoTag), acc)
        }, scene, List.zipWithIndex(rects))

    def pathToTag(path: NodePath): String =
        String.intercalate("/", path)

    type alias FillRect = {
        topLeft = Vec2.Vec2,
        size = Vec2.Vec2,
        isOutline = Bool
    }

    type alias CollisionStyle = {
        fillColor = {r = Float32, g = Float32, b = Float32},
        fillAlpha = Float32,
        outlineColor = {r = Float32, g = Float32, b = Float32},
        outlineAlpha = Float32,
        outlineThickness = Float64
    }

    def collisionStyle(): CollisionStyle =
        {fillColor = {r = 0.4f32, g = 0.7f32, b = 1.0f32}, fillAlpha = 0.4f32,
         outlineColor = {r = 0.1f32, g = 0.5f32, b = 0.8f32}, outlineAlpha = 1.0f32,
         outlineThickness = 1.0}

    def collisionLayerName(): String = "_editor_collision_layer"

    def collisionLayerIndex(): Int32 = 998

    def selectionStyle(): OutlineStyle = {
        layerName = "_editor_box_layer",
        color = {r = 1.0f32, g = 0.85f32, b = 0.2f32},
        thickness = 2.0
    }

    def hoverStyle(): OutlineStyle = {
        layerName = "_editor_hover_layer",
        color = {r = 0.7f32, g = 0.7f32, b = 0.7f32},
        thickness = 1.0
    }

    def addOutline(box: {topLeft = Vec2.Vec2, size = Vec2.Vec2},
                   style: OutlineStyle,
                   scene: Scene[NodeTag]): Scene[NodeTag] =
        let layerName = style#layerName;
        let layer = CanvasLayer.make(overlayLayerIndex());
        let color = style#color;
        let thickness = style#thickness;
        let topLeft = box#topLeft;
        let width = box#size#x;
        let height = box#size#y;
        let topLine = makeLine({pos = topLeft,
                                size = {x = width, y = thickness}}, color);
        let bottomLine = makeLine({pos = {x = topLeft#x,
                                          y = topLeft#y + height - thickness},
                                   size = {x = width, y = thickness}}, color);
        let leftLine = makeLine({pos = topLeft,
                                 size = {x = thickness, y = height}}, color);
        let rightLine = makeLine({pos = {x = topLeft#x + width - thickness,
                                         y = topLeft#y},
                                  size = {x = thickness, y = height}}, color);
        scene
            |> Scene.addNode(layerName,
                EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag))
            |> Scene.addChildAt(layerName :: Nil, "top",
                EngineNode.ColorRectWithState(topLine, NodeTag.NoTag))
            |> Scene.addChildAt(layerName :: Nil, "bottom",
                EngineNode.ColorRectWithState(bottomLine, NodeTag.NoTag))
            |> Scene.addChildAt(layerName :: Nil, "left",
                EngineNode.ColorRectWithState(leftLine, NodeTag.NoTag))
            |> Scene.addChildAt(layerName :: Nil, "right",
                EngineNode.ColorRectWithState(rightLine, NodeTag.NoTag))

    def makeLine(line: {pos = Vec2.Vec2, size = Vec2.Vec2},
                 color: {r = Float32, g = Float32, b = Float32}): ColorRect =
        ColorRect.make(line#size, color)
            |> Node2D.setPosition(line#pos)

    def overlayLayerIndex(): Int32 = 999
}
