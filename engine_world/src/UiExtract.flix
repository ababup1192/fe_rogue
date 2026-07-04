// UiExtract — UI entity から描画データへの射影
//
// Bevy の extract フェーズ相当。レイアウト済みの矩形と可視性から、Render.RenderItem 列を作る。
// テキスト実寸計算は engine の Label2D.measure を再利用する（自前のフォントメトリクス計算はしない）。
// 描画は画面固定 HUD 想定で camera scale を掛けない。呼び側が Render.drawAtlas に渡す。

mod UiExtract {

    /// text コンポーネントの内在サイズ（measure）を求める。
    /// atlasOf は font 名→FontAtlas（呼び側が Game.getFontAtlas 等で組む）。
    /// atlasOf が副作用を持つ場合はその effect が伝播する。
    pub def measureTexts(texts: Map[EntityId, UiWidget.TextComp], atlasOf: String -> FontAtlas \ ef): Map[EntityId, Vec2.Vec2] \ ef =
        texts |> Map.map(comp -> Label2D.measure(Label2D.make(comp#text, atlasOf(comp#font), comp#fontSize)))

    /// UI entity を (位置, RenderItem) 列へ射影する。可視 entity のみ・矩形が確定したもののみ。
    /// 並びは (zIndex, 階層深さ, order, id) で安定ソートする（背面から前面へ）。
    /// box → 単色塗り（alpha 反映）、text → 着色テキスト、sprite → スプライト。
    /// sprite のセル分割（frame→regionRect）でテクスチャ寸法を引くため GameEngine.Game を要求する。
    pub def extract(ui: UiStore.UiWorld, rects: Map[EntityId, Rect2.Rect2],
                    vis: Map[EntityId, Bool], atlasOf: String -> FontAtlas \ ef): List[(Vec2.Vec2, Render.RenderItem)] \ (ef + GameEngine.Game) =
        let boxEntries = ui#boxes |> Map.foldLeftWithKey((acc, id, box) ->
            match Map.get(id, rects) {
                case None       => acc
                case Some(rect) => (id, box#zIndex, boxItem(box, rect#size)) :: acc
            }, Nil);
        let spriteEntries = ui#sprites |> Map.foldLeftWithKey((acc, id, sprite) ->
            (id, sprite#zIndex, spriteItem(sprite)) :: acc, Nil);
        let textEntries = Map.foldLeftWithKey((acc, id, comp) ->
            (id, comp#zIndex, textItem(comp, atlasOf)) :: acc,
            (Nil : List[(EntityId, Int32, Render.RenderItem)]), ui#texts);
        List.append(boxEntries, List.append(spriteEntries, textEntries))
            |> List.filter(entry -> {let (id, _z, _item) = entry; Option.getWithDefault(true, Map.get(id, vis))})
            |> List.filterMap(entry -> {
                let (id, z, item) = entry;
                Map.get(id, rects) |> Option.map(rect -> (id, z, rect#position, item))
            })
            |> List.sortBy(entry -> {let (id, z, _pos, _item) = entry; (z, depthOf(id, ui#parents), orderOf(id, ui), id)})
            |> List.map(entry -> {let (_id, _z, pos, item) = entry; (pos, item)})

    /// poly entity を (id, rect 左上, ワールド座標へ移した PolyComp) 列へ射影する。可視かつ rect 確定のみ。
    /// PolyComp#polys の各サブポリ頂点はレイアウト矩形左上を原点とするローカル design px。ここで rect
    /// 左上を全頂点へ足し、design 空間の絶対座標にした polys を持つ PolyComp を返す（tuple の Vec2 は
    /// 適用した左上そのもの）。
    /// 並びは extract と同じ (zIndex, 階層深さ, order, id)。PolygonRenderCmd への最終変換
    /// （layer zIndex 加算・engine 型への詰め替え）は UiRender が行い、ここは engine 型へ依存しない。
    pub def extractPolys(ui: UiStore.UiWorld, rects: Map[EntityId, Rect2.Rect2],
                         vis: Map[EntityId, Bool]): List[(EntityId, Vec2.Vec2, UiWidget.PolyComp)] =
        ui#polys
            |> Map.toList
            |> List.filter(entry -> {let (id, _poly) = entry; Option.getWithDefault(true, Map.get(id, vis))})
            |> List.filterMap(entry -> {
                let (id, poly) = entry;
                Map.get(id, rects) |> Option.map(rect -> (id, rect#position, offsetPoly(poly, rect#position)))
            })
            |> List.sortBy(entry -> {let (id, _pos, poly) = entry; (poly#zIndex, depthOf(id, ui#parents), orderOf(id, ui), id)})

    /// PolyComp の全サブポリの各頂点にレイアウト矩形左上 origin を足し、ローカル座標を design 空間の
    /// 絶対座標へ移す。
    def offsetPoly(poly: UiWidget.PolyComp, origin: Vec2.Vec2): UiWidget.PolyComp =
        {polys = poly#polys |> List.map(sub ->
            sub |> List.map(p -> ({x = p#x + origin#x, y = p#y + origin#y}: Vec2.Vec2))) | poly}

    /// box の RenderItem。BoxComp の枠・角丸を BoxStyle へ写す（stripe 系は UI では未使用）。
    /// borderWidth>0 のときだけ borderAlpha=1.0 にして枠を有効化する。
    def boxItem(box: UiWidget.BoxComp, size: Vec2.Vec2): Render.RenderItem =
        let style = ({
            cornerRadius = box#cornerRadius,
            borderWidth  = box#borderWidth,
            borderColor  = box#borderColor,
            borderAlpha  = if (box#borderWidth > 0.0) 1.0f32 else 0.0f32,
            stripeColor  = box#borderColor,
            stripeAlpha  = 0.0f32,
            stripeWidth  = 0.0,
            stripePeriod = 0.0
        }: GameEngine.BoxStyle);
        Render.RenderItem.Box({size = size, color = box#color, alpha = box#alpha, style = Some(style), zIndex = box#zIndex})

    /// text の RenderItem。atlasOf で font 名から FontAtlas を引く。
    def textItem(comp: UiWidget.TextComp, atlasOf: String -> FontAtlas \ ef): Render.RenderItem \ ef =
        Render.textTinted(comp#text, atlasOf(comp#font), comp#fontSize, comp#tint, comp#zIndex)

    /// sprite の RenderItem。左上原点（centered=false）でレイアウト矩形の位置に合わせる。
    /// regionRect を持たず格子分割（hframes*vframes>1）があるときは frame からセル矩形を導く。
    def spriteItem(sprite: UiWidget.SpriteComp): Render.RenderItem \ GameEngine.Game =
        let regionOpt = resolveRegion(sprite);
        Render.RenderItem.Sprite({texture = sprite#texture, tint = sprite#tint, alpha = 1.0f32,
                                  scale = regionAdjustedScale(sprite, regionOpt), rotation = 0.0, centered = false,
                                  flipH = sprite#flipH, flipV = sprite#flipV,
                                  regionRect = regionOpt, zIndex = sprite#zIndex})

    /// region 使用時の描画 scale 補正。レンダラは quad を「テクスチャ全体サイズ × scale」で張るため、
    /// region（セル）描画では scale に regionSize/texSize を掛けて quad をセルサイズ × scale にする
    /// （engine `spriteToDrawable` の drawScale と同じ補正。`Render.drawAtlas` は UV のみ計算し
    /// scale を素通しするので、ここで織り込まないとアトラス全体サイズで巨大描画される）。
    /// region なし・テクスチャ未登録のときは無補正。
    def regionAdjustedScale(sprite: UiWidget.SpriteComp, regionOpt: Option[Rect2.Rect2]): Vec2.Vec2 \ GameEngine.Game =
        match regionOpt {
            case None       => sprite#scale
            case Some(rect) => match GameEngine.Game.getTextureInfo(sprite#texture) {
                case None       => sprite#scale
                case Some(info) =>
                    {x = sprite#scale#x * rect#size#x / info#width,
                     y = sprite#scale#y * rect#size#y / info#height}
            }
        }

    /// 表示セルの切り出し矩形を求める。regionRect が明示されていればそれを使う。
    /// 無く格子分割がある場合はテクスチャ寸法を引き、frame をセルへ写す（engine Sprite2D.computeUv と
    /// 同じ規則: cellW=texW/hframes, cellH=texH/vframes, col=frame mod hframes, row=frame/hframes）。
    /// テクスチャ未登録・分割なしのときはテクスチャ全体（None）。
    def resolveRegion(sprite: UiWidget.SpriteComp): Option[Rect2.Rect2] \ GameEngine.Game =
        if (sprite#hframes * sprite#vframes > 1 and Option.isEmpty(sprite#regionRect))
            match GameEngine.Game.getTextureInfo(sprite#texture) {
                case None       => None
                case Some(info) => Some(frameRect(info#width, info#height, sprite#hframes, sprite#vframes, sprite#frame))
            }
        else sprite#regionRect

    /// テクスチャ全体を hframes×vframes に等分し、frame 番目のセル矩形（左上原点・px）を返す。
    def frameRect(texWidth: Float64, texHeight: Float64, hframes: Int32, vframes: Int32, frame: Int32): Rect2.Rect2 =
        let cellWidth  = texWidth  / Int32.toFloat64(hframes);
        let cellHeight = texHeight / Int32.toFloat64(vframes);
        let col = Int32.modulo(frame, hframes);
        let row = frame / hframes;
        {position = {x = Int32.toFloat64(col) * cellWidth, y = Int32.toFloat64(row) * cellHeight},
         size = {x = cellWidth, y = cellHeight}}

    /// entity の階層深さ（root=0）。parents をたどった段数。
    def depthOf(id: EntityId, parents: Map[EntityId, EntityId]): Int32 =
        match Map.get(id, parents) {
            case None    => 0
            case Some(p) => 1 + depthOf(p, parents)
        }

    /// entity の兄弟内並び順（未登録は 0）。
    def orderOf(id: EntityId, ui: UiStore.UiWorld): Int32 =
        Option.getWithDefault(0, Map.get(id, ui#order))
}
