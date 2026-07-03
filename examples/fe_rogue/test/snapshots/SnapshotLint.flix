// SnapshotLint — UiWorld → RenderLint.Input のブリッジ（fe_rogue 依存）。
//
// RenderLint はゲーム非依存の純リンタ。ここが唯一の橋渡しで、UI entity 群を「実際に描かれる
// 外接矩形＋祖先パス」の構造レコードへ射影する。幾何は描画経路（UiLayout / UiExtract）と同じ算式で
// 求める:
//   - box    : レイアウト rect そのもの。
//   - text   : rect 左上 + measure（実寸）。レイアウトの stretch で rect が伸びても、描かれる文字は
//              measure ぶんなので実描画に忠実な bbox になる。
//   - sprite : rect 左上 + 描画サイズ（= region/texture サイズ × scale。UiExtract の region 補正と
//              同じ帰結）。レイアウトが確保する箱ではなく実際に描かれる大きさを使う（巨大化検出のため）。
//   - poly   : rect 左上 + ローカル頂点の外接（extractPolys と同じオフセット）。
//
// 可視性・rect は renderRoot と同じく root 単位に computeLayout / resolveInherited して合流する。
mod SnapshotLint {

    /// 各射影関数が引き回す文脈（rect/vis/親子/名前）。root 越しに解決した rect・vis と、
    /// 祖先パス解決に要る parents・idPath を 1 レコードに束ねる。
    type alias Ctx = {
        rects   = Map[EntityId, Rect2.Rect2],
        vis     = Map[EntityId, Bool],
        parents = Map[EntityId, EntityId],
        idPath  = Map[EntityId, String]
    }

    /// UiWorld を 1 シーンぶんの RenderLint 入力へ射影する。`allow` は抑制 rule 名（カタログタグ由来）。
    pub def buildInput(sceneName: String, allow: List[String], screenW: Float64, screenH: Float64,
                       ui: UiStore.UiWorld): RenderLint.Input \ GameEngine.Game =
        let atlasOf = name -> GameEngine.Game.getFontAtlas(name);
        let measures = UiExtract.measureTexts(ui#texts, atlasOf);
        let rootRect: Rect2.Rect2 =
            {position = {x = 0.0, y = 0.0}, size = {x = screenW, y = screenH}};
        let roots = rootsOf(ui);
        let rects = List.foldLeft((acc, r) ->
            mergeInto(acc, UiLayout.computeLayout(
                {styles = ui#styles, parents = ui#parents, order = ui#order,
                 measures = measures, visible = ui#visible}, r, rootRect)),
            (Map.empty(): Map[EntityId, Rect2.Rect2]), roots);
        let vis = List.foldLeft((acc, r) ->
            mergeInto(acc, UiHierarchy.resolveInherited(ui#visible, ui#parents, r, ui#order)),
            (Map.empty(): Map[EntityId, Bool]), roots);
        let ctx = {rects = rects, vis = vis, parents = ui#parents, idPath = invertNames(ui#names)};
        let elements = List.append(boxElements(ui, ctx),
                       List.append(textElements(ui, ctx, measures),
                       List.append(spriteElements(ui, ctx),
                                   polyElements(ui, ctx))));
        {sceneName = sceneName, screenW = screenW, screenH = screenH,
         elements = elements, allow = allow}

    // ── 要素射影（種別ごと）──

    def boxElements(ui: UiStore.UiWorld, ctx: Ctx): List[RenderLint.Element] =
        ui#boxes |> Map.foldLeftWithKey((acc, id, comp) ->
            match liveRect(id, ctx) {
                case None       => acc
                case Some(rect) =>
                    element(id, RenderLint.Kind.Box, comp#zIndex, rectToBbox(rect), ctx) :: acc
            }, Nil)

    def textElements(ui: UiStore.UiWorld, ctx: Ctx, measures: Map[EntityId, Vec2.Vec2]): List[RenderLint.Element] =
        ui#texts |> Map.foldLeftWithKey((acc, id, comp) ->
            if (String.isEmpty(String.trim(comp#text))) acc
            else match liveRect(id, ctx) {
                case None       => acc
                case Some(rect) =>
                    let size = Option.getWithDefault(rect#size, Map.get(id, measures));
                    let bbox = {minX = rect#position#x, minY = rect#position#y,
                                maxX = rect#position#x + size#x, maxY = rect#position#y + size#y};
                    element(id, RenderLint.Kind.Text, comp#zIndex, bbox, ctx) :: acc
            }, Nil)

    def spriteElements(ui: UiStore.UiWorld, ctx: Ctx): List[RenderLint.Element] \ GameEngine.Game =
        Map.foldLeftWithKey((acc, id, comp) ->
            match liveRect(id, ctx) {
                case None       => acc
                case Some(rect) => match spriteDrawnSize(comp) {
                    case None       => acc // テクスチャ未登録: サイズ不明なので検査から外す
                    case Some(size) =>
                        let bbox = {minX = rect#position#x, minY = rect#position#y,
                                    maxX = rect#position#x + size#x, maxY = rect#position#y + size#y};
                        element(id, RenderLint.Kind.Sprite, comp#zIndex, bbox, ctx) :: acc
                }
            }, (Nil: List[RenderLint.Element]), ui#sprites)

    def polyElements(ui: UiStore.UiWorld, ctx: Ctx): List[RenderLint.Element] =
        ui#polys |> Map.foldLeftWithKey((acc, id, comp) ->
            match liveRect(id, ctx) {
                case None       => acc
                case Some(rect) => match polyBbox(comp#polys, rect#position) {
                    case None       => acc
                    case Some(bbox) =>
                        element(id, RenderLint.Kind.Poly, comp#zIndex, bbox, ctx) :: acc
                }
            }, Nil)

    // ── 幾何 ──

    /// 可視かつ rect が確定した entity の rect（不可視/未配置は None）。
    def liveRect(id: EntityId, ctx: Ctx): Option[Rect2.Rect2] =
        if (Option.getWithDefault(false, Map.get(id, ctx#vis))) Map.get(id, ctx#rects) else None

    def rectToBbox(rect: Rect2.Rect2): RenderLint.Rect =
        {minX = rect#position#x, minY = rect#position#y,
         maxX = rect#position#x + rect#size#x, maxY = rect#position#y + rect#size#y}

    /// sprite の実描画サイズ = 有効セルサイズ × scale（UiExtract の region 補正と同じ帰結）。
    /// regionRect 明示ならその寸法、格子分割ならテクスチャ寸法をセルに割る、無ければテクスチャ全体。
    /// テクスチャ未登録なら None。
    def spriteDrawnSize(comp: UiWidget.SpriteComp): Option[Vec2.Vec2] \ GameEngine.Game =
        match comp#regionRect {
            case Some(r) => Some({x = r#size#x * comp#scale#x, y = r#size#y * comp#scale#y})
            case None    => match GameEngine.Game.getTextureInfo(comp#texture) {
                case None       => None
                case Some(info) =>
                    let (cw, ch) =
                        if (comp#hframes * comp#vframes > 1)
                            (info#width / Int32.toFloat64(comp#hframes),
                             info#height / Int32.toFloat64(comp#vframes))
                        else (info#width, info#height);
                    Some({x = cw * comp#scale#x, y = ch * comp#scale#y})
            }
        }

    /// ローカル頂点列（矩形左上原点）を rect 左上でずらした外接矩形。頂点が無ければ None。
    def polyBbox(polys: List[List[Vec2.Vec2]], origin: Vec2.Vec2): Option[RenderLint.Rect] =
        let verts = List.flatten(polys);
        match verts {
            case Nil => None
            case _   =>
                let xs = List.map(v -> v#x + origin#x, verts);
                let ys = List.map(v -> v#y + origin#y, verts);
                Some({minX = List.foldLeft(Float64.min, 1.0e9, xs),
                      minY = List.foldLeft(Float64.min, 1.0e9, ys),
                      maxX = List.foldLeft(Float64.max, -1.0e9, xs),
                      maxY = List.foldLeft(Float64.max, -1.0e9, ys)})
        }

    // ── 祖先パス・名前 ──

    /// entity から RenderLint.Element を組む（path・祖先パスを名前表 / parents から引く）。
    def element(id: EntityId, kind: RenderLint.Kind, z: Int32, bbox: RenderLint.Rect,
                ctx: Ctx): RenderLint.Element =
        {path = pathOf(id, ctx#idPath), kind = kind, z = z, bbox = bbox,
         ancestors = ancestorsOf(id, ctx#parents, ctx#idPath)}

    /// id の名前パス（未登録は id リテラル）。
    def pathOf(id: EntityId, idPath: Map[EntityId, String]): String =
        Option.getWithDefault("id:${id}", Map.get(id, idPath))

    /// parents を辿った祖先の名前パス列（直近の親から root へ・nearest-first）。
    def ancestorsOf(id: EntityId, parents: Map[EntityId, EntityId], idPath: Map[EntityId, String]): List[String] =
        match Map.get(id, parents) {
            case None    => Nil
            case Some(p) => pathOf(p, idPath) :: ancestorsOf(p, parents, idPath)
        }

    /// names（path→id）を id→path に反転する。各 entity は 1 パスなので単射。
    def invertNames(names: Map[String, EntityId]): Map[EntityId, String] =
        names |> Map.foldLeftWithKey((acc, path, id) -> Map.insert(id, path, acc), Map.empty())

    /// 親を持たない entity（各 root）を列挙する（renderRoot の rootsOf と同じ）。
    def rootsOf(ui: UiStore.UiWorld): List[EntityId] =
        Map.valuesOf(ui#names) |> List.filter(id -> Option.isEmpty(Map.get(id, ui#parents)))

    /// 2 つの Map を左優先で合流する（root ごとの rect/vis を 1 枚に束ねる。キーは root 間で素）。
    def mergeInto(acc: Map[k, v], m: Map[k, v]): Map[k, v] with Order[k] =
        Map.foldLeftWithKey((a, key, value) -> Map.insert(key, value, a), acc, m)
}
