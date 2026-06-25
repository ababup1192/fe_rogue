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
                            transform: Camera2D.ViewTransform, zoom: Float64,
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
                        // 形状ごとのハンドル（円=半径1個 / カプセル=半径+高さ / 他=8）。
                        let allowed = match Scene.getEngineNode(nodePath, scene) {
                            case Some(n) => EditableNode.allowedHandles(n)
                            case None    => ResizeHandle.all()
                        };
                        // 選択表示は赤丸＋白フチのハンドルのみ（塗り/境界線/中心マークは
                        // 衝突オーバーレイが常時描く）。黄色の選択枠は出さない。
                        addResizeHandles(box, zoom, allowed, defaultTag, scene)
                }
        }

    /// 選択ノードのハンドル（小さな赤丸）を最前面に置く。円は半径ハンドル 1 個。
    /// ハンドルは zoom 補正で画面上一定サイズ（投影で ×zoom されるため /zoom）。
    pub def addResizeHandles(box: {topLeft = Vec2.Vec2, size = Vec2.Vec2},
                              zoom: Float64, allowed: List[ResizeHandle.Handle],
                              defaultTag: t, scene: Scene[t]): Scene[t] =
        let layerName = handleLayerName();
        let layer = CanvasLayer.make(overlayLayerIndex());
        let hs = ResizeHandle.handleSizeFor(zoom);
        // 白フチは画面上 1.5px（投影で ×zoom されるので /zoom）。
        let rim = 1.5 / (if (zoom <= 0.0) 1.0 else zoom);
        let withLayer = Scene.addNode(layerName,
            EngineNode.CanvasLayerWithState(layer, defaultTag), scene);
        // 回転ノブは Godot 風にスッキリさせるため描かない（回転は Inspector の Rotation で可能）。
        ResizeHandle.overlayRects(box, hs)
            |> List.filter(indexed -> List.memberOf(fst(indexed), allowed))
            |> List.foldLeft((acc, indexed) -> {
                let (handle, rect) = indexed;
                acc |> addDotHandle("${handle}", rect, rim, defaultTag)
            }, withLayer)

    def handleRedColor(): {r = Float32, g = Float32, b = Float32} =
        {r = 0.9f32, g = 0.2f32, b = 0.2f32}
    def handleWhiteColor(): {r = Float32, g = Float32, b = Float32} =
        {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    /// Godot 風ハンドル: 赤い丸 + 白フチ。Panel 1 枚で bg=赤・border=白・cornerRadius=半径 と指定し、
    /// 縁はシェーダが正確に描く（2 円重ねだと細い縁が AA で消えるズームがあるため 1 枚方式）。
    def addDotHandle(tag: String, rect: Rect2.Rect2, rim: Float64,
                     defaultTag: t, scene: Scene[t]): Scene[t] =
        let panel = Panel.make(rect#size, handleRedColor())
            |> Panel.setBorderColor(handleWhiteColor())
            |> Panel.setBorderWidth(rim)
            |> Panel.setCornerRadius(rect#size#x / 2.0)
            |> Node2D.setPosition(rect#position);
        Scene.addChildAt(handleLayerName() :: Nil, tag,
            EngineNode.PanelWithState(panel, defaultTag), scene)

    /// ハンドル群を載せる CanvasLayer のノード名
    def handleLayerName(): String = "_editor_handle_layer"

    /// マウス位置の編集対象ノードに薄い枠を描く（zoom 補正で画面上一定の細さ）
    pub def addHoverBox(rootJsonIndex: Map[NodeName, String],
                        mousePos: Vec2.Vec2,
                        selected: Option[Editor.Selection],
                        transform: Camera2D.ViewTransform, zoom: Float64,
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
                    let hStyle = {thickness = overlayLineThickness(zoom) | hoverStyle()};
                    addOutline(box, hStyle, defaultTag, scene)
                }
        }

    /// hover 対象が選択中ノードと一致するかを判定
    def isSelectedPath(path: NodePath, selected: Option[Editor.Selection]): Bool =
        match selected {
            case Some(sel) => path == sel#nodePath
            case None      => false
        }

    /// シーンに含まれるすべての CollisionObject2D の衝突形状を可視化する
    pub def addCollisionShapes(transform: Camera2D.ViewTransform, zoom: Float64,
                               defaultTag: t, scene: Scene[t]): Scene[t] =
        let layerName = collisionLayerName();
        let layer = CanvasLayer.make(collisionLayerIndex());
        let withLayer = Scene.addNode(layerName,
            EngineNode.CanvasLayerWithState(layer, defaultTag), scene);
        Scene.preorderPaths(scene)
            |> List.foldLeft((accScene, path) ->
                addShapeAtPath(layerName, path, transform, zoom, scene, defaultTag, accScene), withLayer)

    /// 指定パスのノードに衝突形状があれば描画する。輪郭/中心マークは zoom 補正で
    /// 画面上一定の細さ。輪郭は形状の境界線上に重ねる（選択ハンドルと一致させるため）。
    def addShapeAtPath(layerName: String, path: NodePath,
                       transform: Camera2D.ViewTransform, zoom: Float64,
                       sourceScene: Scene[t],
                       defaultTag: t,
                       acc: Scene[t]): Scene[t] =
        match Scene.getEngineNode(path, sourceScene) {
            case None => acc
            case Some(node) => match CollisionObject2D.getCollisionShape(node) {
                case None => acc
                case Some(shape) =>
                    let center = Scene.screenPositionAtWith(path, transform, editor = true, sourceScene);
                    // 輪郭は画面上 1px（投影で ×zoom されるので 1/zoom）。
                    let th = 1.0 / (if (zoom <= 0.0) 1.0 else zoom);
                    let markHalf = 7.0 / (if (zoom <= 0.0) 1.0 else zoom);
                    let pathTag = pathToTag(path);
                    // Rect は ColorRect の塗り＋辺、Circle/Capsule は Panel(cornerRadius) で
                    // なめらかに描く（スキャンラインだと zoom 拡大でジャギになるため）。
                    let withShape = match shape {
                        case CollisionShape2D.RectShape2D(r) =>
                            appendFillRects(layerName, pathTag,
                                rectFillAndOutlineRects(center, r#width, r#height, th),
                                collisionStyle(), defaultTag, acc)
                        case _ =>
                            addShapePanel(layerName, pathTag, center, shape, th, defaultTag, acc)
                    };
                    // 中心十字は塗りに埋もれないよう赤橙で別描画
                    addCenterCross(layerName, pathTag, center, markHalf, th, defaultTag, withShape)
            }
        }

    /// 円/カプセルを Panel(cornerRadius) でなめらかに描く（シェーダ AA）。
    /// 塗り = fillColor/fillAlpha、輪郭 = outlineColor を borderW(1px) で。
    def addShapePanel(layerName: String, pathTag: String, center: Vec2.Vec2,
                      shape: CollisionShape2D, borderW: Float64,
                      defaultTag: t, scene: Scene[t]): Scene[t] =
        let (w, h, cr) = panelDimsFor(shape);
        let style = collisionStyle();
        let panel = Panel.make({x = w, y = h}, style#fillColor)
            |> Panel.setBackgroundAlpha(style#fillAlpha)
            |> Panel.setBorderColor(style#outlineColor)
            |> Panel.setBorderAlpha(style#outlineAlpha)
            |> Panel.setBorderWidth(borderW)
            |> Panel.setCornerRadius(cr)
            |> Node2D.setPosition({x = center#x - w / 2.0, y = center#y - h / 2.0});
        Scene.addChildAt(layerName :: Nil, "${pathTag}_panel",
            EngineNode.PanelWithState(panel, defaultTag), scene)

    /// Panel の (幅, 高さ, cornerRadius)。円は 2r 正方＋半径 r、カプセルは 角丸=r の角丸矩形。
    def panelDimsFor(shape: CollisionShape2D): (Float64, Float64, Float64) =
        match shape {
            case CollisionShape2D.CircleShape2D(c) => (2.0 * c#radius, 2.0 * c#radius, c#radius)
            case CollisionShape2D.CapsuleShape2D(c) =>
                if (c#vertical) (2.0 * c#radius, c#height, c#radius)
                else            (c#height, 2.0 * c#radius, c#radius)
            case CollisionShape2D.RectShape2D(r)    => (r#width, r#height, 0.0)
        }

    /// 形状中心の白い十字マーク（teal 塗りの上で視認できるよう別色 ColorRect で描く）
    def addCenterCross(layerName: String, pathTag: String, center: Vec2.Vec2,
                       markHalf: Float64, th: Float64, defaultTag: t, scene: Scene[t]): Scene[t] =
        let markColor = {r = 0.95f32, g = 0.45f32, b = 0.2f32};  // Godot 風の赤橙
        let hBar = ColorRect.make({x = 2.0 * markHalf, y = th}, markColor)
            |> Node2D.setPosition({x = center#x - markHalf, y = center#y - th / 2.0});
        let vBar = ColorRect.make({x = th, y = 2.0 * markHalf}, markColor)
            |> Node2D.setPosition({x = center#x - th / 2.0, y = center#y - markHalf});
        scene
            |> Scene.addChildAt(layerName :: Nil, "${pathTag}_mark_h",
                EngineNode.ColorRectWithState(hBar, defaultTag))
            |> Scene.addChildAt(layerName :: Nil, "${pathTag}_mark_v",
                EngineNode.ColorRectWithState(vBar, defaultTag))

    /// 矩形コリジョンを Godot 風に描画する: 半透明の塗り + 細い枠線 + 中心の十字マーク。
    /// 塗りは fillColor/fillAlpha（青・薄め）、枠と中心マークは outlineColor。
    def rectFillAndOutlineRects(center: Vec2.Vec2, width: Float64, height: Float64,
                                 th: Float64): List[FillRect] =
        let halfW = width / 2.0;
        let halfH = height / 2.0;
        let topLeft = {x = center#x - halfW, y = center#y - halfH};
        // 内部塗り（半透明青）。Godot のように形状を塗って視認性を上げる
        let fill = {topLeft = topLeft, size = {x = width, y = height}, isOutline = false};
        // 境界線は形状の辺の「上」に重ねる（中心を辺に合わせて straddle）。
        // こうすると選択ハンドル（辺の隅・中点）が境界線にちょうど乗る。
        let topEdge = {topLeft = {x = topLeft#x - th / 2.0, y = topLeft#y - th / 2.0},
                       size = {x = width + th, y = th}, isOutline = true};
        let bottomEdge = {topLeft = {x = topLeft#x - th / 2.0, y = topLeft#y + height - th / 2.0},
                          size = {x = width + th, y = th}, isOutline = true};
        let leftEdge = {topLeft = {x = topLeft#x - th / 2.0, y = topLeft#y - th / 2.0},
                        size = {x = th, y = height + th}, isOutline = true};
        let rightEdge = {topLeft = {x = topLeft#x + width - th / 2.0, y = topLeft#y - th / 2.0},
                         size = {x = th, y = height + th}, isOutline = true};
        fill :: topEdge :: bottomEdge :: leftEdge :: rightEdge :: Nil

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
        // 塗り = #2D6D78 を ~15% 暗くした teal（Godot 寄りのくすんだ色）。
        {fillColor = {r = 0.14f32, g = 0.33f32, b = 0.37f32}, fillAlpha = 0.7f32,
         outlineColor = {r = 0.14f32, g = 0.33f32, b = 0.37f32}, outlineAlpha = 1.0f32,
         outlineThickness = 1.0}

    def collisionLayerName(): String = "_editor_collision_layer"

    def collisionLayerIndex(): Int32 = 998

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
        // 画面枠も 1px（軸・グリッドに揃えて太く見えないように）。
        let th = gridLineThickness(zoom);
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
                |> ColorRect.setAlpha(0.35f32)
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
        // 軸は画面上 1px（細く控えめに）。グリッドと同じ厚み。
        let th = gridLineThickness(zoom);
        // 控えめにするため軸も薄く（グリッドより少し濃い程度）。
        let axisAlpha = 0.22f32;
        // 無限に伸びる軸: 巨大スパンの線を原点(design-px)に置く（描画は scissor 無しで帯にも描かれる）。
        let big = 100000.0;
        let originScreen = {x = 0.0, y = 0.0};
        let layerName = "_origin_layer";
        let layer = CanvasLayer.make(originLayerIndex());
        let base = Scene.addNode(layerName,
            EngineNode.CanvasLayerWithState(layer, defaultTag), scene);
        let xAxis = ColorRect.make({x = 2.0 * big, y = th}, {r = 0.85f32, g = 0.35f32, b = 0.37f32})
            |> ColorRect.setAlpha(axisAlpha)
            |> Node2D.setPosition({x = 0.0 - big, y = originScreen#y});
        let yAxis = ColorRect.make({x = th, y = 2.0 * big}, {r = 0.4f32, g = 0.8f32, b = 0.45f32})
            |> ColorRect.setAlpha(axisAlpha)
            |> Node2D.setPosition({x = originScreen#x, y = 0.0 - big});
        base
            |> Scene.addChildAt(layerName :: Nil, "origin_x",
                EngineNode.ColorRectWithState(xAxis, defaultTag))
            |> Scene.addChildAt(layerName :: Nil, "origin_y",
                EngineNode.ColorRectWithState(yAxis, defaultTag))

    def originLayerIndex(): Int32 = 1000

    /// スナップ ON 時に、吸着の区切り単位（step）で**白い**グリッド線を敷く。
    /// `visibleTopLeft` = 画面左上の design 座標（= editor pan）。そこから見える範囲を覆うよう
    /// zoom に応じた広さ（estCanvas/zoom）で線を生成する（画面外にはみ出た線は FBO で clip）。
    /// 原点(0,0)起点・design-px なので線は snapVec と同じ格子に一致（pan/zoom は投影で追従）。
    /// 線の太さは zoom 補正で画面上一定。step<=0（=スナップ OFF）なら何も描かない。
    pub def addSnapGrid(visibleTopLeft: Vec2.Vec2, step: Float64, zoom: Float64,
                        defaultTag: t, scene: Scene[t]): Scene[t] =
        if (step <= 0.0) scene
        else {
            let z = if (zoom <= 0.0) 1.0 else zoom;
            // 見える design 範囲 ≒ canvas_px / zoom。canvas_px は取得 API が無いため広めに見積もる
            // （estCanvas）。はみ出し分は clip されるので過大見積りは無害、過小だと端が欠ける。
            let span = estCanvasPx() / z;
            let x0 = Float64.floor(visibleTopLeft#x / step) * step;
            let y0 = Float64.floor(visibleTopLeft#y / step) * step;
            let x1 = visibleTopLeft#x + span;
            let y1 = visibleTopLeft#y + span;
            let th = gridLineThickness(z);
            let layerName = "_design_grid_layer";
            let layer = CanvasLayer.make(gridLayerIndex());
            let base = Scene.addNode(layerName,
                EngineNode.CanvasLayerWithState(layer, defaultTag), scene);
            let lineH = y1 - y0;
            let lineW = x1 - x0;
            let (afterV, _) = List.foldLeft((acc, x) -> {
                let (sc, i) = acc;
                let line = ColorRect.make({x = th, y = lineH}, gridColor())
                    |> ColorRect.setAlpha(gridAlpha())
                    |> Node2D.setPosition({x = x, y = y0});
                (Scene.addChildAt(layerName :: Nil, "v_${i}",
                    EngineNode.ColorRectWithState(line, defaultTag), sc), i + 1)
            }, (base, 0), gridCoords(x0, x1, step));
            let (afterH, _) = List.foldLeft((acc, y) -> {
                let (sc, i) = acc;
                let line = ColorRect.make({x = lineW, y = th}, gridColor())
                    |> ColorRect.setAlpha(gridAlpha())
                    |> Node2D.setPosition({x = x0, y = y});
                (Scene.addChildAt(layerName :: Nil, "h_${i}",
                    EngineNode.ColorRectWithState(line, defaultTag), sc), i + 1)
            }, (afterV, 0), gridCoords(y0, y1, step));
            afterH
        }

    def gridColor(): {r = Float32, g = Float32, b = Float32} =
        {r = 1.0f32, g = 1.0f32, b = 1.0f32}
    def gridAlpha(): Float32 = 0.08f32
    def gridLineThickness(zoom: Float64): Float64 =
        1.0 / (if (zoom <= 0.0) 1.0 else zoom)
    // 見える canvas 幅の見積り(logical px)。実 canvas より広めにして端の欠けを防ぐ（はみ出しは clip）。
    def estCanvasPx(): Float64 = 2600.0
    // グリッド線数の安全上限（fine step + ズームアウトでの暴走を防ぐ）。
    def gridMaxLines(): Int32 = 400
    // start から step 間隔で end 未満の座標を最大 gridMaxLines 個生成する。
    def gridCoords(start: Float64, end: Float64, step: Float64): List[Float64] =
        gridCoordsAcc(start, end, step, 0, Nil) |> List.reverse
    def gridCoordsAcc(cur: Float64, end: Float64, step: Float64,
                      n: Int32, acc: List[Float64]): List[Float64] =
        if (cur >= end or n >= gridMaxLines()) acc
        else gridCoordsAcc(cur + step, end, step, n + 1, cur :: acc)
    // グリッドは衝突形状(998)より下に敷き、guide として背面に置く。
    def gridLayerIndex(): Int32 = 997

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
