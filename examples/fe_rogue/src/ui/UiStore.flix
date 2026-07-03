// UiStore — UI コンポーネント store の束と基本操作
//
// Bevy 方式の UI: entity(EntityId) + 細粒度 component(Map[EntityId, _])。太いノードは作らない。
// spec 由来 store（parents/order/styles/…）は despawnRoot で消え、再 spawn で作り直される。
// 動的 store（selection/focus）は安定名パス（String）をキーにするため、despawn+再 spawn で
// id が変わってもリロードを生き延びる。

mod UiStore {

    /// UI 全体の状態。
    /// `nextId`: 次に採番する entity id（unit 側の id 空間とは独立）。
    /// `parents`: 子→親（root は非在）。`order`: 兄弟内の並び順。
    /// `styles`: レイアウト属性。`boxes`/`texts`/`sprites`/`polys`: 描画コンポーネント。
    /// `visible`: ユーザー設定の可視（継承前）。`bindings`: text 流し込み先の bind key。
    /// `metas`: メニュー項目等の識別 metadata。`names`: 完全名パス→entity。
    /// `selection`: リスト選択カーソル（key=リスト所有 entity の名前パス）。
    /// `focus`: 入力フォーカス scope（モーダル占有。key=名前パス）。
    /// `layers`: root の描画レイヤ（CanvasLayer.layerStride 倍して zIndex に加算する）。
    /// `sources`: root 名パス→ui.json アセットパス。リロード（reloadAll）が各 root を
    /// どのファイルから読み直すかの台帳。despawnRoot では消さず、respawn 後も引き継ぐ。
    pub type alias UiWorld = {
        nextId    = Int32,
        parents   = Map[EntityId, EntityId],
        order     = Map[EntityId, Int32],
        styles    = Map[EntityId, UiLayout.Style],
        boxes     = Map[EntityId, UiWidget.BoxComp],
        texts     = Map[EntityId, UiWidget.TextComp],
        sprites   = Map[EntityId, UiWidget.SpriteComp],
        polys     = Map[EntityId, UiWidget.PolyComp],
        visible   = Map[EntityId, Bool],
        bindings  = Map[EntityId, String],
        metas     = Map[EntityId, String],
        names     = Map[String, EntityId],
        selection = Map[String, Int32],
        focus     = Option[String],
        layers    = Map[EntityId, Int32],
        sources   = Map[String, String]
    }

    /// 空の UI 状態。id 採番は 1 から始める。
    pub def empty(): UiWorld =
        {nextId = 1,
         parents = Map.empty(), order = Map.empty(), styles = Map.empty(),
         boxes = Map.empty(), texts = Map.empty(), sprites = Map.empty(), polys = Map.empty(),
         visible = Map.empty(), bindings = Map.empty(), metas = Map.empty(),
         names = Map.empty(),
         selection = Map.empty(), focus = None,
         layers = Map.empty(), sources = Map.empty()}

    /// 次の entity id を採番して返す（nextId を進めた新 UiWorld と組で返す）。
    /// 各 store への登録・名前パス登録は呼び側（UiSpec.spawn）が行う低レベル口。
    pub def alloc(ui: UiWorld): (EntityId, UiWorld) =
        (ui#nextId, {nextId = ui#nextId + 1 | ui})

    // ========================================================================
    // 名前パス ⇔ entity
    // ========================================================================

    /// 完全名パスから entity を引く。
    pub def idOf(path: String, ui: UiWorld): Option[EntityId] =
        Map.get(path, ui#names)

    /// entity から完全名パスを逆引きする（names を走査）。
    pub def pathOf(id: EntityId, ui: UiWorld): Option[String] =
        ui#names |> Map.foldLeftWithKey((acc, path, entity) -> if (entity == id) Some(path) else acc, None)

    // ========================================================================
    // ゲームコードからの書き込み口（名前パス指定）
    // ========================================================================

    /// 名前パスの entity の可視を設定する。未登録パスは no-op。
    pub def setVisible(path: String, v: Bool, ui: UiWorld): UiWorld =
        match idOf(path, ui) {
            case None     => ui
            case Some(id) => {visible = Map.insert(id, v, ui#visible) | ui}
        }

    /// 名前パスの entity の識別 metadata（メニュー項目の識別子）を設定する。未登録パスは no-op。
    /// 項目列が文脈で変わるメニュー（ActionMenu 等）で、スロットの meta を毎フレーム差し替える。
    pub def setMeta(path: String, meta: String, ui: UiWorld): UiWorld =
        match idOf(path, ui) {
            case None     => ui
            case Some(id) => {metas = Map.insert(id, meta, ui#metas) | ui}
        }

    /// 名前パスの entity の metadata を消す（未使用スロットを項目列から外す）。未登録パスは no-op。
    /// meta を持つ子だけを項目列とみなす規約（UiMenu.itemIds）と組で使い、meta を消したスロットは
    /// 選択カーソルの対象から外れる。
    pub def clearMeta(path: String, ui: UiWorld): UiWorld =
        match idOf(path, ui) {
            case None     => ui
            case Some(id) => {metas = Map.remove(id, ui#metas) | ui}
        }

    /// 名前パスの text コンポーネントの文字列を差し替える。text を持たなければ no-op。
    pub def setText(path: String, text: String, ui: UiWorld): UiWorld =
        let updated = idOf(path, ui)
            |> Option.flatMap(id -> Map.get(id, ui#texts) |> Option.map(comp -> (id, {text = text | comp})));
        match updated {
            case None          => ui
            case Some((id, comp)) => {texts = Map.insert(id, comp, ui#texts) | ui}
        }

    /// 名前パスの text コンポーネントの tint（文字色）を差し替える。text を持たなければ no-op。
    pub def setTextTint(path: String, tint: Color, ui: UiWorld): UiWorld =
        let updated = idOf(path, ui)
            |> Option.flatMap(id -> Map.get(id, ui#texts) |> Option.map(comp -> (id, {tint = tint | comp})));
        match updated {
            case None             => ui
            case Some((id, comp)) => {texts = Map.insert(id, comp, ui#texts) | ui}
        }

    /// 名前パスの entity の style 幅を固定 px（`SizeSpec.Px`）へ差し替える。style を持たなければ no-op。
    /// ワイプ演出のように幅を毎フレーム動かす widget（bandSweep / underlineSweep）で使う。
    pub def setWidthPx(path: String, px: Float64, ui: UiWorld): UiWorld =
        let updated = idOf(path, ui)
            |> Option.flatMap(id -> Map.get(id, ui#styles) |> Option.map(style -> (id, {width = UiLayout.SizeSpec.Px(px) | style})));
        match updated {
            case None             => ui
            case Some((id, style)) => {styles = Map.insert(id, style, ui#styles) | ui}
        }

    /// 名前パスの entity の style 幅が固定 px（`SizeSpec.Px`）ならその値を返す。
    /// Auto / Grow / 未登録は None。内容フィットで設定した幅を読み戻す（隣接窓の右端追従）ために使う。
    pub def widthPxOf(path: String, ui: UiWorld): Option[Float64] =
        idOf(path, ui)
            |> Option.flatMap(id -> Map.get(id, ui#styles))
            |> Option.flatMap(style -> match style#width {
                case UiLayout.SizeSpec.Px(v) => Some(v)
                case _                       => None
            })

    /// 名前パスの box コンポーネントの色を差し替える。box を持たなければ no-op。
    pub def setBoxColor(path: String, c: Color, ui: UiWorld): UiWorld =
        let updated = idOf(path, ui)
            |> Option.flatMap(id -> Map.get(id, ui#boxes) |> Option.map(comp -> (id, {color = c | comp})));
        match updated {
            case None             => ui
            case Some((id, comp)) => {boxes = Map.insert(id, comp, ui#boxes) | ui}
        }

    /// 名前パスの box コンポーネントの不透明度（fill alpha）を差し替える。box を持たなければ no-op。
    /// 中央ポップアップの窓のようにフェードで alpha を毎フレーム動かす widget で使う。
    pub def setBoxAlpha(path: String, alpha: Float32, ui: UiWorld): UiWorld =
        let updated = idOf(path, ui)
            |> Option.flatMap(id -> Map.get(id, ui#boxes) |> Option.map(comp -> (id, {alpha = alpha | comp})));
        match updated {
            case None             => ui
            case Some((id, comp)) => {boxes = Map.insert(id, comp, ui#boxes) | ui}
        }

    /// 名前パスの box コンポーネントの枠線色を差し替える。box を持たなければ no-op。
    /// ユニットカードの枠を味方=青 / 敵=赤 に毎フレーム塗り分けるために使う（塗り色は setBoxColor）。
    pub def setBoxBorderColor(path: String, c: Color, ui: UiWorld): UiWorld =
        let updated = idOf(path, ui)
            |> Option.flatMap(id -> Map.get(id, ui#boxes) |> Option.map(comp -> (id, {borderColor = c | comp})));
        match updated {
            case None             => ui
            case Some((id, comp)) => {boxes = Map.insert(id, comp, ui#boxes) | ui}
        }

    /// 名前パスの entity のフロー外オフセット（style#abs）を差し替える。style を持たなければ no-op。
    /// カード内の要素を実測幅で右寄せ / 隣接配置する（Lv・EXP バー・HP 数値・アイコン）ときや、
    /// 敵カード panel をデザイン解像度の右端へ寄せるときに使う。
    pub def setAbs(path: String, pos: Vec2.Vec2, ui: UiWorld): UiWorld =
        let updated = idOf(path, ui)
            |> Option.flatMap(id -> Map.get(id, ui#styles) |> Option.map(style -> (id, {abs = Some(pos) | style})));
        match updated {
            case None              => ui
            case Some((id, style)) => {styles = Map.insert(id, style, ui#styles) | ui}
        }

    /// 名前パスの poly コンポーネントの凸サブポリゴン列を差し替える。poly を持たなければ no-op。
    /// 各サブポリの頂点はノードのレイアウト矩形左上を原点とするローカル design px（extract が矩形
    /// 左上を足す）。1 サブポリ = 1 PolygonRenderCmd（凸前提）なので、中空リング等の凹形状は
    /// 凸クアッド列として渡す。進捗リング（弧が満ちる充填ゲージ）のように毎フレーム点列が変わる
    /// widget で使う。
    pub def setPolyPolys(path: String, polys: List[List[Vec2.Vec2]], ui: UiWorld): UiWorld =
        let updated = idOf(path, ui)
            |> Option.flatMap(id -> Map.get(id, ui#polys) |> Option.map(comp -> (id, {polys = polys | comp})));
        match updated {
            case None             => ui
            case Some((id, comp)) => {polys = Map.insert(id, comp, ui#polys) | ui}
        }

    /// `setSprite` の引数束。
    /// `path`: 差し替え対象 entity の名前パス。
    /// `texture`: 差し替え後のテクスチャ。
    /// `hframes`/`vframes`: スプライトシートの格子分割数。
    /// `frame`: 格子内のセル番号（0 起点）。
    pub type alias SpriteSpec = {
        path    = String,
        texture = String,
        hframes = Int32,
        vframes = Int32,
        frame   = Int32
    }

    /// 名前パスの sprite コンポーネントの texture と格子分割（hframes/vframes/frame）を差し替える。
    /// regionRect / scale / flip / tint / zIndex は保持する。sprite を持たなければ no-op。
    /// スプライトシートの表示セルを実行時に切り替える（アニメ・状態差分）ために使う。
    pub def setSprite(spec: SpriteSpec, ui: UiWorld): UiWorld =
        let updated = idOf(spec#path, ui)
            |> Option.flatMap(id -> Map.get(id, ui#sprites)
                |> Option.map(comp -> (id, {texture = spec#texture, hframes = spec#hframes,
                                            vframes = spec#vframes, frame = spec#frame | comp})));
        match updated {
            case None             => ui
            case Some((id, comp)) => {sprites = Map.insert(id, comp, ui#sprites) | ui}
        }

    // ========================================================================
    // リロード台帳（sources）と可視の名前パス採取
    // ========================================================================

    /// root 名パスに ui.json アセットパスを紐付ける（reloadAll の走査対象になる）。
    pub def putSource(rootPath: String, assetPath: String, ui: UiWorld): UiWorld =
        {sources = Map.insert(rootPath, assetPath, ui#sources) | ui}

    /// root 名パスを台帳から外す（恒久削除時に呼ぶ。以後 reloadAll の対象外）。
    pub def forgetSource(rootPath: String, ui: UiWorld): UiWorld =
        {sources = Map.remove(rootPath, ui#sources) | ui}

    /// root 配下の各ノードの「名前パス→設定可視（継承前の生値）」を集める。
    /// respawn が spec 既定へ戻る前の可視状態を採取し、再 spawn 後へ引き継ぐために使う。
    pub def visibleByPath(rootPath: String, ui: UiWorld): Map[String, Bool] =
        ui#names |> Map.foldLeftWithKey((acc, path, id) ->
            if (underRoot(rootPath, path))
                match Map.get(id, ui#visible) {
                    case None    => acc
                    case Some(v) => Map.insert(path, v, acc)
                }
            else acc, Map.empty())

    /// path が rootPath 自身か、その配下（"rootPath/..."）か。
    def underRoot(rootPath: String, path: String): Bool =
        path == rootPath or String.startsWith(prefix = "${rootPath}/", path)

    /// 「名前パス→可視」を現存ノードへ適用する。存在しないパス（削除済み）は no-op。
    pub def applyVisibleByPath(byPath: Map[String, Bool], ui: UiWorld): UiWorld =
        byPath |> Map.foldLeftWithKey((acc, path, v) -> setVisible(path, v, acc), ui)

    // ========================================================================
    // 部分木削除
    // ========================================================================

    /// rootPath 配下の全 entity を spec 由来 store から除去する。
    /// selection / focus は String key なので保持（リロード生存）。未登録パスは no-op。
    pub def despawnRoot(rootPath: String, ui: UiWorld): UiWorld =
        match idOf(rootPath, ui) {
            case None         => ui
            case Some(rootId) =>
                let dead = UiHierarchy.descendants(rootId, ui#parents);
                {nextId    = ui#nextId,
                 parents   = removeKeys(dead, ui#parents),
                 order     = removeKeys(dead, ui#order),
                 styles    = removeKeys(dead, ui#styles),
                 boxes     = removeKeys(dead, ui#boxes),
                 texts     = removeKeys(dead, ui#texts),
                 sprites   = removeKeys(dead, ui#sprites),
                 polys     = removeKeys(dead, ui#polys),
                 visible   = removeKeys(dead, ui#visible),
                 bindings  = removeKeys(dead, ui#bindings),
                 metas     = removeKeys(dead, ui#metas),
                 names     = ui#names |> Map.filter(entity -> not Set.memberOf(entity, dead)),
                 selection = ui#selection,
                 focus     = ui#focus,
                 layers    = removeKeys(dead, ui#layers),
                 sources   = ui#sources}
        }

    /// 集合 dead に含まれるキーを map から取り除く。
    def removeKeys(dead: Set[EntityId], m: Map[EntityId, v]): Map[EntityId, v] =
        m |> Map.filterWithKey((k, _v) -> not Set.memberOf(k, dead))

    // ========================================================================
    // 動的 store（selection / focus）
    // ========================================================================

    /// 名前パスのリスト選択カーソル値。未登録は 0。
    pub def selectionOf(path: String, ui: UiWorld): Int32 =
        Option.getWithDefault(0, Map.get(path, ui#selection))

    /// 名前パスのリスト選択カーソル値を設定する。
    pub def putSelection(path: String, i: Int32, ui: UiWorld): UiWorld =
        {selection = Map.insert(path, i, ui#selection) | ui}

    /// フォーカス scope を名前パスに設定する（モーダル占有）。
    pub def focusOn(path: String, ui: UiWorld): UiWorld =
        {focus = Some(path) | ui}

    /// フォーカス scope を解除する。
    pub def clearFocus(ui: UiWorld): UiWorld =
        {focus = None | ui}
}
