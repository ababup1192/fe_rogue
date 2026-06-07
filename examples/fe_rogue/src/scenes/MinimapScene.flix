/// MinimapScene — 探索済みマップ（ミニマップ）。M キーで全画面トグル。
///
/// `FogScene`（霧）は「現在いる部屋だけを毎フレーム明るくする・非永続」だが、ミニマップは
/// 逆に **一度でも訪れた部屋/通路(module)を覚え続ける**（探索が進むほど書き足される）。
/// 記憶は driver ノードの state（`Set[Int32]` の訪問 module idx）に蓄積する。フロアを進むと
/// `GameLifecycle.buildPlayingScene` でシーンごと作り直されるため、訪問記憶は自動でリセットされる。
///
/// 表示は `FogScene` と同じ「固定 ColorRect プールを毎フレーム再配置」方式。部屋/通路の矩形と、
/// プレイヤー・階段・アイテムのマーカーを、探索マップ全体が全画面ボックスに収まるよう一様
/// スケールして描く。M を押すたびに表示/非表示が切り替わる（押しっぱなしの連続発火を防ぐため
/// 前フレームのキー状態 `mPrev` でエッジ検出する。`CursorScene` の方向キー検出と同じ作法）。
///
/// 表示機構（CanvasLayer / 後で SubViewport）から描画ロジックを切り離すため、プール子ノードは
/// すべて `contentPath()` 配下に置き、配置関数は path 経由で更新する。SubViewport へ載せ替える
/// 際は `add`（ツリー構築）と `contentPath` だけを差し替えれば `renderMinimap` は無改修で済む。
///
/// ノード構造:
///   Minimap (CanvasLayer, scene.json)                ← 画面 layer。M で内容を出し入れ
///     └─ MinimapContent (Marker2D, NoTag)            ← プール親（描画コンテナ）
///          ├─ Bg (ColorRect)                          ← 背景の暗幕（全画面）
///          ├─ Room_0 .. Room_{N-1} (ColorRect)        ← 訪問済み部屋/通路の矩形プール
///          └─ Marker_0 .. Marker_{M-1} (ColorRect)    ← プレイヤー/階段/アイテムの点プール
///   World/MinimapDriver (Marker2D, MinimapDriver)     ← process redef で毎フレーム蓄積＋描画

mod MinimapScene {

    // ────────────────────────────────────────────────────────
    // (A) 型
    // ────────────────────────────────────────────────────────

    /// driver ノードが持つ永続 state。フロア跨ぎはシーン再構築でリセットされる。
    pub type alias DriverData = {
        visited    = Set[Int32],  // 訪問済み module idx（= 記憶。核心）
        stairsSeen = Bool,        // 一度発見した階段を覚え続ける
        visible    = Bool,        // M 全画面トグル状態
        mPrev      = Bool         // M の前フレーム押下状態（エッジ検出用）
    }

    /// fitTransform が返す「grid → minimap ピクセル」のアフィン変換パラメータ。
    pub type alias Fit = { scale = Float64, ox = Float64, oy = Float64 }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def rootName(): String = "Minimap"
    def contentName(): String = "MinimapContent"
    def contentPath(): NodePath = rootName() :: contentName() :: Nil
    def driverName(): String = "MinimapDriver"
    /// driver ノードの NodePath（`add` は World 直下に追加する）。
    def driverPath(): NodePath = List.append(MapScene.worldPath(), driverName() :: Nil)
    def fontName(): String = "ui"
    def sceneJsonPath(): String = "src/scenes/MinimapScene.scene.json"

    def roomChildName(i: Int32): String = "Room_${i}"
    def roomChildPath(i: Int32): NodePath = List.append(contentPath(), roomChildName(i) :: Nil)
    def markerChildName(i: Int32): String = "Marker_${i}"
    def markerChildPath(i: Int32): NodePath = List.append(contentPath(), markerChildName(i) :: Nil)

    /// 部屋/通路矩形プール。1 フロアの module 数（部屋数 + 通路数）に十分な固定数。
    /// union 分割は module 数より矩形が増えうるので余裕を持たせる。
    def roomPoolSize(): Int32 = 64
    /// マーカープール（プレイヤー≤3 + 階段1 + アイテム数）に十分な固定数。
    def markerPoolSize(): Int32 = 24

    /// 探索マップを収める「左下のボックス」（design 解像度 128×128 のピクセル座標、y は下向き）。
    /// シレン風に左下隅へ半透明で置く。背景枠は描かず、フロア/通路の矩形だけを描く（29×42 を 2 倍 ≈ 58×84）。
    def targetRect(): GridRect = ({x0 = 2, y0 = 38, x1 = 60, y1 = 122}: GridRect)

    /// マーカー（丸）の直径は「セル幅(scale)に比例」させ、隣接セルの円どうしが重ならないよう
    /// セル幅未満に保つ。同時に最大値 `markerMaxPx` で頭打ちにして大きくなりすぎないようにする。
    /// （アイテム・キャラ等は矩形でなく丸 = engine の Polygon2D で表す。）
    def markerCellFraction(): Float64 = 0.85
    def markerMaxPx(): Float64 = 3.9
    /// セル幅 `scale` からマーカー直径（px）を求める。
    def markerDiameter(scale: Float64): Float64 =
        let d = markerCellFraction() * scale;
        if (d < markerMaxPx()) d else markerMaxPx()

    /// zIndex（同一 CanvasLayer 内の描画順）。部屋/通路 < マーカー。
    def roomZIndex(): Int32 = 1
    def markerZIndex(): Int32 = 2

    // 色（半透明で操作の邪魔にならないよう alpha を抑える）
    /// 部屋・通路は同色（区別しない）。
    def moduleColor(): Color = {r = 0.62f32, g = 0.68f32, b = 0.85f32}
    def moduleAlpha(): Float32 = 0.50f32
    def leaderColor(): Color = {r = 0.95f32, g = 0.85f32, b = 0.20f32}
    def playerColor(): Color = {r = 0.30f32, g = 0.70f32, b = 0.95f32}
    def stairsColor(): Color = {r = 0.90f32, g = 0.30f32, b = 0.85f32}
    def itemColor(): Color = {r = 0.95f32, g = 0.60f32, b = 0.20f32}
    def markerAlpha(): Float32 = 0.85f32

    /// 起動時から右上に表示（非侵襲な常設 HUD）。M で出し入れする。
    def initialData(): DriverData =
        {visited = Set.empty(), stairsSeen = false, visible = true, mPrev = false}

    /// driver ノードに蓄積された訪問済み module idx を返す。未登録なら空集合（安全側）。
    /// カーソルの移動可能範囲（既訪エリア）の算出に CursorScene が使う。
    pub def visitedModules(scene: Scene[NodeTag]): Set[Int32] =
        match Scene.getState(driverPath(), scene) {
            case Some(NodeTag.MinimapDriver(d)) => d#visited
            case _                              => Set.empty()
        }

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// CanvasLayer（scene.json）+ 描画コンテナ + 背景 + 矩形/マーカープール（初期非表示）+
    /// 常駐 MinimapDriver を scene tree に追加する。`GameLifecycle.buildPlayingScene` の末尾
    /// （placements / 階段が確定した後）で 1 回だけ呼ぶ。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        let withRoot =
            SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas,
                SceneLoader.constTagParser(NodeTag.NoTag), scene);
        let withContent =
            Scene.addChild(rootName(), contentName(),
                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()), NodeTag.NoTag),
                withRoot);
        let withRooms =
            List.foldLeft((acc, i) ->
                Scene.addChildAt(contentPath(), roomChildName(i),
                    EngineNode.ColorRectWithState(
                        newPoolRect(moduleColor(), roomZIndex(), moduleAlpha()), NodeTag.NoTag),
                    acc),
                withContent, List.range(0, roomPoolSize()));
        let withMarkers =
            List.foldLeft((acc, i) ->
                Scene.addChildAt(contentPath(), markerChildName(i),
                    EngineNode.Polygon2DWithState(newMarkerCircle(), NodeTag.NoTag),
                    acc),
                withRooms, List.range(0, markerPoolSize()));
        Scene.addChild(MapScene.worldName(), driverName(),
            EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()),
                NodeTag.MinimapDriver(initialData())),
            withMarkers)

    def newPoolRect(color: Color, z: Int32, alpha: Float32): ColorRect =
        ColorRect.make(Vec2.zero(), color)
            |> ColorRect.setAlpha(alpha)
            |> CanvasItem.setZIndex(z)
            |> CanvasItem.setVisible(false)

    /// マーカー用の丸 Polygon2D（原点中心・直径 1.0 の単位円、初期非表示）。
    /// 実際の直径は setMarker で Node2D scale を掛けてセル幅に追従させる。色は modulate。
    def newMarkerCircle(): Polygon2D =
        Polygon2D.circle(0.5, playerColor())
            |> Polygon2D.setAlpha(markerAlpha())
            |> CanvasItem.setZIndex(markerZIndex())
            |> CanvasItem.setVisible(false)

    // ────────────────────────────────────────────────────────
    // (D) ロジック（毎フレーム）
    // ────────────────────────────────────────────────────────

    /// Game.flix の `process` redef から `NodeTag.MinimapDriver` に対して dispatch される
    /// per-frame entry。訪問 module を蓄積し、M トグルを反映し、ミニマップを再描画する。
    /// レベルアップ画面（`LevelUpView`）の間は M トグル状態を保ったまま強制的に隠す。
    pub def process(_delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     _path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag]) \ {GameEngine.Game, TurnPhase.State} =
        match node {
            case EngineNode.Marker2DWithState(m, NodeTag.MinimapDriver(data)) =>
                let mDown = GameEngine.Game.isKeyPressed(GameEngine.Key.M);
                let visible2 = if (mDown and not data#mPrev) not data#visible else data#visible;
                let placements = MapScene.getPlacements(scene);
                let frame = visitedThisFrame(PlayerScene.getAll(scene), placements);
                let visited2 = accumulate(data#visited, frame);
                let stairs2 = data#stairsSeen or stairsDiscovered(visited2, placements, scene);
                let nextData = {visited = visited2, stairsSeen = stairs2,
                                visible = visible2, mPrev = mDown};
                // レベルアップ画面の間は隠す（M トグルの記憶 visible2 は維持）。
                let levelUp = TurnPhase.State.get() == TurnPhase.Phase.LevelUpView;
                let show = visible2 and not levelUp;
                (EngineNode.Marker2DWithState(m, NodeTag.MinimapDriver(nextData)),
                 renderMinimap(show, nextData, scene))
            case _ => (node, scene)
        }

    /// 階段が「発見済み」か。階段セルの属する module が訪問済みなら発見扱い。
    def stairsDiscovered(visited: Set[Int32],
                          placements: List[DungeonComposer.ModulePlacement],
                          scene: Scene[NodeTag]): Bool =
        match StairsScene.getPos(scene) {
            case None       => false
            case Some(cell) =>
                match MapScene.moduleOfCellIn(cell, placements) {
                    case Some(idx) => Set.memberOf(idx, visited)
                    case None      => false
                }
        }

    /// ミニマップを描画する（純粋な Scene 変換）。`show=false` 時は全プールを隠す。
    /// フレームは「フロア全体の bbox」基準にして、探索しても配置が動かないようにする。
    /// 描画対象は「訪問済み module」＋「訪問済みに隣接する未訪問の通路（出口ヒント）」を
    /// union 分割して一体化（重なり部分を二重描画しない）。
    def renderMinimap(show: Bool, data: DriverData, scene: Scene[NodeTag]): Scene[NodeTag] =
        if (not show)
            hideAll(scene)
        else {
            let placements = MapScene.getPlacements(scene);
            let roomCount  = MapScene.getRoomCount(scene);
            let rawRects   = displayedModuleRects(data#visited, placements, roomCount);
            // スケールはフロア全体基準（探索しても拡大率が変わらない）。配置は探索済み
            // コンテンツの bbox を画面ボックスの左下に合わせる（左下の部屋を画面左下へ）。
            let t          = anchorBL(tightRegion(placements), boundsOf(rawRects), targetRect());
            let disjoint   = unionBands(rawRects);
            let markers    = collectMarkers(data, placements, roomCount, scene);
            scene
                |> drawRoomPool(disjoint, t)
                |> drawMarkerPool(markers, t)
        }

    /// 表示すべきマーカー（セル + 色）一覧。プレイヤー（非 hidden、リーダーは別色）+ 発見済み
    /// 階段 + 訪問済み部屋内のアイテム。
    def collectMarkers(data: DriverData,
                        placements: List[DungeonComposer.ModulePlacement],
                        roomCount: Int32, scene: Scene[NodeTag]):
                       List[{cell = {x = Int32, y = Int32}, color = Color}] =
        let players =
            PlayerScene.getAll(scene)
                |> List.filter(d -> not d#hidden)
                |> List.map(d -> {cell = d#gridPos,
                                  color = if (d#id == 0) leaderColor() else playerColor()});
        let stairsM =
            if (data#stairsSeen)
                match StairsScene.getPos(scene) {
                    case Some(cell) => {cell = cell, color = stairsColor()} :: Nil
                    case None       => Nil
                }
            else Nil;
        let itemsM =
            ItemScene.getAllPositions(scene)
                |> List.filter(cell -> inVisitedRoom(cell, placements, roomCount, data#visited))
                |> List.map(cell -> {cell = cell, color = itemColor()});
        List.append(players, List.append(stairsM, itemsM))

    def inVisitedRoom(cell: {x = Int32, y = Int32},
                       placements: List[DungeonComposer.ModulePlacement],
                       roomCount: Int32, visited: Set[Int32]): Bool =
        match MapScene.moduleOfCellIn(cell, placements) {
            case Some(idx) => idx < roomCount and Set.memberOf(idx, visited)
            case None      => false
        }

    // ─── プール再配置 ─────────────────────────────────────────

    /// 互いに重ならない矩形群（部屋・通路を一体化した union 分割）を部屋プールに割り当てる。
    /// 重なりが無いので半透明でも継ぎ目（重なり部分の濃い帯）が出ない。
    def drawRoomPool(rects: List[GridRect], t: Fit, scene: Scene[NodeTag]): Scene[NodeTag] =
        let used = List.length(rects);
        let withActive =
            List.foldLeft((acc, entry) -> {
                let (i, r) = entry;
                if (i < roomPoolSize()) setRoomRect(i, r, t, acc) else acc
            }, scene, List.zipWithIndex(rects));
        List.foldLeft((acc, i) ->
            if (i >= used) hideRoom(i, acc) else acc,
            withActive, List.range(0, roomPoolSize()))

    def setRoomRect(i: Int32, r: GridRect, t: Fit, scene: Scene[NodeTag]): Scene[NodeTag] =
        let pr = mapRect(r, t);
        Scene.mapEngineNode(roomChildPath(i),
            n -> EngineNode.mapColorRect(c ->
                c |> ColorRect.setSize(pr#size)
                  |> Node2D.setPosition(pr#pos)
                  |> CanvasItem.setModulate(moduleColor())
                  |> CanvasItem.setVisible(true), n),
            scene)

    def hideRoom(i: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(roomChildPath(i),
            n -> EngineNode.mapColorRect(c -> CanvasItem.setVisible(false, c), n), scene)

    /// マーカーをマーカープールに割り当てる（先頭 used 個を配置・表示、残りは非表示）。
    def drawMarkerPool(markers: List[{cell = {x = Int32, y = Int32}, color = Color}],
                        t: Fit, scene: Scene[NodeTag]): Scene[NodeTag] =
        let used = List.length(markers);
        let withActive =
            List.foldLeft((acc, entry) -> {
                let (i, mk) = entry;
                if (i < markerPoolSize()) setMarker(i, mk#cell, mk#color, t, acc) else acc
            }, scene, List.zipWithIndex(markers));
        List.foldLeft((acc, i) ->
            if (i >= used) hideMarker(i, acc) else acc,
            withActive, List.range(0, markerPoolSize()))

    def setMarker(i: Int32, cell: {x = Int32, y = Int32}, color: Color, t: Fit,
                   scene: Scene[NodeTag]): Scene[NodeTag] =
        let c    = mapCell(cell, t);
        let half = t#scale / 2.0;
        // 円は原点中心なので位置はセル中心。直径はセル幅に比例（隣接円が重ならない）。
        let pos: Vec2.Vec2 = {x = c#x + half, y = c#y + half};
        let d = markerDiameter(t#scale);
        Scene.mapEngineNode(markerChildPath(i),
            n -> EngineNode.mapPolygon2D(p ->
                p |> Node2D.setPosition(pos)
                  |> Node2D.setScale({x = d, y = d})
                  |> CanvasItem.setModulate(color)
                  |> CanvasItem.setVisible(true), n),
            scene)

    def hideMarker(i: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(markerChildPath(i),
            n -> EngineNode.mapPolygon2D(p -> CanvasItem.setVisible(false, p), n), scene)

    /// 非表示時: 全プールを隠す。
    def hideAll(scene: Scene[NodeTag]): Scene[NodeTag] =
        let withRooms =
            List.foldLeft((acc, i) -> hideRoom(i, acc), scene, List.range(0, roomPoolSize()));
        List.foldLeft((acc, i) -> hideMarker(i, acc), withRooms, List.range(0, markerPoolSize()))

    // ────────────────────────────────────────────────────────
    // (E) 純粋ジオメトリ（テスト対象）
    // ────────────────────────────────────────────────────────

    /// 今フレームに非 hidden ユニットが居る module idx の集合（module 外セルは無視）。
    /// 引数は開いた行多相なので `PlayerScene.Data`（gridPos/hidden を含む）をそのまま渡せる。
    pub def visitedThisFrame(units: List[{gridPos = {x = Int32, y = Int32}, hidden = Bool | r}],
                              placements: List[DungeonComposer.ModulePlacement]): Set[Int32] =
        units
            |> List.filter(d -> not d#hidden)
            |> List.filterMap(d -> MapScene.moduleOfCellIn(d#gridPos, placements))
            |> List.toSet

    /// 既存の訪問記憶に今フレーム分を足す（= 記憶。部屋を離れても残る）。
    pub def accumulate(prev: Set[Int32], frame: Set[Int32]): Set[Int32] =
        Set.union(prev, frame)

    /// margin なしの探索マップ bbox（`FogScene.mapRegion` の画面外マージン抜き版）。
    /// 各 module の `FogScene.moduleRect`（壁リング込み）の union。
    pub def tightRegion(placements: List[DungeonComposer.ModulePlacement]): GridRect =
        match List.map(FogScene.moduleRect, placements) {
            case Nil           => ({x0 = 0, y0 = 0, x1 = 0, y1 = 0}: GridRect)
            case first :: rest =>
                List.foldLeft((a, r) -> ({
                    x0 = Int32.min(a#x0, r#x0), y0 = Int32.min(a#y0, r#y0),
                    x1 = Int32.max(a#x1, r#x1), y1 = Int32.max(a#y1, r#y1)}: GridRect),
                    first, rest)
        }

    /// 探索マップ領域 `area` を全画面ボックス `target` に一様スケール + センタリングで収める
    /// アフィン変換パラメータを返す。退化（幅/高さ 0）時は scale=0。
    /// （`region` は Flix の予約語なので使わない。）
    pub def fitTransform(area: GridRect, target: GridRect): Fit =
        let rw = Int32.toFloat64(area#x1 - area#x0);
        let rh = Int32.toFloat64(area#y1 - area#y0);
        let tw = Int32.toFloat64(target#x1 - target#x0);
        let th = Int32.toFloat64(target#y1 - target#y0);
        let scale = if (rw <= 0.0 or rh <= 0.0) 0.0 else minF(tw / rw, th / rh);
        let ox = Int32.toFloat64(target#x0) + (tw - rw * scale) / 2.0 - Int32.toFloat64(area#x0) * scale;
        let oy = Int32.toFloat64(target#y0) + (th - rh * scale) / 2.0 - Int32.toFloat64(area#y0) * scale;
        {scale = scale, ox = ox, oy = oy}

    def minF(a: Float64, b: Float64): Float64 = if (a < b) a else b

    /// 矩形リストの union bbox（空なら原点ゼロ矩形）。
    pub def boundsOf(rects: List[GridRect]): GridRect =
        match rects {
            case Nil           => ({x0 = 0, y0 = 0, x1 = 0, y1 = 0}: GridRect)
            case first :: rest =>
                List.foldLeft((a, r) -> ({
                    x0 = Int32.min(a#x0, r#x0), y0 = Int32.min(a#y0, r#y0),
                    x1 = Int32.max(a#x1, r#x1), y1 = Int32.max(a#y1, r#y1)}: GridRect),
                    first, rest)
        }

    /// スケールは `scaleArea`（フロア全体）を `target` に収める倍率で固定し、配置は
    /// `content`（探索済みコンテンツ）の **左下** を `target` の左下に合わせる。
    /// これで「探索しても拡大率は一定」「左下の部屋は常に画面左下（マージン内）」になる。
    pub def anchorBL(scaleArea: GridRect, content: GridRect, target: GridRect): Fit =
        let scale = fitTransform(scaleArea, target)#scale;
        // content 左下 (x0, y1) を target 左下 (x0, y1) へ。mapCell(c) = o + c*scale。
        let ox = Int32.toFloat64(target#x0) - Int32.toFloat64(content#x0) * scale;
        let oy = Int32.toFloat64(target#y1) - Int32.toFloat64(content#y1) * scale;
        {scale = scale, ox = ox, oy = oy}

    /// grid セル → minimap ピクセル（セル左上）。
    pub def mapCell(cell: {x = Int32, y = Int32}, t: Fit): Vec2.Vec2 =
        {x = t#ox + Int32.toFloat64(cell#x) * t#scale,
         y = t#oy + Int32.toFloat64(cell#y) * t#scale}

    /// world-grid 矩形 → minimap ピクセル矩形（左上 pos + size）。
    pub def mapRect(r: GridRect, t: Fit): {pos = Vec2.Vec2, size = Vec2.Vec2} =
        let pos = mapCell(({x = r#x0, y = r#y0}: {x = Int32, y = Int32}), t);
        let size: Vec2.Vec2 = {x = Int32.toFloat64(r#x1 - r#x0) * t#scale,
                               y = Int32.toFloat64(r#y1 - r#y0) * t#scale};
        {pos = pos, size = size}

    /// 訪問済み module → 描画すべき矩形リスト（idx < roomCount を部屋、それ以外を通路と判定）。
    pub def visitedRects(visited: Set[Int32],
                          placements: List[DungeonComposer.ModulePlacement],
                          roomCount: Int32): List[{idx = Int32, isRoom = Bool, rect = GridRect}] =
        placements
            |> List.filter(p -> Set.memberOf(p#idx, visited))
            |> List.map(p -> {idx = p#idx, isRoom = p#idx < roomCount,
                              rect = FogScene.moduleRect(p)})

    /// 訪問済み module に隣接する「未訪問の通路」idx の集合（出口ヒント）。
    /// 通路が描かれることで「その先にまだ部屋＝行けるエリアがある」ことをプレイヤーに示す。
    /// 通路だけを出し、その先の未訪問の部屋自体は出さない（探索の楽しみを残す）。
    pub def corridorHints(visited: Set[Int32],
                           placements: List[DungeonComposer.ModulePlacement],
                           roomCount: Int32): Set[Int32] =
        placements
            |> List.filter(p -> p#idx >= roomCount)               // 通路のみ
            |> List.filter(p -> not Set.memberOf(p#idx, visited)) // 未訪問のみ
            |> List.filter(p -> adjacentToVisited(p, visited, placements))
            |> List.map(p -> p#idx)
            |> List.toSet

    def adjacentToVisited(c: DungeonComposer.ModulePlacement,
                           visited: Set[Int32],
                           placements: List[DungeonComposer.ModulePlacement]): Bool =
        placements
            |> List.filter(v -> Set.memberOf(v#idx, visited))
            |> List.exists(v -> bboxesAdjacent(c, v))

    /// 2 つの module の floorBounds bbox が隣接（1 タイル膨張で交差）するか。
    def bboxesAdjacent(a: DungeonComposer.ModulePlacement,
                        b: DungeonComposer.ModulePlacement): Bool =
        let aMinX = a#offset#x + a#floorBoundsMin#x - 1;
        let aMinY = a#offset#y + a#floorBoundsMin#y - 1;
        let aMaxX = a#offset#x + a#floorBoundsMaxEx#x + 1;
        let aMaxY = a#offset#y + a#floorBoundsMaxEx#y + 1;
        let bMinX = b#offset#x + b#floorBoundsMin#x;
        let bMinY = b#offset#y + b#floorBoundsMin#y;
        let bMaxX = b#offset#x + b#floorBoundsMaxEx#x;
        let bMaxY = b#offset#y + b#floorBoundsMaxEx#y;
        aMinX < bMaxX and aMaxX > bMinX and aMinY < bMaxY and aMaxY > bMinY

    /// 描画対象 module（訪問済み ＋ 出口ヒント通路）の moduleRect リスト（壁リング込み）。
    pub def displayedModuleRects(visited: Set[Int32],
                                  placements: List[DungeonComposer.ModulePlacement],
                                  roomCount: Int32): List[GridRect] =
        let display = Set.union(visited, corridorHints(visited, placements, roomCount));
        placements
            |> List.filter(p -> Set.memberOf(p#idx, display))
            |> List.map(floorRect)

    /// モジュールの「床のみ」矩形（壁リング edgePad を含めない）。
    /// 通路・部屋の床は doorway で接するので、これでもおおむね繋がって見える。
    pub def floorRect(p: DungeonComposer.ModulePlacement): GridRect =
        ({ x0 = p#offset#x + p#floorBoundsMin#x,
           y0 = p#offset#y + p#floorBoundsMin#y,
           x1 = p#offset#x + p#floorBoundsMaxEx#x,
           y1 = p#offset#y + p#floorBoundsMaxEx#y }: GridRect)

    /// 矩形群の union を「互いに重ならない矩形群」に分割する（横バンド分割）。
    /// `FogScene.bandDecompose` が補集合を返すのに対し、こちらは union（被覆部）を返す。
    /// 半透明描画でも重なりによる濃淡ムラが出ないよう、部屋・通路を一体化するのに使う。
    pub def unionBands(rects: List[GridRect]): List[GridRect] =
        let ys = sortedDistinct(rects |> List.flatMap(r -> r#y0 :: r#y1 :: Nil));
        consecutivePairs(ys) |> List.flatMap(band -> {
            let (ya, yb) = band;
            // このバンド [ya,yb) を縦に跨ぐ矩形の x 区間をマージ（被覆区間）。
            let intervals = rects
                |> List.filter(r -> r#y0 <= ya and r#y1 >= yb)
                |> List.map(r -> (r#x0, r#x1))
                |> List.sortBy(iv -> fst(iv))
                |> mergeIntervals;
            intervals |> List.map(iv -> {
                let (gx0, gx1) = iv;
                ({x0 = gx0, y0 = ya, x1 = gx1, y1 = yb}: GridRect)
            })
        })

    // ─── バンド分割ヘルパー（FogScene と同等の純粋関数） ───────

    def sortedDistinct(xs: List[Int32]): List[Int32] = dedupSorted(List.sort(xs))

    def dedupSorted(xs: List[Int32]): List[Int32] = match xs {
        case a :: b :: rest => if (a == b) dedupSorted(b :: rest) else a :: dedupSorted(b :: rest)
        case _              => xs
    }

    def consecutivePairs(xs: List[Int32]): List[(Int32, Int32)] = match xs {
        case a :: b :: rest => (a, b) :: consecutivePairs(b :: rest)
        case _              => Nil
    }

    /// x0 昇順ソート済みの区間列を、重なり・隣接を結合する。
    def mergeIntervals(xs: List[(Int32, Int32)]): List[(Int32, Int32)] = match xs {
        case Nil               => Nil
        case (a0, a1) :: rest  => mergeGo(a0, a1, rest)
    }

    def mergeGo(c0: Int32, c1: Int32, rest: List[(Int32, Int32)]): List[(Int32, Int32)] = match rest {
        case Nil              => (c0, c1) :: Nil
        case (b0, b1) :: more =>
            if (b0 <= c1) mergeGo(c0, Int32.max(c1, b1), more)
            else (c0, c1) :: mergeGo(b0, b1, more)
    }
}
