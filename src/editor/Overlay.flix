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
    /// layerName は CanvasLayer のキー名で、選択枠とホバー枠が衝突しないよう別名にする
    type alias OutlineStyle = {
        layerName = String,
        color = {r = Float32, g = Float32, b = Float32},
        thickness = Float64
    }

    /// 選択中ノードを取り囲む黄色の矩形（4 辺の細い ColorRect）を最前面に追加する。
    /// さらに 8 個のリサイズハンドル（4 隅 + 4 辺）を選択枠の上に重ねる。
    /// 選択 entry をシーン走査で再取得して、ノードが描画されている screen 座標に枠を置く
    /// （オーバーレイ自体が CanvasLayer なのでカメラの影響を受けず、screen 座標 = 描画位置）
    pub def addSelectionBox(rootJsonIndex: Map[NodeName, String],
                            selected: Option[(String, NodePath)],
                            cameraOffset: Vec2.Vec2,
                            scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        match selected {
            case None => scene
            case Some((_, nodePath)) =>
                let ctx = {rootJsonIndex = rootJsonIndex, scene = scene};
                match EditableNode.findByNodePath(ctx, nodePath) {
                    case None => scene
                    case Some(entry) =>
                        let refPos = Scene.screenPositionAt(nodePath, cameraOffset, scene);
                        let topLeft = Vec2.add(refPos, entry#topLeftOffset);
                        let box = {topLeft = topLeft,
                                   size = {x = entry#width, y = entry#height}};
                        scene
                            |> addOutline(box, selectionStyle())
                            |> addResizeHandles(box)
                }
        }

    /// 選択枠の 8 ハンドルを最前面に置く（選択枠と同じ黄色塗りの 8x8 矩形）。
    /// 描画はハンドルごとに 1 個の塗り ColorRect を専用 CanvasLayer に置くだけ
    pub def addResizeHandles(box: {topLeft = Vec2.Vec2, size = Vec2.Vec2},
                              scene: Scene[NodeTag]): Scene[NodeTag] =
        let layerName = handleLayerName();
        let layer = CanvasLayer.make(overlayLayerIndex());
        let color = selectionStyle()#color;
        let withLayer = Scene.addNode(layerName,
            EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag), scene);
        ResizeHandle.overlayRects(box)
            |> List.foldLeft((acc, indexed) -> {
                let (handle, rect) = indexed;
                let handleTag = "${handle}";
                let fill = ColorRect.make(rect#size, color)
                    |> Node2D.setPosition(rect#position);
                Scene.addChildAt(layerName :: Nil, handleTag,
                    EngineNode.ColorRectWithState(fill, NodeTag.NoTag), acc)
            }, withLayer)

    /// ハンドル群を載せる CanvasLayer のノード名（選択枠の layer と分けて衝突回避）
    def handleLayerName(): String = "_editor_handle_layer"

    /// マウス位置の編集対象ノードに薄い枠を描く（重なりが多いシーンで「何がクリック対象か」
    /// を視覚化する）。選択中ノードは選択枠と重なって見えづらくなるためスキップ。
    /// 何も hit しない / 選択中ノードと一致 のときは scene 不変
    pub def addHoverBox(rootJsonIndex: Map[NodeName, String],
                        mousePos: Vec2.Vec2,
                        selected: Option[(String, NodePath)],
                        cameraOffset: Vec2.Vec2,
                        scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        let ctx = {rootJsonIndex = rootJsonIndex, scene = scene};
        let entries = EditableNode.collectAll(ctx);
        match Picking.pickTopAt(mousePos, entries, cameraOffset, scene) {
            case None => scene
            case Some((entry, _)) =>
                if (isSelectedPath(entry#nodePath, selected)) scene
                else {
                    let refPos = Scene.screenPositionAt(entry#nodePath, cameraOffset, scene);
                    let topLeft = Vec2.add(refPos, entry#topLeftOffset);
                    let box = {topLeft = topLeft,
                               size = {x = entry#width, y = entry#height}};
                    addOutline(box, hoverStyle(), scene)
                }
        }

    /// hover 対象が選択中ノードと一致するかを判定（一致するなら hover 枠を描かない）
    def isSelectedPath(path: NodePath, selected: Option[(String, NodePath)]): Bool =
        match selected {
            case Some((_, selPath)) => path == selPath
            case None               => false
        }

    /// シーンに含まれるすべての CollisionObject2D の衝突形状を、
    /// Godot のデバッグ表示風に薄い水色の半透明で塗りつぶす。
    /// 描画プリミティブは ColorRect しかないため、円・カプセルはスキャンラインで近似する。
    /// 形状の中心座標は `Scene.screenPositionAt` を使い、レンダラの描画位置と一致させる
    pub def addCollisionShapes(cameraOffset: Vec2.Vec2,
                               scene: Scene[NodeTag]): Scene[NodeTag] =
        let layerName = collisionLayerName();
        let layer = CanvasLayer.make(collisionLayerIndex());
        let withLayer = Scene.addNode(layerName,
            EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag), scene);
        Scene.preorderPaths(scene)
            |> List.foldLeft((accScene, path) ->
                addShapeAtPath(layerName, path, cameraOffset, scene, accScene), withLayer)

    /// 指定パスのノードに衝突形状があれば、それを構成する塗り矩形を CanvasLayer の子に追加する。
    /// 形状の中心座標は `Scene.screenPositionAt` を使い、選択枠と同じくカメラ追従を尊重する
    def addShapeAtPath(layerName: String, path: NodePath,
                       cameraOffset: Vec2.Vec2,
                       sourceScene: Scene[NodeTag],
                       acc: Scene[NodeTag]): Scene[NodeTag] =
        match Scene.getEngineNode(path, sourceScene) {
            case None => acc
            case Some(node) => match CollisionObject2D.getCollisionShape(node) {
                case None => acc
                case Some(shape) =>
                    let center = Scene.screenPositionAt(path, cameraOffset, sourceScene);
                    let style = collisionStyle();
                    let rects = collisionShapeToFillRects(center, shape, style);
                    let pathTag = pathToTag(path);
                    appendFillRects(layerName, pathTag, rects, style, acc)
            }
        }

    /// 衝突形状を、塗りつぶし用の矩形リストへ変換する。
    /// 形状を outlineThickness ぶん膨らませた「外側」と元の「内側」の差分にフチ色、
    /// 内側部分に塗り色を割り当てる（リング状に外周だけ outline になる）。
    /// CircleShape2D / CapsuleShape2D は y 方向のスキャンラインで近似する
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

    /// 矩形は「内側 1 枚 + 4 辺の outline」で構成する
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

    /// 円を「外側半径 R+t / 内側半径 R」のリングとしてスキャンラインに展開する
    def circleRingScanLines(center: Vec2.Vec2, radius: Float64,
                             outlineThickness: Float64): List[FillRect] =
        let outerRadius = radius + outlineThickness;
        let outerHalfWidthAt = y -> circleHalfWidthAt(outerRadius, y);
        let innerHalfWidthAt = y -> circleHalfWidthAt(radius, y);
        ringScanLines(center, outerRadius, outerHalfWidthAt, innerHalfWidthAt)

    /// カプセルを「外側 (R+t, H+2t) / 内側 (R, H)」のリングとしてスキャンラインに展開する。
    /// Godot CapsuleShape2D 準拠（vertical=true なら縦長）
    def capsuleRingScanLines(center: Vec2.Vec2, radius: Float64,
                              height: Float64, vertical: Bool,
                              outlineThickness: Float64): List[FillRect] =
        let outerRadius = radius + outlineThickness;
        // 矩形帯の半長は内側 / 外側で同じ（H/2 - R = (H+2t)/2 - (R+t)）
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

    /// 円の半幅（|y| > R で 0、それ以外は sqrt(R^2 - y^2)）
    def circleHalfWidthAt(radius: Float64, y: Float64): Float64 =
        let inside = radius * radius - y * y;
        if (inside <= 0.0) 0.0
        else Vec2.sqrt(inside)

    /// 縦長カプセルの半幅: 矩形帯では R 一定、上下キャップでは円の半幅
    def capsuleVerticalHalfWidthAt(halfSeg: Float64):
            Float64 -> Float64 -> Float64 =
        radius -> y -> {
            let absY = Float64.abs(y);
            if (absY <= halfSeg) radius
            else circleHalfWidthAt(radius, absY - halfSeg)
        }

    /// 横長カプセルの半幅: y 帯では `halfSeg + 円の半幅`
    def capsuleHorizontalHalfWidthAt(halfSeg: Float64):
            Float64 -> Float64 -> Float64 =
        radius -> y -> {
            let circleHalf = circleHalfWidthAt(radius, y);
            if (circleHalf <= 0.0) 0.0
            else halfSeg + circleHalf
        }

    /// 外側形状と内側形状の半幅関数を受け取り、各 y 行に対して
    /// 「左 outline + 中央 fill + 右 outline」または「全幅 outline（内側がない行）」
    /// を作って返す
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
                        // 内側がない行は全幅 outline（円・カプセルの上下キャップ）
                        {topLeft = {x = center#x - outerHalf, y = center#y + y},
                         size = {x = 2.0 * outerHalf, y = 1.0},
                         isOutline = true} :: Nil
                    else {
                        // 左 outline + 中央 fill + 右 outline でリング状の縁を作る
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

    /// FillRect の isOutline を見て塗り or フチの色 / α を選んで ColorRect を作り、
    /// CanvasLayer の子として連番名で追加する
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

    /// NodePath を子ノード名に使える文字列に変換する（"/" 区切り）
    def pathToTag(path: NodePath): String =
        String.intercalate("/", path)

    /// 塗りつぶしに使う 1 枚の矩形（左上 + サイズ + フチ用フラグ）
    type alias FillRect = {
        topLeft = Vec2.Vec2,
        size = Vec2.Vec2,
        isOutline = Bool
    }

    /// 衝突可視化のスタイル（塗りとフチの色 / α / 太さ）
    type alias CollisionStyle = {
        fillColor = {r = Float32, g = Float32, b = Float32},
        fillAlpha = Float32,
        outlineColor = {r = Float32, g = Float32, b = Float32},
        outlineAlpha = Float32,
        outlineThickness = Float64
    }

    /// 衝突可視化のスタイル: Godot のデバッグ表示風（薄い水色塗り + 不透明な水色フチ 1px）
    def collisionStyle(): CollisionStyle =
        {fillColor = {r = 0.4f32, g = 0.7f32, b = 1.0f32}, fillAlpha = 0.4f32,
         outlineColor = {r = 0.1f32, g = 0.5f32, b = 0.8f32}, outlineAlpha = 1.0f32,
         outlineThickness = 1.0}

    /// 衝突可視化用 CanvasLayer のノード名
    def collisionLayerName(): String = "_editor_collision_layer"

    /// 衝突可視化用レイヤ番号: 選択枠（999）より背面、ゲーム本体の最前面 layer=2 より前面
    def collisionLayerIndex(): Int32 = 998

    /// 選択枠のスタイル: 明るい黄色 × 2px
    def selectionStyle(): OutlineStyle = {
        layerName = "_editor_box_layer",
        color = {r = 1.0f32, g = 0.85f32, b = 0.2f32},
        thickness = 2.0
    }

    /// ホバー枠のスタイル: 薄いグレー × 1px（選択枠より控えめに）
    def hoverStyle(): OutlineStyle = {
        layerName = "_editor_hover_layer",
        color = {r = 0.7f32, g = 0.7f32, b = 0.7f32},
        thickness = 1.0
    }

    /// 矩形の 4 辺を CanvasLayer の中に細い ColorRect として配置する。
    /// 選択枠 / ホバー枠で共有
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

    /// 1 本の線分を ColorRect で作る
    def makeLine(line: {pos = Vec2.Vec2, size = Vec2.Vec2},
                 color: {r = Float32, g = Float32, b = Float32}): ColorRect =
        ColorRect.make(line#size, color)
            |> Node2D.setPosition(line#pos)

    /// オーバーレイ用 CanvasLayer のレイヤー番号（既存の最前面 layer=2 より大きく取る）
    def overlayLayerIndex(): Int32 = 999
}
