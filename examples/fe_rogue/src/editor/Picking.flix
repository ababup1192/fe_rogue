// Picking — マウス位置から hit する編集対象ノードを 1 件選ぶ（Godot Object Picking 準拠）
//
// 純粋関数として切り出してあるため `GameEngine.Game` 等のエフェクトモック不要で
// テストできる（候補のリストを呼び出し側が組み立てる前提）。
// Z-index の優先付けは `Scene.effectiveZIndexAt` に揃えるので、レンダラの
// 描画順とエディタの選択順が常に一致する。
// CanvasLayer 配下でないノードはカメラの ViewTransform で画面に描画されるので、
// ヒットテストは `Scene.screenPositionAt` で「実際に描画されている screen 位置」を
// 算出してから比較する（カメラ追従中のノードも正しく拾える）

mod Picking {

    /// 与えられた候補の中からマウス位置にヒットするものを 1 件返す。
    /// 通常モードでは **z-index 最大のノード (= 最前面の子要素)** を返す。
    /// 各 hotspot や個別 sprite を直接ドラッグできる「Godot 流儀」のデフォルト。
    /// `preferDescendant = true` (Shift+クリック) は **コンテナ (CanvasLayer)** に
    /// 切り替え、ダイアログパネル等を 1 単位で動かしたいケースに合わせる。
    /// (パラメータ名は歴史的経緯でこの意味のまま残してあるが、振る舞いは反転している)
    pub def pickTopAt(mousePos: Vec2.Vec2,
                      entries: List[EditableNode.EditableEntry],
                      transform: Camera2D.ViewTransform,
                      preferDescendant: Bool,
                      scene: Scene[NodeTag]):
            Option[(EditableNode.EditableEntry, Vec2.Vec2)] =
        let hits = entries
            |> List.filterMap(entry -> hitInfo(mousePos, entry, transform, scene));
        let chosen = if (preferDescendant)
            // 修飾キー押下時はコンテナ優先 (旧デフォルト)。
            match shallowestContainer(hits) {
                case Some(hit) => Some(hit)
                case None      => highestZ(hits)
            }
        else
            // 通常クリックは葉 (非コンテナ) を優先、なければコンテナにフォールバック。
            match highestZ(hits |> List.filter(h -> not h#entry#isContainer)) {
                case Some(hit) => Some(hit)
                case None      => shallowestContainer(hits)
            };
        Option.map(hit -> (hit#entry, hit#screenPos), chosen)

    /// 1 件分のヒット情報。z は `Scene.effectiveZIndexAt` の値
    type alias HitInfo = {
        z = Int32,
        entry = EditableNode.EditableEntry,
        screenPos = Vec2.Vec2
    }

    /// マウスが entry の bbox 内なら HitInfo を返す
    def hitInfo(mousePos: Vec2.Vec2, entry: EditableNode.EditableEntry,
                transform: Camera2D.ViewTransform, scene: Scene[NodeTag]): Option[HitInfo] =
        let screenPos = Scene.screenPositionAt(entry#nodePath, transform, scene);
        if (Rect2.hasPoint(mousePos, makeBBox(screenPos, entry)))
            Some({z = Scene.effectiveZIndexAt(entry#nodePath, scene),
                  entry = entry, screenPos = screenPos})
        else None

    /// hits の中から z 最大を返す。同値時は後発（preorder で後）を優先するため `>=` 比較
    def highestZ(hits: List[HitInfo]): Option[HitInfo] =
        List.foldLeft((best, cand) ->
            match best {
                case None    => Some(cand)
                case Some(b) => if (cand#z >= b#z) Some(cand) else best
            }, None, hits)

    /// hits の中で `isContainer = true` かつ NodePath が最も短い（root に近い）ものを返す。
    /// コンテナが居なければ None。複数の最浅コンテナがあれば最初に見つけたもの。
    def shallowestContainer(hits: List[HitInfo]): Option[HitInfo] =
        List.foldLeft((best, cand) ->
            if (not cand#entry#isContainer) best
            else match best {
                case None    => Some(cand)
                case Some(b) => if (List.length(cand#entry#nodePath) < List.length(b#entry#nodePath))
                                    Some(cand)
                                else best
            }, None, hits)

    /// グローバル位置と EditableEntry から表示矩形 Rect2 を作る
    pub def makeBBox(refPos: Vec2.Vec2,
                     entry: EditableNode.EditableEntry): Rect2.Rect2 =
        let topLeft = Vec2.add(refPos, entry#topLeftOffset);
        {position = topLeft, size = {x = entry#width, y = entry#height}}
}
