// LiarsLint — UiWorld → RenderLint.Input の薄いブリッジ（liars_room 版）。
//
// RenderLint（engine_tools）はゲーム非依存の純リンタで、ここが唯一の橋渡し:
// UI ページの entity 群を「実際に描かれる外接矩形 + 祖先パス」の構造レコードへ
// 射影する。幾何は描画経路（UiLayout / UiRender）と同じ算式で求めるので、リンタ
// が見る箱は画面に出る箱と一致する。
//
// liars_room のページ（Title・HUD・会話・メモ・結果）はボックスとテキストしか持たないので、
// fe_rogue 版と違って sprite / poly の射影も Game 効果も要らない —— atlas を
// 値で受け取るだけの純粋な関数になる。
mod LiarsLint {

    /// 各射影が引き回す文脈: root 越しに解決済みの rect・可視と、祖先パス解決に
    /// 要る parents・名前表を1レコードに束ねる。
    type alias Ctx = {
        rects   = Map[EntityId, Rect2.Rect2],
        vis     = Map[EntityId, Bool],
        parents = Map[EntityId, EntityId],
        idPath  = Map[EntityId, String]
    }

    /// 検査1回分の設定。sceneName は報告の見出し、allow は抑制する rule 名、
    /// screen は design 画面の寸法、atlas はテキスト実寸の計測に使うフォント。
    pub type alias Req = {
        sceneName = String,
        allow     = List[String],
        screen    = Vec2.Vec2,
        atlas     = FontAtlas
    }

    /// UiWorld 1枚を RenderLint の検査入力へ射影する。描画には一切影響しない
    /// 読み取り専用の変換。
    pub def buildInput(req: Req, ui: UiStore.UiWorld): RenderLint.Input =
        let measures = UiExtract.measureTexts(ui#texts, _ -> req#atlas);
        let rootRect: Rect2.Rect2 =
            { position = { x = 0.0, y = 0.0 }, size = req#screen };
        let roots = rootsOf(ui);
        let rects = List.foldLeft((acc, r) ->
            mergeInto(acc, UiLayout.computeLayout(
                { styles = ui#styles, parents = ui#parents, order = ui#order,
                  measures = measures, visible = ui#visible }, r, rootRect)),
            (Map.empty(): Map[EntityId, Rect2.Rect2]), roots);
        let vis = List.foldLeft((acc, r) ->
            mergeInto(acc, UiHierarchy.resolveInherited(ui#visible, ui#parents, r, ui#order)),
            (Map.empty(): Map[EntityId, Bool]), roots);
        let ctx = { rects = rects, vis = vis, parents = ui#parents,
                    idPath = invertNames(ui#names) };
        { sceneName = req#sceneName, screenW = req#screen#x, screenH = req#screen#y,
          elements = List.append(boxElements(ui, ctx), textElements(ui, ctx, measures)),
          allow = req#allow }

    // ── Finding をテスト・バッジで扱いやすい形へ ──

    /// Finding 列を SnapshotSite のバッジ（有効/抑制の件数 + 詳細）へ畳む。
    pub def badgeOf(findings: List[RenderLint.Finding]): SnapshotSite.LintBadge =
        let active = List.filter(f -> not f#suppressed, findings);
        let suppressed = List.filter(f -> f#suppressed, findings);
        { checked = true,
          findingCount = List.length(active),
          suppressedCount = List.length(suppressed),
          details = List.append(List.map(f -> "${f#rule}: ${f#detail}", active),
                                List.map(f -> "[抑制] ${f#rule}: ${f#detail}", suppressed)) }

    /// 非抑制 Finding の説明行。テストはこれが空リストであることを固定する ——
    /// 違反が出たときは assert の差分にそのまま違反内容が並ぶ。
    pub def activeDetails(findings: List[RenderLint.Finding]): List[String] =
        findings
            |> List.filter(f -> not f#suppressed)
            |> List.map(f -> "[${f#sceneName}] ${f#rule} ${f#severity}: ${f#detail}")

    // ── 要素射影（sokoban のページにあるのは box と text だけ）──

    /// パネル（box）: レイアウト rect がそのまま描かれる箱になる。
    def boxElements(ui: UiStore.UiWorld, ctx: Ctx): List[RenderLint.Element] =
        ui#boxes |> Map.foldLeftWithKey((acc, id, comp) ->
            match liveRect(id, ctx) {
                case None       => acc
                case Some(rect) =>
                    element(id, RenderLint.Kind.Box, comp#zIndex, rectToBbox(rect), ctx) :: acc
            }, Nil)

    /// テキスト: rect 左上 + measure（実寸）。レイアウトの stretch で rect が
    /// 伸びても描かれる文字は measure ぶんなので、実描画に忠実な bbox になる。
    /// 空文字列は何も描かないので検査から外す。
    def textElements(ui: UiStore.UiWorld, ctx: Ctx,
                     measures: Map[EntityId, Vec2.Vec2]): List[RenderLint.Element] =
        ui#texts |> Map.foldLeftWithKey((acc, id, comp) ->
            if (String.isEmpty(String.trim(comp#text))) acc
            else match liveRect(id, ctx) {
                case None       => acc
                case Some(rect) =>
                    let size = Option.getWithDefault(rect#size, Map.get(id, measures));
                    let bbox = { minX = rect#position#x, minY = rect#position#y,
                                 maxX = rect#position#x + size#x, maxY = rect#position#y + size#y };
                    element(id, RenderLint.Kind.Text, comp#zIndex, bbox, ctx) :: acc
            }, Nil)

    // ── 幾何 ──

    /// 可視かつ rect が確定した entity の rect（不可視・未配置は None）。
    def liveRect(id: EntityId, ctx: Ctx): Option[Rect2.Rect2] =
        if (Option.getWithDefault(false, Map.get(id, ctx#vis))) Map.get(id, ctx#rects) else None

    def rectToBbox(rect: Rect2.Rect2): RenderLint.Rect =
        { minX = rect#position#x, minY = rect#position#y,
          maxX = rect#position#x + rect#size#x, maxY = rect#position#y + rect#size#y }

    // ── 祖先パス・名前 ──

    /// entity から RenderLint.Element を組む（path と祖先パスを名前表から引く）。
    def element(id: EntityId, kind: RenderLint.Kind, z: Int32, bbox: RenderLint.Rect,
                ctx: Ctx): RenderLint.Element =
        { path = pathOf(id, ctx#idPath), kind = kind, z = z, bbox = bbox,
          ancestors = ancestorsOf(id, ctx#parents, ctx#idPath) }

    /// id の名前パス（未登録なら id リテラルで代用）。
    def pathOf(id: EntityId, idPath: Map[EntityId, String]): String =
        Option.getWithDefault("id:${id}", Map.get(id, idPath))

    /// parents を辿った祖先の名前パス列（直近の親から root へ）。
    def ancestorsOf(id: EntityId, parents: Map[EntityId, EntityId],
                    idPath: Map[EntityId, String]): List[String] =
        match Map.get(id, parents) {
            case None    => Nil
            case Some(p) => pathOf(p, idPath) :: ancestorsOf(p, parents, idPath)
        }

    /// names（パス→id）を id→パスへ反転する。各 entity は1パスなので単射。
    def invertNames(names: Map[String, EntityId]): Map[EntityId, String] =
        names |> Map.foldLeftWithKey((acc, path, id) -> Map.insert(id, path, acc), Map.empty())

    /// 親を持たない entity（各ページの root）を列挙する。
    def rootsOf(ui: UiStore.UiWorld): List[EntityId] =
        Map.valuesOf(ui#names) |> List.filter(id -> Option.isEmpty(Map.get(id, ui#parents)))

    /// 2つの Map を合流する（root ごとの rect / 可視を1枚に。キーは root 間で素）。
    def mergeInto(acc: Map[k, v], m: Map[k, v]): Map[k, v] with Order[k] =
        Map.foldLeftWithKey((a, key, value) -> Map.insert(key, value, a), acc, m)
}
