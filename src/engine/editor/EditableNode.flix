// EditableNode — エディタが編集対象として扱うノードの抽出と矩形計算
//
// シーンを走査し Sprite2D / AnimatedSprite2D / TextureButton / Label2D / ColorRect /
// CanvasLayer を編集対象として認識する。
// 各ノードの「画面上の表示矩形」（width / height と topLeftOffset）を計算して返すのが主な仕事。
//
// CanvasLayer は「ダイアログウィンドウ等のコンテナ全体」として扱う。
// その bbox は 子ノードの bbox の和集合で計算する（layer ローカル座標）。
//
// rootJsonIndex (root 名 → scene.json パス) に登録されていないルートに属する
// ノードは「JSON 書き戻し先が不明」として除外する（procedural 生成ノードや、
// エディタ自身のオーバーレイなど）

mod EditableNode {

    /// シーン上のノードを「編集対象として扱える形」で問い合わせるための文脈。
    pub type alias LookupCtx = {
        rootJsonIndex = Map[NodeName, String],
        scene = Scene[NodeTag]
    }

    /// 編集対象ノードの 1 件分の情報。
    /// isContainer = true なら CanvasLayer のようなコンテナ。Shift 修飾なしの
    /// クリックで優先される（子要素より先に hit）。
    pub type alias EditableEntry = {
        jsonPath = String,
        nodePath = NodePath,
        width = Float64,
        height = Float64,
        topLeftOffset = Vec2.Vec2,
        isContainer = Bool
    }

    /// シーン全体を走査して編集対象ノードを抽出する。
    pub def collectAll(ctx: LookupCtx): List[EditableEntry] \ GameEngine.Game =
        Scene.preorderPaths(ctx#scene)
            |> List.filterMap(path -> buildEntry(ctx, path))

    /// 指定 NodePath の entry を 1 件取り出す。
    pub def findByNodePath(ctx: LookupCtx, nodePath: NodePath):
            Option[EditableEntry] \ GameEngine.Game =
        buildEntry(ctx, nodePath)

    /// Sprite2D / TextureButton の topLeftOffset 計算（中央基準なら半サイズ分マイナス）。
    pub def boxTopLeftOffset(centered: Bool, size: Vec2.Vec2): Vec2.Vec2 =
        if (centered) {x = -size#x / 2.0, y = -size#y / 2.0}
        else {x = 0.0, y = 0.0}

    /// Label2D の表示矩形を計算する。
    /// 横方向は HorizontalAlignment.Center のときのみ -width/2 オフセット、
    /// それ以外は 0（Left/Right/Fill は本実装では Left と同じ扱い）。
    pub def labelRectInfo(label: Label2D): {size = Vec2.Vec2, topLeftOffset = Vec2.Vec2} =
        let Label2D.Label2D(record) = label;
        let atlas = record#fontAtlas;
        let scale = record#fontSize / atlas#fontSize;
        let lines = TextLayout.splitLines(record#text);
        let lineWidths = List.map(lineChars -> {
            let advances = List.map(ch -> {
                let cp = TextLayout.charToCodePoint(ch);
                match Map.get(cp, atlas#glyphs) {
                    case Some(glyphMetrics) => glyphMetrics#advance
                    case None => 0.0
                }
            }, lineChars);
            TextLayout.totalAdvance(advances) * scale
        }, lines);
        let width = List.foldLeft(Float64.max, 0.0, lineWidths);
        let lineHeight = (atlas#ascent + atlas#descent + atlas#lineGap) * scale;
        let height = lineHeight * Int32.toFloat64(Int32.max(1, List.length(lines)));
        let topLeftOffset = match record#horizontalAlignment {
            case HorizontalAlignment.Center => {x = -width / 2.0, y = 0.0}
            case _                          => {x = 0.0, y = 0.0}
        };
        {size = {x = width, y = height}, topLeftOffset = topLeftOffset}

    /// ColorRect の表示矩形を計算する。position 原点 = 左上なので offset はゼロ。
    def colorRectRectInfo(rect: ColorRect):
            {size = Vec2.Vec2, topLeftOffset = Vec2.Vec2} =
        let ColorRect.ColorRect(r) = rect;
        {size = r#size, topLeftOffset = {x = 0.0, y = 0.0}}

    /// 1 パス分の EditableEntry を構築する。
    def buildEntry(ctx: LookupCtx, path: NodePath):
            Option[EditableEntry] \ GameEngine.Game =
        forM (
            rootName   <- List.head(path);
            jsonPath   <- Map.get(rootName, ctx#rootJsonIndex);
            engineNode <- Scene.getEngineNode(path, ctx#scene);
            rect       <- rectInfoOf(engineNode, path, ctx#scene)
        ) yield {
            jsonPath = jsonPath,
            nodePath = path,
            width = rect#size#x,
            height = rect#size#y,
            topLeftOffset = rect#topLeftOffset,
            isContainer = isContainerNode(engineNode)
        }

    /// CanvasLayer はコンテナとして扱う（クリック時に子より優先される）。
    def isContainerNode(engineNode: EngineNode[NodeTag]): Bool =
        match engineNode {
            case EngineNode.CanvasLayerWithState(_, _) => true
            case _                                     => false
        }

    /// snapshot に保存された開始時の値 × ratio で、新しい EngineNode を返す。
    /// 必ず snapshot の prev 値を起点にするので、毎フレーム呼び出されても
    /// 結果は累乗されず常に「原始 × 現フレームの ratio」になる。
    /// snapshot と engineNode の型が一致しない場合は engineNode を変更しない。
    pub def applyResizeFromSnapshot(snapshot: NodeResizeSnapshot, ratio: Vec2.Vec2):
            EngineNode[NodeTag] -> EngineNode[NodeTag] = engineNode ->
        match engineNode {
            case EngineNode.ColorRectWithState(rect, st) =>
                match snapshot#prevSize {
                    case Some(prev) =>
                        let newSize = {x = prev#x * ratio#x, y = prev#y * ratio#y};
                        EngineNode.ColorRectWithState(ColorRect.setSize(newSize, rect), st)
                    case None => engineNode
                }
            case EngineNode.Label2DWithState(label, st) =>
                match snapshot#prevFontSize {
                    case Some(prev) =>
                        let r = Float64.min(ratio#x, ratio#y);
                        EngineNode.Label2DWithState(
                            Label2D.setFontSize(prev * r, label), st)
                    case None => engineNode
                }
            case EngineNode.Sprite2DWithState(sprite, st) =>
                match snapshot#prevScale {
                    case Some(prev) =>
                        let newScale = {x = prev#x * ratio#x, y = prev#y * ratio#y};
                        EngineNode.Sprite2DWithState(
                            Node2D.setScale(newScale, sprite), st)
                    case None => engineNode
                }
            case EngineNode.AnimSprite2DWithState(sprite, st) =>
                match snapshot#prevScale {
                    case Some(prev) =>
                        let newScale = {x = prev#x * ratio#x, y = prev#y * ratio#y};
                        EngineNode.AnimSprite2DWithState(
                            Node2D.setScale(newScale, sprite), st)
                    case None => engineNode
                }
            case EngineNode.TextureButtonWithState(btn, st) =>
                match snapshot#prevSize {
                    case Some(prev) =>
                        let newSize = {x = prev#x * ratio#x, y = prev#y * ratio#y};
                        EngineNode.TextureButtonWithState(
                            TextureButton.setSize(newSize, btn), st)
                    case None => engineNode
                }
            case EngineNode.RichTextLabelWithState(label, st) =>
                match snapshot#prevSize {
                    case Some(prev) =>
                        let newSize = {x = prev#x * ratio#x, y = prev#y * ratio#y};
                        EngineNode.RichTextLabelWithState(
                            RichTextLabel.setSize(newSize, label), st)
                    case None => engineNode
                }
            case EngineNode.Area2DWithState(area, st) =>
                match snapshot#prevShape {
                    case Some(prev) =>
                        let newShape = scaleCollisionShape(prev, ratio);
                        EngineNode.Area2DWithState(
                            Area2D.setCollisionShape(Some(newShape), area), st)
                    case None => engineNode
                }
            case _ => engineNode
        }

    /// CollisionShape2D を `ratio` で拡縮する。
    /// - Rect: width / height をそれぞれ非対称にスケール
    /// - Circle: radius は等方なので min(ratio.x, ratio.y) を採用
    /// - Capsule: radius は min ratio、height は vertical 軸に合わせて
    def scaleCollisionShape(shape: CollisionShape2D, ratio: Vec2.Vec2): CollisionShape2D =
        match shape {
            case CollisionShape2D.RectShape2D(r) =>
                CollisionShape2D.RectShape2D({
                    width  = r#width  * ratio#x,
                    height = r#height * ratio#y
                })
            case CollisionShape2D.CircleShape2D(c) =>
                let uniform = Float64.min(ratio#x, ratio#y);
                CollisionShape2D.CircleShape2D({radius = c#radius * uniform})
            case CollisionShape2D.CapsuleShape2D(c) =>
                let uniform = Float64.min(ratio#x, ratio#y);
                let heightRatio = if (c#vertical) ratio#y else ratio#x;
                CollisionShape2D.CapsuleShape2D({
                    radius = c#radius * uniform,
                    height = c#height * heightRatio,
                    vertical = c#vertical
                })
        }

    /// ノード型に応じて JSON 書き戻しに必要な FieldUpdate のリストを返す。
    /// リサイズドロップ時に `applyResize` で更新したノードを永続化するためのヘルパ。
    /// `oldNode`: ドラッグ開始時のノード状態（差分検出用）
    /// `newNode`: 現在のシーンに居るノード（リサイズ後の状態）
    /// 位置は別 key（"pos"）で別途記録するためここには含まない
    pub def resizeFieldUpdates(engineNode: EngineNode[NodeTag]):
            List[SceneSerializer.FieldUpdate] =
        match engineNode {
            case EngineNode.ColorRectWithState(rect, _) =>
                {key = "size",
                 value = SceneSerializer.FieldValue.VecValue(ColorRect.getSize(rect))} :: Nil
            case EngineNode.Label2DWithState(label, _) =>
                {key = "fontSize",
                 value = SceneSerializer.FieldValue.ScalarValue(Label2D.getFontSize(label))} :: Nil
            case EngineNode.Sprite2DWithState(sprite, _) =>
                {key = "scale",
                 value = SceneSerializer.FieldValue.VecValue(Node2D.getScale(sprite))} :: Nil
            case EngineNode.AnimSprite2DWithState(sprite, _) =>
                {key = "scale",
                 value = SceneSerializer.FieldValue.VecValue(Node2D.getScale(sprite))} :: Nil
            case EngineNode.TextureButtonWithState(btn, _) =>
                {key = "size",
                 value = SceneSerializer.FieldValue.VecValue(TextureButton.getSize(btn))} :: Nil
            case EngineNode.RichTextLabelWithState(label, _) =>
                {key = "size",
                 value = SceneSerializer.FieldValue.VecValue(RichTextLabel.getSize(label))} :: Nil
            case EngineNode.Area2DWithState(area, _) =>
                match CollisionObject2D.getCollisionShape(area) {
                    case Some(shape) =>
                        {key = "shape",
                         value = SceneSerializer.FieldValue.ShapeValue(shape)} :: Nil
                    case None => Nil
                }
            case _ => Nil
        }

    /// リサイズ巻き戻しに必要な「元の値」を 1 ノード分まとめて記録する。
    /// undo 用の EditHistory.ResizeEntry に詰める前に呼ぶ
    pub type alias NodeResizeSnapshot = {
        nodePath = NodePath,
        prevPosition = Vec2.Vec2,
        prevSize = Option[Vec2.Vec2],          // ColorRect / TextureButton / RichTextLabel 用
        prevFontSize = Option[Float64],         // Label2D 用
        prevScale = Option[Vec2.Vec2],          // Sprite2D / AnimatedSprite2D 用
        prevShape = Option[CollisionShape2D]    // Area2D 用 (CollisionShape2D の幾何)
    }

    /// ノードの現在状態を NodeResizeSnapshot にスナップショットする
    pub def snapshotForResize(nodePath: NodePath,
                              engineNode: EngineNode[NodeTag]): NodeResizeSnapshot =
        let prevPos = Node2D.getPosition(engineNode);
        match engineNode {
            case EngineNode.ColorRectWithState(rect, _) => {
                nodePath = nodePath, prevPosition = prevPos,
                prevSize = Some(ColorRect.getSize(rect)),
                prevFontSize = None, prevScale = None, prevShape = None
            }
            case EngineNode.Label2DWithState(label, _) => {
                nodePath = nodePath, prevPosition = prevPos,
                prevSize = None,
                prevFontSize = Some(Label2D.getFontSize(label)),
                prevScale = None, prevShape = None
            }
            case EngineNode.Sprite2DWithState(sprite, _) => {
                nodePath = nodePath, prevPosition = prevPos,
                prevSize = None, prevFontSize = None,
                prevScale = Some(Node2D.getScale(sprite)),
                prevShape = None
            }
            case EngineNode.AnimSprite2DWithState(sprite, _) => {
                nodePath = nodePath, prevPosition = prevPos,
                prevSize = None, prevFontSize = None,
                prevScale = Some(Node2D.getScale(sprite)),
                prevShape = None
            }
            case EngineNode.TextureButtonWithState(btn, _) => {
                nodePath = nodePath, prevPosition = prevPos,
                prevSize = Some(TextureButton.getSize(btn)),
                prevFontSize = None, prevScale = None, prevShape = None
            }
            case EngineNode.RichTextLabelWithState(label, _) => {
                nodePath = nodePath, prevPosition = prevPos,
                prevSize = Some(RichTextLabel.getSize(label)),
                prevFontSize = None, prevScale = None, prevShape = None
            }
            case EngineNode.Area2DWithState(area, _) => {
                nodePath = nodePath, prevPosition = prevPos,
                prevSize = None, prevFontSize = None, prevScale = None,
                prevShape = CollisionObject2D.getCollisionShape(area)
            }
            case _ => {
                nodePath = nodePath, prevPosition = prevPos,
                prevSize = None, prevFontSize = None, prevScale = None,
                prevShape = None
            }
        }

    /// スナップショットから EngineNode を元の状態に戻す（undo 用）
    pub def restoreFromSnapshot(snapshot: NodeResizeSnapshot,
                                 engineNode: EngineNode[NodeTag]):
            EngineNode[NodeTag] =
        let withPos = Node2D.setPosition(snapshot#prevPosition, engineNode);
        match engineNode {
            case EngineNode.ColorRectWithState(rect, st) =>
                match snapshot#prevSize {
                    case Some(sz) =>
                        EngineNode.ColorRectWithState(
                            ColorRect.setSize(sz, rect)
                                |> Node2D.setPosition(snapshot#prevPosition), st)
                    case None => withPos
                }
            case EngineNode.Label2DWithState(label, st) =>
                match snapshot#prevFontSize {
                    case Some(fs) =>
                        EngineNode.Label2DWithState(
                            Label2D.setFontSize(fs, label)
                                |> Node2D.setPosition(snapshot#prevPosition), st)
                    case None => withPos
                }
            case EngineNode.Sprite2DWithState(_, _) =>
                match snapshot#prevScale {
                    case Some(sc) => Node2D.setScale(sc, withPos)
                    case None => withPos
                }
            case EngineNode.AnimSprite2DWithState(_, _) =>
                match snapshot#prevScale {
                    case Some(sc) => Node2D.setScale(sc, withPos)
                    case None => withPos
                }
            case EngineNode.TextureButtonWithState(btn, st) =>
                match snapshot#prevSize {
                    case Some(sz) =>
                        EngineNode.TextureButtonWithState(
                            TextureButton.setSize(sz, btn)
                                |> Node2D.setPosition(snapshot#prevPosition), st)
                    case None => withPos
                }
            case EngineNode.RichTextLabelWithState(label, st) =>
                match snapshot#prevSize {
                    case Some(sz) =>
                        EngineNode.RichTextLabelWithState(
                            RichTextLabel.setSize(sz, label)
                                |> Node2D.setPosition(snapshot#prevPosition), st)
                    case None => withPos
                }
            case EngineNode.Area2DWithState(area, st) =>
                match snapshot#prevShape {
                    case Some(shape) =>
                        EngineNode.Area2DWithState(
                            Area2D.setCollisionShape(Some(shape), area)
                                |> Node2D.setPosition(snapshot#prevPosition), st)
                    case None => withPos
                }
            case _ => withPos
        }

    /// スナップショットから JSON 書戻用の FieldUpdate を組み立てる（undo 用）
    pub def snapshotToFieldUpdates(snapshot: NodeResizeSnapshot):
            List[SceneSerializer.FieldUpdate] =
        let posUpd: SceneSerializer.FieldUpdate =
            {key = "pos",
             value = SceneSerializer.FieldValue.VecValue(snapshot#prevPosition)};
        let sizeUpds = match snapshot#prevSize {
            case Some(sz) => ({key = "size",
                value = SceneSerializer.FieldValue.VecValue(sz)}
                : SceneSerializer.FieldUpdate) :: Nil
            case None     => Nil
        };
        let fontSizeUpds = match snapshot#prevFontSize {
            case Some(fs) => ({key = "fontSize",
                value = SceneSerializer.FieldValue.ScalarValue(fs)}
                : SceneSerializer.FieldUpdate) :: Nil
            case None     => Nil
        };
        let scaleUpds = match snapshot#prevScale {
            case Some(sc) => ({key = "scale",
                value = SceneSerializer.FieldValue.VecValue(sc)}
                : SceneSerializer.FieldUpdate) :: Nil
            case None     => Nil
        };
        let shapeUpds = match snapshot#prevShape {
            case Some(shape) => ({key = "shape",
                value = SceneSerializer.FieldValue.ShapeValue(shape)}
                : SceneSerializer.FieldUpdate) :: Nil
            case None        => Nil
        };
        posUpd :: sizeUpds ++ fontSizeUpds ++ scaleUpds ++ shapeUpds

    /// ノードの表示サイズと topLeftOffset を返す（編集対象でなければ None）。
    /// CanvasLayer は子の bbox の和集合で計算するため scene と path も受け取る。
    /// Area2D は CollisionShape2D の bbox を出して、エディタで位置・サイズを
    /// 直接ドラッグできるようにする (Marker2D + collision の代わり)。
    def rectInfoOf(engineNode: EngineNode[NodeTag], path: NodePath, scene: Scene[NodeTag]):
            Option[{size = Vec2.Vec2, topLeftOffset = Vec2.Vec2}] \ GameEngine.Game =
        match engineNode {
            case EngineNode.Sprite2DWithState(sprite, _) => spriteRectInfo(sprite)
            case EngineNode.AnimSprite2DWithState(sprite, _) => animatedSpriteRectInfo(sprite)
            case EngineNode.TextureButtonWithState(btn, _) => Some(buttonRectInfo(btn))
            case EngineNode.Label2DWithState(label, _) => Some(labelRectInfo(label))
            case EngineNode.ColorRectWithState(rect, _) => Some(colorRectRectInfo(rect))
            case EngineNode.RichTextLabelWithState(label, _) => Some(richTextLabelRectInfo(label))
            case EngineNode.CanvasLayerWithState(_, _) => canvasLayerRectInfo(path, scene)
            case EngineNode.Area2DWithState(area, _) => area2dRectInfo(area)
            case _ => None
        }

    /// Area2D の表示矩形は `collisionShape` の bbox。
    /// Area2D の position は中心なので topLeftOffset は -size/2。
    /// shape が None / Capsule (bbox 取れない) は None を返してエディタで非選択。
    def area2dRectInfo(area: Area2D):
            Option[{size = Vec2.Vec2, topLeftOffset = Vec2.Vec2}] =
        match CollisionObject2D.getCollisionShape(area) {
            case None        => None
            case Some(shape) => collisionShapeRectInfo(shape)
        }

    /// CollisionShape2D を矩形 bbox に変換する。中心原点なので offset は -size/2。
    def collisionShapeRectInfo(shape: CollisionShape2D):
            Option[{size = Vec2.Vec2, topLeftOffset = Vec2.Vec2}] =
        match shape {
            case CollisionShape2D.RectShape2D(r) =>
                let size: Vec2.Vec2 = {x = r#width, y = r#height};
                Some({size = size,
                      topLeftOffset = ({x = -size#x / 2.0, y = -size#y / 2.0}: Vec2.Vec2)})
            case CollisionShape2D.CircleShape2D(c) =>
                let d = c#radius * 2.0;
                let size: Vec2.Vec2 = {x = d, y = d};
                Some({size = size,
                      topLeftOffset = ({x = -size#x / 2.0, y = -size#y / 2.0}: Vec2.Vec2)})
            case CollisionShape2D.CapsuleShape2D(c) =>
                let size: Vec2.Vec2 =
                    if (c#vertical) {x = c#radius * 2.0, y = c#height}
                    else            {x = c#height, y = c#radius * 2.0};
                Some({size = size,
                      topLeftOffset = ({x = -size#x / 2.0, y = -size#y / 2.0}: Vec2.Vec2)})
        }

    /// RichTextLabel の表示矩形は内蔵の `size` フィールド（描画領域）。
    /// position 原点 = 左上なので offset はゼロ
    def richTextLabelRectInfo(label: RichTextLabel):
            {size = Vec2.Vec2, topLeftOffset = Vec2.Vec2} =
        {size = RichTextLabel.getSize(label), topLeftOffset = {x = 0.0, y = 0.0}}

    /// CanvasLayer の表示矩形を子ノードの bbox の和集合で計算する。
    /// 子は CanvasLayer ローカル座標（layer.position 起点）に居るので、
    /// 各子の (localPos + topLeftOffset) ～ (localPos + topLeftOffset + size) を union する。
    /// 子が一つも居なければ None（移動できないコンテナは扱わない）。
    def canvasLayerRectInfo(path: NodePath, scene: Scene[NodeTag]):
            Option[{size = Vec2.Vec2, topLeftOffset = Vec2.Vec2}] \ GameEngine.Game =
        let childNames = Scene.getChildrenAt(path, scene);
        let childRects = List.filterMap(name -> {
            let childPath = List.append(path, name :: Nil);
            match Scene.getEngineNode(childPath, scene) {
                case None => None
                case Some(childNode) =>
                    forM (
                        rect <- childRectInfoLocal(childNode)
                    ) yield {
                        let localPos = Node2D.getPosition(childNode);
                        {topLeft = Vec2.add(localPos, rect#topLeftOffset),
                         size = rect#size}
                    }
            }
        }, childNames);
        unionRects(childRects)

    /// CanvasLayer の bbox 計算用に、子ノード（CanvasLayer 以外）の bbox を取り出す。
    /// 入れ子の CanvasLayer は再帰しない（深い hierarchies は素直にそのまま）。
    /// Area2D も含めて Layer 全体の選択範囲に寄与させる。
    def childRectInfoLocal(engineNode: EngineNode[NodeTag]):
            Option[{size = Vec2.Vec2, topLeftOffset = Vec2.Vec2}] \ GameEngine.Game =
        match engineNode {
            case EngineNode.Sprite2DWithState(sprite, _) => spriteRectInfo(sprite)
            case EngineNode.AnimSprite2DWithState(sprite, _) => animatedSpriteRectInfo(sprite)
            case EngineNode.TextureButtonWithState(btn, _) => Some(buttonRectInfo(btn))
            case EngineNode.Label2DWithState(label, _) => Some(labelRectInfo(label))
            case EngineNode.ColorRectWithState(rect, _) => Some(colorRectRectInfo(rect))
            case EngineNode.RichTextLabelWithState(label, _) => Some(richTextLabelRectInfo(label))
            case EngineNode.Area2DWithState(area, _) => area2dRectInfo(area)
            case _ => None
        }

    /// 矩形リストの和集合を {size, topLeftOffset} 形式で返す。
    /// 空リストなら None
    def unionRects(rects: List[{topLeft = Vec2.Vec2, size = Vec2.Vec2}]):
            Option[{size = Vec2.Vec2, topLeftOffset = Vec2.Vec2}] =
        match rects {
            case Nil => None
            case first :: rest =>
                let initial = {
                    minX = first#topLeft#x,
                    minY = first#topLeft#y,
                    maxX = first#topLeft#x + first#size#x,
                    maxY = first#topLeft#y + first#size#y
                };
                let bounds = List.foldLeft((acc, r) -> {
                    minX = Float64.min(acc#minX, r#topLeft#x),
                    minY = Float64.min(acc#minY, r#topLeft#y),
                    maxX = Float64.max(acc#maxX, r#topLeft#x + r#size#x),
                    maxY = Float64.max(acc#maxY, r#topLeft#y + r#size#y)
                }, initial, rest);
                Some({
                    size = {x = bounds#maxX - bounds#minX, y = bounds#maxY - bounds#minY},
                    topLeftOffset = {x = bounds#minX, y = bounds#minY}
                })
        }

    /// Sprite2D の矩形情報。
    def spriteRectInfo(sprite: Sprite2D):
            Option[{size = Vec2.Vec2, topLeftOffset = Vec2.Vec2}] \ GameEngine.Game =
        let Sprite2D.Sprite2D(record) = sprite;
        GameEngine.Game.getTextureInfo(record#texture)
            |> Option.map(info -> {
                let size = {x = info#width * record#scale#x,
                            y = info#height * record#scale#y};
                {size = size,
                 topLeftOffset = boxTopLeftOffset(record#centered, size)}
            })

    /// AnimatedSprite2D の矩形情報。
    def animatedSpriteRectInfo(sprite: AnimatedSprite2D):
            Option[{size = Vec2.Vec2, topLeftOffset = Vec2.Vec2}] \ GameEngine.Game =
        let AnimatedSprite2D.AnimatedSprite2D(record) = sprite;
        let texture = AnimatedSprite2D.currentTexture(sprite);
        GameEngine.Game.getTextureInfo(texture)
            |> Option.map(info -> {
                let size = {x = info#width * record#scale#x,
                            y = info#height * record#scale#y};
                {size = size,
                 topLeftOffset = boxTopLeftOffset(record#centered, size)}
            })

    /// TextureButton の矩形情報。
    def buttonRectInfo(btn: TextureButton):
            {size = Vec2.Vec2, topLeftOffset = Vec2.Vec2} =
        let size = TextureButton.getSize(btn);
        {size = size,
         topLeftOffset = boxTopLeftOffset(TextureButton.isCentered(btn), size)}
}
