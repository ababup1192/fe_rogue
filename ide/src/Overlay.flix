// Overlay — エディタ ON 時にだけ追加で描画するオーバーレイ要素
//
// 選択中ノードを取り囲む黄色の矩形を最前面の CanvasLayer に追加する。
// ここで返したシーンは「次フレームに引き継がない」想定。Game.flix の render 直前に
// 1 回だけ合成して使い、次フレームの handleInput は元のシーンから始める

mod Overlay {

    /// 4 辺の枠の見た目を表すスタイル。
    type alias OutlineStyle = {
        layerName = String,
        color = {r = Float32, g = Float32, b = Float32},
        thickness = Float64
    }

    /// 選択中ノードを取り囲む黄色の矩形（4 辺の細い ColorRect）を最前面に追加する。
    /// さらに 8 個のリサイズハンドル（4 隅 + 4 辺）を選択枠の上に重ねる。
    pub def addSelectionBox(rootJsonIndex: Map[NodeName, String],
                            selected: Option[Editor.Selection],
                            transform: Camera2D.ViewTransform,
                            defaultTag: t, scene: Scene[t]): Scene[t] \ GameEngine.Game =
        match selected {
            case None => scene
            case Some(sel) =>
                let nodePath = sel#nodePath;
                let ctx = {rootJsonIndex = rootJsonIndex, scene = scene};
                match EditableNode.findByNodePath(ctx, nodePath) {
                    case None => scene
                    case Some(entry) =>
                        let refPos = Scene.screenPositionAtWith(nodePath, transform, editor = true, scene);
                        let topLeft = Vec2.add(refPos, entry#topLeftOffset);
                        let box = {topLeft = topLeft,
                                   size = {x = entry#width, y = entry#height}};
                        scene
                            |> addOutline(box, selectionStyle(), defaultTag)
                            |> addResizeHandles(box, defaultTag)
                }
        }

    /// 選択枠の 8 ハンドル + 上部の回転ノブを最前面に置く
    pub def addResizeHandles(box: {topLeft = Vec2.Vec2, size = Vec2.Vec2},
                              defaultTag: t, scene: Scene[t]): Scene[t] =
        let layerName = handleLayerName();
        let layer = CanvasLayer.make(overlayLayerIndex());
        let color = selectionStyle()#color;
        let withLayer = Scene.addNode(layerName,
            EngineNode.CanvasLayerWithState(layer, defaultTag), scene);
        let withResize = ResizeHandle.overlayRects(box)
            |> List.foldLeft((acc, indexed) -> {
                let (handle, rect) = indexed;
                let handleTag = "${handle}";
                let fill = ColorRect.make(rect#size, color)
                    |> Node2D.setPosition(rect#position);
                Scene.addChildAt(layerName :: Nil, handleTag,
                    EngineNode.ColorRectWithState(fill, defaultTag), acc)
            }, withLayer);
        addRotateKnob(layerName, box, color, defaultTag, withResize)

    /// 上辺中央から rotateKnobOffset 上にノブを配置し、選択枠との間にリンク線を引く
    def addRotateKnob(layerName: String,
                      box: {topLeft = Vec2.Vec2, size = Vec2.Vec2},
                      color: {r = Float32, g = Float32, b = Float32},
                      defaultTag: t, scene: Scene[t]): Scene[t] =
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
                EngineNode.ColorRectWithState(line, defaultTag))
            |> Scene.addChildAt(layerName :: Nil, "_rotate_knob",
                EngineNode.ColorRectWithState(knob, defaultTag))

    /// ハンドル群を載せる CanvasLayer のノード名
    def handleLayerName(): String = "_editor_handle_layer"

    /// マウス位置の編集対象ノードに薄い枠を描く
    pub def addHoverBox(rootJsonIndex: Map[NodeName, String],
                        mousePos: Vec2.Vec2,
                        selected: Option[Editor.Selection],
                        transform: Camera2D.ViewTransform,
                        defaultTag: t, scene: Scene[t]): Scene[t] \ GameEngine.Game =
        let ctx = {rootJsonIndex = rootJsonIndex, scene = scene};
        let entries = EditableNode.collectAll(ctx);
        let preferDescendant = GameEngine.Game.isKeyPressed(GameEngine.Key.LeftShift);
        match Picking.pickTopAt(mousePos, entries, transform, preferDescendant, scene) {
            case None => scene
            case Some((entry, _)) =>
                if (isSelectedPath(entry#nodePath, selected)) scene
                else {
                    let refPos = Scene.screenPositionAtWith(entry#nodePath, transform, editor = true, scene);
                    let topLeft = Vec2.add(refPos, entry#topLeftOffset);
                    let box = {topLeft = topLeft,
                               size = {x = entry#width, y = entry#height}};
                    addOutline(box, hoverStyle(), defaultTag, scene)
                }
        }

    /// hover 対象が選択中ノードと一致するかを判定
    def isSelectedPath(path: NodePath, selected: Option[Editor.Selection]): Bool =
        match selected {
            case Some(sel) => path == sel#nodePath
            case None      => false
        }

    /// シーンに含まれるすべての CollisionObject2D の衝突形状を可視化する
    pub def addCollisionShapes(transform: Camera2D.ViewTransform,
                               defaultTag: t, scene: Scene[t]): Scene[t] =
        let layerName = collisionLayerName();
        let layer = CanvasLayer.make(collisionLayerIndex());
        let withLayer = Scene.addNode(layerName,
            EngineNode.CanvasLayerWithState(layer, defaultTag), scene);
        Scene.preorderPaths(scene)
            |> List.foldLeft((accScene, path) ->
                addShapeAtPath(layerName, path, transform, scene, defaultTag, accScene), withLayer)

    /// 指定パスのノードに衝突形状があれば描画する
    def addShapeAtPath(layerName: String, path: NodePath,
                       transform: Camera2D.ViewTransform,
                       sourceScene: Scene[t],
                       defaultTag: t,
                       acc: Scene[t]): Scene[t] =
        match Scene.getEngineNode(path, sourceScene) {
            case None => acc
            case Some(node) => match CollisionObject2D.getCollisionShape(node) {
                case None => acc
                case Some(shape) =>
                    let center = Scene.screenPositionAtWith(path, transform, editor = true, sourceScene);
                    let style = collisionStyle();
                    let rects = collisionShapeToFillRects(center, shape, style);
                    let pathTag = pathToTag(path);
                    appendFillRects(layerName, pathTag, rects, style, defaultTag, acc)
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

    /// 矩形コリジョンを **outline のみ** で描画する（fill は使わない）。
    /// Godot のエディタと同様、コリジョン形状は内部塗りつぶしを行わず
    /// 細い枠線だけで表示することで、下の sprite が完全に見えるようにする
    def rectFillAndOutlineRects(center: Vec2.Vec2, width: Float64, height: Float64,
                                 outlineThickness: Float64): List[FillRect] =
        let halfW = width / 2.0;
        let halfH = height / 2.0;
        let topLeft = {x = center#x - halfW, y = center#y - halfH};
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
        topEdge :: bottomEdge :: leftEdge :: rightEdge :: Nil

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
                        // Outline ring only — 内側 fill は描画しない。
                        // 下の sprite を完全に見えるようにするため、左右のエッジだけ残す。
                        let leftEdge = {topLeft = {x = center#x - outerHalf,
                                                   y = center#y + y},
                                        size = {x = outerHalf - innerHalf, y = 1.0},
                                        isOutline = true};
                        let rightEdge = {topLeft = {x = center#x + innerHalf,
                                                    y = center#y + y},
                                         size = {x = outerHalf - innerHalf, y = 1.0},
                                         isOutline = true};
                        leftEdge :: rightEdge :: Nil
                    }
                }
            })

    def appendFillRects(layerName: String, pathTag: String,
                        rects: List[FillRect],
                        style: CollisionStyle,
                        defaultTag: t, scene: Scene[t]): Scene[t] =
        List.foldLeft((acc, indexed) -> {
            let (idx, rect) = indexed;
            let childName = "${pathTag}_${idx}";
            let color = if (rect#isOutline) style#outlineColor else style#fillColor;
            let alpha = if (rect#isOutline) style#outlineAlpha else style#fillAlpha;
            let colorRect = ColorRect.make(rect#size, color)
                |> Node2D.setPosition(rect#topLeft)
                |> ColorRect.setAlpha(alpha);
            Scene.addChildAt(layerName :: Nil, childName,
                EngineNode.ColorRectWithState(colorRect, defaultTag), acc)
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

    /// デザイン解像度（実ゲーム画面）の枠を **細い淡色の実線** でうっすら描く。配置の基準＝画面の大きさ。
    /// transform (editor の pan/zoom) を適用するので、枠は world 上の矩形としてパン・ズームに追従する。
    /// 線の太さは画面上一定 (zoom に依らず 1px)。
    /// ゲーム既定解像度の枠。座標は design-px（投影で pan/zoom）。線の厚みだけ 1/zoom にして
    /// 画面上で常に一定 px に保つ（zoom 縮小で 1px 未満になり消える/ちらつくのを防ぐ）。
    pub def addDesignFrame(viewportSize: Vec2.Vec2, zoom: Float64,
                           defaultTag: t, scene: Scene[t]): Scene[t] =
        let w = viewportSize#x;
        let h = viewportSize#y;
        let tl = {x = 0.0, y = 0.0};
        let sw = w;
        let sh = h;
        let th = overlayLineThickness(zoom);
        let edges =
            {pos = tl,                              size = {x = sw, y = th}} ::
            {pos = {x = tl#x, y = tl#y + sh - th},  size = {x = sw, y = th}} ::
            {pos = tl,                              size = {x = th, y = sh}} ::
            {pos = {x = tl#x + sw - th, y = tl#y},  size = {x = th, y = sh}} :: Nil;
        let layerName = "_design_frame_layer";
        let layer = CanvasLayer.make(overlayLayerIndex());
        let withLayer = Scene.addNode(layerName,
            EngineNode.CanvasLayerWithState(layer, defaultTag), scene);
        // Godot の "Show Viewport" 同様、ゲーム既定解像度を **藍色(indigo)** の矩形で示す。
        let color = {r = 0.5f32, g = 0.5f32, b = 0.85f32};
        let (result, _) = List.foldLeft((acc, r) -> {
            let (sc, i) = acc;
            let edge = ColorRect.make(r#size, color)
                |> ColorRect.setAlpha(0.6f32)
                |> Node2D.setPosition(r#pos);
            let sc2 = Scene.addChildAt(layerName :: Nil, "edge_${i}",
                EngineNode.ColorRectWithState(edge, defaultTag), sc);
            (sc2, i + 1)
        }, (withLayer, 0), edges);
        result

    /// Godot の "Show Origin" 同様、原点 (0,0) で交わる **赤=X軸・緑=Y軸** の線を引く。
    /// transform 後の原点位置を通り、ビューポート全幅/全高に伸びる（負方向も突き抜ける）。
    /// frame(藍) より前面に置き、原点が赤緑で分かるようにする。
    pub def addOriginLines(_viewportSize: Vec2.Vec2, zoom: Float64,
                           defaultTag: t, scene: Scene[t]): Scene[t] =
        let th = overlayLineThickness(zoom);
        // 無限に伸びる軸: 巨大スパンの線を原点(design-px)に置く（描画は scissor 無しで帯にも描かれる）。
        let big = 100000.0;
        let originScreen = {x = 0.0, y = 0.0};
        let layerName = "_origin_layer";
        let layer = CanvasLayer.make(originLayerIndex());
        let base = Scene.addNode(layerName,
            EngineNode.CanvasLayerWithState(layer, defaultTag), scene);
        let xAxis = ColorRect.make({x = 2.0 * big, y = th}, {r = 0.85f32, g = 0.35f32, b = 0.37f32})
            |> ColorRect.setAlpha(0.6f32)
            |> Node2D.setPosition({x = 0.0 - big, y = originScreen#y});
        let yAxis = ColorRect.make({x = th, y = 2.0 * big}, {r = 0.4f32, g = 0.8f32, b = 0.45f32})
            |> ColorRect.setAlpha(0.6f32)
            |> Node2D.setPosition({x = originScreen#x, y = 0.0 - big});
        base
            |> Scene.addChildAt(layerName :: Nil, "origin_x",
                EngineNode.ColorRectWithState(xAxis, defaultTag))
            |> Scene.addChildAt(layerName :: Nil, "origin_y",
                EngineNode.ColorRectWithState(yAxis, defaultTag))

    def originLayerIndex(): Int32 = 1000

    /// デザイン領域内に薄いグリッドを敷く。細線(fine)＋一定間隔の太線(coarse)で大きさを掴みやすく。
    /// さらに原点(0,0=画面左上)に短い赤(X)・緑(Y)の軸を置く(Godot 流の原点表示)。
    /// グリッドの矩形＝ゲーム画面、というもう一つの視覚手掛かりにもなる。
    pub def addDesignGrid(viewportSize: Vec2.Vec2, defaultTag: t, scene: Scene[t]): Scene[t] =
        let w = viewportSize#x;
        let h = viewportSize#y;
        let fine = gridFine();
        let layerName = "_design_grid_layer";
        let layer = CanvasLayer.make(gridLayerIndex());
        let base = Scene.addNode(layerName,
            EngineNode.CanvasLayerWithState(layer, defaultTag), scene);
        let vPos = dashStarts(0.0, w + 0.5, fine);
        let hPos = dashStarts(0.0, h + 0.5, fine);
        let (afterV, _) = List.foldLeft((acc, x) -> {
            let (sc, i) = acc;
            let line = ColorRect.make({x = 1.0, y = h}, gridColor())
                |> ColorRect.setAlpha(gridAlpha(i))
                |> Node2D.setPosition({x = x, y = 0.0});
            (Scene.addChildAt(layerName :: Nil, "v_${i}",
                EngineNode.ColorRectWithState(line, defaultTag), sc), i + 1)
        }, (base, 0), vPos);
        let (afterH, _) = List.foldLeft((acc, y) -> {
            let (sc, i) = acc;
            let line = ColorRect.make({x = w, y = 1.0}, gridColor())
                |> ColorRect.setAlpha(gridAlpha(i))
                |> Node2D.setPosition({x = 0.0, y = y});
            (Scene.addChildAt(layerName :: Nil, "h_${i}",
                EngineNode.ColorRectWithState(line, defaultTag), sc), i + 1)
        }, (afterV, 0), hPos);
        addOriginAxes(layerName, defaultTag, afterH)

    def gridFine(): Float64 = 16.0
    def gridCoarseEvery(): Int32 = 5
    def gridColor(): {r = Float32, g = Float32, b = Float32} =
        {r = 0.6f32, g = 0.6f32, b = 0.72f32}
    def gridAlpha(i: Int32): Float32 =
        if (Int32.modulo(i, gridCoarseEvery()) == 0) 0.16f32 else 0.06f32
    def gridLayerIndex(): Int32 = 998

    /// 原点 (0,0)=画面左上に短い赤(X右向き)・緑(Y下向き)の軸を置く。
    def addOriginAxes(layerName: String, defaultTag: t, scene: Scene[t]): Scene[t] =
        let len = 16.0;
        let th = 2.0;
        let xAxis = ColorRect.make({x = len, y = th}, {r = 1.0f32, g = 0.35f32, b = 0.35f32})
            |> Node2D.setPosition({x = 0.0, y = 0.0});
        let yAxis = ColorRect.make({x = th, y = len}, {r = 0.35f32, g = 0.9f32, b = 0.45f32})
            |> Node2D.setPosition({x = 0.0, y = 0.0});
        scene
            |> Scene.addChildAt(layerName :: Nil, "axis_x",
                EngineNode.ColorRectWithState(xAxis, defaultTag))
            |> Scene.addChildAt(layerName :: Nil, "axis_y",
                EngineNode.ColorRectWithState(yAxis, defaultTag))

    /// start から step 間隔で end 未満の位置リストを返す（グリッド線の位置生成に使う）。
    def dashStarts(start: Float64, end: Float64, step: Float64): List[Float64] =
        if (start >= end) Nil
        else start :: dashStarts(start + step, end, step)

    def addOutline(box: {topLeft = Vec2.Vec2, size = Vec2.Vec2},
                   style: OutlineStyle,
                   defaultTag: t, scene: Scene[t]): Scene[t] =
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
                EngineNode.CanvasLayerWithState(layer, defaultTag))
            |> Scene.addChildAt(layerName :: Nil, "top",
                EngineNode.ColorRectWithState(topLine, defaultTag))
            |> Scene.addChildAt(layerName :: Nil, "bottom",
                EngineNode.ColorRectWithState(bottomLine, defaultTag))
            |> Scene.addChildAt(layerName :: Nil, "left",
                EngineNode.ColorRectWithState(leftLine, defaultTag))
            |> Scene.addChildAt(layerName :: Nil, "right",
                EngineNode.ColorRectWithState(rightLine, defaultTag))

    def makeLine(line: {pos = Vec2.Vec2, size = Vec2.Vec2},
                 color: {r = Float32, g = Float32, b = Float32}): ColorRect =
        ColorRect.make(line#size, color)
            |> Node2D.setPosition(line#pos)

    def overlayLayerIndex(): Int32 = 999

    /// design-px の線厚を返す。投影が zoom 倍するので 1/zoom にしておくと画面上で常に一定 px になり、
    /// zoom 縮小で線が 1px 未満になって消える/ちらつくのを防ぐ。画面上 ≈1.5px に揃える。
    def overlayLineThickness(zoom: Float64): Float64 =
        let z = if (zoom <= 0.0) 1.0 else zoom;
        2.0 / z
}
