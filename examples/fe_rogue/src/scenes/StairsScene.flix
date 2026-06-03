/// StairsScene — フロアの「次の階へ降りる階段」マーカー
///
/// 各フロアに 1 つだけ、床のランダムなセルに配置される。味方がそのセルに乗ると
/// 行動メニューに「かいだん」が出て、選ぶとその味方はマップから退場し次フロアへ進む。
///
/// ノード構造（Cursor / Flag と並列のトップレベル）:
///   Stairs (Marker2D, NodeTag.Stairs(Data))
///     └─ Sprite (Sprite2D, stairs.png)
///
/// 設計（FlagScene を踏襲）:
///   - 親 Marker2D に配置セルと placed フラグを持たせる
///   - 配置するまでは親 Marker2D を invisible にする（add 直後）
///   - `placeRandom` で床セルを 1 つ選び、`isAt` で「そのセルに階段があるか」を答える
mod StairsScene {

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// `gridPos`: 階段を置いたグリッド座標（placed = false のときは未使用）
    /// `placed`: 階段が配置済みか。false の間は描画されず、`isAt` も常に false を返す
    pub type alias Data = {
        gridPos = {x = Int32, y = Int32},
        placed  = Bool
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def name(): String = "Stairs"
    pub def stairsPath(): NodePath = name() :: Nil

    /// scene.json への相対パス（cwd = プロジェクトルート想定）
    def scenePath(): String = "src/scenes/StairsScene.scene.json"

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// MapScene 登録済みの scene に階段ノードを追加する（初期は未配置 = 非表示）。
    /// レイアウト（Marker2D + 子 Sprite2D, テクスチャ, scale, zIndex, 初期不可視）は
    /// `StairsScene.scene.json` に閉じ込めてあり、ロード後にゲーム状態 (`Data`) を
    /// `Scene.setState` で後付け注入する分業（FlagScene.add と同じ）。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead} =
        let initialData: Data = {gridPos = {x = 0, y = 0}, placed = false};
        SceneLoader.loadScene(scenePath(),
                               SceneLoader.constTagParser(NodeTag.NoTag),
                               scene)
            |> Scene.setState(stairsPath(), NodeTag.Stairs(initialData))

    /// 床セルからランダムに 1 つ選んで階段を配置する。
    /// 候補は「部屋の床 かつ 駒（味方・敵）に占有されていない かつ 床アイテムが無い」セル。
    /// 部屋は anchor（プレイヤー初期配置, idx=0）を除いた idx 1..roomCount を対象にする
    /// （= 階段はスタート部屋以外に出す）。EnemyScene / ItemScene と同じ床セル列挙を使うので、
    /// usedRect の void（部屋外）を拾って画面外に出る不具合が起きない。
    /// 候補が 1 つも無い極端なマップでは何もしない（階段は非表示のまま）。
    /// プレイヤー・敵・アイテム配置が済んだ後（= buildPlayingScene の末尾）に呼ぶ。
    pub def placeRandom(scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        let layer      = MapScene.getMapLayer(scene);
        let placements = MapScene.getPlacements(scene);
        let roomCount  = MapScene.getRoomCount(scene);
        let occupied   = List.append(
            PlayerScene.getAll(scene) |> List.map(d -> d#gridPos),
            EnemyScene.getAll(scene)  |> List.map(d -> d#gridPos));
        // anchor (idx=0) を除いた部屋だけを候補に（idx >= 1 かつ idx < roomCount = 部屋）
        let rooms = List.filter(p -> p#idx >= 1 and p#idx < roomCount, placements);
        let candidates = rooms
            |> List.flatMap(p -> floorCellsInRoom(layer, p))
            |> List.filter(cell ->
                not isOccupied(cell, occupied)
                and Option.isEmpty(ItemScene.findAt(cell, scene)));
        match RandomUtil.pick(candidates) {
            case Some(cell) => placeAt(cell, scene)
            case None       => scene
        }

    /// 部屋の bbox（offset + floorBounds）に含まれる床セルを列挙する。
    /// n-format で通路の床が候補に混ざらないよう floorBounds で絞る（ItemScene と同じロジック）。
    def floorCellsInRoom(layer: TileMapLayer,
                          p: DungeonComposer.ModulePlacement): List[{x = Int32, y = Int32}] =
        let minX = p#offset#x + p#floorBoundsMin#x;
        let minY = p#offset#y + p#floorBoundsMin#y;
        let maxX = p#offset#x + p#floorBoundsMaxEx#x;
        let maxY = p#offset#y + p#floorBoundsMaxEx#y;
        let xs = List.range(minX, maxX);
        let ys = List.range(minY, maxY);
        ys
            |> List.flatMap(y ->
                xs |> List.map(x -> ({x = x, y = y}: {x = Int32, y = Int32})))
            |> List.filter(cell -> TileMapLayer.isFloor(cell, layer))

    /// セルが占有リストに含まれるか。
    def isOccupied(cell: {x = Int32, y = Int32},
                    occupied: List[{x = Int32, y = Int32}]): Bool =
        List.exists(o -> o#x == cell#x and o#y == cell#y, occupied)

    /// `target` セルに階段を配置する純粋なマーク操作（位置更新 + 可視化）。
    /// `placeRandom` の内部実装。テストからも床セルを固定して配置確認に使う。
    pub def placeAt(target: {x = Int32, y = Int32}, scene: Scene[NodeTag]): Scene[NodeTag] =
        let world = MapScene.cellCenter(target);
        scene
            |> Scene.setGlobalPositionAt(stairsPath(), world)
            |> mapStairs((marker, _) ->
                (CanvasItem.setVisible(true, marker),
                 ({gridPos = target, placed = true}: Data)))

    // ────────────────────────────────────────────────────────
    // (D) 問い合わせ
    // ────────────────────────────────────────────────────────

    /// 指定セルに（配置済みの）階段があるか。ActionMenuScene が「かいだん」コマンドの
    /// 出現条件として使う。
    pub def isAt(gridPos: {x = Int32, y = Int32}, scene: Scene[NodeTag]): Bool =
        match Scene.getState(stairsPath(), scene) {
            case Some(NodeTag.Stairs(data)) =>
                data#placed
                and data#gridPos#x == gridPos#x
                and data#gridPos#y == gridPos#y
            case _ => false
        }

    /// 階段の現在の配置セル。未配置なら None。
    pub def getPos(scene: Scene[NodeTag]): Option[{x = Int32, y = Int32}] =
        match Scene.getState(stairsPath(), scene) {
            case Some(NodeTag.Stairs(data)) =>
                if (data#placed) Some(data#gridPos) else None
            case _ => None
        }

    // ────────────────────────────────────────────────────────
    // (E) ボイラプレート
    // ────────────────────────────────────────────────────────

    /// Stairs の Marker2D + Data をまとめて変換する（FlagScene.mapFlag と同形）。
    def mapStairs(f: (Marker2D, Data) -> (Marker2D, Data),
                   scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(stairsPath(), engineNode -> match engineNode {
            case EngineNode.Marker2DWithState(marker, NodeTag.Stairs(data)) =>
                let (newMarker, newData) = f(marker, data);
                EngineNode.Marker2DWithState(newMarker, NodeTag.Stairs(newData))
            case other => other
        }, scene)

}
