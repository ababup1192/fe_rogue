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
///          ├─ Room_0 .. Room_{N-1} (ColorRect)        ← 訪問済み部屋/通路の矩形プール
///          ├─ Floor_0 .. Floor_{K-1} (ColorRect)      ← 歩ける床の黒くり抜きプール
///          └─ Marker_0 .. Marker_{M-1} (Polygon2D の円) ← プレイヤー/階段/アイテム/敵の点プール
///   World/MinimapDriver (Marker2D, MinimapDriver)     ← step で毎フレーム蓄積＋描画

mod MinimapScene {

    /// driver ノードが持つ永続 state。フロア跨ぎはシーン再構築でリセットされる。
    pub type alias DriverData = {
        visited    = Set[Int32],  // 訪問済み module idx（= 記憶。核心）
        stairsSeen = Bool,        // 一度発見した階段を覚え続ける
        visible    = Bool,        // M 全画面トグル状態
        mPrev      = Bool         // M の前フレーム押下状態（エッジ検出用）
    }

    /// fitTransform が返す「grid → minimap ピクセル」のアフィン変換パラメータ。
    pub type alias Fit = { scale = Float64, ox = Float64, oy = Float64 }

    def rootName(): String = "Minimap"
    /// render-from-World が minimap サブツリー（ColorRect の room/floor ＋ Polygon2D のマーカー）を描く/隠す root。
    pub def rootPath(): NodePath = rootName() :: Nil
    def contentName(): String = "MinimapContent"
    def contentPath(): NodePath = rootName() :: contentName() :: Nil
    def driverName(): String = "MinimapDriver"
    /// driver ノードの NodePath（`add` は World 直下に追加する）。
    def driverPath(): NodePath = List.append(MapScene.worldPath(), driverName() :: Nil)
    def fontName(): String = "ui"
    def sceneJsonPath(): String = AssetPath.resolve("src/scenes/MinimapScene.scene.json")

    def roomChildName(i: Int32): String = "Room_${i}"
    def roomChildPath(i: Int32): NodePath = List.append(contentPath(), roomChildName(i) :: Nil)
    /// 歩ける床（黒くり抜き）プール。壁プール（Room_i）と 1:1 対応。
    def floorChildName(i: Int32): String = "Floor_${i}"
    def floorChildPath(i: Int32): NodePath = List.append(contentPath(), floorChildName(i) :: Nil)
    def markerChildName(i: Int32): String = "Marker_${i}"
    def markerChildPath(i: Int32): NodePath = List.append(contentPath(), markerChildName(i) :: Nil)

    /// 部屋/通路矩形プール。1 フロアの module 数（部屋数 + 通路数）に十分な固定数。
    /// union 分割は module 数より矩形が増えうるので余裕を持たせる。
    def roomPoolSize(): Int32 = 64
    /// 歩ける床の黒くり抜きプール。床セルを行ごとの横ランで描くので部屋プールより多め。
    def floorPoolSize(): Int32 = 384
    /// マーカープール（プレイヤー≤3 + 階段1 + アイテム数 + 同室の敵）に十分な固定数。
    def markerPoolSize(): Int32 = 40

    /// 探索マップを収める「左下のボックス」（design 解像度 170×128 のピクセル座標、y は下向き）。
    /// シレン風に左下隅へ半透明で置く。背景枠は描かず、フロア/通路の矩形だけを描く（29×42 を 2 倍 ≈ 58×84）。
    /// x0=5 で画面左端から約 5px のマージンを空けて左下へ置く（横長キャンバスでの左寄せ）。
    pub def targetRect(): GridRect = ({x0 = 5, y0 = 38, x1 = 63, y1 = 122}: GridRect)

    /// スケール基準となる「参照フロア寸法」（タイル）。実測した最大級フロアの bbox
    /// (おおよそ 47×51) を基準にする。**この1枚を `targetRect` に収める倍率を全フロア
    /// 共通の縮尺とする**ことで、フロアの実寸（部屋数）に依らずミニマップのズーム率を
    /// 一定（= どのフロアでも 3F と同じ見え方）にする。見せ方（左下アンカー・アスペクト
    /// 比維持・フレームレス）は変えない。
    def scaleReferenceRect(): GridRect = ({x0 = 0, y0 = 0, x1 = 47, y1 = 51}: GridRect)

    /// 全フロア共通の縮尺（定数）。`scaleReferenceRect` を `targetRect` に収める倍率。
    pub def referenceScale(): Float64 = fitTransform(scaleReferenceRect(), targetRect())#scale

    /// マーカー（丸）の直径は「セル幅(scale)に比例」させ、隣接セルの円どうしが重ならないよう
    /// セル幅未満に保つ。同時に最大値 `markerMaxPx` で頭打ちにして大きくなりすぎないようにする。
    /// （アイテム・キャラ等は矩形でなく丸 = engine の Polygon2D で表す。）
    def markerCellFraction(): Float64 = 0.85
    def markerMaxPx(): Float64 = 3.9
    /// セル幅 `scale` からマーカー直径（px）を求める。
    def markerDiameter(scale: Float64): Float64 =
        let d = markerCellFraction() * scale;
        if (d < markerMaxPx()) d else markerMaxPx()

    /// zIndex（同一 CanvasLayer 内の描画順）。壁(下) < 歩ける床の黒(中) < マーカー(上)。
    /// 探索済みエリアを壁色ブロックで塗り、その上に黒で歩ける床を「くり抜く」2 層構成。
    def roomZIndex(): Int32 = 1     // 壁/構造（拡張した外枠ブロック）
    def floorZIndex(): Int32 = 2    // 歩ける床（黒。壁ブロックから碁盤目をくり抜く）
    def markerZIndex(): Int32 = 3

    // 色（半透明で操作の邪魔にならないよう alpha を抑える）
    /// 壁/構造の色（歩ける床を囲む外枠ブロック）。
    def moduleColor(): Color = {r = 0.62f32, g = 0.68f32, b = 0.85f32}
    def moduleAlpha(): Float32 = 0.50f32
    /// 歩ける床は黒（何もなし）でくり抜いて表現する。壁の上に重ねるので不透明寄りに。
    def floorColor(): Color = {r = 0.0f32, g = 0.0f32, b = 0.0f32}
    def floorAlpha(): Float32 = 0.92f32
    def leaderColor(): Color = {r = 0.95f32, g = 0.85f32, b = 0.20f32}
    def playerColor(): Color = {r = 0.30f32, g = 0.70f32, b = 0.95f32}
    def stairsColor(): Color = {r = 0.90f32, g = 0.30f32, b = 0.85f32}
    def itemColor(): Color = {r = 0.95f32, g = 0.60f32, b = 0.20f32}
    /// 今プレイヤーと同じ部屋に居る敵を示す赤丸。
    def enemyColor(): Color = {r = 0.92f32, g = 0.25f32, b = 0.22f32}
    def markerAlpha(): Float32 = 0.85f32

    /// 起動時から左下に表示（非侵襲な常設 HUD）。M で出し入れする。
    def initialData(): DriverData =
        {visited = Set.empty(), stairsSeen = false, visible = true, mPrev = false}

    /// driver ノードに蓄積された訪問済み module idx を返す。未登録なら空集合（安全側）。
    /// カーソルの移動可能範囲（既訪エリア）の算出に CursorScene が使う。
    pub def visitedModules(scene: Scene[NodeTag]): Set[Int32] =
        match Scene.getState(driverPath(), scene) {
            case Some(NodeTag.MinimapDriver(d)) => d#visited
            case _                              => Set.empty()
        }

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
        // 歩ける床の黒くり抜きプール（壁プールの上に重ねる。床セルを横ランで描くので多め）。
        let withFloors =
            List.foldLeft((acc, i) ->
                Scene.addChildAt(contentPath(), floorChildName(i),
                    EngineNode.ColorRectWithState(
                        newPoolRect(floorColor(), floorZIndex(), floorAlpha()), NodeTag.NoTag),
                    acc),
                withRooms, List.range(0, floorPoolSize()));
        let withMarkers =
            List.foldLeft((acc, i) ->
                Scene.addChildAt(contentPath(), markerChildName(i),
                    EngineNode.Polygon2DWithState(newMarkerCircle(), NodeTag.NoTag),
                    acc),
                withFloors, List.range(0, markerPoolSize()));
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

    /// gameLoop がパイプライン段で 1 回呼ぶ frame-paced
    /// System。訪問 module を蓄積し、M トグルを反映し、ミニマップを再描画する。
    /// レベルアップ画面（`LevelUpView`）の間は M トグル状態を保ったまま強制的に隠す。
    /// driver の DriverData は StairsExit と同型に `driverPath()` ノードの state で持ち、
    /// `Scene.getState` で読み `writeData` で書き戻す（node 引数不要）。
    pub def step(scene: Scene[NodeTag]):
                    Scene[NodeTag]
                    \ {GameEngine.Game, TurnPhase.State, SelectedPlayer.State,
                       PlayerData.PartyQuery, EnemyData.RosterQuery,
                       World.WorldQuery} =  // 味方/敵/階段位置の読みは World 経由
        match Scene.getState(driverPath(), scene) {
            case Some(NodeTag.MinimapDriver(data)) =>
                let phase = TurnPhase.State.get();
                let mDown = GameEngine.Game.isKeyPressed(GameEngine.Key.M);
                // 敵ターン中は M を受け付けない（エネミーフェーズ中はミニマップを開けないようにする）。
                // トグル自体を無視するので、敵ターン中に押しても敵ターン明けに開いたりしない。
                let acceptsToggle = phase != TurnPhase.Phase.EnemyTurn;
                let visible2 =
                    if (mDown and not data#mPrev and acceptsToggle) not data#visible
                    else data#visible;
                let placements = MapScene.getPlacements(scene);
                let roomCount  = MapScene.getRoomCount(scene);
                // 部屋の記憶（visited）と敵赤丸（litRooms）は fog と同じく origin 基準にする。
                // 移動ドラフト中に新しく踏み込んだ部屋は確定（drafts クリア）まで地図に出さない。
                let drafts = SelectedPlayer.State.get()#drafts;
                let units  = PlayerData.PartyQuery.getAll()
                    |> List.map(d -> {id = d#id, gridPos = d#gridPos, hidden = d#hidden,
                                      origin = MoveDraft.originOf(d#id, drafts)
                                               |> Option.getWithDefault(d#gridPos)});
                let frame    = visitedThisFrameDrafted(units, placements, roomCount);
                let litRooms = litRoomsDrafted(units, placements, roomCount);
                let visited2 = accumulate(data#visited, frame);
                let stairs2 = data#stairsSeen or stairsDiscovered(visited2, placements, scene);
                let nextData = {visited = visited2, stairsSeen = stairs2,
                                visible = visible2, mPrev = mDown};
                // レベルアップ画面・敵ターン中は隠す（M トグルの記憶 visible2 は維持）。
                let hidden = phase == TurnPhase.Phase.LevelUpView
                              or phase == TurnPhase.Phase.EnemyTurn;
                let show = visible2 and not hidden;
                renderMinimap(show, nextData, litRooms, writeData(nextData, scene))
            case _ => scene
        }

    /// DriverData を driver ノードの state へ書き戻す（step の明示書き込み）。
    def writeData(data: DriverData, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(driverPath(), node -> match node {
            case EngineNode.Marker2DWithState(m, NodeTag.MinimapDriver(_)) =>
                EngineNode.Marker2DWithState(m, NodeTag.MinimapDriver(data))
            case other => other
        }, scene)

    /// 階段が「発見済み」か。階段セルの属する module が訪問済みなら発見扱い。
    /// 階段位置は World.stairsPos から読む。
    def stairsDiscovered(visited: Set[Int32],
                          placements: List[DungeonComposer.ModulePlacement],
                          _scene: Scene[NodeTag]): Bool \ World.WorldQuery =
        match World.stairsPosOf(World.WorldQuery.get()) {
            case None       => false
            case Some(cell) =>
                match MapSnapshot.moduleOfCellIn(cell, placements) {
                    case Some(idx) => Set.memberOf(idx, visited)
                    case None      => false
                }
        }

    /// ミニマップを描画する（純粋な Scene 変換）。`show=false` 時は全プールを隠す。
    /// フレームは「フロア全体の bbox」基準にして、探索しても配置が動かないようにする。
    /// 描画対象は「訪問済み module」＋「訪問済みに隣接する未訪問の通路（出口ヒント）」を
    /// union 分割して一体化（重なり部分を二重描画しない）。
    def renderMinimap(show: Bool, data: DriverData, litRooms: Set[Int32],
                       scene: Scene[NodeTag]): Scene[NodeTag]
                       \ {PlayerData.PartyQuery, EnemyData.RosterQuery, World.WorldQuery} =
        if (not show)
            hideAll(scene)
        else {
            let placements = MapScene.getPlacements(scene);
            let roomCount  = MapScene.getRoomCount(scene);
            let rawRects   = displayedModuleRects(data#visited, placements, roomCount);
            // 縮尺は全フロア共通の固定値（`referenceScale`）。フロアの実寸に依らず一定。
            // ただし参照より大きい稀な巨大フロアは画面ボックスからはみ出さないよう、その
            // フロアの fit 倍率でクランプ（縮小）する。配置は探索済みコンテンツの bbox を
            // 画面ボックスの左下に合わせる（左下の部屋を画面左下へ）。
            let fitScale   = fitTransform(tightRegion(placements), targetRect())#scale;
            let scale      = minF(referenceScale(), fitScale);
            let t          = anchorBLWithScale(scale, boundsOf(rawRects), targetRect());
            let disjoint   = unionBands(rawRects);
            // 壁/構造を青のベタ塗り（モジュール床 bbox。内壁・柱もここに含まれて青く残る）、
            // その上に「歩ける床セルだけ」を黒くくり抜く（壁セルは MapSnapshot で除外）。
            let snapshot   = mapSnapshot(scene);
            let floorRuns  = floorRunsIn(disjoint, snapshot);
            let markers    = collectMarkers(data, placements, roomCount, litRooms, scene);
            scene
                |> drawRoomPool(disjoint, t)
                |> drawFloorPool(floorRuns, t)
                |> drawMarkerPool(markers, t)
        }

    /// 描画用の MapSnapshot（壁セル判定に使う）。BoardSnapshot.fromScene と同じ射影。
    def mapSnapshot(scene: Scene[NodeTag]): MapSnapshot =
        let layer     = MapScene.getMapLayer(scene);
        let mapGlobal = Scene.globalPositionAt(MapScene.mapPath(), scene);
        let placements = MapScene.getPlacements(scene);
        MapScene.snapshotOf(layer, mapGlobal, placements)

    /// 青ベタ塗りバンド群の中から「歩ける床セル」だけを行ごとの横ラン（1 セル高の矩形）に
    /// まとめて返す。これを黒で重ね描きすると、壁セル（内壁・柱・外周）が青のまま残る。
    def floorRunsIn(bands: List[GridRect], m: MapSnapshot): List[GridRect] =
        List.flatMap(b -> bandFloorRuns(b, m), bands)

    def bandFloorRuns(band: GridRect, m: MapSnapshot): List[GridRect] =
        List.flatMap(y -> rowFloorRuns(band#x0, band#x1, y, m), List.range(band#y0, band#y1))

    /// 行 y の x0..x1（排他）を走査し、連続する床セルを 1 本の横ランにまとめる。
    def rowFloorRuns(x0: Int32, x1: Int32, y: Int32, m: MapSnapshot): List[GridRect] =
        let step = (acc, x) -> {
            let (runs, cur) = acc;
            let isF = MapSnapshot.isFloor(({x = x, y = y}: {x = Int32, y = Int32}), m);
            match (cur, isF) {
                case (None,    true)  => (runs, Some(x))
                case (Some(_), true)  => (runs, cur)
                case (Some(s), false) => (closeRun(s, x, y) :: runs, None)
                case (None,    false) => (runs, None)
            }
        };
        let (runs, cur) = List.foldLeft(step, ((Nil, None): (List[GridRect], Option[Int32])),
                                        List.range(x0, x1));
        match cur {
            case Some(s) => closeRun(s, x1, y) :: runs
            case None    => runs
        }

    /// 床ラン [s, e)（行 y, 高さ 1）を GridRect 化する。
    def closeRun(s: Int32, e: Int32, y: Int32): GridRect =
        ({x0 = s, y0 = y, x1 = e, y1 = y + 1}: GridRect)

    /// 表示すべきマーカー（セル + 色）一覧。プレイヤー（非 hidden、リーダーは別色）+ 発見済み
    /// 階段 + 訪問済み部屋内のアイテム。
    def collectMarkers(data: DriverData,
                        placements: List[DungeonComposer.ModulePlacement],
                        roomCount: Int32, litRooms: Set[Int32], _scene: Scene[NodeTag]):
                       List[{cell = {x = Int32, y = Int32}, color = Color}]
                       \ {PlayerData.PartyQuery, EnemyData.RosterQuery, World.WorldQuery} =
        let players =
            PlayerData.PartyQuery.getAll()
                |> List.filter(d -> not d#hidden)
                |> List.map(d -> {cell = d#gridPos,
                                  color = if (d#id == 0) leaderColor() else playerColor()});
        // 階段位置は World.stairsPos から読む。
        let stairsM =
            if (data#stairsSeen)
                match World.stairsPosOf(World.WorldQuery.get()) {
                    case Some(cell) => {cell = cell, color = stairsColor()} :: Nil
                    case None       => Nil
                }
            else Nil;
        let itemsM =
            // 床アイテム位置は World store から読む。
            (World.groundItemsOf(World.WorldQuery.get()) |> Map.valuesOf |> List.map(d -> d#gridPos))
                |> List.filter(cell -> inVisitedRoom(cell, placements, roomCount, data#visited))
                |> List.map(cell -> {cell = cell, color = itemColor()});
        // いま点灯している部屋(litRooms)に居る敵を赤丸で（アイテムより手前＝後ろに連結して上に描く）。
        let enemiesM = enemiesSharingPlayerRoom(litRooms, placements);
        List.append(players, List.append(stairsM, List.append(itemsM, enemiesM)))

    /// 「いま点灯している部屋に居る敵」マーカー（赤丸）。点灯部屋集合 `litRooms`（origin 基準で
    /// 求めた room module。`litRoomsDrafted` が算出）に居る生存敵（hp>0 かつ not isDying）を拾う。
    /// 点灯している部屋＝霧で照らされ既に見えているので別途の可視判定は省く。移動中に踏み込んだ
    /// だけの暗い新規部屋は litRooms に含まれないため、その敵は地図にも出ない（fog と一貫）。
    def enemiesSharingPlayerRoom(litRooms: Set[Int32],
                                  placements: List[DungeonComposer.ModulePlacement]):
                                 List[{cell = {x = Int32, y = Int32}, color = Color}]
                                 \ EnemyData.RosterQuery =
        EnemyData.RosterQuery.getAll()
            |> List.filter(e -> e#hp > 0 and not e#isDying)
            |> List.filter(e -> match MapSnapshot.moduleOfCellIn(e#gridPos, placements) {
                                    case Some(idx) => Set.memberOf(idx, litRooms)
                                    case None      => false
                                })
            |> List.map(e -> {cell = e#gridPos, color = enemyColor()})

    def inVisitedRoom(cell: {x = Int32, y = Int32},
                       placements: List[DungeonComposer.ModulePlacement],
                       roomCount: Int32, visited: Set[Int32]): Bool =
        match MapSnapshot.moduleOfCellIn(cell, placements) {
            case Some(idx) => idx < roomCount and Set.memberOf(idx, visited)
            case None      => false
        }

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

    /// 壁/構造の青ベタ塗り（モジュール床 bbox。内壁・柱もここに含まれて青く残る）。
    /// 歩ける床はこの上に黒で重ねてくり抜く（`drawFloorPool`）。
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

    /// 歩ける床ランを黒くり抜きプール（Floor_i）に割り当てる。先頭 used 個を配置、残りは非表示。
    def drawFloorPool(runs: List[GridRect], t: Fit, scene: Scene[NodeTag]): Scene[NodeTag] =
        let used = List.length(runs);
        let withActive =
            List.foldLeft((acc, entry) -> {
                let (i, r) = entry;
                if (i < floorPoolSize()) setFloorRect(i, r, t, acc) else acc
            }, scene, List.zipWithIndex(runs));
        List.foldLeft((acc, i) ->
            if (i >= used) hideFloor(i, acc) else acc,
            withActive, List.range(0, floorPoolSize()))

    def setFloorRect(i: Int32, r: GridRect, t: Fit, scene: Scene[NodeTag]): Scene[NodeTag] =
        let pr = mapRect(r, t);
        Scene.mapEngineNode(floorChildPath(i),
            n -> EngineNode.mapColorRect(c ->
                c |> ColorRect.setSize(pr#size)
                  |> Node2D.setPosition(pr#pos)
                  |> CanvasItem.setModulate(floorColor())
                  |> CanvasItem.setVisible(true), n),
            scene)

    def hideFloor(i: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(floorChildPath(i),
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

    /// M で閉じたとき・LevelUpView/EnemyTurn で強制非表示になったとき、
    /// 前フレームのプール残骸が画面に残らないようすべての矩形とマーカーを消す。
    def hideAll(scene: Scene[NodeTag]): Scene[NodeTag] =
        let withRooms =
            List.foldLeft((acc, i) -> hideRoom(i, acc), scene, List.range(0, roomPoolSize()));
        let withFloors =
            List.foldLeft((acc, i) -> hideFloor(i, acc), withRooms, List.range(0, floorPoolSize()));
        List.foldLeft((acc, i) -> hideMarker(i, acc), withFloors, List.range(0, markerPoolSize()))

    /// 今フレームに非 hidden ユニットが居る module idx の集合（module 外セルは無視）。
    /// 引数は開いた行多相なので `PlayerScene.Data`（gridPos/hidden を含む）をそのまま渡せる。
    pub def visitedThisFrame(units: List[{gridPos = {x = Int32, y = Int32}, hidden = Bool | r}],
                              placements: List[DungeonComposer.ModulePlacement]): Set[Int32] =
        units
            |> List.filter(d -> not d#hidden)
            |> List.filterMap(d -> MapSnapshot.moduleOfCellIn(d#gridPos, placements))
            |> List.toSet

    /// `visitedThisFrame` の draft 対応版。room module は origin（ターン開始位置）が同じ部屋に
    /// あるときだけ訪問済みに数え、corridor module はライブ位置で数える。移動中に新しく踏み込んだ
    /// 部屋を確定（drafts クリア）まで地図に記録しない（fog の `holesForDraft` と一貫）。
    pub def visitedThisFrameDrafted(units: List[{gridPos = {x = Int32, y = Int32},
                                                  origin = {x = Int32, y = Int32}, hidden = Bool | r}],
                                     placements: List[DungeonComposer.ModulePlacement],
                                     roomCount: Int32): Set[Int32] =
        units
            |> List.filter(d -> not d#hidden)
            |> List.filterMap(d -> revealedModuleOf(d#gridPos, d#origin, placements, roomCount))
            |> List.toSet

    /// いま点灯している room module の集合（origin 基準）。ミニマップの敵赤丸を「明るい部屋に
    /// 居る敵」だけに絞るために使う（暗い新規部屋の敵は地図にも出さない＝fog と一貫）。
    pub def litRoomsDrafted(units: List[{gridPos = {x = Int32, y = Int32},
                                          origin = {x = Int32, y = Int32}, hidden = Bool | r}],
                             placements: List[DungeonComposer.ModulePlacement],
                             roomCount: Int32): Set[Int32] =
        units
            |> List.filter(d -> not d#hidden)
            |> List.filterMap(d -> revealedModuleOf(d#gridPos, d#origin, placements, roomCount))
            |> List.filter(idx -> idx < roomCount)
            |> List.toSet

    /// このユニットが現フレームに reveal する module idx（fog の `holeFor` と同じ部屋デファー規則）。
    /// 通路 module はライブ採用、room module は origin が同じ部屋にあるときだけ採用、新規部屋は None。
    def revealedModuleOf(live: {x = Int32, y = Int32}, origin: {x = Int32, y = Int32},
                          placements: List[DungeonComposer.ModulePlacement],
                          roomCount: Int32): Option[Int32] =
        match MapSnapshot.moduleOfCellIn(live, placements) {
            case None    => None
            case Some(m) =>
                if (m >= roomCount) Some(m)
                else if (MapSnapshot.moduleOfCellIn(origin, placements) == Some(m)) Some(m)
                else None
        }

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
        anchorBLWithScale(fitTransform(scaleArea, target)#scale, content, target)

    /// `anchorBL` の **scale 固定版**。倍率を呼び出し側が決め、`content` の左下 (x0, y1) を
    /// `target` の左下 (x0, y1) へ合わせる。mapCell(c) = o + c*scale。
    pub def anchorBLWithScale(scale: Float64, content: GridRect, target: GridRect): Fit =
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
    /// 青ベタ塗りは壁リング込みの bbox（`FogScene.moduleRect`）を使う。床だけの bbox では
    /// 通路（1 幅の床）に脇壁が無く全部黒く抜けてしまうため、壁リングまで青で覆ってから
    /// 歩ける床セルを黒くくり抜く（通路にも青い脇壁が残る）。
    pub def displayedModuleRects(visited: Set[Int32],
                                  placements: List[DungeonComposer.ModulePlacement],
                                  roomCount: Int32): List[GridRect] =
        let display = Set.union(visited, corridorHints(visited, placements, roomCount));
        placements
            |> List.filter(p -> Set.memberOf(p#idx, display))
            |> List.map(FogScene.moduleRect)

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

    // FogScene のバンド分割は「霧として覆う補集合」を返すため流用できない。
    // ミニマップは被覆部（union）が必要なので、同一アルゴリズムをここで再実装している。

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
